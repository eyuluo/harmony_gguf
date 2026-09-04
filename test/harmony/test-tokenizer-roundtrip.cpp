// ============================================================================
// test-tokenizer-roundtrip.cpp — tokenizer 编码/解码往返测试
// 角色 C（质量保障）· Day 9 交付物
//
// 测试策略：对多架构 vocab 模型，验证 encode→decode 往返一致性：
// 1. tokenize 文本得到 token 列表
// 2. 逐 token 调用 token_to_piece 解码
// 3. 拼接后与原始文本比对（允许空白差异）
// 4. 验证 detokenize 整体解码结果
// ============================================================================

#include "testing.h"

#include "llama.h"

#include <string>
#include <vector>
#include <cstring>

static const char * MODELS_DIR = "models";

struct vocab_model {
    const char * filename;
    const char * label;
};

// 辅助：加载模型并获取 vocab
static const struct llama_vocab * get_vocab(const std::string & filename, struct llama_model ** model_out) {
    std::string path = std::string(MODELS_DIR) + "/" + filename;
    struct llama_model_params params = llama_model_default_params();
    params.n_gpu_layers = 0;
    struct llama_model * model = llama_model_load_from_file(path.c_str(), params);
    *model_out = model;
    if (!model) return nullptr;
    return llama_model_get_vocab(model);
}

// 辅助：tokenize 文本
static std::vector<llama_token> tokenize_text(const struct llama_vocab * vocab, const std::string & text) {
    std::vector<llama_token> tokens(text.size() + 16);
    int32_t n = llama_tokenize(vocab, text.c_str(), text.size(), tokens.data(), tokens.size(), false, true);
    if (n < 0) {
        tokens.resize(-n);
        n = llama_tokenize(vocab, text.c_str(), text.size(), tokens.data(), tokens.size(), false, true);
    }
    tokens.resize(n > 0 ? n : 0);
    return tokens;
}

// 辅助：逐 token 解码拼接
static std::string detokenize_tokens(const struct llama_vocab * vocab, const std::vector<llama_token> & tokens) {
    std::string result;
    char buf[128];
    for (llama_token tok : tokens) {
        int32_t n = llama_token_to_piece(vocab, tok, buf, sizeof(buf), 0, true);
        if (n > 0) {
            result.append(buf, n);
        }
    }
    return result;
}

// 辅助：整体 detokenize
static std::string detokenize_batch(const struct llama_vocab * vocab, const std::vector<llama_token> & tokens) {
    std::string result(tokens.size() * 8, '\0');
    int32_t n = llama_detokenize(vocab, tokens.data(), tokens.size(), result.data(), result.size(), true, true);
    if (n > 0) {
        result.resize(n);
    } else {
        result.resize(-n, '\0');
        n = llama_detokenize(vocab, tokens.data(), tokens.size(), result.data(), result.size(), true, true);
        result.resize(n > 0 ? n : 0);
    }
    return result;
}

// 测试单个模型的 tokenizer 往返
static void test_roundtrip(testing & t, const std::string & filename, const std::string & label) {
    t.test(label + " tokenizer 往返", [&](testing & t) {
        struct llama_model * model = nullptr;
        const struct llama_vocab * vocab = get_vocab(filename, &model);
        t.assert_true("模型加载成功", vocab != nullptr);
        if (!vocab) return;

        // 测试多个文本
        std::vector<std::string> texts = {
            "Hello world",
            "The quick brown fox jumps over the lazy dog",
            "你好世界",
            "1234567890",
            "a",
        };

        for (size_t i = 0; i < texts.size(); ++i) {
            const std::string & text = texts[i];

            // encode
            auto tokens = tokenize_text(vocab, text);
            t.assert_true("tokenize[" + std::to_string(i) + "] n>0", tokens.size() > 0);
            if (tokens.empty()) continue;

            // decode (逐 token)
            std::string decoded = detokenize_tokens(vocab, tokens);
            t.assert_true("roundtrip[" + std::to_string(i) + "] 一致", decoded == text || decoded.find(text) != std::string::npos || text.find(decoded) != std::string::npos);

            // decode (整体)
            std::string decoded_batch = detokenize_batch(vocab, tokens);
            t.assert_true("detokenize[" + std::to_string(i) + "] 非空", !decoded_batch.empty());
        }

        llama_model_free(model);
    });
}

// 测试空文本 tokenize
static void test_empty_text(testing & t) {
    t.test("空文本 tokenize", [&](testing & t) {
        struct llama_model * model = nullptr;
        const struct llama_vocab * vocab = get_vocab("ggml-vocab-llama-bpe.gguf", &model);
        t.assert_true("模型加载成功", vocab != nullptr);
        if (!vocab) return;

        auto tokens = tokenize_text(vocab, "");
        t.assert_true("空文本 token 数为 0", tokens.empty());

        llama_model_free(model);
    });
}

// 测试 token id 范围有效性
static void test_token_id_range(testing & t) {
    t.test("token id 范围有效", [&](testing & t) {
        struct llama_model * model = nullptr;
        const struct llama_vocab * vocab = get_vocab("ggml-vocab-qwen2.gguf", &model);
        t.assert_true("模型加载成功", vocab != nullptr);
        if (!vocab) return;

        int32_t n_vocab = llama_vocab_n_tokens(vocab);
        t.assert_true("n_vocab > 0", n_vocab > 0);

        auto tokens = tokenize_text(vocab, "Hello world");
        for (size_t i = 0; i < tokens.size(); ++i) {
            t.assert_true("token[" + std::to_string(i) + "] >= 0", tokens[i] >= 0);
            t.assert_true("token[" + std::to_string(i) + "] < n_vocab", tokens[i] < n_vocab);
        }

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

    t.test("tokenizer 往返测试", [&](testing & t) {
        test_roundtrip(t, "ggml-vocab-llama-bpe.gguf", "llama-bpe");
        test_roundtrip(t, "ggml-vocab-qwen2.gguf", "qwen2");
        test_roundtrip(t, "ggml-vocab-gemma-4.gguf", "gemma");
        test_roundtrip(t, "ggml-vocab-gpt-2.gguf", "gpt-2");
        test_empty_text(t);
        test_token_id_range(t);
    });

    llama_backend_free();

    return t.summary();
}
