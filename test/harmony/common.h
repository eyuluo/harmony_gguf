#pragma once

// ============================================================================
// common.h — 测试框架最小工具集
// 角色 C（质量保障）维护
// 提供 testing.h 所需的 string_join 等工具函数，避免依赖上游完整 common.h
// ============================================================================

#include <string>
#include <vector>
#include <sstream>

// 将字符串向量用分隔符连接为单个字符串
inline std::string string_join(const std::vector<std::string> & vec, const std::string & sep) {
    std::string result;
    for (size_t i = 0; i < vec.size(); ++i) {
        if (i > 0) {
            result += sep;
        }
        result += vec[i];
    }
    return result;
}
