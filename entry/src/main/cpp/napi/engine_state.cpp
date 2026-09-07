<<<<<<< HEAD
#include "engine_state.h"

#include <cstdio>
#include <sys/stat.h>

#include "error_code.h"

// 停止生成的中止回调：返回 true 时 llama_decode 立即中止
static bool abort_callback(void * /*data*/) {
    return EngineState::Instance().StopRequested();
}

// llama.cpp 日志重定向到 stderr（OHOS 下输出到 hilog）
static void llama_log_callback(enum ggml_log_level /*level*/, const char * text, void * /*user_data*/) {
    fprintf(stderr, "llama: %s", text);
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
    llama_log_set(llama_log_callback, nullptr);

    // 文件存在性检查
    struct stat st;
    if (stat(path.c_str(), &st) != 0) {
        fprintf(stderr, "[Harmony-GGUF] model file not found: %s\n", path.c_str());
        return error_code_value(ErrorCode::ModelLoadFailed);
    }
    fprintf(stderr, "[Harmony-GGUF] loading model: %s (%lld bytes)\n", path.c_str(), (long long)st.st_size);

    llama_model_params model_params = llama_model_default_params();
    model_params.load_mode = LLAMA_LOAD_MODE_AUTO;
    model_params.progress_callback = nullptr;

    llama_model * model = llama_model_load_from_file(path.c_str(), model_params);
    if (model == nullptr) {
        fprintf(stderr, "[Harmony-GGUF] llama_model_load_from_file failed\n");
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
        fprintf(stderr, "[Harmony-GGUF] llama_init_from_model failed\n");
        llama_model_free(model);
        return error_code_value(ErrorCode::ModelLoadFailed);
    }

    // 绑定中止回调，用于 stopGenerate
    llama_set_abort_callback(ctx, abort_callback, nullptr);

    model_ = model;
    ctx_ = ctx;

    fprintf(stderr, "[Harmony-GGUF] model loaded successfully\n");

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
=======
#include "engine_state.h"

#include <cstdio>
#include <sys/stat.h>

#include "error_code.h"

// 停止生成的中止回调：返回 true 时 llama_decode 立即中止
static bool abort_callback(void * /*data*/) {
    return EngineState::Instance().StopRequested();
}

// llama.cpp 日志重定向到 stderr（OHOS 下输出到 hilog）
static void llama_log_callback(enum ggml_log_level /*level*/, const char * text, void * /*user_data*/) {
    fprintf(stderr, "llama: %s", text);
}

EngineState & EngineState::Instance() {
    static EngineState instance;
    return instance;
}

int32_t EngineState::LoadModel(const std::string & path, const LoadConfig & config) {
    // 停止并等待旧推理线程退出；free 在锁内完成，与 TryBeginGenerate 串行，避免 use-after-free
    RequestStop();
    {
        std::unique_lock<std::mutex> lock(mutex_);
        gen_cv_.wait(lock, [this]() { return !generating_; });

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

    // 耗时加载放在锁外，避免阻塞 generate 的 IsLoaded/TryBeginGenerate
    llama_backend_init();
    llama_log_set(llama_log_callback, nullptr);

    struct stat st;
    if (stat(path.c_str(), &st) != 0) {
        fprintf(stderr, "[Harmony-GGUF] model file not found: %s\n", path.c_str());
        return error_code_value(ErrorCode::ModelLoadFailed);
    }
    fprintf(stderr, "[Harmony-GGUF] loading model: %s (%lld bytes)\n", path.c_str(), (long long)st.st_size);

    llama_model_params model_params = llama_model_default_params();

    llama_model * model = llama_model_load_from_file(path.c_str(), model_params);
    if (model == nullptr) {
        fprintf(stderr, "[Harmony-GGUF] llama_model_load_from_file failed\n");
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
        fprintf(stderr, "[Harmony-GGUF] llama_init_from_model failed\n");
        llama_model_free(model);
        return error_code_value(ErrorCode::ModelLoadFailed);
    }

    // 绑定中止回调，用于 stopGenerate
    llama_set_abort_callback(ctx, abort_callback, nullptr);

    {
        std::lock_guard<std::mutex> lock(mutex_);
        model_ = model;
        ctx_ = ctx;
    }

    fprintf(stderr, "[Harmony-GGUF] model loaded successfully\n");

    return error_code_value(ErrorCode::Ok);
}

void EngineState::UnloadModel() {
    // 停止并等待推理线程退出；free 在锁内完成，避免释放其正在使用的 ctx
    RequestStop();
    {
        std::unique_lock<std::mutex> lock(mutex_);
        gen_cv_.wait(lock, [this]() { return !generating_; });

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
}

bool EngineState::IsLoaded() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return model_ != nullptr && ctx_ != nullptr;
}
>>>>>>> cpp
