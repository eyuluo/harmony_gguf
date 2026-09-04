// ============================================================================
// test-smoke-generate.cpp — 主路径冒烟测试：加载→前向→采样→解码
// 角色 C（质量保障）· Day 7-8 交付物
//
// 测试策略：
// - vocab 测试模型（无权重）：验证加载 + tokenize + token_to_piece
// - 推理冒烟（decode + sample）：需要 Q4 量化模型，当前标记 SKIP
//   获取模型后运行：bash scripts/fetch-test-models.sh llama
//   然后切换 INFERENCE_MODELS_DIR 指向 test/models/inference/
// ============================================================================

#include "testing.h"

#include "llama.h"

#include <string>
#include <vector>
#include <cstdio>

static const char * MODELS_DIR = "models";
static const char * INFERENCE_MODELS_DIR = "models/inference";

// 检查文件是否存在
static bool file_exists(const std::string & path) {
    FILE * f = fopen(path.c_str(), "rb");
    if (f) { fclose(f); return true; }
    return false;
}

// vocab 冒烟：加载模型 + tokenize + token_to_piece（不需要权重）
static void vocab_smoke(testing & t, const std::string & filename, const std::string & label) {
    t.test(label + " vocab 冒烟", [&](testing & t) {
        std::string path = std::string(MODELS_DIR) + "/" + filename;

        // 1. 加载模型（vocab_only）
        struct llama_model_params mparams = llama_model_default_params();
        mparams.n_gpu_layers = 0;
        mparams.vocab_only = true;
        struct llama_model * model = llama_model_load_from_file(path.c_str(), mparams);
        t.assert_true("模型加载成功", model != nullptr);
        if (!model) return;

        // 2. 获取 vocab
        const struct llama_vocab * vocab = llama_model_get_vocab(model);
        t.assert_true("vocab 可用", vocab != nullptr);
        if (!vocab) { llama_model_free(model); return; }

        // 3. tokenize
        const char * prompt = "Hello";
        std::vector<llama_token> tokens(32);
        int32_t n_tokens = llama_tokenize(vocab, prompt, (int32_t)strlen(prompt), tokens.data(), (int32_t)tokens.size(), false, true);
        if (n_tokens < 0) {
            tokens.resize(-n_tokens);
            n_tokens = llama_tokenize(vocab, prompt, (int32_t)strlen(prompt), tokens.data(), (int32_t)tokens.size(), false, true);
        }
        t.assert_true("tokenize 成功", n_tokens > 0);

        // 4. token_to_piece 解码
        if (n_tokens > 0) {
            char buf[64] = {0};
            int32_t n = llama_token_to_piece(vocab, tokens[0], buf, sizeof(buf), 0, true);
            t.assert_true("token_to_piece 成功", n > 0);
        }

        llama_model_free(model);
    });
}

// 推理冒烟：加载 Q4 模型 → 创建 context → 前向 → 采样 → 解码
static void inference_smoke(testing & t, const std::string & filename, const std::string & label) {
    t.test(label + " 推理冒烟", [&](testing & t) {
        std::string path = std::string(INFERENCE_MODELS_DIR) + "/" + filename;

        if (!file_exists(path)) {
            t.skip("需要 Q4 量化模型，运行 fetch-test-models.sh 获取");
            return;
        }

        // 1. 加载模型（含权重）
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
        struct llama_context * ctx = llama_init_from_model(model, cparams);
        t.assert_true("context 创建成功", ctx != nullptr);
        if (!ctx) { llama_model_free(model); return; }

        // 3. tokenize
        const struct llama_vocab * vocab = llama_model_get_vocab(model);
        t.assert_true("vocab 可用", vocab != nullptr);
        if (!vocab) { llama_free(ctx); llama_model_free(model); return; }

        const char * prompt = "Hello";
        std::vector<llama_token> tokens(32);
        int32_t n_tokens = llama_tokenize(vocab, prompt, (int32_t)strlen(prompt), tokens.data(), (int32_t)tokens.size(), false, true);
        if (n_tokens < 0) {
            tokens.resize(-n_tokens);
            n_tokens = llama_tokenize(vocab, prompt, (int32_t)strlen(prompt), tokens.data(), (int32_t)tokens.size(), false, true);
        }
        t.assert_true("tokenize 成功", n_tokens > 0);
        if (n_tokens <= 0) { llama_free(ctx); llama_model_free(model); return; }
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

            if (token >= 0) {
                char buf[64] = {0};
                int32_t n = llama_token_to_piece(vocab, token, buf, sizeof(buf), 0, true);
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
        // vocab 冒烟（使用 vocab 测试模型，无需权重）
        vocab_smoke(t, "ggml-vocab-llama-bpe.gguf", "llama-bpe");
        vocab_smoke(t, "ggml-vocab-qwen2.gguf", "qwen2");

        // 推理冒烟（需要 Q4 量化模型，当前自动 SKIP）
        inference_smoke(t, "tinyllama-1.1b-chat-q4_k_m.gguf", "tinyllama");
        inference_smoke(t, "qwen2-0.5b-instruct-q4_k_m.gguf", "qwen2");
    });

    llama_backend_free();

    return t.summary();
}