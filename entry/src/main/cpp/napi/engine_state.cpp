#include "engine_state.h"

#include <cstdio>

#include "error_code.h"

// 停止生成的中止回调：返回 true 时 llama_decode 立即中止
static bool abort_callback(void * /*data*/) {
    return EngineState::Instance().StopRequested();
}

EngineState & EngineState::Instance() {
    static EngineState instance;
    return instance;
}

int32_t EngineState::LoadModel(const std::string & path, const LoadConfig & config) {
    std::lock_guard<std::mutex> lock(mutex_);

    // 单模型实例：先卸载旧模型
    if (ctx_ != nullptr) {
        llama_free(ctx_);
        ctx_ = nullptr;
    }
    if (model_ != nullptr) {
        llama_model_free(model_);
        model_ = nullptr;
    }
    ClearStop();

    llama_backend_init();

    llama_model_params model_params = llama_model_default_params();
    model_params.load_mode = LLAMA_LOAD_MODE_AUTO;
    model_params.progress_callback = nullptr;

    llama_model * model = llama_model_load_from_file(path.c_str(), model_params);
    if (model == nullptr) {
        return error_code_value(ErrorCode::ModelLoadFailed);
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = config.context_length; // 0 = 使用模型默认
    if (config.threads > 0) {
        ctx_params.n_threads = config.threads;
        ctx_params.n_threads_batch = config.threads;
    }

    llama_context * ctx = llama_init_from_model(model, ctx_params);
    if (ctx == nullptr) {
        llama_model_free(model);
        return error_code_value(ErrorCode::ModelLoadFailed);
    }

    // 绑定中止回调，用于 stopGenerate
    llama_set_abort_callback(ctx, abort_callback, nullptr);

    model_ = model;
    ctx_ = ctx;

    return error_code_value(ErrorCode::Ok);
}

void EngineState::UnloadModel() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (ctx_ != nullptr) {
        llama_free(ctx_);
        ctx_ = nullptr;
    }
    if (model_ != nullptr) {
        llama_model_free(model_);
        model_ = nullptr;
    }
    ClearStop();
}

bool EngineState::IsLoaded() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return model_ != nullptr && ctx_ != nullptr;
}
