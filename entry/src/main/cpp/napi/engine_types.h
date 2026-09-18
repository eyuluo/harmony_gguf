#ifndef HARMONY_GGUF_ENGINE_TYPES_H
#define HARMONY_GGUF_ENGINE_TYPES_H

#include <cstdint>
#include <string>
#include <vector>

// 模型元数据（对应 NAPI ModelMetadata）
struct ModelMetadata {
    std::string architecture;
    std::string parameters;
    std::string quantization;
    uint32_t context_length = 0;
    std::string tokenizer;
    uint64_t file_size = 0;
    uint32_t embd_dim = 0; // 模型输入 embedding 维度（用于 mmproj 匹配）
};

// mmproj 视觉投影元数据（对应 NAPI MmprojMetadata）
struct MmprojMetadata {
    std::string architecture;    // "clip"
    std::string projector_type;  // "mlp" / "qwen2vl" 等
    uint32_t embd_dim = 0;       // 投影输出维度（用于与模型匹配）
    bool has_vision = false;
    bool has_audio = false;
    uint64_t file_size = 0;
};

// 生成参数（对应 NAPI GenerateParams）
struct GenerateParams {
    std::string prompt;
    float temperature = 0.8f;
    int32_t top_k = 40;
    float top_p = 0.95f;
    float repeat_penalty = 1.0f;
    int32_t max_tokens = 512;
    int32_t threads = 0;
    std::vector<std::string> images; // 图片文件路径（多模态，空 = 纯文本）
};

// 生成统计（对应 NAPI GenerateStats）
struct GenerateStats {
    int32_t prompt_tokens = 0;
    int32_t generated_tokens = 0;
    double ttft_ms = 0.0;
    double tokens_per_second = 0.0;
};

#endif // HARMONY_GGUF_ENGINE_TYPES_H
