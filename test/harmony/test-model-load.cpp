// ============================================================================
// test-model-load.cpp — 模型加载冒烟测试
// 角色 C（质量保障）· Day 5-6 交付物
//
// 测试策略：使用 llama API 加载 vocab 测试模型，验证模型指针非空、
// vocab 可用、token 数量合理。不执行推理，仅验证加载链路。
// ============================================================================

#include "testing.h"

#include "llama.h"

#include <string>
#include <cstdio>

static const char * MODELS_DIR = "models";

static struct llama_model * load_model(const std::string & filename) {
    std::string path = std::string(MODELS_DIR) + "/" + filename;
    struct llama_model_params params = llama_model_default_params();
    params.n_gpu_layers = 0; // 仅 CPU
    params.vocab_only = true; // vocab 测试模型无权重，仅加载词表
    return llama_model_load_from_file(path.c_str(), params);
}

static void test_load_llama_bpe(testing & t) {
    t.test("加载 llama-bpe 模型", [&](testing & t) {
        struct llama_model * model = load_model("ggml-vocab-llama-bpe.gguf");
        t.assert_true("模型加载成功", model != nullptr);
        if (!model) return;

        const struct llama_vocab * vocab = llama_model_get_vocab(model);
        t.assert_true("vocab 可用", vocab != nullptr);
        if (vocab) {
            int32_t n_tokens = llama_vocab_n_tokens(vocab);
            t.assert_true("n_tokens > 0", n_tokens > 0);
        }

        llama_model_free(model);
    });
}

static void test_load_qwen2(testing & t) {
    t.test("加载 qwen2 模型", [&](testing & t) {
        struct llama_model * model = load_model("ggml-vocab-qwen2.gguf");
        t.assert_true("模型加载成功", model != nullptr);
        if (!model) return;

        const struct llama_vocab * vocab = llama_model_get_vocab(model);
        t.assert_true("vocab 可用", vocab != nullptr);

        llama_model_free(model);
    });
}

static void test_load_gemma(testing & t) {
    t.test("加载 gemma 模型", [&](testing & t) {
        struct llama_model * model = load_model("ggml-vocab-gemma-4.gguf");
        t.assert_true("模型加载成功", model != nullptr);
        if (!model) return;

        const struct llama_vocab * vocab = llama_model_get_vocab(model);
        t.assert_true("vocab 可用", vocab != nullptr);

        llama_model_free(model);
    });
}

static void test_load_deepseek(testing & t) {
    t.test("加载 deepseek-coder 模型", [&](testing & t) {
        struct llama_model * model = load_model("ggml-vocab-deepseek-coder.gguf");
        t.assert_true("模型加载成功", model != nullptr);
        if (!model) return;

        const struct llama_vocab * vocab = llama_model_get_vocab(model);
        t.assert_true("vocab 可用", vocab != nullptr);

        llama_model_free(model);
    });
}

static void test_load_nonexistent(testing & t) {
    t.test("加载不存在的文件返回空", [&](testing & t) {
        struct llama_model_params params = llama_model_default_params();
        struct llama_model * model = llama_model_load_from_file("nonexistent.gguf", params);
        t.assert_true("模型加载失败(预期)", model == nullptr);
    });
}

// ----------------------------------------------------------------------------
// 主函数
// ----------------------------------------------------------------------------

int main(int argc, char ** argv) {
    // 初始化 llama 后端
    llama_backend_init();

    testing t;

    if (argc > 1) {
        t.set_filter(argv[1]);
    }

    t.test("模型加载冒烟", [&](testing & t) {
        test_load_llama_bpe(t);
        test_load_qwen2(t);
        test_load_gemma(t);
        test_load_deepseek(t);
        test_load_nonexistent(t);
    });

    llama_backend_free();

    return t.summary();
}
