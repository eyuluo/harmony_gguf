#include "engine_state.h"

#include <cstdio>
#include <sys/stat.h>

#include "error_code.h"
#include "mtmd.h"

// 停止生成的中止回调：返回 true 时 llama_decode 立即中止
static bool abort_callback(void * /*data*/) {
    EngineState & state = EngineState::Instance();
    return state.StopAllRequested() || state.ActiveStopRequested();
}

// llama.cpp 日志重定向到 stderr（OHOS 下输出到 hilog）
static void llama_log_callback(enum ggml_log_level /*level*/, const char * text, void * /*user_data*/) {
    fprintf(stderr, "llama: %s", text);
}

EngineState & EngineState::Instance() {
    static EngineState instance;
    return instance;
}

int32_t EngineState::AcquireSlotLocked(SlotPool pool) {
    if (n_slots_per_pool_ == 0 || slot_used_.empty()) {
        return -1;
    }
    const size_t begin = (pool == SlotPool::Napi) ? 0 : n_slots_per_pool_;
    const size_t end = begin + n_slots_per_pool_;
    for (size_t i = begin; i < end && i < slot_used_.size(); i++) {
        if (!slot_used_[i]) {
            slot_used_[i] = true;
            return static_cast<int32_t>(i);
        }
    }
    return -1;
}

void EngineState::ReleaseSlot(llama_seq_id seq_id) {
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        if (seq_id >= 0 && static_cast<size_t>(seq_id) < slot_used_.size()) {
            slot_used_[static_cast<size_t>(seq_id)] = false;
        }
        slot_cv_.notify_one();
    }
    // 清除该序列的 KV cache（与 decode 互斥）
    std::lock_guard<std::mutex> lock(decode_mutex_);
    if (ctx_ != nullptr) {
        llama_memory_t mem = llama_get_memory(ctx_);
        if (mem != nullptr) {
            llama_memory_seq_rm(mem, seq_id, -1, -1);
        }
    }
}

uint64_t EngineState::CommitGenerate(int32_t seq_id, llama_seq_id & out_seq_id,
                                     std::shared_ptr<std::atomic_bool> & out_stop_flag) {
    auto flag = std::make_shared<std::atomic_bool>(false);
    uint64_t id = next_id_.fetch_add(1, std::memory_order_relaxed);

    {
        std::lock_guard<std::mutex> lock(sessions_mutex_);
        sessions_[id] = flag;
    }
    {
        std::lock_guard<std::mutex> lock(mutex_);
        active_count_++;
    }

    out_seq_id = static_cast<llama_seq_id>(seq_id);
    out_stop_flag = flag;
    return id;
}

uint64_t EngineState::BeginGenerate(SlotPool pool, llama_seq_id & out_seq_id,
                                    std::shared_ptr<std::atomic_bool> & out_stop_flag) {
    int32_t seq_id = -1;
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        seq_id = AcquireSlotLocked(pool);
    }
    if (seq_id < 0) {
        return 0;
    }
    return CommitGenerate(seq_id, out_seq_id, out_stop_flag);
}

uint64_t EngineState::BeginGenerateBlocking(SlotPool pool, llama_seq_id & out_seq_id,
                                            std::shared_ptr<std::atomic_bool> & out_stop_flag,
                                            const std::function<bool()> & external_stop) {
    std::unique_lock<std::mutex> lock(slot_mutex_);
    slot_cv_.wait(lock, [this, pool, &external_stop]() {
        if (slot_used_.empty() || n_slots_per_pool_ == 0) {
            return true; // 模型未加载，无法服务
        }
        if (external_stop()) {
            return true;
        }
        if (stop_all_.load(std::memory_order_relaxed)) {
            return true;
        }
        const size_t begin = (pool == SlotPool::Napi) ? 0 : n_slots_per_pool_;
        const size_t end = begin + n_slots_per_pool_;
        for (size_t i = begin; i < end && i < slot_used_.size(); i++) {
            if (!slot_used_[i]) {
                return true;
            }
        }
        return false;
    });
    if (slot_used_.empty() || n_slots_per_pool_ == 0 || external_stop() ||
        stop_all_.load(std::memory_order_relaxed)) {
        return 0;
    }
    int32_t seq_id = AcquireSlotLocked(pool);
    if (seq_id < 0) {
        return 0;
    }
    lock.unlock();

    return CommitGenerate(seq_id, out_seq_id, out_stop_flag);
}

void EngineState::EndGenerate(uint64_t id, llama_seq_id seq_id) {
    {
        std::lock_guard<std::mutex> lock(sessions_mutex_);
        sessions_.erase(id);
    }
    ReleaseSlot(seq_id);
    {
        std::lock_guard<std::mutex> lock(mutex_);
        active_count_--;
        gen_cv_.notify_all();
    }
}

void EngineState::RequestStop(uint64_t id) {
    std::lock_guard<std::mutex> lock(sessions_mutex_);
    auto it = sessions_.find(id);
    if (it != sessions_.end()) {
        it->second->store(true, std::memory_order_relaxed);
    }
}

void EngineState::RequestStopAll() {
    stop_all_.store(true, std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(sessions_mutex_);
        for (auto & kv : sessions_) {
            kv.second->store(true, std::memory_order_relaxed);
        }
    }
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        slot_cv_.notify_all();
    }
}

int32_t EngineState::LoadModel(const std::string & path, const LoadConfig & config) {
    // 停止并等待所有旧推理线程退出；free 在锁内完成，避免 use-after-free
    // 加载完成前保持 stop_all_，阻止加载期间新请求进入（Serve 阻塞请求被唤醒返回，NAPI 因未加载被拒）
    RequestStopAll();
    {
        std::unique_lock<std::mutex> lock(mutex_);
        gen_cv_.wait(lock, [this]() { return active_count_ == 0; });

        if (mtmd_ctx_ != nullptr) {
            mtmd_free(mtmd_ctx_);
            mtmd_ctx_ = nullptr;
        }
        if (ctx_ != nullptr) {
            llama_free(ctx_);
            ctx_ = nullptr;
        }
        if (model_ != nullptr) {
            llama_model_free(model_);
            model_ = nullptr;
        }
        slot_context_ = 0;
    }
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        slot_used_.clear();
        n_slots_per_pool_ = 0;
    }
    {
        std::lock_guard<std::mutex> lock(sessions_mutex_);
        sessions_.clear();
    }

    // 耗时加载放在锁外，避免阻塞 generate 的 IsLoaded/BeginGenerate
    llama_backend_init();
    llama_log_set(llama_log_callback, nullptr);

    struct stat st;
    if (stat(path.c_str(), &st) != 0) {
        fprintf(stderr, "[Harmony-GGUF] model file not found: %s\n", path.c_str());
        ClearStopAll();
        return error_code_value(ErrorCode::ModelLoadFailed);
    }
    fprintf(stderr, "[Harmony-GGUF] loading model: %s (%lld bytes)\n", path.c_str(), (long long)st.st_size);

    llama_model_params model_params = llama_model_default_params();

    llama_model * model = llama_model_load_from_file(path.c_str(), model_params);
    if (model == nullptr) {
        fprintf(stderr, "[Harmony-GGUF] llama_model_load_from_file failed\n");
        ClearStopAll();
        return error_code_value(ErrorCode::ModelLoadFailed);
    }

    // parallel 为每池最大并发槽位数（软上限），槽位按需分配；KV 统一缓冲，总容量 = 每槽位长度 × 2 × parallel
    const uint32_t parallel = config.parallel > 0 ? config.parallel : 1;
    uint32_t n_ctx_seq = config.context_length;
    if (n_ctx_seq == 0) {
        n_ctx_seq = static_cast<uint32_t>(llama_model_n_ctx_train(model));
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.kv_unified = true;                  // 统一 KV 缓冲：seq_id 按需分配（上限 LLAMA_MAX_SEQ），不预分割槽位
    ctx_params.n_ctx = n_ctx_seq * parallel * 2;   // 总 KV 容量（所有槽位共享）
    ctx_params.n_seq_max = parallel * 2;           // 逻辑槽位上限（recurrent 状态与输出缓冲按此预留）
    if (config.threads > 0) {
        ctx_params.n_threads = config.threads;
        ctx_params.n_threads_batch = config.threads;
    }

    llama_context * ctx = llama_init_from_model(model, ctx_params);
    if (ctx == nullptr) {
        fprintf(stderr, "[Harmony-GGUF] llama_init_from_model failed\n");
        llama_model_free(model);
        ClearStopAll();
        return error_code_value(ErrorCode::ModelLoadFailed);
    }

    // 绑定中止回调，用于 stopGenerate/stopAll
    llama_set_abort_callback(ctx, abort_callback, nullptr);

    // 加载多模态视觉投影（mmproj）；加载失败仅禁用多模态，不阻断纯文本模型
    mtmd_context * mctx = nullptr;
    if (!config.mmproj_path.empty()) {
        struct stat mst;
        if (stat(config.mmproj_path.c_str(), &mst) != 0) {
            fprintf(stderr, "[Harmony-GGUF] mmproj file not found: %s\n", config.mmproj_path.c_str());
        } else {
            mtmd_context_params mparams = mtmd_context_params_default();
            mparams.use_gpu = false;                                  // 纯 CPU 后端
            mparams.n_threads = config.threads > 0 ? config.threads : 4;
            mparams.warmup = false;                                   // 跳过预热，缩短加载耗时
            mparams.print_timings = false;
            mctx = mtmd_init_from_file(config.mmproj_path.c_str(), model, mparams);
            if (mctx == nullptr) {
                fprintf(stderr, "[Harmony-GGUF] mtmd_init_from_file failed: %s\n", config.mmproj_path.c_str());
            }
        }
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        model_ = model;
        ctx_ = ctx;
        mtmd_ctx_ = mctx;
        slot_context_ = n_ctx_seq; // 每槽位逻辑软上限（kv_unified 下 llama_n_ctx_seq 返回总容量，不可用）
    }
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        n_slots_per_pool_ = parallel;
        slot_used_.assign(static_cast<size_t>(parallel) * 2, false);
    }

    ClearStopAll();

    fprintf(stderr, "[Harmony-GGUF] model loaded successfully (parallel=%u per pool, total_seq=%u, slot_ctx=%u, kv_unified)\n",
            parallel, parallel * 2, n_ctx_seq);

    return error_code_value(ErrorCode::Ok);
}

void EngineState::UnloadModel() {
    // 停止并等待所有推理线程退出；free 在锁内完成，避免释放其正在使用的 ctx
    RequestStopAll();
    {
        std::unique_lock<std::mutex> lock(mutex_);
        gen_cv_.wait(lock, [this]() { return active_count_ == 0; });

        if (mtmd_ctx_ != nullptr) {
            mtmd_free(mtmd_ctx_);
            mtmd_ctx_ = nullptr;
        }
        if (ctx_ != nullptr) {
            llama_free(ctx_);
            ctx_ = nullptr;
        }
        if (model_ != nullptr) {
            llama_model_free(model_);
            model_ = nullptr;
        }
        slot_context_ = 0;
    }
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        slot_used_.clear();
        n_slots_per_pool_ = 0;
    }
    {
        std::lock_guard<std::mutex> lock(sessions_mutex_);
        sessions_.clear();
    }
    ClearStopAll();
}

bool EngineState::IsLoaded() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return model_ != nullptr && ctx_ != nullptr;
}
