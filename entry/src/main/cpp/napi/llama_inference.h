#ifndef HARMONY_GGUF_LLAMA_INFERENCE_H
#define HARMONY_GGUF_LLAMA_INFERENCE_H

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>

#include "engine_types.h"
#include "llama.h"

namespace inference {

// 生成结果：区分自然结束、被停止、出错
enum class GenResult {
    Completed, // 自然结束（遇到 EOG 或达到 max_tokens）
    Aborted,   // 被 should_stop / stop_flag 中断
    Failed,    // 出错
};

// 执行一次生成：tokenize → decode 循环 → 采样。
// seq_id 为分配给该任务的 KV cache 序列槽位。
// stop_flag 为 per-request 停止标志（可为空）。
// 每个生成 token 调用一次 on_token（传入 token 文本）。
// should_stop 返回 true 时提前中止，结果返回 Aborted。
// 成功返回 Completed/Aborted，out_stats 写入统计信息；出错返回 Failed。
GenResult RunGeneration(
    llama_seq_id seq_id,
    const std::shared_ptr<std::atomic_bool> & stop_flag,
    const GenerateParams & params,
    const std::function<void(const char * text)> & on_token,
    const std::function<bool()> & should_stop,
    GenerateStats & out_stats);

// 异步执行生成：在独立线程运行 RunGeneration，结束后释放槽位并回调 on_done。
// 借鉴 llama-server：推理与调用线程（如 HTTP 线程）解耦，避免在请求线程里执行 decode。
// on_token / on_done 在推理线程调用，调用方需自行处理线程安全。
// 返回 false 表示线程创建失败（调用方需自行释放槽位）。
bool RunGenerationAsync(
    uint64_t request_id,
    llama_seq_id seq_id,
    const std::shared_ptr<std::atomic_bool> & stop_flag,
    const GenerateParams & params,
    const std::function<void(const char * text)> & on_token,
    const std::function<void(GenResult, const GenerateStats &)> & on_done,
    const std::function<bool()> & should_stop);

} // namespace inference

#endif // HARMONY_GGUF_LLAMA_INFERENCE_H
