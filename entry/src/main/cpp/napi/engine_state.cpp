#include "engine_state.h"

#include <algorithm>
#include <cstdio>
#include <sys/stat.h>

#include "error_code.h"
#include "mtmd.h"
#include "conversation_slots.h"
#include "ggml-cpu.h"
#include "llama-chat.h"
#ifdef GGML_USE_HARMONY_NPU
#include "harmony_npu.h"
#endif

namespace {
struct PendingModel {
    llama_model * model = nullptr;
    llama_context * context = nullptr;
    ggml_threadpool_t threadpool = nullptr;
    mtmd_context * projector = nullptr;
    bool committed = false;
    ~PendingModel() {
        if (committed) { return; }
#ifdef GGML_USE_HARMONY_NPU
        try {
            HarmonyNpuConfigure(false);
        } catch (...) {
            fprintf(stderr, "[Harmony-GGUF] 清理失败加载的 NPU 状态时发生异常\n");
        }
#endif
        if (projector) { mtmd_free(projector); }
        if (context) {
            llama_detach_threadpool(context);
            llama_free(context);
        }
        if (threadpool) { ggml_threadpool_free(threadpool); }
        if (model) { llama_model_free(model); }
    }
};
}

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

int32_t EngineState::AcquireSlotLocked(SlotPool pool, uint64_t conversation_id) {
    if (n_slots_per_pool_ == 0 || slot_used_.empty()) {
        return -1;
    }
    const size_t begin = (pool == SlotPool::Napi) ? 0 : n_slots_per_pool_;
    const size_t end = begin + n_slots_per_pool_;
    const size_t selected = SelectConversationSlot(slot_used_, slot_owners_, slot_recency_,
        begin, end, conversation_id);
    if (selected == slot_used_.size()) {
        return -1;
    }
    slot_reset_[selected] = conversation_id == 0 || slot_owners_[selected] != conversation_id;
    slot_owners_[selected] = conversation_id;
    slot_recency_[selected] = ++recency_clock_;
    slot_used_[selected] = true;
    return static_cast<int32_t>(selected);
}

void EngineState::ReleaseUnusedSlot(int32_t seq_id) {
    std::lock_guard<std::mutex> lock(slot_mutex_);
    if (seq_id >= 0 && static_cast<size_t>(seq_id) < slot_used_.size()) {
        slot_used_[static_cast<size_t>(seq_id)] = false;
    }
    slot_cv_.notify_one();
}

void EngineState::ReleaseSlot(llama_seq_id seq_id) {
    // 先清理 KV，再释放槽位，避免新任务复用 seq_id 后被旧任务清空上下文。
    {
        std::lock_guard<std::mutex> lock(decode_mutex_);
        {
            std::lock_guard<std::mutex> slot_lock(slot_mutex_);
            if (slot_owners_[seq_id] == 0) {
                cached_tokens_[seq_id].clear();
            }
        }
        if (ctx_ != nullptr) {
            llama_memory_t mem = llama_get_memory(ctx_);
            if (mem != nullptr && cached_tokens_[seq_id].empty()) {
                llama_memory_seq_rm(mem, seq_id, -1, -1);
            }
        }
    }
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        if (seq_id >= 0 && static_cast<size_t>(seq_id) < slot_used_.size()) {
            slot_used_[static_cast<size_t>(seq_id)] = false;
        }
        slot_cv_.notify_one();
    }
}

uint64_t EngineState::CommitGenerate(int32_t seq_id, llama_seq_id & out_seq_id,
                                     std::shared_ptr<std::atomic_bool> & out_stop_flag) {
    std::lock_guard<std::mutex> lifecycle_lock(mutex_);
    if (model_ == nullptr || stop_all_.load(std::memory_order_relaxed)) {
        return 0;
    }

    auto flag = std::make_shared<std::atomic_bool>(false);
    uint64_t id = next_id_.fetch_add(1, std::memory_order_relaxed);

    {
        std::lock_guard<std::mutex> lock(sessions_mutex_);
        sessions_[id] = flag;
    }
    active_count_++;

    out_seq_id = static_cast<llama_seq_id>(seq_id);
    out_stop_flag = flag;
    return id;
}

uint64_t EngineState::BeginGenerate(SlotPool pool, llama_seq_id & out_seq_id,
                                    std::shared_ptr<std::atomic_bool> & out_stop_flag, uint64_t conversation_id) {
    int32_t seq_id = -1;
    bool reset = false;
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        seq_id = AcquireSlotLocked(pool, conversation_id);
        if (seq_id >= 0) {
            reset = slot_reset_[seq_id];
        }
    }
    if (seq_id < 0) {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        fprintf(stderr, "[Harmony-GGUF] 槽位分配失败：来源=%s，每池容量=%zu，停止状态=%d，占用=",
            pool == SlotPool::Napi ? "NAPI" : "Serve", n_slots_per_pool_, StopAllRequested());
        for (bool used : slot_used_) {
            fprintf(stderr, "%d", used ? 1 : 0);
        }
        fprintf(stderr, "\n");
        return 0;
    }
    uint64_t id = CommitGenerate(seq_id, out_seq_id, out_stop_flag);
    if (id == 0) {
        ReleaseUnusedSlot(seq_id);
    } else if (reset) {
        std::lock_guard<std::mutex> lock(decode_mutex_);
        cached_tokens_[seq_id].clear();
        if (ctx_ != nullptr) {
            auto mem = llama_get_memory(ctx_);
            if (mem != nullptr) {
                llama_memory_seq_rm(mem, seq_id, -1, -1);
            }
        }
    }
    return id;
}

void EngineState::DeleteConversation(uint64_t conversation_id) {
    if (conversation_id == 0) {
        return;
    }
    std::lock_guard<std::mutex> lifecycle_lock(mutex_);
    std::lock_guard<std::mutex> decode_lock(decode_mutex_);
    std::lock_guard<std::mutex> slot_lock(slot_mutex_);
    for (size_t i = 0; i < slot_owners_.size(); ++i) {
        if (slot_owners_[i] != conversation_id) {
            continue;
        }
        slot_owners_[i] = 0;
        slot_recency_[i] = 0;
        if (!slot_used_[i]) {
            cached_tokens_[i].clear();
            if (ctx_ != nullptr) {
                auto mem = llama_get_memory(ctx_);
                if (mem != nullptr) {
                    llama_memory_seq_rm(mem, static_cast<llama_seq_id>(i), -1, -1);
                }
            }
        }
    }
}

uint64_t EngineState::BeginGenerateBlocking(SlotPool pool, llama_seq_id & out_seq_id,
                                            std::shared_ptr<std::atomic_bool> & out_stop_flag,
                                            const std::function<bool()> & external_stop,
                                            std::chrono::milliseconds timeout) {
    std::unique_lock<std::mutex> lock(slot_mutex_);
    const bool available = slot_cv_.wait_for(lock, timeout, [this, pool, &external_stop]() {
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
    if (!available || slot_used_.empty() || n_slots_per_pool_ == 0 || external_stop() ||
        stop_all_.load(std::memory_order_relaxed)) {
        return 0;
    }
    int32_t seq_id = AcquireSlotLocked(pool);
    if (seq_id < 0) {
        return 0;
    }
    lock.unlock();

    uint64_t id = CommitGenerate(seq_id, out_seq_id, out_stop_flag);
    if (id == 0) {
        ReleaseUnusedSlot(seq_id);
    }
    return id;
}

void EngineState::EndGenerate(uint64_t id, llama_seq_id seq_id) {
    bool removed = false;
    {
        std::lock_guard<std::mutex> lock(sessions_mutex_);
        removed = sessions_.erase(id) > 0;
    }
    if (!removed) {
        return;
    }
    ReleaseSlot(seq_id);
    fprintf(stderr, "[Harmony-GGUF] 请求 %llu 已释放槽位 %d\n",
        static_cast<unsigned long long>(id), seq_id);
    {
        std::lock_guard<std::mutex> lock(mutex_);
        active_count_--;
        if (active_count_ == 0 && clear_stop_all_when_idle_.load(std::memory_order_relaxed)) {
            stop_all_.store(false, std::memory_order_relaxed);
            clear_stop_all_when_idle_.store(false, std::memory_order_relaxed);
        }
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

void EngineState::RequestStopAll(bool clear_when_idle) {
    stop_all_.store(true, std::memory_order_relaxed);
    clear_stop_all_when_idle_.store(clear_when_idle, std::memory_order_relaxed);
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
    if (clear_when_idle) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (active_count_ == 0) {
            stop_all_.store(false, std::memory_order_relaxed);
            clear_stop_all_when_idle_.store(false, std::memory_order_relaxed);
        }
    }
}

void EngineState::NotifySlotWaiters() {
    std::lock_guard<std::mutex> lock(slot_mutex_);
    slot_cv_.notify_all();
}

int32_t EngineState::LoadModel(const std::string & path, const LoadConfig & config) {
    std::lock_guard<std::mutex> model_op_lock(model_op_mutex_);
    // 停止并等待所有旧推理线程退出；free 在锁内完成，避免 use-after-free
    // 加载完成前保持 stop_all_，阻止加载期间新请求进入（Serve 阻塞请求被唤醒返回，NAPI 因未加载被拒）
    RequestStopAll();
    {
        std::unique_lock<std::mutex> lock(mutex_);
        gen_cv_.wait(lock, [this]() { return active_count_ == 0; });

#ifdef GGML_USE_HARMONY_NPU
        HarmonyNpuConfigure(false);
#endif

        if (mtmd_ctx_ != nullptr) {
            mtmd_free(mtmd_ctx_);
            mtmd_ctx_ = nullptr;
        }
        if (ctx_ != nullptr) {
            llama_detach_threadpool(ctx_);
            llama_free(ctx_);
            ctx_ = nullptr;
        }
        if (cpu_threadpool_ != nullptr) {
            ggml_threadpool_free(cpu_threadpool_);
            cpu_threadpool_ = nullptr;
        }
        if (model_ != nullptr) {
            llama_model_free(model_);
            model_ = nullptr;
        }
        slot_context_ = 0;
        context_threads_ = 0;
        decltype(cached_tokens_)().swap(cached_tokens_);
    }
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        decltype(slot_used_)().swap(slot_used_);
        decltype(slot_owners_)().swap(slot_owners_);
        decltype(slot_recency_)().swap(slot_recency_);
        decltype(slot_reset_)().swap(slot_reset_);
        recency_clock_ = 0;
        n_slots_per_pool_ = 0;
    }
    {
        std::lock_guard<std::mutex> lock(sessions_mutex_);
        sessions_.clear();
    }

    try {
    PendingModel pending;
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
    model_params.vocab_only = config.vocab_only;
#ifdef GGML_USE_HARMONY_NPU
    HarmonyNpuConfigure(config.use_npu && !config.vocab_only);
#endif

    llama_model * model = pending.model = llama_model_load_from_file(path.c_str(), model_params);
    if (model == nullptr) {
        fprintf(stderr, "[Harmony-GGUF] llama_model_load_from_file failed\n");
        ClearStopAll();
        return error_code_value(ErrorCode::ModelLoadFailed);
    }

    // parallel 为每池最大并发槽位数（软上限），槽位按需分配；KV 统一缓冲，总容量 = 每槽位长度 × 2 × parallel
    const uint32_t parallel = config.parallel > 0 ? config.parallel : 1;
    const uint32_t model_ctx = static_cast<uint32_t>(llama_model_n_ctx_train(model));
    const uint32_t available_ctx = model_ctx > 0 ? model_ctx : 4096u;
    const uint32_t n_ctx_seq = config.context_length > 0
        ? std::min(config.context_length, available_ctx)
        : std::min(available_ctx, 4096u);

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.kv_unified = true;                  // 统一 KV 缓冲：seq_id 按需分配（上限 LLAMA_MAX_SEQ），不预分割槽位
    ctx_params.n_ctx = n_ctx_seq * parallel * 2;   // 总 KV 容量（所有槽位共享）
    ctx_params.n_seq_max = parallel * 2;           // 逻辑槽位上限（recurrent 状态与输出缓冲按此预留）
    if (config.threads > 0) {
        ctx_params.n_threads = config.threads;
        ctx_params.n_threads_batch = config.threads;
    }
    llama_context * ctx = nullptr;
    ggml_threadpool_t cpu_threadpool = nullptr;
    if (!config.vocab_only) {
        ctx = pending.context = llama_init_from_model(model, ctx_params);
        if (ctx == nullptr) {
            fprintf(stderr, "[Harmony-GGUF] llama_init_from_model failed\n");
            ClearStopAll();
            return error_code_value(ErrorCode::ModelLoadFailed);
        }
        llama_set_abort_callback(ctx, abort_callback, nullptr);
        auto threadpool_params = ggml_threadpool_params_default(llama_n_threads(ctx));
        threadpool_params.poll = 0;
        threadpool_params.paused = true;
        cpu_threadpool = pending.threadpool = ggml_threadpool_new(&threadpool_params);
        if (cpu_threadpool == nullptr) {
            ClearStopAll();
            return error_code_value(ErrorCode::OutOfMemory);
        }
        llama_attach_threadpool(ctx, cpu_threadpool, cpu_threadpool);
    }

    // 加载多模态视觉投影（mmproj）；加载失败仅禁用多模态，不阻断纯文本模型
    mtmd_context * mctx = nullptr;
    if (!config.mmproj_path.empty()) {
        struct stat mst;
        if (stat(config.mmproj_path.c_str(), &mst) != 0) {
            fprintf(stderr, "[Harmony-GGUF] mmproj file not found: %s\n", config.mmproj_path.c_str());
        } else {
            mtmd_context_params mparams = mtmd_context_params_default();
            mparams.use_gpu = false;                                  // 纯 CPU 后端
            mparams.n_threads = ctx_params.n_threads_batch;
            mparams.image_max_tokens = config.image_max_tokens > 0 ? config.image_max_tokens : -1;
            mparams.warmup = false;                                   // 跳过预热，缩短加载耗时
            mparams.print_timings = false;
            mctx = pending.projector = mtmd_init_from_file(config.mmproj_path.c_str(), model, mparams);
            if (mctx == nullptr) {
                fprintf(stderr, "[Harmony-GGUF] mtmd_init_from_file failed: %s\n", config.mmproj_path.c_str());
            }
        }
    }

    std::vector<bool> slots(static_cast<size_t>(parallel) * 2, false);
    std::vector<std::vector<llama_token>> tokens(slots.size());
    std::vector<uint64_t> owners(slots.size(), 0);
    std::vector<uint64_t> recency(slots.size(), 0);
    std::vector<bool> reset(slots.size(), true);
    {
        std::lock_guard<std::mutex> lock(mutex_);
        model_ = model;
        ctx_ = ctx;
        cpu_threadpool_ = cpu_threadpool;
        mtmd_ctx_ = mctx;
        slot_context_ = n_ctx_seq; // 每槽位逻辑软上限（kv_unified 下 llama_n_ctx_seq 返回总容量，不可用）
        context_threads_ = ctx_params.n_threads;
    }
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        n_slots_per_pool_ = parallel;
        slot_used_.swap(slots);
        cached_tokens_.swap(tokens);
        slot_owners_.swap(owners);
        slot_recency_.swap(recency);
        slot_reset_.swap(reset);
    }
    pending.committed = true;
    ClearStopAll();

    fprintf(stderr, "[Harmony-GGUF] model loaded successfully (parallel=%u per pool, total_seq=%u, slot_ctx=%u, kv_unified)\n",
            parallel, parallel * 2, n_ctx_seq);

    return error_code_value(ErrorCode::Ok);
    } catch (const std::bad_alloc &) {
        ClearStopAll();
        return error_code_value(ErrorCode::OutOfMemory);
    } catch (const std::exception & error) {
        fprintf(stderr, "[Harmony-GGUF] 模型初始化失败：%s\n", error.what());
        ClearStopAll();
        return error_code_value(ErrorCode::ModelLoadFailed);
    }
}

void EngineState::UnloadModel() {
    std::lock_guard<std::mutex> model_op_lock(model_op_mutex_);
    // 停止并等待所有推理线程退出；free 在锁内完成，避免释放其正在使用的 ctx
    RequestStopAll();
    {
        std::unique_lock<std::mutex> lock(mutex_);
        gen_cv_.wait(lock, [this]() { return active_count_ == 0; });

#ifdef GGML_USE_HARMONY_NPU
        HarmonyNpuConfigure(false);
#endif

        if (mtmd_ctx_ != nullptr) {
            mtmd_free(mtmd_ctx_);
            mtmd_ctx_ = nullptr;
        }
        if (ctx_ != nullptr) {
            llama_detach_threadpool(ctx_);
            llama_free(ctx_);
            ctx_ = nullptr;
        }
        if (cpu_threadpool_ != nullptr) {
            ggml_threadpool_free(cpu_threadpool_);
            cpu_threadpool_ = nullptr;
        }
        if (model_ != nullptr) {
            llama_model_free(model_);
            model_ = nullptr;
        }
        slot_context_ = 0;
        context_threads_ = 0;
        decltype(cached_tokens_)().swap(cached_tokens_);
    }
    {
        std::lock_guard<std::mutex> lock(slot_mutex_);
        decltype(slot_used_)().swap(slot_used_);
        decltype(slot_owners_)().swap(slot_owners_);
        decltype(slot_recency_)().swap(slot_recency_);
        decltype(slot_reset_)().swap(slot_reset_);
        recency_clock_ = 0;
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
    return model_ != nullptr;
}

std::string EngineState::ModelMetaString(const char * key) const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (model_ == nullptr) {
        return "";
    }
    char value[128] = {0};
    const int32_t len = llama_model_meta_val_str(model_, key, value, sizeof(value));
    return len > 0 ? std::string(value, static_cast<size_t>(len)) : std::string();
}

std::string EngineState::ModelChatTemplate() const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (model_ == nullptr) {
        return "";
    }
    const char * value = llama_model_chat_template(model_, nullptr);
    return value != nullptr ? std::string(value) : std::string();
}

std::string EngineState::ResolvedChatTemplate() const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!model_) { return ""; }
    const char * raw = llama_model_chat_template(model_, nullptr);
    const std::string builtin = raw ? raw : "";
    char arch[128] = {};
    const auto length = llama_model_meta_val_str(model_, "general.architecture", arch, sizeof(arch));
    const std::string architecture = length > 0 && length < static_cast<int32_t>(sizeof(arch)) ? arch : "";
    std::vector<std::string> markers;
    if (builtin.empty()) {
        const auto * vocab = llama_model_get_vocab(model_);
        const std::vector<std::string> known = {"<|turn>", "<turn|>", "]~b]", "[e~[", "<|im_start|>",
            "<|im_end|>", "<|header_start|>", "<|header_end|>", "<|start_header_id|>",
            "<|end_header_id|>", "<start_of_turn>", "<｜User｜>", "<｜Assistant｜>", "[INST]", "[/INST]", "<think>"};
        for (int32_t i = 0; vocab && i < llama_vocab_n_tokens(vocab); ++i) {
            const char * token = llama_vocab_get_text(vocab, i);
            if (token && std::find(known.begin(), known.end(), token) != known.end()) { markers.emplace_back(token); }
        }
    }
    return llm_chat_resolve_template(builtin, architecture, markers);
}
