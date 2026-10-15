#ifndef HARMONY_GGUF_NPU_LAYOUT_H
#define HARMONY_GGUF_NPU_LAYOUT_H

#include "ggml.h"
#include <climits>
#include <cmath>
#include <cstring>
#include <vector>

inline bool HarmonyNpuLargeMatmul(int64_t rows, int64_t inner, int64_t outputs) {
    return rows >= 32 && inner > 0 && outputs > 0 &&
        double(inner)*double(outputs) >= 32.0*1024*1024;
}

inline bool HarmonyNpuFaster(double npu_ms, double cpu_ms) {
    return std::isfinite(npu_ms) && std::isfinite(cpu_ms) &&
        npu_ms > 0 && cpu_ms > 0 && npu_ms < cpu_ms*0.8;
}

inline bool HarmonyNpuReadable(const ggml_tensor * t) {
    if (!t) { return false; }
    for (int i = 0; i < 4; ++i) {
        if (t->ne[i] <= 0 || t->ne[i] > INT_MAX) { return false; }
    }
    if (ggml_is_quantized(t->type) && t->ne[0] % ggml_blck_size(t->type) != 0) { return false; }
    return t->type == GGML_TYPE_F32 || ggml_get_type_traits(t->type)->to_float != nullptr;
}

inline bool HarmonyNpuBroadcast(const ggml_tensor * a, const ggml_tensor * b) {
    for (int i = 0; i < 4; ++i) {
        if (a->ne[i] != b->ne[i] && a->ne[i] != 1 && b->ne[i] != 1) { return false; }
    }
    return true;
}

inline bool HarmonyNpuClose(float actual, float expected) {
    return std::isfinite(actual) && std::isfinite(expected) &&
        std::abs(actual - expected) <= 0.02f*(1.0f + std::abs(expected));
}

inline void HarmonyNpuPackRows(const ggml_tensor * t, float * dst, ggml_to_float_t convert) {
    const auto * base = static_cast<const char *>(t->data);
    size_t row = 0;
    for (int64_t i3 = 0; i3 < t->ne[3]; ++i3) {
        for (int64_t i2 = 0; i2 < t->ne[2]; ++i2) {
            for (int64_t i1 = 0; i1 < t->ne[1]; ++i1, ++row) {
                const char * src = base + i3*t->nb[3] + i2*t->nb[2] + i1*t->nb[1];
                float * out = dst + row*t->ne[0];
                if (t->type == GGML_TYPE_F32) {
                    if (t->nb[0] == sizeof(float)) {
                        memcpy(out, src, t->ne[0]*sizeof(float));
                        continue;
                    }
                    for (int64_t i0 = 0; i0 < t->ne[0]; ++i0) {
                        memcpy(out + i0, src + i0*t->nb[0], sizeof(float));
                    }
                } else {
                    convert(src, out, t->ne[0]);
                }
            }
        }
    }
}

inline void HarmonyNpuPack(const ggml_tensor * t, float * dst) {
    HarmonyNpuPackRows(t, dst, ggml_get_type_traits(t->type)->to_float);
}

#endif
