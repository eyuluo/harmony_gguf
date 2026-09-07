#include <napi/native_api.h>

#include <cstdint>
#include <cstdio>
#include <string>

#include "engine_state.h"
#include "engine_types.h"
#include "error_code.h"
#include "llama.h"
#include "napi_util.h"

// 读取 GGUF 元数据字符串（key -> value）
static std::string read_meta_str(const llama_model * model, const char * key) {
    char buf[512] = {0};
    int32_t len = llama_model_meta_val_str(model, key, buf, sizeof(buf));
    if (len <= 0) {
        return "";
    }
    return std::string(buf, static_cast<size_t>(len));
}

// 将 vocab 类型映射为 tokenizer 字符串
static std::string vocab_type_name(enum llama_vocab_type type) {
    switch (type) {
        case LLAMA_VOCAB_TYPE_SPM:  return "sentencepiece";
        case LLAMA_VOCAB_TYPE_BPE:  return "bpe";
        case LLAMA_VOCAB_TYPE_WPM:  return "wordpiece";
        case LLAMA_VOCAB_TYPE_UGM:  return "unigram";
        case LLAMA_VOCAB_TYPE_RWKV: return "rwkv";
        case LLAMA_VOCAB_TYPE_PLAMO2: return "plamo2";
        default:                    return "unknown";
    }
}

// 将参数量格式化为 "7B" / "1.5B" / "350M" 等
static std::string format_params(uint64_t n_params) {
    char buf[64] = {0};
    if (n_params >= 1'000'000'000) {
        snprintf(buf, sizeof(buf), "%.1fB", static_cast<double>(n_params) / 1e9);
    } else if (n_params >= 1'000'000) {
        snprintf(buf, sizeof(buf), "%.0fM", static_cast<double>(n_params) / 1e6);
    } else if (n_params >= 1'000) {
        snprintf(buf, sizeof(buf), "%.0fK", static_cast<double>(n_params) / 1e3);
    } else {
        snprintf(buf, sizeof(buf), "%llu", static_cast<unsigned long long>(n_params));
    }
    return std::string(buf);
}

// 填充 ModelMetadata 并转换为 napi 对象
static napi_value build_metadata_object(napi_env env, const ModelMetadata & meta) {
    napi_value obj = napi_util::NewObject(env);
    napi_util::SetProperty(env, obj, "architecture", napi_util::NewString(env, meta.architecture));
    napi_util::SetProperty(env, obj, "parameters", napi_util::NewString(env, meta.parameters));
    napi_util::SetProperty(env, obj, "quantization", napi_util::NewString(env, meta.quantization));
    napi_util::SetProperty(env, obj, "contextLength", napi_util::NewUint32(env, meta.context_length));
    napi_util::SetProperty(env, obj, "tokenizer", napi_util::NewString(env, meta.tokenizer));
    napi_util::SetProperty(env, obj, "fileSize", napi_util::NewDouble(env, static_cast<double>(meta.file_size)));
    return obj;
}

// parseGgufMetadata(path: string): ModelMetadata
static napi_value ParseGgufMetadata(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string path;
    if (argc < 1 || !napi_util::GetString(env, args[0], path) || path.empty()) {
        napi_util::ThrowError(env, error_code_value(ErrorCode::InvalidArgument), "path is required");
        return nullptr;
    }

    // 仅加载 vocab 与元数据，不加载权重（轻量）
    llama_model_params params = llama_model_default_params();
    params.vocab_only = true;

    llama_model * model = llama_model_load_from_file(path.c_str(), params);
    if (model == nullptr) {
        napi_util::ThrowError(env, error_code_value(ErrorCode::ModelLoadFailed), "failed to parse gguf metadata");
        return nullptr;
    }

    ModelMetadata meta;
    meta.architecture = read_meta_str(model, "general.architecture");
    meta.quantization = llama_ftype_name(llama_model_ftype(model));
    meta.context_length = static_cast<uint32_t>(llama_model_n_ctx_train(model));
    meta.file_size = llama_model_size(model);
    meta.parameters = format_params(llama_model_n_params(model));

    const llama_vocab * vocab = llama_model_get_vocab(model);
    meta.tokenizer = vocab != nullptr ? vocab_type_name(llama_vocab_type(vocab)) : "unknown";

    napi_value result = build_metadata_object(env, meta);

    llama_model_free(model);

    return result;
}

// loadModel(path: string, config?: LoadConfig): number (modelId)
static napi_value LoadModel(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string path;
    if (argc < 1 || !napi_util::GetString(env, args[0], path) || path.empty()) {
        napi_util::ThrowError(env, error_code_value(ErrorCode::InvalidArgument), "path is required");
        return nullptr;
    }

    LoadConfig config;
    if (argc >= 2) {
        uint32_t context_length = 0;
        int32_t threads = 0;
        uint32_t parallel = config.parallel;
        napi_util::GetOptionalUint32(env, args[1], "contextLength", context_length);
        napi_util::GetOptionalInt32(env, args[1], "threads", threads);
        napi_util::GetOptionalUint32(env, args[1], "parallel", parallel);
        config.context_length = context_length;
        config.threads = threads;
        config.parallel = parallel;
    }

    int32_t code = EngineState::Instance().LoadModel(path, config);
    if (code != error_code_value(ErrorCode::Ok)) {
        napi_util::ThrowError(env, code, "failed to load model");
        return nullptr;
    }

    // 单模型实例：modelId 固定为 1
    napi_value result = nullptr;
    napi_create_int32(env, 1, &result);
    return result;
}

// unloadModel(modelId: number): void
static napi_value UnloadModel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    EngineState::Instance().UnloadModel();

    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

// 导出模型管理相关接口
void RegisterModelApi(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "parseGgufMetadata", nullptr, ParseGgufMetadata, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "loadModel", nullptr, LoadModel, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "unloadModel", nullptr, UnloadModel, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
