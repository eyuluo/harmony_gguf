#include "llama_inference.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "engine_state.h"
#include "prompt_cache.h"
#include "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include "stb/stb_image.h"

namespace inference {

namespace {

// 为 batch 中 n 个 token 设置 seq_id 与显式 pos；最后一个 token 输出 logits（供采样）。
void FillBatchSeq(llama_batch & batch, llama_seq_id seq_id, int32_t n, llama_pos pos_start, bool last_logits) {
    batch.n_tokens = n;
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
    explicit BatchGuard(int32_t n_tokens)
        : batch_(llama_batch_init(n_tokens, 0, 1)), n_tokens_(n_tokens) {}
    ~BatchGuard() { llama_batch_free(batch_); }
    BatchGuard(const BatchGuard &) = delete;
    BatchGuard & operator=(const BatchGuard &) = delete;
    bool valid() const {
        return batch_.token != nullptr && batch_.pos != nullptr &&
            batch_.n_seq_id != nullptr && batch_.seq_id != nullptr &&
            batch_.logits != nullptr && [&]() {
                for (int32_t i = 0; i < n_tokens_; i++) {
                    if (batch_.seq_id[i] == nullptr) {
                        return false;
                    }
                }
                return true;
            }();
    }
    llama_batch & get() { return batch_; }

private:
    llama_batch batch_;
    int32_t n_tokens_;
};

class ActiveStopGuard {
public:
    ActiveStopGuard(EngineState & state, const std::atomic_bool * flag)
        : state_(state) {
        state_.SetActiveStopFlag(flag);
    }

    ~ActiveStopGuard() {
        state_.ClearActiveStopFlag();
    }

    ActiveStopGuard(const ActiveStopGuard &) = delete;
    ActiveStopGuard & operator=(const ActiveStopGuard &) = delete;

private:
    EngineState & state_;
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

    const int64_t t_start = llama_time_us();
    int64_t t_first = 0;
    bool first_token = true;
    bool stopped = false;
    int64_t decode_us = 0;
    int32_t decode_steps = 0;
    llama_token new_token_id = LLAMA_TOKEN_NULL;

    const uint32_t slot_ctx = state.slot_context();
    llama_memory_t mem = llama_get_memory(ctx);
    const bool can_shift = mem != nullptr && llama_memory_can_shift(mem);

    int32_t n_prompt = 0;
    llama_pos n_past = 0;
    std::vector<llama_token> evaluated_tokens;
    bool cache_valid = params.images.empty() && mem != nullptr && llama_memory_can_shift(mem);

    if (!params.images.empty()) {
        {
            std::lock_guard<std::mutex> lock(state.decode_mutex());
            state.cached_tokens(seq_id).clear();
            if (mem != nullptr && !llama_memory_seq_rm(mem, seq_id, -1, -1)) {
                return GenResult::Failed;
            }
        }
        // === 多模态：mtmd tokenize + 逐 chunk decode（prompt 含图片）===
        mtmd_context * mctx = state.mtmd_ctx();
        if (mctx == nullptr) {
            out_stats.error_message = "未加载可用的视觉投影器，请加载匹配的 mmproj";
            return GenResult::Failed;
        }

        using BitmapPtr = std::unique_ptr<mtmd_bitmap, decltype(&mtmd_bitmap_free)>;
        std::vector<BitmapPtr> bitmap_storage;
        std::vector<const mtmd_bitmap *> bitmaps;
        bitmaps.reserve(params.images.size());
        for (const auto & path : params.images) {
            if (stop_requested()) {
                return GenResult::Aborted;
            }
            int nx = 0;
            int ny = 0;
            int nc = 0;
            std::unique_ptr<unsigned char, decltype(&stbi_image_free)> data(
                stbi_load(path.c_str(), &nx, &ny, &nc, 3), stbi_image_free);
            if (data == nullptr) {
                return GenResult::Failed;
            }
            bitmap_storage.emplace_back(mtmd_bitmap_init(static_cast<uint32_t>(nx),
                static_cast<uint32_t>(ny), data.get()), mtmd_bitmap_free);
            if (!bitmap_storage.back()) {
                return GenResult::Failed;
            }
            bitmaps.push_back(bitmap_storage.back().get());
        }

        // prompt 未含媒体标记时，在最前为每张图片补一个标记
        std::string prompt = params.prompt;
        if (prompt.find(mtmd_default_marker()) == std::string::npos) {
            std::string prefix;
            for (size_t i = 0; i < bitmaps.size(); i++) {
                prefix += mtmd_default_marker();
            }
            prompt = prefix + prompt;
        }

        mtmd_input_text text{ prompt.c_str(), prompt.size(), true, true };
        std::unique_ptr<mtmd_input_chunks, decltype(&mtmd_input_chunks_free)> chunks(
            mtmd_input_chunks_init(), mtmd_input_chunks_free);
        std::unique_lock<std::mutex> mtmd_lock(state.mtmd_mutex());
        if (stop_requested()) {
            return GenResult::Aborted;
        }
        int32_t res = mtmd_tokenize(mctx, chunks.get(), &text, bitmaps.data(), bitmaps.size());
        if (res != 0) {
            return GenResult::Failed;
        }

        out_stats.prompt_tokens = static_cast<int32_t>(mtmd_helper_get_n_tokens(chunks.get()));
        if (slot_ctx > 0 && mtmd_helper_get_n_pos(chunks.get()) > static_cast<llama_pos>(slot_ctx)) {
            out_stats.error_message = "图片与文字超过加载上下文，请降低图片 token 上限、减少图片或提高上下文长度";
            return GenResult::Failed;
        }
        const int64_t t_prepared = llama_time_us();
        int64_t encode_us = 0;
        int64_t decode_us = 0;

        const int32_t n_batch = static_cast<int32_t>(llama_n_batch(ctx));
        const size_t n_chunks = mtmd_input_chunks_size(chunks.get());
        if (n_batch <= 0 || n_chunks == 0) {
            return GenResult::Failed;
        }
        for (size_t i = 0; i < n_chunks; ++i) {
            if (stop_requested()) {
                return GenResult::Aborted;
            }
            const auto * chunk = mtmd_input_chunks_get(chunks.get(), i);
            const bool is_text = mtmd_input_chunk_get_type(chunk) == MTMD_INPUT_CHUNK_TYPE_TEXT;
            const bool is_last = i + 1 == n_chunks;
            if (!is_text) {
                const int64_t t_encode = llama_time_us();
                res = mtmd_encode_chunk(mctx, chunk);
                encode_us += llama_time_us() - t_encode;
                if (res != 0) {
                    return stop_requested() ? GenResult::Aborted : GenResult::Failed;
                }
            }
            if (stop_requested()) {
                return GenResult::Aborted;
            }
            const int64_t t_decode = llama_time_us();
            {
                std::lock_guard<std::mutex> lock(state.decode_mutex());
                ActiveStopGuard active_stop(state, stop_flag.get());
                if (is_text) {
                    res = mtmd_helper_eval_chunk_single(mctx, ctx, chunk, n_past, seq_id,
                        n_batch, is_last, &n_past);
                } else {
                    res = mtmd_helper_decode_image_chunk(mctx, ctx, chunk, mtmd_get_output_embd(mctx),
                        n_past, seq_id, n_batch, &n_past, nullptr, nullptr);
                }
                if (res == 0 && is_last && is_text) {
                    new_token_id = llama_sampler_sample(smpl.get(), ctx, -1);
                }
            }
            decode_us += llama_time_us() - t_decode;
            if (res != 0) {
                return stop_requested() ? GenResult::Aborted : GenResult::Failed;
            }
        }
        if (new_token_id == LLAMA_TOKEN_NULL) {
            return GenResult::Failed;
        }
        fprintf(stderr, "[Harmony-GGUF] 多模态输入：%d tokens，准备 %.1f ms，视觉编码 %.1f ms，prefill（含等待） %.1f ms\n",
            out_stats.prompt_tokens, (t_prepared - t_start) / 1000.0, encode_us / 1000.0, decode_us / 1000.0);
    } else {
        // === 纯文本：tokenize + 一次性 decode prompt（pos 0..n_prompt-1）===
        n_prompt = -llama_tokenize(vocab, params.prompt.c_str(), static_cast<int32_t>(params.prompt.size()),
                                   nullptr, 0, true, true);
        if (n_prompt <= 0) {
            out_stats.error_message = "输入分词失败或输入为空";
            return GenResult::Failed;
        }

        std::vector<llama_token> prompt_tokens(static_cast<size_t>(n_prompt));
        if (llama_tokenize(vocab, params.prompt.c_str(), static_cast<int32_t>(params.prompt.size()),
                           prompt_tokens.data(), n_prompt, true, true) < 0) {
            return GenResult::Failed;
        }

        if (FitPromptContext(prompt_tokens, slot_ctx)) {
            n_prompt = static_cast<int32_t>(prompt_tokens.size());
            fprintf(stderr, "[Harmony-GGUF] 历史超过上下文，保留首 token 与最近 %d tokens\n", n_prompt - 1);
        }
        if (slot_ctx <= 1 || static_cast<uint32_t>(n_prompt) >= slot_ctx) {
            out_stats.error_message = "加载上下文过小，无法为输入与生成提供空间";
            return GenResult::Failed;
        }

        out_stats.prompt_tokens = n_prompt;
        int32_t reuse = 0;
        {
            std::lock_guard<std::mutex> lock(state.decode_mutex());
            auto & cached = state.cached_tokens(seq_id);
            if (cache_valid) {
                reuse = static_cast<int32_t>(ReusablePromptTokens(cached, prompt_tokens));
            }
            if (mem != nullptr) {
                if (reuse == 0 || !llama_memory_seq_rm(mem, seq_id, reuse, -1)) {
                    reuse = 0;
                    if (!llama_memory_seq_rm(mem, seq_id, -1, -1)) {
                        cached.clear();
                        return GenResult::Failed;
                    }
                }
            }
            cached.clear();
        }
        const int64_t t_prefill = llama_time_us();

        const int32_t n_batch = static_cast<int32_t>(llama_n_batch(ctx));
        if (n_batch <= 0) {
            return GenResult::Failed;
        }
        BatchGuard prompt_batch(std::min(n_batch, n_prompt - reuse));
        if (!prompt_batch.valid()) {
            return GenResult::Failed;
        }
        for (int32_t offset = reuse; offset < n_prompt;) {
            if (stop_requested()) {
                return GenResult::Aborted;
            }
            const int32_t count = std::min(n_batch, n_prompt - offset);
            for (int32_t i = 0; i < count; i++) {
                prompt_batch.get().token[i] = prompt_tokens[static_cast<size_t>(offset + i)];
            }
            FillBatchSeq(prompt_batch.get(), seq_id, count, offset, offset + count == n_prompt);

            {
                std::lock_guard<std::mutex> lock(state.decode_mutex());
                ActiveStopGuard active_stop(state, stop_flag.get());
                const int32_t rc = llama_decode(ctx, prompt_batch.get());
                if (rc != 0) {
                    if (stop_requested()) {
                        return GenResult::Aborted;
                    }
                    return GenResult::Failed;
                }
                if (offset + count == n_prompt) {
                    new_token_id = llama_sampler_sample(smpl.get(), ctx, -1);
                }
            }
            offset += count;
        }
        n_past = n_prompt;
        fprintf(stderr, "[Harmony-GGUF] 文本 prefill：总 %d tokens，复用 %d，计算 %d，耗时 %.1f ms\n",
            n_prompt, reuse, n_prompt - reuse, (llama_time_us() - t_prefill) / 1000.0);
        if (cache_valid) {
            evaluated_tokens = std::move(prompt_tokens);
            evaluated_tokens.reserve(evaluated_tokens.size() +
                std::min(static_cast<size_t>(params.max_tokens), static_cast<size_t>(slot_ctx - n_prompt)));
        }
    }

    // 单 token batch：生成循环复用。prompt / 多模态 chunks decode 后已经产出首个 logits，
    // 因此循环必须先采样，再把采样 token decode 成下一步 logits。
    BatchGuard one(1);
    if (!one.valid()) {
        return GenResult::Failed;
    }
    one.get().n_tokens = 1;
    one.get().n_seq_id[0] = 1;
    one.get().seq_id[0][0] = seq_id;
    one.get().logits[0] = 1;
    std::vector<char> piece(256);

    for (int32_t i = 0; i < params.max_tokens; i++) {
        if (stop_requested()) {
            stopped = true;
            break;
        }

        if (first_token) {
            t_first = llama_time_us();
            out_stats.ttft_ms = (t_first - t_start) / 1000.0;
            first_token = false;
        }

        if (llama_vocab_is_eog(vocab, new_token_id)) {
            break;
        }

        int32_t n = llama_token_to_piece(vocab, new_token_id, piece.data(), static_cast<int32_t>(piece.size() - 1), 0, true);
        if (n < 0) {
            piece.resize(static_cast<size_t>(-n) + 1);
            n = llama_token_to_piece(vocab, new_token_id, piece.data(), static_cast<int32_t>(piece.size() - 1), 0, true);
        }
        if (n > 0) {
            piece[static_cast<size_t>(n)] = '\0';
            on_token(piece.data());
        }

        out_stats.generated_tokens++;

        llama_sampler_accept(smpl.get(), new_token_id);

        if (i + 1 >= params.max_tokens) {
            break;
        }
        if (!can_shift && slot_ctx > 0 && n_past >= static_cast<llama_pos>(slot_ctx)) {
            break;
        }

        one.get().token[0] = new_token_id;
        one.get().pos[0] = n_past;
        int32_t rc = 0;
        const int64_t t_decode = llama_time_us();
        {
            std::lock_guard<std::mutex> lock(state.decode_mutex());
            ActiveStopGuard active_stop(state, stop_flag.get());
            rc = llama_decode(ctx, one.get());
            if (rc == 0) {
                new_token_id = llama_sampler_sample(smpl.get(), ctx, -1);
            }
        }
        decode_us += llama_time_us() - t_decode;
        ++decode_steps;
        if (rc != 0) {
            if (stop_requested()) {
                stopped = true;
                break;
            }
            return GenResult::Failed;
        }
        n_past += 1;
        if (cache_valid) {
            evaluated_tokens.push_back(one.get().token[0]);
        }

        // 接近槽位上下文上限时滑动窗口（context shift），避免长对话被截断。
        // 借鉴 llama-server：seq_rm 丢弃中间一段，seq_add 把后续 token 位置前移。
        if (can_shift && slot_ctx > 0 && static_cast<llama_pos>(n_past) + 1 >= static_cast<llama_pos>(slot_ctx)) {
            const int n_left = static_cast<int>(n_past);
            int n_discard = std::max(1, n_left / 2);
            if (n_discard >= n_left) {
                n_discard = n_left - 1;
            }
            if (n_discard > 0) {
                cache_valid = false;
                std::lock_guard<std::mutex> lock(state.decode_mutex());
                llama_memory_seq_rm(mem, seq_id, 0, n_discard);
                llama_memory_seq_add(mem, seq_id, n_discard, n_past, -n_discard);
                n_past -= n_discard;
                one.get().pos[0] = n_past;
            }
        }
    }

    const int64_t t_end = llama_time_us();
    fprintf(stderr, "[Harmony-GGUF] decode：%d 步，计算与等待 %.1f ms，%.2f tokens/s\n",
        decode_steps, decode_us / 1000.0, decode_us > 0 ? decode_steps * 1000000.0 / decode_us : 0.0);
    if (!stopped && cache_valid) {
        std::lock_guard<std::mutex> lock(state.decode_mutex());
        state.cached_tokens(seq_id) = std::move(evaluated_tokens);
    }
    if (out_stats.generated_tokens > 0) {
        const double elapsed = static_cast<double>(t_end - t_start) / 1000000.0;
        out_stats.tokens_per_second = elapsed > 0.0 ? out_stats.generated_tokens / elapsed : 0.0;
    }

    return stopped ? GenResult::Aborted : GenResult::Completed;
}

bool RunGenerationAsync(
    uint64_t request_id,
    llama_seq_id seq_id,
    const std::shared_ptr<std::atomic_bool> & stop_flag,
    const GenerateParams & params,
    const std::function<void(const char * text)> & on_token,
    const std::function<void(GenResult, const GenerateStats &)> & on_done,
    const std::function<bool()> & should_stop) {

    auto run = [request_id, seq_id, stop_flag, params, on_token, on_done, should_stop]() {
        GenerateStats stats;
        GenResult result = GenResult::Failed;
        try {
            result = RunGeneration(seq_id, stop_flag, params, on_token, should_stop, stats);
        } catch (...) {
            result = GenResult::Failed;
        }
        EngineState::Instance().EndGenerate(request_id, seq_id);
        try {
            on_done(result, stats);
        } catch (...) {
        }
    };

    try {
        std::thread t(run);
        t.detach();
    } catch (...) {
        return false;
    }
    return true;
}

} // namespace inference
