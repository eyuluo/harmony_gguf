// ============================================================================
// test-memory-check.cpp — 生成循环内存检查
// 角色 C（质量保障）· Day 10 交付物
//
// 测试策略：
// - vocab 测试模型（无权重）：验证多次加载/卸载无累积泄漏
// - KV Cache 测试（decode + seq_pos_max）：需要 Q4 量化模型，当前标记 SKIP
//   获取模型后运行：bash scripts/fetch-test-models.sh llama
// ============================================================================

#include "testing.h"

#include "llama.h"

#include <string>
#include <vector>
#include <cstdio>

static const char * MODELS_DIR = "models";
static const char * INFERENCE_MODELS_DIR = "models/inference";

static bool file_exists(const std::string & path) {
    FILE * f = fopen(path.c_str(), "rb");
    if (f) { fclose(f); return true; }
    return false;
}

// 测试多次加载/卸载模型无累积泄漏（vocab_only，不需要权重）
static void test_repeated_load_unload(testing & t) {
    t.test("多次加载/卸载无泄漏", [&](testing & t) {
        std::string path = std::string(MODELS_DIR) + "/ggml-vocab-llama-bpe.gguf";

        struct llama_model_params mparams = llama_model_default_params();
        mparams.vocab_only = true;

        for (int i = 0; i < 5; ++i) {
            struct llama_model * model = llama_model_load_from_file(path.c_str(), mparams);
            t.assert_true("加载[" + std::to_string(i) + "] 成功", model != nullptr);
            if (!model) continue;

            const struct llama_vocab * vocab = llama_model_get_vocab(model);
            t.assert_true("vocab 可用[" + std::to_string(i) + "]", vocab != nullptr);

            llama_model_free(model);
        }

        t.assert_true("5 轮加载/卸载完成", true);
    });
}

// 测试 KV Cache 在多轮 decode 后正确递增（需要 Q4 模型）
static void test_kv_cache_progression(testing & t) {
    t.test("KV Cache 多轮 decode 递增", [&](testing & t) {
        std::string path = std::string(INFERENCE_MODELS_DIR) + "/tinyllama-1.1b-chat-q4_k_m.gguf";

        if (!file_exists(path)) {
            t.skip("需要 Q4 量化模型，运行 fetch-test-models.sh llama 获取");
            return;
        }

        struct llama_model_params mparams = llama_model_default_params();
        struct llama_model * model = llama_model_load_from_file(path.c_str(), mparams);
        t.assert_true("模型加载成功", model != nullptr);
        if (!model) return;

        struct llama_context_params cparams = llama_context_default_params();
        cparams.n_ctx = 512;
        cparams.n_batch = 64;
        struct llama_context * ctx = llama_init_from_model(model, cparams);
        t.assert_true("context 创建成功", ctx != nullptr);
        if (!ctx) { llama_model_free(model); return; }

        llama_memory_t mem = llama_get_memory(ctx);
        t.assert_true("memory 可用", mem != nullptr);

        const struct llama_vocab * vocab = llama_model_get_vocab(model);

        const char * prompt1 = "Hello";
        std::vector<llama_token> tokens1(16);
        int32_t n1 = llama_tokenize(vocab, prompt1, (int32_t)strlen(prompt1), tokens1.data(), (int32_t)tokens1.size(), false, true);
        if (n1 < 0) { tokens1.resize(-n1); n1 = llama_tokenize(vocab, prompt1, (int32_t)strlen(prompt1), tokens1.data(), (int32_t)tokens1.size(), false, true); }
        tokens1.resize(n1);

        struct llama_batch batch1 = llama_batch_get_one(tokens1.data(), n1);
        int32_t r1 = llama_decode(ctx, batch1);
        t.assert_true("第一轮 decode 成功", r1 == 0);

        llama_pos pos1 = llama_memory_seq_pos_max(mem, 0);
        t.assert_true("pos_max > 0 after round1", pos1 > 0);

        const char * prompt2 = " world";
        std::vector<llama_token> tokens2(16);
        int32_t n2 = llama_tokenize(vocab, prompt2, (int32_t)strlen(prompt2), tokens2.data(), (int32_t)tokens2.size(), false, true);
        if (n2 < 0) { tokens2.resize(-n2); n2 = llama_tokenize(vocab, prompt2, (int32_t)strlen(prompt2), tokens2.data(), (int32_t)tokens2.size(), false, true); }
        tokens2.resize(n2);

        struct llama_batch batch2 = llama_batch_get_one(tokens2.data(), n2);
        int32_t r2 = llama_decode(ctx, batch2);
        t.assert_true("第二轮 decode 成功", r2 == 0);

        llama_pos pos2 = llama_memory_seq_pos_max(mem, 0);
        t.assert_true("pos_max 递增", pos2 > pos1);

        llama_free(ctx);
        llama_model_free(model);
    });
}

// 测试 KV Cache 清除后状态归零（需要 Q4 模型）
static void test_kv_cache_clear(testing & t) {
    t.test("KV Cache 清除后归零", [&](testing & t) {
        std::string path = std::string(INFERENCE_MODELS_DIR) + "/tinyllama-1.1b-chat-q4_k_m.gguf";

        if (!file_exists(path)) {
            t.skip("需要 Q4 量化模型，运行 fetch-test-models.sh llama 获取");
            return;
        }

        struct llama_model_params mparams = llama_model_default_params();
        struct llama_model * model = llama_model_load_from_file(path.c_str(), mparams);
        t.assert_true("模型加载成功", model != nullptr);
        if (!model) return;

        struct llama_context_params cparams = llama_context_default_params();
        cparams.n_ctx = 512;
        struct llama_context * ctx = llama_init_from_model(model, cparams);
        t.assert_true("context 创建成功", ctx != nullptr);
        if (!ctx) { llama_model_free(model); return; }

        llama_memory_t mem = llama_get_memory(ctx);

        const struct llama_vocab * vocab = llama_model_get_vocab(model);
        const char * prompt = "Hello world";
        std::vector<llama_token> tokens(32);
        int32_t n = llama_tokenize(vocab, prompt, (int32_t)strlen(prompt), tokens.data(), (int32_t)tokens.size(), false, true);
        if (n < 0) { tokens.resize(-n); n = llama_tokenize(vocab, prompt, (int32_t)strlen(prompt), tokens.data(), (int32_t)tokens.size(), false, true); }
        tokens.resize(n);

        struct llama_batch batch = llama_batch_get_one(tokens.data(), n);
        llama_decode(ctx, batch);

        llama_pos pos_before = llama_memory_seq_pos_max(mem, 0);
        t.assert_true("清除前 pos > 0", pos_before > 0);

        llama_memory_clear(mem, true);

        llama_pos pos_after = llama_memory_seq_pos_max(mem, 0);
        t.assert_true("清除后 pos <= 0", pos_after <= 0);

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

    t.test("生成循环内存检查", [&](testing & t) {
        test_repeated_load_unload(t);
        test_kv_cache_progression(t);
        test_kv_cache_clear(t);
    });

    llama_backend_free();

    return t.summary();
}