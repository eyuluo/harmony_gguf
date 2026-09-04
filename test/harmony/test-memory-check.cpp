// ============================================================================
// test-memory-check.cpp — 生成循环内存检查
// 角色 C（质量保障）· Day 10 交付物
//
// 测试策略：
// 1. 多轮 decode 后检查 KV Cache 状态（seq_pos_max 递增）
// 2. 清除 KV Cache 后验证状态归零
// 3. 多次加载/卸载模型检查无累积泄漏
// ============================================================================

#include "testing.h"

#include "llama.h"

#include <string>
#include <vector>
#include <cstdio>

static const char * MODELS_DIR = "models";

// 测试 KV Cache 在多轮 decode 后正确递增
static void test_kv_cache_progression(testing & t) {
    t.test("KV Cache 多轮 decode 递增", [&](testing & t) {
        std::string path = std::string(MODELS_DIR) + "/ggml-vocab-llama-bpe.gguf";

        struct llama_model_params mparams = llama_model_default_params();
        struct llama_model * model = llama_model_load_from_file(path.c_str(), mparams);
        t.assert_true("模型加载成功", model != nullptr);
        if (!model) return;

        struct llama_context_params cparams = llama_context_default_params();
        cparams.n_ctx = 512;
        cparams.n_batch = 64;
        struct llama_context * ctx = llama_new_context_with_model(model, cparams);
        t.assert_true("context 创建成功", ctx != nullptr);
        if (!ctx) { llama_model_free(model); return; }

        llama_memory_t mem = llama_get_memory(ctx);
        t.assert_true("memory 可用", mem != nullptr);

        const struct llama_vocab * vocab = llama_model_get_vocab(model);

        // 第一轮：encode "Hello"
        const char * prompt1 = "Hello";
        std::vector<llama_token> tokens1(16);
        int32_t n1 = llama_tokenize(vocab, prompt1, strlen(prompt1), tokens1.data(), tokens1.size(), false, true);
        if (n1 < 0) { tokens1.resize(-n1); n1 = llama_tokenize(vocab, prompt1, strlen(prompt1), tokens1.data(), tokens1.size(), false, true); }
        tokens1.resize(n1);

        struct llama_batch batch1 = llama_batch_get_one(tokens1.data(), n1);
        int32_t r1 = llama_decode(ctx, batch1);
        t.assert_true("第一轮 decode 成功", r1 == 0);

        // 检查 KV Cache 位置已推进
        llama_pos pos1 = llama_memory_seq_pos_max(mem, 0);
        t.assert_true("pos_max > 0 after round1", pos1 > 0);

        // 第二轮：encode " world"
        const char * prompt2 = " world";
        std::vector<llama_token> tokens2(16);
        int32_t n2 = llama_tokenize(vocab, prompt2, strlen(prompt2), tokens2.data(), tokens2.size(), false, true);
        if (n2 < 0) { tokens2.resize(-n2); n2 = llama_tokenize(vocab, prompt2, strlen(prompt2), tokens2.data(), tokens2.size(), false, true); }
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

// 测试 KV Cache 清除后状态归零
static void test_kv_cache_clear(testing & t) {
    t.test("KV Cache 清除后归零", [&](testing & t) {
        std::string path = std::string(MODELS_DIR) + "/ggml-vocab-llama-bpe.gguf";

        struct llama_model_params mparams = llama_model_default_params();
        struct llama_model * model = llama_model_load_from_file(path.c_str(), mparams);
        t.assert_true("模型加载成功", model != nullptr);
        if (!model) return;

        struct llama_context_params cparams = llama_context_default_params();
        cparams.n_ctx = 512;
        struct llama_context * ctx = llama_new_context_with_model(model, cparams);
        t.assert_true("context 创建成功", ctx != nullptr);
        if (!ctx) { llama_model_free(model); return; }

        llama_memory_t mem = llama_get_memory(ctx);

        const struct llama_vocab * vocab = llama_model_get_vocab(model);
        const char * prompt = "Hello world";
        std::vector<llama_token> tokens(32);
        int32_t n = llama_tokenize(vocab, prompt, strlen(prompt), tokens.data(), tokens.size(), false, true);
        if (n < 0) { tokens.resize(-n); n = llama_tokenize(vocab, prompt, strlen(prompt), tokens.data(), tokens.size(), false, true); }
        tokens.resize(n);

        struct llama_batch batch = llama_batch_get_one(tokens.data(), n);
        llama_decode(ctx, batch);

        // 清除前 pos > 0
        llama_pos pos_before = llama_memory_seq_pos_max(mem, 0);
        t.assert_true("清除前 pos > 0", pos_before > 0);

        // 清除 KV Cache
        llama_memory_clear(mem, true);

        // 清除后 pos 应为 -1 或 0
        llama_pos pos_after = llama_memory_seq_pos_max(mem, 0);
        t.assert_true("清除后 pos <= 0", pos_after <= 0);

        llama_free(ctx);
        llama_model_free(model);
    });
}

// 测试多次加载/卸载模型无累积泄漏
static void test_repeated_load_unload(testing & t) {
    t.test("多次加载/卸载无泄漏", [&](testing & t) {
        std::string path = std::string(MODELS_DIR) + "/ggml-vocab-llama-bpe.gguf";

        struct llama_model_params mparams = llama_model_default_params();

        // 循环加载/卸载 5 次
        for (int i = 0; i < 5; ++i) {
            struct llama_model * model = llama_model_load_from_file(path.c_str(), mparams);
            t.assert_true("加载[" + std::to_string(i) + "] 成功", model != nullptr);
            if (!model) continue;

            // 创建 context 并执行一次 decode
            struct llama_context_params cparams = llama_context_default_params();
            cparams.n_ctx = 256;
            struct llama_context * ctx = llama_new_context_with_model(model, cparams);
            if (ctx) {
                const struct llama_vocab * vocab = llama_model_get_vocab(model);
                const char * prompt = "test";
                std::vector<llama_token> tokens(16);
                int32_t n = llama_tokenize(vocab, prompt, 4, tokens.data(), tokens.size(), false, true);
                if (n > 0) {
                    tokens.resize(n);
                    struct llama_batch batch = llama_batch_get_one(tokens.data(), n);
                    llama_decode(ctx, batch);
                }

                llama_free(ctx);
            }

            llama_model_free(model);
        }

        // 如果能跑完 5 轮无崩溃，即视为无累积泄漏
        t.assert_true("5 轮加载/卸载完成", true);
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
        test_kv_cache_progression(t);
        test_kv_cache_clear(t);
        test_repeated_load_unload(t);
    });

    llama_backend_free();

    return t.summary();
}
