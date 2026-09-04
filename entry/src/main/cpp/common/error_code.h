#ifndef HARMONY_GGUF_ERROR_CODE_H
#define HARMONY_GGUF_ERROR_CODE_H

#include <cstdint>

// NAPI 统一错误码（0 / 1001–1007）
enum class ErrorCode : int32_t {
    Ok = 0,
    InvalidArgument = 1001,
    ModelNotLoaded = 1002,
    ModelLoadFailed = 1003,
    InferenceFailed = 1004,
    InvalidState = 1005,
    OutOfMemory = 1006,
    GenerationAborted = 1007,
};

inline int32_t error_code_value(ErrorCode code) {
    return static_cast<int32_t>(code);
}

#endif // HARMONY_GGUF_ERROR_CODE_H
