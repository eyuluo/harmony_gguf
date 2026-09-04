// ============================================================================
// test-smoke-generate.cpp — 主路径冒烟测试：加载→前向→采样→解码
// 角色 C（质量保障）· Day 7-8 交付物
//
// 测试策略：加载 vocab 测试模型，执行一次前向推理 + 采样，验证：
// 1. context 创建成功
// 2. llama_decode 返回成功
// 3. logits 非空
// 4. 采样得到有效 token id
// 5. token 可解码为文本
// ============================================================================

#include "testing.h"

#include "llama.h"

#include <string>
#include <vector>
#include <cstdio>
#include <chrono>

static const char * MODELS_DIR = "models";

// 完整的生成冒烟：加载模型 → 创建 context → 前向 → 采样 → 解码
static void smoke_generate(testing & t, const std::string & filename, const std::string & label) {
    t.test(label + " 生成冒烟", [&](testing & t) {
        std::string path = std::string(MODELS_DIR) + "/" + filename;

        // 1. 加载模型
        struct llama_model_params mparams = llama_model_default_params();
        mparams.n_gpu_layers = 0;
        struct llama_model * model = llama_model_load_from_file(path.c_str(), mparams);
        t.assert_true("模型加载成功", model != nullptr);
        if (!model) return;

        // 2. 创建 context
        struct llama_context_params cparams = llama_context_default_params();
        cparams.n_ctx = 512;
        cparams.n_batch = 512;
        cparams.n_threads = 2;
        cparams.n_threads_batch = 2;
        struct llama_context * ctx = llama_new_context_with_model(model, cparams);
        t.assert_true("context 创建成功", ctx != nullptr);
        if (!ctx) {
            llama_model_free(model);
            return;
        }

        // 3. tokenize 一个简单 prompt
        const struct llama_vocab * vocab = llama_model_get_vocab(model);
        t.assert_true("vocab 可用", vocab != nullptr);
        if (!vocab) {
            llama_free(ctx);
            llama_model_free(model);
            return;
        }

        const char * prompt = "Hello";
        std::vector<llama_token> tokens(32);
        int32_t n_tokens = llama_tokenize(vocab, prompt, strlen(prompt), tokens.data(), tokens.size(), false, true);
        if (n_tokens < 0) {
            tokens.resize(-n_tokens);
            n_tokens = llama_tokenize(vocab, prompt, strlen(prompt), tokens.data(), tokens.size(), false, true);
        }
        t.assert_true("tokenize 成功", n_tokens > 0);
        if (n_tokens <= 0) {
            llama_free(ctx);
            llama_model_free(model);
            return;
        }
        tokens.resize(n_tokens);

        // 4. 前向推理
        struct llama_batch batch = llama_batch_get_one(tokens.data(), n_tokens);
        int32_t decode_result = llama_decode(ctx, batch);
        t.assert_true("llama_decode 成功", decode_result == 0);

        // 5. 获取 logits
        float * logits = llama_get_logits(ctx);
        t.assert_true("logits 非空", logits != nullptr);

        // 6. 采样
        if (logits) {
            struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
            struct llama_sampler * sampler = llama_sampler_chain_init(sparams);
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.8f));
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(42));

            llama_token token = llama_sampler_sample(sampler, ctx, -1);
            t.assert_true("采样 token >= 0", token >= 0);

            // 7. 解码 token 为文本
            if (token >= 0) {
                char buf[64] = {0};
                int32_t n = llama_token_to_piece(vocab, token, buf, sizeof(buf), 0, true, nullptr);
                t.assert_true("token_to_piece 成功", n > 0);
            }

            llama_sampler_free(sampler);
        }

        llama_free(ctx);
        llama_model_free(model);
    });
}

// ----------------------------------------------------------------------------
// 主函数
// ----------------------------------------------------------------------------

int main(int argc, char ** argv) {
    llama_backend_init();

    testing t;

    if (argc > 1) {
        t.set_filter(argv[1]);
    }

    t.test("主路径生成冒烟", [&](testing & t) {
        smoke_generate(t, "ggml-vocab-llama-bpe.gguf", "llama-bpe");
        smoke_generate(t, "ggml-vocab-qwen2.gguf", "qwen2");
    });

    llama_backend_free();

    return t.summary();
}
