#ifndef HARMONY_GGUF_NPU_H
#define HARMONY_GGUF_NPU_H

#include "ggml.h"
#include <functional>
#include <string>

struct HarmonyNpuStatus {
    bool enabled = true;
    bool available = false;
    std::string device;
    std::string last_error;
    uint64_t executions = 0;
    uint64_t fallbacks = 0;
    uint64_t cpu_graphs = 0;
    double last_npu_ms = 0;
    double last_cpu_ms = 0;
    size_t cached_bytes = 0;
};

void HarmonyNpuConfigure(bool enabled);
HarmonyNpuStatus HarmonyNpuGetStatus();
ggml_status HarmonyNpuCompute(ggml_cgraph * graph,
    const std::function<ggml_status(ggml_cgraph *)> & cpu,
    ggml_abort_callback abort, void * abort_data);

#endif
