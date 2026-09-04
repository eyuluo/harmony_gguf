#include "ts_fn.h"

#include <string>

TsFn::TsFn(napi_env env, napi_value func, const char * name, JsCall js_call) {
    napi_value resource_name = nullptr;
    napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &resource_name);

    napi_status status = napi_create_threadsafe_function(
        env,
        func,
        nullptr,
        resource_name,
        0,    // 无界队列
        1,    // 初始线程数
        nullptr,
        nullptr,
        nullptr,
        js_call,
        &tsfn_);

    if (status != napi_ok) {
        tsfn_ = nullptr;
    }
}

TsFn::~TsFn() {
    if (tsfn_ != nullptr) {
        napi_release_threadsafe_function(tsfn_, napi_tsfn_release);
        tsfn_ = nullptr;
    }
}

void TsFn::Call(void * data) {
    if (tsfn_ == nullptr) {
        return;
    }
    napi_call_threadsafe_function(tsfn_, data, napi_tsfn_nonblocking);
}

void TsFn::Release() {
    if (tsfn_ != nullptr) {
        napi_release_threadsafe_function(tsfn_, napi_tsfn_release);
        tsfn_ = nullptr;
    }
}

void TsFn::Abort() {
    if (tsfn_ != nullptr) {
        napi_release_threadsafe_function(tsfn_, napi_tsfn_abort);
        tsfn_ = nullptr;
    }
}
