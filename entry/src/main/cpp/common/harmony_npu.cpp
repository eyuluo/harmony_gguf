#include "harmony_npu.h"
#include "harmony_npu_layout.h"
#include "ggml-backend.h"
#include "ggml-cpu.h"
#include "ggml-impl.h"
#include <neural_network_runtime/neural_network_runtime.h>
#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>

namespace {
constexpr size_t CACHE_LIMIT = 256u * 1024u * 1024u;
constexpr size_t PLAN_LIMIT = 128;

#define NPU_FUNCTIONS(X) \
    X(OH_NNDevice_GetAllDevicesID) X(OH_NNDevice_GetType) X(OH_NNDevice_GetName) \
    X(OH_NNModel_Construct) X(OH_NNModel_Destroy) X(OH_NNModel_AddTensorToModel) \
    X(OH_NNModel_SetTensorData) X(OH_NNModel_SetTensorType) X(OH_NNModel_AddOperation) \
    X(OH_NNModel_SpecifyInputsAndOutputs) X(OH_NNModel_Finish) \
    X(OH_NNCompilation_Construct) X(OH_NNCompilation_Destroy) X(OH_NNCompilation_SetDevice) \
    X(OH_NNCompilation_Build) X(OH_NNCompilation_SetPerformanceMode) \
    X(OH_NNTensorDesc_Create) X(OH_NNTensorDesc_Destroy) X(OH_NNTensorDesc_SetDataType) \
    X(OH_NNTensorDesc_SetShape) X(OH_NNTensorDesc_SetFormat) X(OH_NNTensor_Create) \
    X(OH_NNTensor_Destroy) X(OH_NNTensor_GetDataBuffer) X(OH_NNTensor_GetOffset) \
    X(OH_NNTensor_GetSize) X(OH_NNExecutor_Construct) X(OH_NNExecutor_Destroy) X(OH_NNExecutor_RunSync)

struct Api {
    void * runtime = nullptr;
    void * core = nullptr;
#define DECLARE(name) decltype(&name) name = nullptr;
    NPU_FUNCTIONS(DECLARE)
#undef DECLARE
    bool Load() {
        runtime = dlopen("libneural_network_runtime.so", RTLD_NOW | RTLD_LOCAL);
        core = dlopen("libneural_network_core.so", RTLD_NOW | RTLD_LOCAL);
#define RESOLVE(name) name = reinterpret_cast<decltype(name)>(core ? dlsym(core, #name) : nullptr); \
        if (!name && runtime) { name = reinterpret_cast<decltype(name)>(dlsym(runtime, #name)); } \
        if (!name) { return false; }
        NPU_FUNCTIONS(RESOLVE)
#undef RESOLVE
        return true;
    }
    ~Api() {
        if (core) { dlclose(core); }
        if (runtime) { dlclose(runtime); }
    }
};

void Check(OH_NN_ReturnCode code) {
    if (code != OH_NN_SUCCESS) {
        throw std::runtime_error("NNRt 错误码 " + std::to_string(code));
    }
}

bool Host(const ggml_tensor * t) {
    return t && t->data && (!t->buffer || ggml_backend_buffer_is_host(t->buffer));
}

bool Supported(const ggml_tensor * t) {
    if (!t || t->type != GGML_TYPE_F32 || !ggml_is_contiguous(t) || !HarmonyNpuReadable(t)) { return false; }
    const auto * a = t->src[0];
    const auto * b = t->src[1];
    if (!HarmonyNpuReadable(a)) { return false; }
    if (a->buffer && ggml_backend_buffer_get_usage(a->buffer) == GGML_BACKEND_BUFFER_USAGE_WEIGHTS &&
        ggml_backend_buffer_get_type(a->buffer) != ggml_backend_cpu_buffer_type()) { return false; }
    if (a->type != GGML_TYPE_F32 && a->nb[0] != ggml_type_size(a->type)) { return false; }
    switch (t->op) {
        case GGML_OP_MUL_MAT:
            return HarmonyNpuReadable(b) && b->type == GGML_TYPE_F32 &&
                a->ne[0] == b->ne[0] &&
                (a->ne[2] == b->ne[2] || a->ne[2] == 1) &&
                (a->ne[3] == b->ne[3] || a->ne[3] == 1);
        case GGML_OP_ADD: case GGML_OP_SUB: case GGML_OP_MUL: case GGML_OP_DIV:
            return HarmonyNpuReadable(b) && a->type == GGML_TYPE_F32 && b->type == GGML_TYPE_F32 &&
                HarmonyNpuBroadcast(a, b);
        case GGML_OP_SQR: case GGML_OP_SQRT: case GGML_OP_RMS_NORM:
            return a->type == GGML_TYPE_F32;
        case GGML_OP_UNARY:
            if (a->type != GGML_TYPE_F32) { return false; }
            switch (ggml_get_unary_op(t)) {
                case GGML_UNARY_OP_ABS: case GGML_UNARY_OP_NEG: case GGML_UNARY_OP_RELU:
                case GGML_UNARY_OP_SIGMOID: case GGML_UNARY_OP_TANH: case GGML_UNARY_OP_EXP:
                case GGML_UNARY_OP_SILU: return true;
                default: return false;
            }
        default: return false;
    }
}

struct Plan {
    Api & api;
    OH_NNModel * model = nullptr;
    OH_NNCompilation * compilation = nullptr;
    OH_NNExecutor * executor = nullptr;
    std::vector<NN_Tensor *> inputs;
    std::vector<NN_Tensor *> outputs;
    std::vector<std::vector<float>> constants;
    std::vector<std::vector<uint8_t>> parameters;
    std::vector<uint32_t> input_ids;
    std::vector<uint32_t> output_ids;
    std::vector<size_t> output_nodes;
    std::unordered_map<const ggml_tensor *, uint32_t> tensors;
    uint32_t next = 0;
    size_t bytes = 0;
    bool validated = false;
    explicit Plan(Api & a) : api(a) {}
    ~Plan() {
        for (auto * t : inputs) { api.OH_NNTensor_Destroy(&t); }
        for (auto * t : outputs) { api.OH_NNTensor_Destroy(&t); }
        if (executor) { api.OH_NNExecutor_Destroy(&executor); }
        if (compilation) { api.OH_NNCompilation_Destroy(&compilation); }
        if (model) { api.OH_NNModel_Destroy(&model); }
    }
    uint32_t Tensor(std::vector<int32_t> shape, OH_NN_DataType type = OH_NN_FLOAT32,
                    OH_NN_TensorType role = OH_NN_TENSOR, const void * data = nullptr, size_t length = 0) {
        NN_TensorDesc * desc = api.OH_NNTensorDesc_Create();
        if (!desc) { throw std::runtime_error("创建 NPU 张量描述失败"); }
        auto destroy = [&]() { api.OH_NNTensorDesc_Destroy(&desc); };
        try {
            Check(api.OH_NNTensorDesc_SetShape(desc, shape.data(), shape.size()));
            Check(api.OH_NNTensorDesc_SetDataType(desc, type));
            Check(api.OH_NNTensorDesc_SetFormat(desc, OH_NN_FORMAT_ND));
            Check(api.OH_NNModel_AddTensorToModel(model, desc));
            const uint32_t id = next++;
            Check(api.OH_NNModel_SetTensorType(model, id, role));
            if (data) {
                parameters.emplace_back(length);
                memcpy(parameters.back().data(), data, length);
                Check(api.OH_NNModel_SetTensorData(model, id, parameters.back().data(), length));
            }
            destroy();
            return id;
        } catch (...) { destroy(); throw; }
    }
    std::vector<int32_t> Shape(const ggml_tensor * t) {
        return {static_cast<int32_t>(t->ne[3]), static_cast<int32_t>(t->ne[2]),
            static_cast<int32_t>(t->ne[1]), static_cast<int32_t>(t->ne[0])};
    }
    uint32_t Data(const ggml_tensor * t, bool external) {
        auto it = tensors.find(t);
        if (it != tensors.end()) { return it->second; }
        const bool weight = external && t->buffer &&
            ggml_backend_buffer_get_usage(t->buffer) == GGML_BACKEND_BUFFER_USAGE_WEIGHTS;
        const uint32_t id = Tensor(Shape(t));
        tensors[t] = id;
        if (weight) {
            constants.emplace_back(static_cast<size_t>(ggml_nelements(t)));
            HarmonyNpuPack(t, constants.back().data());
            Check(api.OH_NNModel_SetTensorData(model, id, constants.back().data(), constants.back().size()*sizeof(float)));
        } else if (external) {
            input_ids.push_back(id);
        }
        return id;
    }
    void Op(OH_NN_OperationType op, std::vector<uint32_t> in, uint32_t out,
            std::vector<uint32_t> params = {}) {
        OH_NN_UInt32Array p{params.data(), static_cast<uint32_t>(params.size())};
        OH_NN_UInt32Array i{in.data(), static_cast<uint32_t>(in.size())};
        OH_NN_UInt32Array o{&out, 1};
        Check(api.OH_NNModel_AddOperation(model, op, &p, &i, &o));
    }
    void Node(const ggml_tensor * t) {
        auto source = [&](int n) { return Data(t->src[n], tensors.count(t->src[n]) == 0); };
        const uint32_t a = source(0);
        const uint32_t out = Data(t, false);
        switch (t->op) {
            case GGML_OP_MUL_MAT: {
                bool transpose = true;
                const auto p = Tensor({1}, OH_NN_BOOL, OH_NN_MATMUL_TRANSPOSE_B, &transpose, sizeof(transpose));
                Op(OH_NN_OPS_MATMUL, {source(1), a}, out, {p});
                break;
            }
            case GGML_OP_ADD: Op(OH_NN_OPS_ADD, {a, source(1)}, out); break;
            case GGML_OP_SUB: Op(OH_NN_OPS_SUB, {a, source(1)}, out); break;
            case GGML_OP_MUL: Op(OH_NN_OPS_MUL, {a, source(1)}, out); break;
            case GGML_OP_DIV: Op(OH_NN_OPS_DIV, {a, source(1)}, out); break;
            case GGML_OP_SQR: Op(OH_NN_OPS_MUL, {a, a}, out); break;
            case GGML_OP_SQRT: Op(OH_NN_OPS_SQRT, {a}, out); break;
            case GGML_OP_RMS_NORM: {
                auto shape = Shape(t);
                const uint32_t sq = Tensor(shape);
                shape.back() = 1;
                const uint32_t mean = Tensor(shape), sum = Tensor(shape), root = Tensor(shape);
                int32_t axis = 3;
                bool keep = true;
                float epsilon;
                memcpy(&epsilon, t->op_params, sizeof(epsilon));
                const uint32_t axes = Tensor({1}, OH_NN_INT32, OH_NN_TENSOR, &axis, sizeof(axis));
                const uint32_t p = Tensor({1}, OH_NN_BOOL, OH_NN_REDUCE_MEAN_KEEP_DIMS, &keep, sizeof(keep));
                const uint32_t eps = Tensor({1}, OH_NN_FLOAT32, OH_NN_TENSOR, &epsilon, sizeof(epsilon));
                Op(OH_NN_OPS_MUL, {a, a}, sq);
                Op(OH_NN_OPS_REDUCE_MEAN, {sq, axes}, mean, {p});
                Op(OH_NN_OPS_ADD, {mean, eps}, sum);
                Op(OH_NN_OPS_SQRT, {sum}, root);
                Op(OH_NN_OPS_DIV, {a, root}, out);
                break;
            }
            case GGML_OP_UNARY:
                switch (ggml_get_unary_op(t)) {
                    case GGML_UNARY_OP_ABS: Op(OH_NN_OPS_ABS, {a}, out); break;
                    case GGML_UNARY_OP_NEG: Op(OH_NN_OPS_NEG, {a}, out); break;
                    case GGML_UNARY_OP_RELU: Op(OH_NN_OPS_RELU, {a}, out); break;
                    case GGML_UNARY_OP_SIGMOID: Op(OH_NN_OPS_SIGMOID, {a}, out); break;
                    case GGML_UNARY_OP_TANH: Op(OH_NN_OPS_TANH, {a}, out); break;
                    case GGML_UNARY_OP_EXP: Op(OH_NN_OPS_EXP, {a}, out); break;
                    case GGML_UNARY_OP_SILU: {
                        const uint32_t sig = Tensor(Shape(t));
                        Op(OH_NN_OPS_SIGMOID, {a}, sig);
                        Op(OH_NN_OPS_MUL, {a, sig}, out);
                        break;
                    }
                    default: throw std::runtime_error("未支持的 NPU 激活函数");
                }
                break;
            default: throw std::runtime_error("未支持的 NPU 算子");
        }
    }
    NN_Tensor * Buffer(size_t device, const ggml_tensor * t) {
        NN_TensorDesc * desc = api.OH_NNTensorDesc_Create();
        if (!desc) { throw std::runtime_error("创建 NPU 缓冲描述失败"); }
        try {
            const auto shape = Shape(t);
            Check(api.OH_NNTensorDesc_SetShape(desc, shape.data(), shape.size()));
            Check(api.OH_NNTensorDesc_SetDataType(desc, OH_NN_FLOAT32));
            Check(api.OH_NNTensorDesc_SetFormat(desc, OH_NN_FORMAT_ND));
            NN_Tensor * buffer = api.OH_NNTensor_Create(device, desc);
            api.OH_NNTensorDesc_Destroy(&desc);
            if (!buffer) { throw std::runtime_error("分配 NPU 共享缓冲失败"); }
            return buffer;
        } catch (...) {
            if (desc) { api.OH_NNTensorDesc_Destroy(&desc); }
            throw;
        }
    }
    float * BufferData(NN_Tensor * t, size_t expected) {
        size_t offset = 0, size = 0;
        Check(api.OH_NNTensor_GetOffset(t, &offset));
        Check(api.OH_NNTensor_GetSize(t, &size));
        auto * data = static_cast<char *>(api.OH_NNTensor_GetDataBuffer(t));
        if (!data || offset > size || expected > size - offset) { throw std::runtime_error("NPU 共享缓冲大小异常"); }
        return reinterpret_cast<float *>(data + offset);
    }
};

struct Package {
    std::vector<ggml_tensor *> nodes;
    std::vector<const ggml_tensor *> inputs;
    std::vector<size_t> outputs;
    std::string key;
    size_t bytes = 0;
};

Package Describe(ggml_cgraph * graph, int begin, int end) {
    Package p;
    std::unordered_map<const ggml_tensor *, size_t> local;
    std::unordered_map<const ggml_tensor *, size_t> external;
    std::ostringstream key;
    for (int i = begin; i < end; ++i) {
        auto * t = graph->nodes[i];
        local[t] = p.nodes.size();
        p.nodes.push_back(t);
        key << t->op << ':' << t->type << ':';
        for (int d = 0; d < 4; ++d) { key << t->ne[d] << ','; }
        for (int d = 0; d < GGML_MAX_OP_PARAMS/4; ++d) { key << t->op_params[d] << ','; }
        p.bytes += static_cast<size_t>(ggml_nelements(t))*sizeof(float)*8;
        for (int s = 0; s < GGML_MAX_SRC && t->src[s]; ++s) {
            const auto * src = t->src[s];
            const auto found = local.find(src);
            if (found != local.end()) { key << 'n' << found->second << ';'; continue; }
            if (!Host(src)) { throw std::runtime_error("NPU 输入不在可读取的 CPU 缓冲中"); }
            const bool weight = src->buffer && ggml_backend_buffer_get_usage(src->buffer) == GGML_BACKEND_BUFFER_USAGE_WEIGHTS;
            auto inserted = external.emplace(src, external.size());
            key << 'i' << inserted.first->second << ':' << src->type << ':';
            for (int d = 0; d < 4; ++d) { key << src->ne[d] << ',' << src->nb[d] << ','; }
            if (weight) { key << 'w' << src->data; }
            key << ';';
            if (inserted.second) {
                p.bytes += static_cast<size_t>(ggml_nelements(src))*sizeof(float)*2;
                if (!weight) { p.inputs.push_back(src); }
            }
        }
    }
    std::unordered_set<const ggml_tensor *> required;
    for (int i = end; i < graph->n_nodes; ++i) {
        for (const auto * src : graph->nodes[i]->src) { if (src) { required.insert(src); } }
    }
    for (size_t i = 0; i < p.nodes.size(); ++i) {
        if ((p.nodes[i]->flags & GGML_TENSOR_FLAG_OUTPUT) || required.count(p.nodes[i]) || i + 1 == p.nodes.size()) {
            p.outputs.push_back(i);
            key << 'o' << i << ';';
        }
    }
    p.key = key.str();
    return p;
}

struct Runtime {
    std::mutex mutex;
    Api api;
    HarmonyNpuStatus status;
    std::mutex snapshot_mutex;
    HarmonyNpuStatus snapshot;
    void Publish() {
        std::lock_guard<std::mutex> lock(snapshot_mutex);
        snapshot = status;
    }
    bool probed = false;
    size_t device = 0;
    std::unordered_map<std::string, std::unique_ptr<Plan>> plans;
    std::unordered_set<std::string> rejected;
    bool Probe() {
        if (probed) { return status.available; }
        probed = true;
        if (!api.Load()) { status.last_error = "设备未提供完整 NNRt 接口"; return false; }
        const size_t * ids = nullptr;
        uint32_t count = 0;
        if (api.OH_NNDevice_GetAllDevicesID(&ids, &count) != OH_NN_SUCCESS) {
            status.last_error = "查询 NPU 设备失败"; return false;
        }
        for (uint32_t i = 0; i < count; ++i) {
            OH_NN_DeviceType type = OH_NN_OTHERS;
            if (api.OH_NNDevice_GetType(ids[i], &type) == OH_NN_SUCCESS && type == OH_NN_ACCELERATOR) {
                device = ids[i];
                const char * name = nullptr;
                api.OH_NNDevice_GetName(device, &name);
                status.device = name ? name : "NNRt 加速器";
                status.available = true;
                status.last_error.clear();
                fprintf(stderr, "[Harmony-GGUF] NPU 设备：%s\n", status.device.c_str());
                return true;
            }
        }
        status.last_error = "未发现 NNRt 专用加速器";
        return false;
    }
    Plan & Build(const Package & p) {
        if (plans.size() >= PLAN_LIMIT || p.bytes > CACHE_LIMIT - status.cached_bytes) {
            throw std::runtime_error("NPU 子图缓存达到内存预算，使用 CPU");
        }
        auto plan = std::make_unique<Plan>(api);
        plan->model = api.OH_NNModel_Construct();
        if (!plan->model) { throw std::runtime_error("构造 NPU 子图失败"); }
        for (auto * t : p.nodes) { plan->Node(t); }
        for (size_t index : p.outputs) { plan->output_ids.push_back(plan->tensors.at(p.nodes[index])); }
        OH_NN_UInt32Array in{plan->input_ids.data(), static_cast<uint32_t>(plan->input_ids.size())};
        OH_NN_UInt32Array out{plan->output_ids.data(), static_cast<uint32_t>(plan->output_ids.size())};
        Check(api.OH_NNModel_SpecifyInputsAndOutputs(plan->model, &in, &out));
        Check(api.OH_NNModel_Finish(plan->model));
        plan->compilation = api.OH_NNCompilation_Construct(plan->model);
        if (!plan->compilation) { throw std::runtime_error("创建 NPU 编译器失败"); }
        Check(api.OH_NNCompilation_SetDevice(plan->compilation, device));
        api.OH_NNCompilation_SetPerformanceMode(plan->compilation, OH_NN_PERFORMANCE_HIGH);
        Check(api.OH_NNCompilation_Build(plan->compilation));
        plan->executor = api.OH_NNExecutor_Construct(plan->compilation);
        if (!plan->executor) { throw std::runtime_error("创建 NPU 执行器失败"); }
        plan->inputs.reserve(p.inputs.size());
        plan->outputs.reserve(p.outputs.size());
        for (const auto * t : p.inputs) { plan->inputs.push_back(plan->Buffer(device, t)); }
        for (size_t i : p.outputs) { plan->outputs.push_back(plan->Buffer(device, p.nodes[i])); }
        plan->bytes = p.bytes;
        plan->output_nodes = p.outputs;
        auto result = plans.emplace(p.key, std::move(plan));
        status.cached_bytes += p.bytes;
        return *result.first->second;
    }
};

Runtime & GetRuntime() { static Runtime r; return r; }

struct PublishStatus {
    Runtime & runtime;
    ~PublishStatus() {
        std::lock_guard<std::mutex> lock(runtime.mutex);
        runtime.Publish();
    }
};

bool WorthTrying(ggml_cgraph * graph, int begin, int end) {
    for (int i = begin; i < end; ++i) {
        const auto * t = graph->nodes[i];
        if (t->op == GGML_OP_MUL_MAT && Supported(t) &&
            HarmonyNpuLargeMatmul(t->src[1]->ne[1], t->src[0]->ne[0], ggml_nelements(t))) {
            return true;
        }
    }
    return false;
}
}

void HarmonyNpuConfigure(bool enabled) {
    auto & r = GetRuntime();
    std::lock_guard<std::mutex> lock(r.mutex);
    r.plans.clear();
    r.rejected.clear();
    r.status.enabled = enabled;
    r.status.executions = 0;
    r.status.fallbacks = 0;
    r.status.cpu_graphs = 0;
    r.status.last_npu_ms = 0;
    r.status.last_cpu_ms = 0;
    r.status.cached_bytes = 0;
    if (enabled) { r.Probe(); }
    r.Publish();
    fprintf(stderr, "[Harmony-GGUF] NPU 混合计算：%s，%s\n", enabled ? "开启" : "关闭", r.status.last_error.c_str());
}

HarmonyNpuStatus HarmonyNpuGetStatus() {
    auto & r = GetRuntime();
    std::lock_guard<std::mutex> lock(r.snapshot_mutex);
    return r.snapshot;
}

ggml_status HarmonyNpuCompute(ggml_cgraph * graph,
    const std::function<ggml_status(ggml_cgraph *)> & cpu,
    ggml_abort_callback abort, void * abort_data) {
    auto & r = GetRuntime();
    PublishStatus publish{r};
    {
        std::lock_guard<std::mutex> lock(r.mutex);
        if (!r.status.enabled || !r.Probe()) { return cpu(graph); }
    }
    if (!WorthTrying(graph, 0, graph->n_nodes)) {
        {
            std::lock_guard<std::mutex> lock(r.mutex);
            ++r.status.cpu_graphs;
        }
        return cpu(graph);
    }
    int cpu_begin = 0;
    for (int begin = 0; begin < graph->n_nodes;) {
        if (abort && abort(abort_data)) { return GGML_STATUS_ABORTED; }
        bool supported = Supported(graph->nodes[begin]);
        int end = begin + 1;
        while (end < graph->n_nodes && Supported(graph->nodes[end]) == supported &&
            (!supported || end - begin < 32)) { ++end; }
        supported = supported && WorthTrying(graph, begin, end);
        if (supported) {
            while (end > begin + 1) {
                try {
                    if (Describe(graph, begin, end).bytes <= CACHE_LIMIT) { break; }
                    end = begin + (end - begin)/2;
                } catch (...) {
                    end = begin + (end - begin)/2;
                }
            }
            supported = WorthTrying(graph, begin, end);
        }
        auto view = ggml_graph_view(graph, begin, end);
        bool executed = false;
        if (supported) {
            if (cpu_begin < begin) {
                auto pending = ggml_graph_view(graph, cpu_begin, begin);
                const auto rc = cpu(&pending);
                if (rc != GGML_STATUS_SUCCESS) { return rc; }
            }
            cpu_begin = begin;
            std::lock_guard<std::mutex> lock(r.mutex);
            std::string key;
            try {
                const auto p = Describe(graph, begin, end);
                key = p.key;
                if (!r.rejected.count(key)) {
                    auto found = r.plans.find(key);
                    Plan & plan = found == r.plans.end() ? r.Build(p) : *found->second;
                    const auto npu_start = std::chrono::steady_clock::now();
                    for (size_t i = 0; i < p.inputs.size(); ++i) {
                        HarmonyNpuPack(p.inputs[i], plan.BufferData(plan.inputs[i], ggml_nelements(p.inputs[i])*sizeof(float)));
                    }
                    if (abort && abort(abort_data)) { return GGML_STATUS_ABORTED; }
                    Check(r.api.OH_NNExecutor_RunSync(plan.executor, plan.inputs.data(), plan.inputs.size(),
                        plan.outputs.data(), plan.outputs.size()));
                    if (!plan.validated) {
                        std::vector<std::vector<float>> results;
                        for (size_t i = 0; i < p.outputs.size(); ++i) {
                            const auto * t = p.nodes[p.outputs[i]];
                            const auto * data = plan.BufferData(plan.outputs[i], ggml_nbytes(t));
                            results.emplace_back(data, data + ggml_nelements(t));
                        }
                        const auto npu_time = std::chrono::steady_clock::now() - npu_start;
                        const auto cpu_start = std::chrono::steady_clock::now();
                        const auto rc = cpu(&view);
                        if (rc != GGML_STATUS_SUCCESS) { return rc; }
                        const auto cpu_time = std::chrono::steady_clock::now() - cpu_start;
                        r.status.last_npu_ms = std::chrono::duration<double, std::milli>(npu_time).count();
                        r.status.last_cpu_ms = std::chrono::duration<double, std::milli>(cpu_time).count();
                        executed = true;
                        for (size_t i = 0; i < p.outputs.size(); ++i) {
                            const auto * t = p.nodes[p.outputs[i]];
                            const auto * actual = results[i].data();
                            const auto * expected = static_cast<const float *>(t->data);
                            for (int64_t n = 0; n < ggml_nelements(t); ++n) {
                                if (!HarmonyNpuClose(actual[n], expected[n])) {
                                    throw std::runtime_error("NPU 子图数值校验失败，使用 CPU");
                                }
                            }
                        }
                        fprintf(stderr, "[Harmony-GGUF] NPU 收益测试：NPU %.2f ms，CPU %.2f ms\n",
                            std::chrono::duration<double, std::milli>(npu_time).count(),
                            std::chrono::duration<double, std::milli>(cpu_time).count());
                        if (!HarmonyNpuFaster(std::chrono::duration<double, std::milli>(npu_time).count(),
                            std::chrono::duration<double, std::milli>(cpu_time).count())) {
                            throw std::runtime_error("NPU 含搬运耗时未比 CPU 降低 20%，后续使用 CPU");
                        }
                        plan.validated = true;
                        fprintf(stderr, "[Harmony-GGUF] NPU 子图校验通过：%zu 节点，缓存估算 %zu 字节\n",
                            p.nodes.size(), plan.bytes);
                    }
                    if (abort && abort(abort_data)) { return GGML_STATUS_ABORTED; }
                    for (size_t i = 0; !executed && i < p.outputs.size(); ++i) {
                        auto * t = p.nodes[p.outputs[i]];
                        memcpy(t->data, plan.BufferData(plan.outputs[i], ggml_nbytes(t)), ggml_nbytes(t));
                    }
                    if (!executed) { ++r.status.executions; }
                    executed = true;
                }
            } catch (const std::exception & e) {
                r.status.last_error = e.what();
                if (!key.empty()) {
                    auto found = r.plans.find(key);
                    if (found != r.plans.end()) {
                        r.status.cached_bytes -= found->second->bytes;
                        r.plans.erase(found);
                    }
                    if (r.rejected.size() < 1024) { r.rejected.insert(key); }
                }
                fprintf(stderr, "[Harmony-GGUF] NPU 回退：%s\n", e.what());
            }
            if (!executed || r.rejected.count(key)) { ++r.status.fallbacks; }
        }
        if (executed) { cpu_begin = end; }
        begin = end;
    }
    if (cpu_begin < graph->n_nodes) {
        auto pending = ggml_graph_view(graph, cpu_begin, graph->n_nodes);
        return cpu(&pending);
    }
    return GGML_STATUS_SUCCESS;
}
