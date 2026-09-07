#include "napi/native_api.h"

// 各模块的导出注册
void RegisterModelApi(napi_env env, napi_value exports);
void RegisterGenerateApi(napi_env env, napi_value exports);
void RegisterServeApi(napi_env env, napi_value exports);

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    RegisterModelApi(env, exports);
    RegisterGenerateApi(env, exports);
    RegisterServeApi(env, exports);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
