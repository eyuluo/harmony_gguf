#include "llama_inference.h"

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <vector>

#include "engine_state.h"
#include "llama.h"

namespace inference {

namespace {

// 为 batch 中 n 个 token 设置 seq_id 与显式 pos；最后一个 token 输出 logits（供采样）。
void FillBatchSeq(llama_batch & batch, llama_seq_id seq_id, int32_t n, llama_pos pos_start, bool last_logits) {
    for (int32_t i = 0; i < n; i++) {
        batch.pos[i] = pos_start + i;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = seq_id;
        batch.logits[i] = 0;
    }
    if (last_logits && n > 0) {
        batch.logits[n - 1] = 1;
    }
}

// RAII 封装 llama_sampler / llama_batch，提前返回时自动释放。
class SamplerGuard {
public:
    explicit SamplerGuard(llama_sampler * smpl) : smpl_(smpl) {}
    ~SamplerGuard() {
        if (smpl_ != nullptr) {
            llama_sampler_free(smpl_);
        }
    }
    SamplerGuard(const SamplerGuard &) = delete;
    SamplerGuard & operator=(const SamplerGuard &) = delete;
    llama_sampler * get() const { return smpl_; }

private:
    llama_sampler * smpl_;
};

class BatchGuard {
public:
    explicit BatchGuard(int32_t n_tokens) : batch_(llama_batch_init(n_tokens, 0, 1)) {}
    ~BatchGuard() { llama_batch_free(batch_); }
    BatchGuard(const BatchGuard &) = delete;
    BatchGuard & operator=(const BatchGuard &) = delete;
    llama_batch & get() { return batch_; }

private:
    llama_batch batch_;
};

} // namespace

GenResult RunGeneration(
    llama_seq_id seq_id,
    const std::shared_ptr<std::atomic_bool> & stop_flag,
    const GenerateParams & params,
    const std::function<void(const char * text)> & on_token,
    const std::function<bool()> & should_stop,
    GenerateStats & out_stats) {

    EngineState & state = EngineState::Instance();
    llama_model * model = state.model();
    llama_context * ctx = state.ctx();
    const llama_vocab * vocab = state.vocab();

    if (model == nullptr || ctx == nullptr || vocab == nullptr) {
        return GenResult::Failed;
    }

    if (params.threads > 0) {
        llama_set_n_threads(ctx, params.threads, params.threads);
    }

    // 生效的停止条件：外部 should_stop + per-request 停止标志 + 全局停止
    auto stop_requested = [&]() {
        if (should_stop()) {
            return true;
        }
        if (stop_flag && stop_flag->load(std::memory_order_relaxed)) {
            return true;
        }
        return state.StopAllRequested();
    };

    // 采样链：penalties -> top_k -> temp -> top_p -> dist
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    SamplerGuard smpl(llama_sampler_chain_init(sparams));

    const int32_t n_vocab = llama_vocab_n_tokens(vocab);
    llama_sampler_chain_add(smpl.get(), llama_sampler_init_penalties(n_vocab, 64, params.repeat_penalty, 0.0f, 0.0f));
    llama_sampler_chain_add(smpl.get(), llama_sampler_init_top_k(params.top_k));
    llama_sampler_chain_add(smpl.get(), llama_sampler_init_temp(params.temperature));
    llama_sampler_chain_add(smpl.get(), llama_sampler_init_top_p(params.top_p, 1));
    llama_sampler_chain_add(smpl.get(), llama_sampler_init_dist(static_cast<uint32_t>(llama_time_us())));

    // 分词
    const int32_t n_prompt = -llama_tokenize(vocab, params.prompt.c_str(), static_cast<int32_t>(params.prompt.size()),
                                             nullptr, 0, true, true);
    if (n_prompt <= 0) {
        return GenResult::Failed;
    }

    std::vector<llama_token> prompt_tokens(static_cast<size_t>(n_prompt));
    if (llama_tokenize(vocab, params.prompt.c_str(), static_cast<int32_t>(params.prompt.size()),
                       prompt_tokens.data(), n_prompt, true, true) < 0) {
        return GenResult::Failed;
    }

    const uint32_t slot_ctx = state.slot_context();
    if (slot_ctx > 0 && static_cast<uint32_t>(n_prompt) > slot_ctx) {
        return GenResult::Failed;
    }

    llama_memory_t mem = llama_get_memory(ctx);
    const bool can_shift = mem != nullptr && llama_memory_can_shift(mem);

    out_stats.prompt_tokens = n_prompt;

    // prompt batch：一次性 decode 全部 prompt token（pos 0..n_prompt-1）
    BatchGuard prompt_batch(n_prompt);
    for (int32_t i = 0; i < n_prompt; i++) {
        prompt_batch.get().token[i] = prompt_tokens[i];
    }
    FillBatchSeq(prompt_batch.get(), seq_id, n_prompt, 0, true);

    // 单 token batch：生成循环复用
    BatchGuard one(1);
    one.get().n_seq_id[0] = 1;
    one.get().seq_id[0][0] = seq_id;
    one.get().logits[0] = 1;

    const int64_t t_start = llama_time_us();
    int64_t t_first = 0;
    bool first_token = true;
    bool stopped = false;
    llama_token new_token_id = LLAMA_TOKEN_NULL;
    llama_pos n_past = 0;

    for (int32_t i = 0; i < params.max_tokens; i++) {
        if (stop_requested()) {
            stopped = true;
            break;
        }

        llama_batch * cur = (n_past == 0) ? &prompt_batch.get() : &one.get();

        int32_t rc = 0;
        {
            std::lock_guard<std::mutex> lock(state.decode_mutex());
            state.SetActiveStopFlag(stop_flag.get());
            rc = llama_decode(ctx, *cur);
            if (rc == 0) {
                new_token_id = llama_sampler_sample(smpl.get(), ctx, -1);
            }
            state.ClearActiveStopFlag();
        }

        if (rc != 0) {
            if (stop_requested()) {
                stopped = true;
                break;
            }
            return GenResult::Failed;
        }

        if (first_token) {
            t_first = llama_time_us();
            out_stats.ttft_ms = (t_first - t_start) / 1000.0;
            first_token = false;
        }

        if (llama_vocab_is_eog(vocab, new_token_id)) {
            break;
        }

        char piece[256] = {0};
        int32_t n = llama_token_to_piece(vocab, new_token_id, piece, static_cast<int32_t>(sizeof(piece)), 0, true);
        if (n > 0) {
            on_token(piece);
        }

        out_stats.generated_tokens++;

        llama_sampler_accept(smpl.get(), new_token_id);

        n_past += (n_past == 0) ? n_prompt : 1;
        one.get().token[0] = new_token_id;
        one.get().pos[0] = n_past;

        // 接近槽位上下文上限时滑动窗口（context shift），避免长对话被截断。
        // 借鉴 llama-server：seq_rm 丢弃中间一段，seq_add 把后续 token 位置前移。
        if (can_shift && slot_ctx > 0 && static_cast<llama_pos>(n_past) + 1 >= static_cast<llama_pos>(slot_ctx)) {
            const int n_left = static_cast<int>(n_past);
            int n_discard = std::max(1, n_left / 2);
            if (n_discard >= n_left) {
                n_discard = n_left - 1;
            }
            if (n_discard > 0) {
                std::lock_guard<std::mutex> lock(state.decode_mutex());
                llama_memory_seq_rm(mem, seq_id, 0, n_discard);
                llama_memory_seq_add(mem, seq_id, n_discard, n_past, -n_discard);
                n_past -= n_discard;
                one.get().pos[0] = n_past;
            }
        }
    }

    const int64_t t_end = llama_time_us();
    if (out_stats.generated_tokens > 0) {
        const double elapsed = static_cast<double>(t_end - t_start) / 1000000.0;
        out_stats.tokens_per_second = elapsed > 0.0 ? out_stats.generated_tokens / elapsed : 0.0;
    }

    return stopped ? GenResult::Aborted : GenResult::Completed;
}

} // namespace inference
