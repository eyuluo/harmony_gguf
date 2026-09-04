// ============================================================================
// test-ggml-ops.cpp — ggml 基础算子单元测试
// 角色 C（质量保障）· Day 3-4 交付物
//
// 测试策略：构造已知输入，通过 ggml 计算图执行算子，与 CPU 参考实现比对数值。
// 覆盖：add, mul, mul_mat, softmax, rms_norm, silu, rope
// ============================================================================

#include "testing.h"

#include "ggml.h"
#include "ggml-cpu.h"

#include <cmath>
#include <vector>
#include <string>

// ----------------------------------------------------------------------------
// 辅助函数
// ----------------------------------------------------------------------------

static void fill_tensor_f32(ggml_tensor * t, const std::vector<float> & data) {
    GGML_ASSERT(ggml_nelements(t) == (int64_t)data.size());
    memcpy(ggml_get_data(t), data.data(), ggml_nbytes(t));
}

static std::vector<float> read_tensor_f32(const ggml_tensor * t) {
    std::vector<float> result(ggml_nelements(t));
    memcpy(result.data(), ggml_get_data(t), ggml_nbytes(t));
    return result;
}

static bool approx_equal(float a, float b, float eps = 1e-4f) {
    return std::fabs(a - b) < eps;
}

static bool vectors_match(const std::vector<float> & a, const std::vector<float> & b, float eps = 1e-4f) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i) {
        if (!approx_equal(a[i], b[i], eps)) return false;
    }
    return true;
}

// 执行计算图并读取结果
static std::vector<float> compute_graph(ggml_context * ctx, ggml_tensor * result, int n_threads = 1) {
    struct ggml_cgraph * gf = ggml_new_graph(ctx);
    ggml_build_forward_expand(gf, result);
    ggml_graph_compute_with_ctx(ctx, gf, n_threads);
    return read_tensor_f32(result);
}

// ----------------------------------------------------------------------------
// 测试用例
// ----------------------------------------------------------------------------

static void test_add(testing & t) {
    t.test("ggml_add: 逐元素加法", [&](testing & t) {
        ggml_init_params params = { .mem_size = 1024 * 1024, .mem_buffer = nullptr };
        ggml_context * ctx = ggml_init(params);

        ggml_tensor * a = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 4);
        ggml_tensor * b = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 4);

        fill_tensor_f32(a, {1.0f, 2.0f, 3.0f, 4.0f});
        fill_tensor_f32(b, {10.0f, 20.0f, 30.0f, 40.0f});

        ggml_tensor * c = ggml_add(ctx, a, b);
        auto result = compute_graph(ctx, c);

        t.assert_equal("add[0]", 11.0f, result[0]);
        t.assert_equal("add[1]", 22.0f, result[1]);
        t.assert_equal("add[2]", 33.0f, result[2]);
        t.assert_equal("add[3]", 44.0f, result[3]);

        ggml_free(ctx);
    });
}

static void test_mul(testing & t) {
    t.test("ggml_mul: 逐元素乘法", [&](testing & t) {
        ggml_init_params params = { .mem_size = 1024 * 1024, .mem_buffer = nullptr };
        ggml_context * ctx = ggml_init(params);

        ggml_tensor * a = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 3);
        ggml_tensor * b = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 3);

        fill_tensor_f32(a, {2.0f, 3.0f, 4.0f});
        fill_tensor_f32(b, {5.0f, 6.0f, 7.0f});

        ggml_tensor * c = ggml_mul(ctx, a, b);
        auto result = compute_graph(ctx, c);

        t.assert_equal("mul[0]", 10.0f, result[0]);
        t.assert_equal("mul[1]", 18.0f, result[1]);
        t.assert_equal("mul[2]", 28.0f, result[2]);

        ggml_free(ctx);
    });
}

static void test_mul_mat(testing & t) {
    t.test("ggml_mul_mat: 矩阵乘法", [&](testing & t) {
        ggml_init_params params = { .mem_size = 1024 * 1024, .mem_buffer = nullptr };
        ggml_context * ctx = ggml_init(params);

        // a: 2x3 矩阵 (行主序: [1,2,3, 4,5,6])
        ggml_tensor * a = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, 3, 2);
        // b: 3x1 向量
        ggml_tensor * b = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, 1, 3);

        fill_tensor_f32(a, {1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f});
        fill_tensor_f32(b, {7.0f, 8.0f, 9.0f});

        // c = a @ b, 结果为 2x1
        ggml_tensor * c = ggml_mul_mat(ctx, a, b);
        auto result = compute_graph(ctx, c);

        // [1*7+2*8+3*9, 4*7+5*8+6*9] = [50, 122]
        t.assert_equal("mul_mat[0]", 50.0f, result[0]);
        t.assert_equal("mul_mat[1]", 122.0f, result[1]);

        ggml_free(ctx);
    });
}

static void test_softmax(testing & t) {
    t.test("ggml_softmax: 归一化指数", [&](testing & t) {
        ggml_init_params params = { .mem_size = 1024 * 1024, .mem_buffer = nullptr };
        ggml_context * ctx = ggml_init(params);

        ggml_tensor * a = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 3);
        fill_tensor_f32(a, {1.0f, 2.0f, 3.0f});

        ggml_tensor * s = ggml_softmax(ctx, a);
        auto result = compute_graph(ctx, s);

        // softmax([1,2,3]) = [e^1, e^2, e^3] / sum
        float e1 = std::exp(1.0f), e2 = std::exp(2.0f), e3 = std::exp(3.0f);
        float sum = e1 + e2 + e3;

        t.assert_true("softmax[0]", approx_equal(result[0], e1 / sum));
        t.assert_true("softmax[1]", approx_equal(result[1], e2 / sum));
        t.assert_true("softmax[2]", approx_equal(result[2], e3 / sum));

        // 验证和为 1
        float total = result[0] + result[1] + result[2];
        t.assert_true("softmax sum=1", approx_equal(total, 1.0f));

        ggml_free(ctx);
    });
}

static void test_rms_norm(testing & t) {
    t.test("ggml_rms_norm: RMS 归一化", [&](testing & t) {
        ggml_init_params params = { .mem_size = 1024 * 1024, .mem_buffer = nullptr };
        ggml_context * ctx = ggml_init(params);

        ggml_tensor * a = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 4);
        fill_tensor_f32(a, {1.0f, 2.0f, 3.0f, 4.0f});

        // eps = 1e-5
        ggml_tensor * r = ggml_rms_norm(ctx, a, 1e-5f);
        auto result = compute_graph(ctx, r);

        // 参考: rms = sqrt(mean(x^2) + eps), out = x / rms
        float sq_sum = 1.0f + 4.0f + 9.0f + 16.0f;
        float rms = std::sqrt(sq_sum / 4.0f + 1e-5f);

        for (int i = 0; i < 4; ++i) {
            float expected = (i + 1.0f) / rms;
            t.assert_true("rms_norm[" + std::to_string(i) + "]", approx_equal(result[i], expected, 1e-3f));
        }

        ggml_free(ctx);
    });
}

static void test_silu(testing & t) {
    t.test("ggml_silu: SiLU 激活函数", [&](testing & t) {
        ggml_init_params params = { .mem_size = 1024 * 1024, .mem_buffer = nullptr };
        ggml_context * ctx = ggml_init(params);

        ggml_tensor * a = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 3);
        fill_tensor_f32(a, {-1.0f, 0.0f, 1.0f});

        ggml_tensor * s = ggml_silu(ctx, a);
        auto result = compute_graph(ctx, s);

        // silu(x) = x * sigmoid(x) = x / (1 + exp(-x))
        for (int i = 0; i < 3; ++i) {
            float x = -1.0f + i;
            float expected = x / (1.0f + std::exp(-x));
            t.assert_true("silu[" + std::to_string(i) + "]", approx_equal(result[i], expected, 1e-3f));
        }

        // silu(0) 应为 0
        t.assert_true("silu(0)=0", approx_equal(result[1], 0.0f, 1e-6f));

        ggml_free(ctx);
    });
}

static void test_rope(testing & t) {
    t.test("ggml_rope: 旋转位置编码", [&](testing & t) {
        ggml_init_params params = { .mem_size = 1024 * 1024, .mem_buffer = nullptr };
        ggml_context * ctx = ggml_init(params);

        // 4 维向量，2 个 head（ne[0]=4, ne[1]=2）
        int ne0 = 4, ne1 = 2;
        ggml_tensor * a = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, ne0, ne1);
        fill_tensor_f32(a, {1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f, 7.0f, 8.0f});

        // 位置参数
        ggml_tensor * pos = ggml_new_tensor_1d(ctx, GGML_TYPE_I32, ne1);
        int32_t pos_data[2] = {0, 1};
        memcpy(ggml_get_data(pos), pos_data, sizeof(pos_data));

        // 标准 RoPE（mode=0）
        ggml_tensor * r = ggml_rope(ctx, a, pos, ne0, 0, 1, 32.0f);
        auto result = compute_graph(ctx, r);

        // 位置 0 时 RoPE 不改变值（cos=1, sin=0）
        t.assert_true("rope pos0[0]", approx_equal(result[0], 1.0f, 1e-3f));
        t.assert_true("rope pos0[1]", approx_equal(result[1], 2.0f, 1e-3f));

        ggml_free(ctx);
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

    t.test("ggml 基础算子", [&](testing & t) {
        test_add(t);
        test_mul(t);
        test_mul_mat(t);
        test_softmax(t);
        test_rms_norm(t);
        test_silu(t);
        test_rope(t);
    });

    return t.summary();
}
