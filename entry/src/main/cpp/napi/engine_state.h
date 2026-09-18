#ifndef HARMONY_GGUF_ENGINE_STATE_H
#define HARMONY_GGUF_ENGINE_STATE_H

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "llama.h"

// 多模态视觉上下文（libmtmd），在 engine_state.cpp 中定义与释放
struct mtmd_context;

// 槽位池来源：NAPI 直接调用与 Serve HTTP 服务各自独立池，互不抢占
enum class SlotPool : uint8_t {
    Napi = 0,  // NAPI generate 直接调用
    Serve = 1, // HTTP 服务（/v1/completions、/v1/chat/completions）
};

// 加载模型时的配置（对应 NAPI loadModel 的加载参数）
struct LoadConfig {
    uint32_t context_length = 0; // 0 = 使用模型默认
    int32_t  threads = 0;        // 0 = 使用默认线程数
    uint32_t parallel = 8;       // 每池最大并发槽位数（软上限，槽位按需分配；NAPI 与 Serve 各 parallel 个）
    std::string mmproj_path;     // mmproj 视觉投影文件路径（空 = 纯文本，不启用多模态）
};

// 引擎全局状态：单模型实例 + 多槽位并发。
// 每个生成任务占用一个 seq_id（KV cache 序列槽位），推理在独立 pthread 执行。
// llama_context 非线程安全，decode/采样用 decode_mutex_ 互斥，请求间交错执行。
class EngineState {
public:
    static EngineState & Instance();

    EngineState(const EngineState &) = delete;
    EngineState & operator=(const EngineState &) = delete;

    // 加载模型（若已有模型则先卸载），成功返回 0，失败返回错误码
    int32_t LoadModel(const std::string & path, const LoadConfig & config);
    // 卸载当前模型
    void UnloadModel();

    bool IsLoaded() const;

    llama_model * model() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return model_;
    }

    llama_context * ctx() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return ctx_;
    }

    const llama_vocab * vocab() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return model_ != nullptr ? llama_model_get_vocab(model_) : nullptr;
    }

    // 多模态视觉上下文（未加载 mmproj 时为 nullptr）
    mtmd_context * mtmd_ctx() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return mtmd_ctx_;
    }

    // 每槽位逻辑上下文软上限（用于 context shift；未加载时为 0）
    uint32_t slot_context() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return slot_context_;
    }

    // decode/采样的互斥锁：RunGeneration 在每次 decode 前加锁。
    std::mutex & decode_mutex() { return decode_mutex_; }

    // ---- 生成会话（槽位）管理 ----

    // 非阻塞从指定槽位池分配一个槽位：返回 request id（>0），该池无空闲槽位返回 0。
    // 成功时同时写入 seq_id 与 per-request 停止标志。
    uint64_t BeginGenerate(SlotPool pool, llama_seq_id & out_seq_id,
                           std::shared_ptr<std::atomic_bool> & out_stop_flag);

    // 阻塞从指定槽位池分配一个槽位：等待该池空闲槽位，external_stop 或全局停止时返回 0。
    uint64_t BeginGenerateBlocking(SlotPool pool, llama_seq_id & out_seq_id,
                                   std::shared_ptr<std::atomic_bool> & out_stop_flag,
                                   const std::function<bool()> & external_stop);

    // 结束会话：释放槽位、注销停止标志、清除该序列 KV cache。
    void EndGenerate(uint64_t id, llama_seq_id seq_id);

    // 请求停止指定会话（按 request id）
    void RequestStop(uint64_t id);

    // 请求停止所有会话（stopAll / 卸载模型）
    void RequestStopAll();
    void ClearStopAll() { stop_all_.store(false, std::memory_order_relaxed); }
    bool StopAllRequested() const { return stop_all_.load(std::memory_order_relaxed); }

    // 当前正在 decode 的请求的停止标志（供 llama abort_callback 查询）
    void SetActiveStopFlag(const std::atomic_bool * flag) { active_stop_flag_.store(flag, std::memory_order_relaxed); }
    void ClearActiveStopFlag() { active_stop_flag_.store(nullptr, std::memory_order_relaxed); }
    bool ActiveStopRequested() const {
        const std::atomic_bool * flag = active_stop_flag_.load(std::memory_order_relaxed);
        return flag != nullptr && flag->load(std::memory_order_relaxed);
    }

    // 等待所有生成会话结束（调用前应先 RequestStopAll 以触发生成线程退出）
    void WaitGenerateEnd() {
        std::unique_lock<std::mutex> lock(mutex_);
        gen_cv_.wait(lock, [this]() { return active_count_ == 0; });
    }

private:
    EngineState() = default;

    int32_t AcquireSlotLocked(SlotPool pool);
    void ReleaseUnusedSlot(int32_t seq_id);
    void ReleaseSlot(llama_seq_id seq_id);
    // 已分配槽位后：注册会话、递增活跃计数、写回输出参数，返回 request id
    uint64_t CommitGenerate(int32_t seq_id, llama_seq_id & out_seq_id,
                            std::shared_ptr<std::atomic_bool> & out_stop_flag);

    mutable std::mutex mutex_;       // 保护 model_/ctx_/mtmd_ctx_/slot_context_/active_count_ 生命周期
    std::condition_variable gen_cv_; // 等待所有生成结束
    std::mutex decode_mutex_;        // 保护 llama_decode/采样/KV cache 操作
    llama_model * model_ = nullptr;
    llama_context * ctx_ = nullptr;
    mtmd_context * mtmd_ctx_ = nullptr;
    uint32_t slot_context_ = 0;
    int32_t active_count_ = 0;

    std::atomic_bool stop_all_{false};                                  // 停止所有
    std::atomic<const std::atomic_bool *> active_stop_flag_{nullptr};   // 当前 decode 的请求停止标志

    std::atomic<uint64_t> next_id_{1};

    std::mutex slot_mutex_;
    std::condition_variable slot_cv_;
    std::vector<bool> slot_used_;      // seq_id 占用表：Napi 池 [0, n_slots_per_pool_)，Serve 池 [n_slots_per_pool_, 2*n_slots_per_pool_)
    size_t n_slots_per_pool_ = 0;      // 每池最大并发槽位数（软上限，未加载时为 0）

    std::mutex sessions_mutex_;
    std::unordered_map<uint64_t, std::shared_ptr<std::atomic_bool>> sessions_;
};

#endif // HARMONY_GGUF_ENGINE_STATE_H
