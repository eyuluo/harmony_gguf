<<<<<<< HEAD
#ifndef HARMONY_GGUF_LLAMA_INFERENCE_H
#define HARMONY_GGUF_LLAMA_INFERENCE_H

#include <functional>

#include "engine_types.h"

namespace inference {

// 执行一次生成：tokenize → decode 循环 → 采样
// 每个生成 token 调用一次 on_token（传入 token 文本）
// should_stop 返回 true 时提前中止
// 成功返回 true，out_stats 写入统计信息；失败返回 false
bool RunGeneration(
    const GenerateParams & params,
    const std::function<void(const char * text)> & on_token,
    const std::function<bool()> & should_stop,
    GenerateStats & out_stats);

} // namespace inference

#endif // HARMONY_GGUF_LLAMA_INFERENCE_H
=======
#ifndef HARMONY_GGUF_LLAMA_INFERENCE_H
#define HARMONY_GGUF_LLAMA_INFERENCE_H

#include <functional>

#include "engine_types.h"

namespace inference {

// 生成结果：区分自然结束、被停止、出错
enum class GenResult {
    Completed, // 自然结束（遇到 EOG 或达到 max_tokens）
    Aborted,   // 被 should_stop 中断
    Failed,    // 出错
};

// 执行一次生成：tokenize → decode 循环 → 采样
// 每个生成 token 调用一次 on_token（传入 token 文本）
// should_stop 返回 true 时提前中止，结果返回 Aborted
// 成功返回 Completed/Aborted，out_stats 写入统计信息；出错返回 Failed
GenResult RunGeneration(
    const GenerateParams & params,
    const std::function<void(const char * text)> & on_token,
    const std::function<bool()> & should_stop,
    GenerateStats & out_stats);

} // namespace inference

#endif // HARMONY_GGUF_LLAMA_INFERENCE_H
>>>>>>> cpp
