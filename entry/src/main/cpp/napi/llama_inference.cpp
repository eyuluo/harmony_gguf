#include "llama_inference.h"

#include <cstdint>
#include <vector>

#include "engine_state.h"
#include "llama.h"

namespace inference {

GenResult RunGeneration(
    const GenerateParams & params,
    const std::function<void(const char * text)> & on_token,
    const std::function<bool()> & should_stop,
    GenerateStats & out_stats) {

    llama_model * model = EngineState::Instance().model();
    llama_context * ctx = EngineState::Instance().ctx();
    const llama_vocab * vocab = EngineState::Instance().vocab();

    if (model == nullptr || ctx == nullptr || vocab == nullptr) {
        return GenResult::Failed;
    }

    if (params.threads > 0) {
        llama_set_n_threads(ctx, params.threads, params.threads);
    }

    // 采样链：penalties -> top_k -> temp -> top_p -> dist
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    llama_sampler * smpl = llama_sampler_chain_init(sparams);

    const int32_t n_vocab = llama_vocab_n_tokens(vocab);
    llama_sampler_chain_add(smpl, llama_sampler_init_penalties(n_vocab, 64, params.repeat_penalty, 0.0f, 0.0f));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_k(params.top_k));
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(params.temperature));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(params.top_p, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(static_cast<uint32_t>(llama_time_us())));

    // 分词
    const int32_t n_prompt = -llama_tokenize(vocab, params.prompt.c_str(), static_cast<int32_t>(params.prompt.size()),
                                             nullptr, 0, true, true);
    if (n_prompt <= 0) {
        llama_sampler_free(smpl);
        return GenResult::Failed;
    }

    std::vector<llama_token> prompt_tokens(static_cast<size_t>(n_prompt));
    if (llama_tokenize(vocab, params.prompt.c_str(), static_cast<int32_t>(params.prompt.size()),
                       prompt_tokens.data(), n_prompt, true, true) < 0) {
        llama_sampler_free(smpl);
        return GenResult::Failed;
    }

    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()));

    out_stats.prompt_tokens = n_prompt;

    const int64_t t_start = llama_time_us();
    int64_t t_first = 0;
    bool first_token = true;
    bool stopped = false;
    llama_token new_token_id = LLAMA_TOKEN_NULL;

    for (int32_t i = 0; i < params.max_tokens; i++) {
        if (should_stop()) {
            stopped = true;
            break;
        }

        if (llama_decode(ctx, batch) != 0) {
            if (should_stop()) {
                stopped = true;
                break;
            }
            llama_sampler_free(smpl);
            return GenResult::Failed;
        }

        new_token_id = llama_sampler_sample(smpl, ctx, -1);

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

        llama_sampler_accept(smpl, new_token_id);
        batch = llama_batch_get_one(&new_token_id, 1);
    }

    const int64_t t_end = llama_time_us();
    if (out_stats.generated_tokens > 0) {
        const double elapsed = static_cast<double>(t_end - t_start) / 1000000.0;
        out_stats.tokens_per_second = elapsed > 0.0 ? out_stats.generated_tokens / elapsed : 0.0;
    }

    llama_sampler_free(smpl);
    return stopped ? GenResult::Aborted : GenResult::Completed;
}

} // namespace inference
