#include "testing.h"
#include "harmony_npu_layout.h"
#include <limits>

int main() {
    testing t;
    t.test("NPU 卸载要求足够计算量和实测收益", [](testing & t) {
        t.assert_true("单 token 解码保留 CPU", !HarmonyNpuLargeMatmul(1, 4096, 4096));
        t.assert_true("小批量保留 CPU", !HarmonyNpuLargeMatmul(16, 4096, 65536));
        t.assert_true("小矩阵保留 CPU", !HarmonyNpuLargeMatmul(32, 64, 2048));
        t.assert_true("大批量投影可尝试 NPU", HarmonyNpuLargeMatmul(32, 4096, 131072));
        t.assert_true("比 CPU 慢不保留", !HarmonyNpuFaster(12, 10));
        t.assert_true("收益不足不保留", !HarmonyNpuFaster(9, 10));
        t.assert_true("达到收益门槛才保留", HarmonyNpuFaster(7, 10));
        t.assert_true("无效测量不保留", !HarmonyNpuFaster(0, 0));
    });
    t.test("NPU 输入打包保留非连续张量顺序", [](testing & t) {
        float input[]{1, 9, 2, 9, 3, 9, 4, 9};
        ggml_tensor tensor{};
        tensor.type = GGML_TYPE_F32;
        tensor.data = input;
        tensor.ne[0] = 2; tensor.ne[1] = 2; tensor.ne[2] = 1; tensor.ne[3] = 1;
        tensor.nb[0] = 2*sizeof(float); tensor.nb[1] = 4*sizeof(float);
        tensor.nb[2] = tensor.nb[3] = sizeof(input);
        float packed[4]{};
        HarmonyNpuPackRows(&tensor, packed, nullptr);
        for (int i = 0; i < 4; ++i) {
            t.assert_equal("按 ggml 逻辑顺序转换", float(i + 1), packed[i]);
        }
        tensor.nb[0] = 4*sizeof(float); tensor.nb[1] = 2*sizeof(float);
        HarmonyNpuPackRows(&tensor, packed, nullptr);
        t.assert_equal("转置视图第二个元素", 3.0f, packed[1]);
        t.assert_equal("转置视图第三个元素", 2.0f, packed[2]);
    });
    t.test("NNRt 标准广播拒绝 ggml 周期重复", [](testing & t) {
        ggml_tensor a{}, b{};
        for (int i = 0; i < 4; ++i) { a.ne[i] = b.ne[i] = 1; }
        a.ne[0] = 8; b.ne[0] = 1;
        t.assert_true("接受单元素广播", HarmonyNpuBroadcast(&a, &b));
        b.ne[0] = 4;
        t.assert_true("周期重复由 CPU 执行", !HarmonyNpuBroadcast(&a, &b));
    });
    t.test("量化行转换遵循批维步长", [](testing & t) {
        int8_t input[]{1, 2, 99, 3, 4, 99};
        ggml_tensor tensor{};
        tensor.type = GGML_TYPE_Q8_0;
        tensor.data = input;
        tensor.ne[0] = 2; tensor.ne[1] = 1; tensor.ne[2] = 2; tensor.ne[3] = 1;
        tensor.nb[0] = 1; tensor.nb[1] = 2; tensor.nb[2] = 3; tensor.nb[3] = 6;
        float packed[4]{};
        HarmonyNpuPackRows(&tensor, packed, [](const void * src, float * dst, int64_t count) {
            const auto * values = static_cast<const int8_t *>(src);
            for (int64_t i = 0; i < count; ++i) { dst[i] = float(values[i])*0.5f; }
        });
        t.assert_equal("转换首批首元素", 0.5f, packed[0]);
        t.assert_equal("转换第二批首元素", 1.5f, packed[2]);
        t.assert_equal("跳过行间填充", 2.0f, packed[3]);
    });
    t.test("NPU 数值验收拒绝非有限与过大误差", [](testing & t) {
        t.assert_true("允许有限精度误差", HarmonyNpuClose(1.001f, 1.0f));
        t.assert_true("拒绝转置或布局错误", !HarmonyNpuClose(2.0f, 1.0f));
        t.assert_true("拒绝 NaN", !HarmonyNpuClose(std::numeric_limits<float>::quiet_NaN(), 1.0f));
        t.assert_true("拒绝无穷", !HarmonyNpuClose(std::numeric_limits<float>::infinity(), 1.0f));
    });
    return t.summary();
}
