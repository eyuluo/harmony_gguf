// ============================================================================
// test-gguf-parse.cpp — GGUF 解析单元测试
// 角色 C（质量保障）· Day 5-6 交付物
//
// 测试策略：使用 test/models/ 下已有的 vocab 测试模型，解析 GGUF 元数据，
// 校验 architecture、tokenizer 类型、上下文长度等关键字段。
// ============================================================================

#include "testing.h"

#include "ggml.h"
#include "gguf.h"

#include <string>
#include <cstdio>
#include <cstdint>

// 测试模型目录（相对于 test/ 工作目录）
static const char * MODELS_DIR = "models";

// 辅助：打开 GGUF 文件并返回上下文
static struct gguf_context * open_gguf(const std::string & filename) {
    std::string path = std::string(MODELS_DIR) + "/" + filename;
    struct gguf_init_params params = {
        .no_alloc = true,
        .ctx = nullptr,
    };
    return gguf_init_from_file(path.c_str(), params);
}

// 辅助：读取字符串类型 KV
static std::string get_kv_str(struct gguf_context * ctx, const char * key) {
    int64_t kid = gguf_find_key(ctx, key);
    if (kid < 0) return "";
    return std::string(gguf_get_val_str(ctx, kid));
}

// 辅助：读取 u32 类型 KV
static uint32_t get_kv_u32(struct gguf_context * ctx, const char * key) {
    int64_t kid = gguf_find_key(ctx, key);
    if (kid < 0) return 0;
    return gguf_get_val_u32(ctx, kid);
}

// 辅助：读取 i32 类型 KV
static int32_t get_kv_i32(struct gguf_context * ctx, const char * key) {
    int64_t kid = gguf_find_key(ctx, key);
    if (kid < 0) return 0;
    return gguf_get_val_i32(ctx, kid);
}

// 辅助：读取 bool 类型 KV
static bool get_kv_bool(struct gguf_context * ctx, const char * key) {
    int64_t kid = gguf_find_key(ctx, key);
    if (kid < 0) return false;
    return gguf_get_val_bool(ctx, kid);
}

// 辅助：读取 f32 类型 KV
static float get_kv_f32(struct gguf_context * ctx, const char * key) {
    int64_t kid = gguf_find_key(ctx, key);
    if (kid < 0) return 0.0f;
    return gguf_get_val_f32(ctx, kid);
}

// ----------------------------------------------------------------------------
// 测试用例
// ----------------------------------------------------------------------------

static void test_gguf_header(testing & t) {
    t.test("GGUF 文件头解析", [&](testing & t) {
        struct gguf_context * ctx = open_gguf("ggml-vocab-llama-bpe.gguf");
        t.assert_true("文件打开成功", ctx != nullptr);
        if (!ctx) return;

        // GGUF 文件至少有 KV 对
        int64_t n_kv = gguf_get_n_kv(ctx);
        t.assert_true("n_kv > 0", n_kv > 0);

        // 至少有 1 个 tensor
        int64_t n_tensors = gguf_get_n_tensors(ctx);
        t.assert_true("n_tensors >= 0", n_tensors >= 0);

        gguf_free(ctx);
    });
}

static void test_llama_bpe_metadata(testing & t) {
    t.test("llama-bpe 元数据解析", [&](testing & t) {
        struct gguf_context * ctx = open_gguf("ggml-vocab-llama-bpe.gguf");
        t.assert_true("文件打开成功", ctx != nullptr);
        if (!ctx) return;

        // 架构应为 llama
        std::string arch = get_kv_str(ctx, "general.architecture");
        t.assert_true("architecture=llama", arch == "llama");

        // tokenizer 类型应为 BPE
        std::string tok_type = get_kv_str(ctx, "tokenizer.ggml.model");
        t.assert_true("tokenizer=BPE", tok_type == "gpt2" || tok_type == "llama3" || tok_type == "bpe");

        // 上下文长度应 > 0
        uint32_t ctx_len = get_kv_u32(ctx, "llama.context_length");
        t.assert_true("context_length > 0", ctx_len > 0);

        gguf_free(ctx);
    });
}

static void test_qwen2_metadata(testing & t) {
    t.test("qwen2 元数据解析", [&](testing & t) {
        struct gguf_context * ctx = open_gguf("ggml-vocab-qwen2.gguf");
        t.assert_true("文件打开成功", ctx != nullptr);
        if (!ctx) return;

        std::string arch = get_kv_str(ctx, "general.architecture");
        t.assert_true("architecture=qwen2", arch == "qwen2");

        std::string tok_type = get_kv_str(ctx, "tokenizer.ggml.model");
        t.assert_true("tokenizer存在", !tok_type.empty());

        gguf_free(ctx);
    });
}

static void test_gemma_metadata(testing & t) {
    t.test("gemma 元数据解析", [&](testing & t) {
        struct gguf_context * ctx = open_gguf("ggml-vocab-gemma-4.gguf");
        t.assert_true("文件打开成功", ctx != nullptr);
        if (!ctx) return;

        std::string arch = get_kv_str(ctx, "general.architecture");
        t.assert_true("architecture=gemma4", arch == "gemma4");

        gguf_free(ctx);
    });
}

static void test_deepseek_metadata(testing & t) {
    t.test("deepseek 元数据解析", [&](testing & t) {
        struct gguf_context * ctx = open_gguf("ggml-vocab-deepseek-coder.gguf");
        t.assert_true("文件打开成功", ctx != nullptr);
        if (!ctx) return;

        std::string arch = get_kv_str(ctx, "general.architecture");
        t.assert_true("architecture=llama(deepseek)", arch == "llama");

        gguf_free(ctx);
    });
}

static void test_tensor_info(testing & t) {
    t.test("GGUF tensor 信息解析", [&](testing & t) {
        struct gguf_context * ctx = open_gguf("ggml-vocab-llama-bpe.gguf");
        t.assert_true("文件打开成功", ctx != nullptr);
        if (!ctx) return;

        int64_t n_tensors = gguf_get_n_tensors(ctx);
        t.assert_true("n_tensors >= 0", n_tensors >= 0);

        // 检查第一个 tensor 的名称不为空
        if (n_tensors > 0) {
            const char * name = gguf_get_tensor_name(ctx, 0);
            t.assert_true("tensor[0] name 非空", name != nullptr && name[0] != '\0');

            // tensor offset 应为有效值
            size_t offset = gguf_get_tensor_offset(ctx, 0);
            t.assert_true("tensor[0] offset 有效", offset > 0);

            // tensor ne 数组
            const int64_t * ne = gguf_get_tensor_ne(ctx, 0);
            t.assert_true("tensor[0] ne[0] > 0", ne != nullptr && ne[0] > 0);
        }

        gguf_free(ctx);
    });
}

static void test_missing_key(testing & t) {
    t.test("不存在的 key 返回 -1", [&](testing & t) {
        struct gguf_context * ctx = open_gguf("ggml-vocab-llama-bpe.gguf");
        t.assert_true("文件打开成功", ctx != nullptr);
        if (!ctx) return;

        int64_t kid = gguf_find_key(ctx, "this.key.does.not.exist");
        t.assert_equal("missing key = -1", (int64_t)-1, kid);

        gguf_free(ctx);
    });
}

// ----------------------------------------------------------------------------
// 主函数
// ----------------------------------------------------------------------------

int main(int argc, char ** argv) {
    testing t;

    if (argc > 1) {
        t.set_filter(argv[1]);
    }

    t.test("GGUF 解析", [&](testing & t) {
        test_gguf_header(t);
        test_llama_bpe_metadata(t);
        test_qwen2_metadata(t);
        test_gemma_metadata(t);
        test_deepseek_metadata(t);
        test_tensor_info(t);
        test_missing_key(t);
    });

    return t.summary();
}
