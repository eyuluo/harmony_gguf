#include <napi/native_api.h>
#include <pthread.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "engine_state.h"
#include "engine_types.h"
#include "error_code.h"
#include "llama.h"
#include "napi_util.h"
#include "ts_fn.h"

namespace {

enum GenEvent : int32_t {
    EVENT_TOKEN = 0,
    EVENT_DONE = 1,
    EVENT_ERROR = 2,
};

// 通过 TSFN 传递给 JS 回调的事件数据
struct GenCallbackData {
    int32_t event;
    char text[2048];
    int32_t prompt_tokens;
    int32_t generated_tokens;
    double ttft_ms;
    double tokens_per_second;
    int32_t error_code;
    char error_message[512];
};

struct GenerateTask {
    GenerateParams params;
    TsFn * callback;
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
            js_event = napi_util::NewString(env, "done");
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
    snprintf(data->text, sizeof(data->text), "%s", text);
    cb->Call(data);
}

void SendDone(TsFn * cb, const GenerateStats & stats) {
    GenCallbackData * data = new GenCallbackData();
    std::memset(data, 0, sizeof(*data));
    data->event = EVENT_DONE;
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

// 推理线程：执行完整的生成循环，逐 token 回调
void * GenerateThread(void * arg) {
    GenerateTask * task = static_cast<GenerateTask *>(arg);
    TsFn * cb = task->callback;
    const GenerateParams & params = task->params;

    llama_model * model = EngineState::Instance().model();
    llama_context * ctx = EngineState::Instance().ctx();
    const llama_vocab * vocab = EngineState::Instance().vocab();

    if (model == nullptr || ctx == nullptr || vocab == nullptr) {
        SendError(cb, error_code_value(ErrorCode::ModelNotLoaded), "model not loaded");
        cb->Release();
        delete cb;
        delete task;
        return nullptr;
    }

    EngineState::Instance().ClearStop();

    if (params.threads > 0) {
        llama_set_n_threads(ctx, params.threads, params.threads);
    }

    // 构建采样链：penalties -> top_k -> temp -> top_p -> dist
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    llama_sampler * smpl = llama_sampler_chain_init(sparams);

    const int32_t n_vocab = llama_vocab_n_tokens(vocab);
    llama_sampler_chain_add(smpl, llama_sampler_init_penalties(n_vocab, 64, params.repeat_penalty, 0.0f, 0.0f));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_k(params.top_k));
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(params.temperature));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(params.top_p, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(static_cast<uint32_t>(llama_time_us())));

    // 分词
    const int32_t n_prompt = -llama_tokenize(vocab, params.prompt.c_str(), static_cast<int32_t>(params.prompt.size()),
                                             nullptr, 0, true, true);
    if (n_prompt <= 0) {
        llama_sampler_free(smpl);
        SendError(cb, error_code_value(ErrorCode::InferenceFailed), "failed to tokenize prompt");
        cb->Release();
        delete cb;
        delete task;
        return nullptr;
    }

    std::vector<llama_token> prompt_tokens(static_cast<size_t>(n_prompt));
    if (llama_tokenize(vocab, params.prompt.c_str(), static_cast<int32_t>(params.prompt.size()),
                       prompt_tokens.data(), n_prompt, true, true) < 0) {
        llama_sampler_free(smpl);
        SendError(cb, error_code_value(ErrorCode::InferenceFailed), "failed to tokenize prompt");
        cb->Release();
        delete cb;
        delete task;
        return nullptr;
    }

    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()));

    GenerateStats stats;
    stats.prompt_tokens = n_prompt;

    const int64_t t_start = llama_time_us();
    int64_t t_first = 0;
    bool first_token = true;
    llama_token new_token_id = LLAMA_TOKEN_NULL;

    for (int32_t i = 0; i < params.max_tokens; i++) {
        if (EngineState::Instance().StopRequested()) {
            break;
        }

        if (llama_decode(ctx, batch) != 0) {
            if (EngineState::Instance().StopRequested()) {
                break;
            }
            llama_sampler_free(smpl);
            SendError(cb, error_code_value(ErrorCode::InferenceFailed), "decode failed");
            cb->Release();
            delete cb;
            delete task;
            return nullptr;
        }

        new_token_id = llama_sampler_sample(smpl, ctx, -1);

        if (first_token) {
            t_first = llama_time_us();
            stats.ttft_ms = static_cast<double>(t_first - t_start) / 1000.0;
            first_token = false;
        }

        if (llama_vocab_is_eog(vocab, new_token_id)) {
            break;
        }

        char piece[256] = {0};
        int32_t n = llama_token_to_piece(vocab, new_token_id, piece, static_cast<int32_t>(sizeof(piece)), 0, true);
        if (n > 0) {
            SendToken(cb, piece);
        }

        stats.generated_tokens++;

        llama_sampler_accept(smpl, new_token_id);
        batch = llama_batch_get_one(&new_token_id, 1);
    }

    const int64_t t_end = llama_time_us();
    if (stats.generated_tokens > 0) {
        const double elapsed = static_cast<double>(t_end - t_start) / 1000000.0;
        stats.tokens_per_second = elapsed > 0.0 ? stats.generated_tokens / elapsed : 0.0;
    }

    llama_sampler_free(smpl);

    SendDone(cb, stats);
    cb->Release();
    delete cb;
    delete task;
    return nullptr;
}

} // namespace

// generate(prompt: string, params: GenerateParams, callback: (event, data) => void): void
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
        delete cb;
        napi_util::ThrowError(env, error_code_value(ErrorCode::InferenceFailed), "failed to create callback");
        return nullptr;
    }

    GenerateTask * task = new GenerateTask();
    task->params = params;
    task->callback = cb;

    pthread_t thread;
    int rc = pthread_create(&thread, nullptr, GenerateThread, task);
    if (rc != 0) {
        delete task;
        cb->Release();
        delete cb;
        napi_util::ThrowError(env, error_code_value(ErrorCode::InferenceFailed), "failed to create inference thread");
        return nullptr;
    }
    pthread_detach(thread);

    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

// stopGenerate(): void
static napi_value StopGenerate(napi_env env, napi_callback_info info) {
    EngineState::Instance().RequestStop();

    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

// 注册生成相关接口
void RegisterGenerateApi(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "generate", nullptr, Generate, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopGenerate", nullptr, StopGenerate, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
