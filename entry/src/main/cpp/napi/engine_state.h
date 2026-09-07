<<<<<<< HEAD
#ifndef HARMONY_GGUF_ENGINE_STATE_H
#define HARMONY_GGUF_ENGINE_STATE_H

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>

#include "llama.h"

// 加载模型时的配置（对应 NAPI loadModel 的加载参数）
struct LoadConfig {
    uint32_t context_length = 0; // 0 = 使用模型默认
    int32_t  threads = 0;        // 0 = 使用默认线程数
};

// 引擎全局状态：单模型实例（同一时刻仅一个已加载模型）
// 推理在独立 pthread 执行，停止走原子标志位。
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

    // 请求停止当前生成
    void RequestStop() { stop_requested_.store(true, std::memory_order_relaxed); }
    void ClearStop() { stop_requested_.store(false, std::memory_order_relaxed); }
    bool StopRequested() const { return stop_requested_.load(std::memory_order_relaxed); }

private:
    EngineState() = default;

    mutable std::mutex mutex_;
    llama_model * model_ = nullptr;
    llama_context * ctx_ = nullptr;
    std::atomic_bool stop_requested_{false};
};

#endif // HARMONY_GGUF_ENGINE_STATE_H
=======
#ifndef HARMONY_GGUF_ENGINE_STATE_H
#define HARMONY_GGUF_ENGINE_STATE_H

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <string>

#include "llama.h"

// 加载模型时的配置（对应 NAPI loadModel 的加载参数）
struct LoadConfig {
    uint32_t context_length = 0; // 0 = 使用模型默认
    int32_t  threads = 0;        // 0 = 使用默认线程数
};

// 引擎全局状态：单模型实例（同一时刻仅一个已加载模型）
// 推理在独立 pthread 执行，停止走原子标志位。
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

    // 请求停止当前生成
    void RequestStop() { stop_requested_.store(true, std::memory_order_relaxed); }
    void ClearStop() { stop_requested_.store(false, std::memory_order_relaxed); }
    bool StopRequested() const { return stop_requested_.load(std::memory_order_relaxed); }

    // 尝试开始生成：同一时刻仅一个生成任务，返回 false 表示已有生成进行中。
    // 与 LoadModel/UnloadModel 共用 mutex_，保证「检查 generating → free」原子。
    bool TryBeginGenerate() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (generating_) {
            return false;
        }
        generating_ = true;
        return true;
    }

    void EndGenerate() {
        std::lock_guard<std::mutex> lock(mutex_);
        generating_ = false;
        gen_cv_.notify_all();
    }

    // 等待当前生成结束（调用前应先 RequestStop 以触发生成线程退出）
    void WaitGenerateEnd() {
        std::unique_lock<std::mutex> lock(mutex_);
        gen_cv_.wait(lock, [this]() { return !generating_; });
    }

private:
    EngineState() = default;

    mutable std::mutex mutex_;
    std::condition_variable gen_cv_;
    llama_model * model_ = nullptr;
    llama_context * ctx_ = nullptr;
    std::atomic_bool stop_requested_{false};
    bool generating_ = false;
};

#endif // HARMONY_GGUF_ENGINE_STATE_H
>>>>>>> cpp
