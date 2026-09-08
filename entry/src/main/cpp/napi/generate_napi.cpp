#include <napi/native_api.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>

#include "engine_state.h"
#include "engine_types.h"
#include "error_code.h"
#include "llama_inference.h"
#include "napi_util.h"
#include "ts_fn.h"

namespace {

enum GenEvent : int32_t {
    EVENT_TOKEN = 0,
    EVENT_DONE = 1,
    EVENT_ERROR = 2,
    EVENT_STOPPED = 3,
};

// 通过 TSFN 传递给 JS 回调的事件数据
struct GenCallbackData {
    int32_t event;
    char text[512];
    int32_t prompt_tokens;
    int32_t generated_tokens;
    double ttft_ms;
    double tokens_per_second;
    int32_t error_code;
    char error_message[512];
};

void FillStats(GenCallbackData * data, const GenerateStats & stats) {
    data->prompt_tokens = stats.prompt_tokens;
    data->generated_tokens = stats.generated_tokens;
    data->ttft_ms = stats.ttft_ms;
    data->tokens_per_second = stats.tokens_per_second;
}

// TSFN 的 JS 线程回调：把 GenCallbackData 转换为 (event, data) 并调用 JS 回调
void GenerateJsCallback(napi_env env, napi_value js_cb, void * /*context*/, void * data) {
    GenCallbackData * cb = static_cast<GenCallbackData *>(data);
    if (cb == nullptr) {
        return;
    }

    napi_value js_event = nullptr;
    napi_value js_data = napi_util::NewObject(env);

    switch (cb->event) {
        case EVENT_TOKEN:
            js_event = napi_util::NewString(env, "token");
            napi_util::SetProperty(env, js_data, "text", napi_util::NewString(env, cb->text));
            break;
        case EVENT_DONE:
        case EVENT_STOPPED:
            js_event = napi_util::NewString(env, cb->event == EVENT_DONE ? "done" : "stopped");
            napi_util::SetProperty(env, js_data, "promptTokens", napi_util::NewInt32(env, cb->prompt_tokens));
            napi_util::SetProperty(env, js_data, "generatedTokens", napi_util::NewInt32(env, cb->generated_tokens));
            napi_util::SetProperty(env, js_data, "ttftMs", napi_util::NewDouble(env, cb->ttft_ms));
            napi_util::SetProperty(env, js_data, "tokensPerSecond", napi_util::NewDouble(env, cb->tokens_per_second));
            break;
        case EVENT_ERROR:
            js_event = napi_util::NewString(env, "error");
            napi_util::SetProperty(env, js_data, "code", napi_util::NewInt32(env, cb->error_code));
            napi_util::SetProperty(env, js_data, "message", napi_util::NewString(env, cb->error_message));
            break;
        default:
            js_event = napi_util::NewString(env, "unknown");
            break;
    }

    napi_value argv[2] = { js_event, js_data };
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_call_function(env, undefined, js_cb, 2, argv, nullptr);

    delete cb;
}

void SendToken(TsFn * cb, const char * text) {
    GenCallbackData * data = new GenCallbackData();
    std::memset(data, 0, sizeof(*data));
    data->event = EVENT_TOKEN;
    strncpy(data->text, text, sizeof(data->text) - 1);
    cb->Call(data);
}

void SendDone(TsFn * cb, const GenerateStats & stats) {
    GenCallbackData * data = new GenCallbackData();
    std::memset(data, 0, sizeof(*data));
    data->event = EVENT_DONE;
    FillStats(data, stats);
    cb->Call(data);
}

void SendStopped(TsFn * cb, const GenerateStats & stats) {
    GenCallbackData * data = new GenCallbackData();
    std::memset(data, 0, sizeof(*data));
    data->event = EVENT_STOPPED;
    FillStats(data, stats);
    cb->Call(data);
}

void SendError(TsFn * cb, int32_t code, const char * message) {
    GenCallbackData * data = new GenCallbackData();
    std::memset(data, 0, sizeof(*data));
    data->event = EVENT_ERROR;
    data->error_code = code;
    snprintf(data->error_message, sizeof(data->error_message), "%s", message);
    cb->Call(data);
}

} // namespace

// generate(prompt: string, params: GenerateParams, callback: (event, data) => void): number (requestId)
static napi_value Generate(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 3) {
        napi_util::ThrowError(env, error_code_value(ErrorCode::InvalidArgument), "prompt, params and callback are required");
        return nullptr;
    }

    std::string prompt;
    if (!napi_util::GetString(env, args[0], prompt)) {
        napi_util::ThrowError(env, error_code_value(ErrorCode::InvalidArgument), "prompt must be a string");
        return nullptr;
    }

    if (!napi_util::IsFunction(env, args[2])) {
        napi_util::ThrowError(env, error_code_value(ErrorCode::InvalidArgument), "callback must be a function");
        return nullptr;
    }

    if (!EngineState::Instance().IsLoaded()) {
        napi_util::ThrowError(env, error_code_value(ErrorCode::ModelNotLoaded), "model not loaded");
        return nullptr;
    }

    // 分配并发槽位（非阻塞，槽位满则报错）
    llama_seq_id seq_id = -1;
    std::shared_ptr<std::atomic_bool> stop_flag;
    uint64_t request_id = EngineState::Instance().BeginGenerate(SlotPool::Napi, seq_id, stop_flag);
    if (request_id == 0) {
        napi_util::ThrowError(env, error_code_value(ErrorCode::InvalidState), "no available generation slot");
        return nullptr;
    }

    GenerateParams params;
    params.prompt = prompt;

    double temperature = params.temperature;
    double top_p = params.top_p;
    double repeat_penalty = params.repeat_penalty;
    int32_t top_k = params.top_k;
    int32_t max_tokens = params.max_tokens;
    int32_t threads = params.threads;

    napi_util::GetOptionalDouble(env, args[1], "temperature", temperature);
    napi_util::GetOptionalInt32(env, args[1], "topK", top_k);
    napi_util::GetOptionalDouble(env, args[1], "topP", top_p);
    napi_util::GetOptionalDouble(env, args[1], "repeatPenalty", repeat_penalty);
    napi_util::GetOptionalInt32(env, args[1], "maxTokens", max_tokens);
    napi_util::GetOptionalInt32(env, args[1], "threads", threads);

    params.temperature = static_cast<float>(temperature);
    params.top_k = top_k;
    params.top_p = static_cast<float>(top_p);
    params.repeat_penalty = static_cast<float>(repeat_penalty);
    params.max_tokens = max_tokens;
    params.threads = threads;

    TsFn * cb = new TsFn(env, args[2], "generate", GenerateJsCallback);
    if (!cb->valid()) {
        EngineState::Instance().EndGenerate(request_id, seq_id);
        delete cb;
        napi_util::ThrowError(env, error_code_value(ErrorCode::InferenceFailed), "failed to create callback");
        return nullptr;
    }

    // 异步执行：推理置于独立线程（借鉴 llama-server），逐 token / 完成经 TSFN 回调
    bool ok = inference::RunGenerationAsync(
        request_id,
        seq_id,
        stop_flag,
        params,
        [cb](const char * text) { SendToken(cb, text); },
        [cb](inference::GenResult result, const GenerateStats & stats) {
            if (result == inference::GenResult::Completed) {
                SendDone(cb, stats);
            } else if (result == inference::GenResult::Aborted) {
                SendStopped(cb, stats);
            } else {
                SendError(cb, error_code_value(ErrorCode::InferenceFailed), "generation failed");
            }
            cb->Release();
            delete cb;
        },
        []() { return false; });

    if (!ok) {
        EngineState::Instance().EndGenerate(request_id, seq_id);
        cb->Release();
        delete cb;
        napi_util::ThrowError(env, error_code_value(ErrorCode::InferenceFailed), "failed to create inference thread");
        return nullptr;
    }

    napi_value result = nullptr;
    napi_create_int64(env, static_cast<int64_t>(request_id), &result);
    return result;
}

// stopGenerate(requestId: number): void
static napi_value StopGenerate(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc >= 1) {
        int64_t request_id = 0;
        if (napi_get_value_int64(env, args[0], &request_id) == napi_ok) {
            EngineState::Instance().RequestStop(static_cast<uint64_t>(request_id));
        }
    }

    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

// stopAllGenerations(): void
static napi_value StopAllGenerations(napi_env env, napi_callback_info info) {
    EngineState::Instance().RequestStopAll();

    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

// 注册生成相关接口
void RegisterGenerateApi(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "generate", nullptr, Generate, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopGenerate", nullptr, StopGenerate, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopAllGenerations", nullptr, StopAllGenerations, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
