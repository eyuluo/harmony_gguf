#ifndef HARMONY_GGUF_NAPI_UTIL_H
#define HARMONY_GGUF_NAPI_UTIL_H

#include <napi/native_api.h>

#include <cstdint>
#include <string>

namespace napi_util {

// 从 napi_value 读取 UTF-8 字符串，失败返回 false
static inline bool GetString(napi_env env, napi_value value, std::string & out) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok) {
        return false;
    }
    out.resize(len);
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, &out[0], len + 1, &copied) != napi_ok) {
        return false;
    }
    out.resize(copied);
    return true;
}

static inline bool GetInt32(napi_env env, napi_value value, int32_t & out) {
    return napi_get_value_int32(env, value, &out) == napi_ok;
}

static inline bool GetUint32(napi_env env, napi_value value, uint32_t & out) {
    return napi_get_value_uint32(env, value, &out) == napi_ok;
}

static inline bool GetDouble(napi_env env, napi_value value, double & out) {
    return napi_get_value_double(env, value, &out) == napi_ok;
}

static inline bool GetBool(napi_env env, napi_value value, bool & out) {
    return napi_get_value_bool(env, value, &out) == napi_ok;
}

// 读取对象属性，不存在或非对象时返回 nullptr
static inline napi_value GetProperty(napi_env env, napi_value obj, const char * name) {
    napi_value result = nullptr;
    if (napi_get_named_property(env, obj, name, &result) != napi_ok) {
        return nullptr;
    }
    return result;
}

static inline bool GetOptionalString(napi_env env, napi_value obj, const char * name, std::string & out) {
    napi_value value = GetProperty(env, obj, name);
    if (value == nullptr) {
        return false;
    }
    bool has = false;
    napi_has_named_property(env, obj, name, &has);
    if (!has) {
        return false;
    }
    return GetString(env, value, out);
}

static inline bool GetOptionalInt32(napi_env env, napi_value obj, const char * name, int32_t & out) {
    napi_value value = GetProperty(env, obj, name);
    if (value == nullptr) {
        return false;
    }
    bool has = false;
    napi_has_named_property(env, obj, name, &has);
    if (!has) {
        return false;
    }
    return GetInt32(env, value, out);
}

static inline bool GetOptionalUint32(napi_env env, napi_value obj, const char * name, uint32_t & out) {
    napi_value value = GetProperty(env, obj, name);
    if (value == nullptr) {
        return false;
    }
    bool has = false;
    napi_has_named_property(env, obj, name, &has);
    if (!has) {
        return false;
    }
    return GetUint32(env, value, out);
}

static inline bool GetOptionalDouble(napi_env env, napi_value obj, const char * name, double & out) {
    napi_value value = GetProperty(env, obj, name);
    if (value == nullptr) {
        return false;
    }
    bool has = false;
    napi_has_named_property(env, obj, name, &has);
    if (!has) {
        return false;
    }
    return GetDouble(env, value, out);
}

static inline napi_value NewString(napi_env env, const char * str) {
    napi_value result = nullptr;
    napi_create_string_utf8(env, str, NAPI_AUTO_LENGTH, &result);
    return result;
}

static inline napi_value NewString(napi_env env, const std::string & str) {
    return NewString(env, str.c_str());
}

static inline napi_value NewObject(napi_env env) {
    napi_value result = nullptr;
    napi_create_object(env, &result);
    return result;
}

static inline napi_value NewInt32(napi_env env, int32_t value) {
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
    return result;
}

static inline napi_value NewUint32(napi_env env, uint32_t value) {
    napi_value result = nullptr;
    napi_create_uint32(env, value, &result);
    return result;
}

static inline napi_value NewDouble(napi_env env, double value) {
    napi_value result = nullptr;
    napi_create_double(env, value, &result);
    return result;
}

static inline void SetProperty(napi_env env, napi_value obj, const char * name, napi_value value) {
    napi_set_named_property(env, obj, name, value);
}

// 抛出带错误码的异常
static inline void ThrowError(napi_env env, int32_t code, const char * message) {
    std::string msg = "[error " + std::to_string(code) + "] " + message;
    napi_throw_error(env, nullptr, msg.c_str());
}

// 判断是否函数类型
static inline bool IsFunction(napi_env env, napi_value value) {
    napi_valuetype type = napi_undefined;
    napi_typeof(env, value, &type);
    return type == napi_function;
}

} // namespace napi_util

#endif // HARMONY_GGUF_NAPI_UTIL_H
