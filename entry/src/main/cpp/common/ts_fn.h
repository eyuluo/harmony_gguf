<<<<<<< HEAD
#ifndef HARMONY_GGUF_TS_FN_H
#define HARMONY_GGUF_TS_FN_H

#include <napi/native_api.h>

// 线程安全函数（napi_threadsafe_function）封装
// 用于从推理线程安全地回调到 JS 线程。
class TsFn {
public:
    using JsCall = void (*)(napi_env env, napi_value js_cb, void * context, void * data);

    // 创建线程安全函数，绑定 JS 回调 func
    TsFn(napi_env env, napi_value func, const char * name, JsCall js_call);
    ~TsFn();

    TsFn(const TsFn &) = delete;
    TsFn & operator=(const TsFn &) = delete;

    // 从任意线程调用（非阻塞），data 的所有权转移给 JS 回调
    void Call(void * data);

    // 释放线程安全函数（最后一个引用释放后真正销毁）
    void Release();

    // 禁止再入队（用于停止生成后不再派发回调）
    void Abort();

    bool valid() const { return tsfn_ != nullptr; }

private:
    napi_threadsafe_function tsfn_ = nullptr;
};

#endif // HARMONY_GGUF_TS_FN_H
=======
#ifndef HARMONY_GGUF_TS_FN_H
#define HARMONY_GGUF_TS_FN_H

#include <napi/native_api.h>

// 线程安全函数（napi_threadsafe_function）封装
// 用于从推理线程安全地回调到 JS 线程。
class TsFn {
public:
    using JsCall = void (*)(napi_env env, napi_value js_cb, void * context, void * data);

    // 创建线程安全函数，绑定 JS 回调 func
    TsFn(napi_env env, napi_value func, const char * name, JsCall js_call);
    ~TsFn();

    TsFn(const TsFn &) = delete;
    TsFn & operator=(const TsFn &) = delete;

    // 从任意线程调用（非阻塞），data 的所有权转移给 JS 回调
    void Call(void * data);

    // 释放线程安全函数（最后一个引用释放后真正销毁）
    void Release();

    bool valid() const { return tsfn_ != nullptr; }

private:
    napi_threadsafe_function tsfn_ = nullptr;
};

#endif // HARMONY_GGUF_TS_FN_H
>>>>>>> cpp
