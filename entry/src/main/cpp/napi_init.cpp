#include "napi/native_api.h"

#include "engine_state.h"
#include "http_server.h"

// 各模块的导出注册
void RegisterModelApi(napi_env env, napi_value exports);
void RegisterGenerateApi(napi_env env, napi_value exports);
void RegisterServeApi(napi_env env, napi_value exports);

static void CleanupNapiEnvironment(void *)
{
    EngineState::Instance().RequestStopAll();
    HttpServer::Instance().Stop();
    EngineState::Instance().WaitGenerateEnd();
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    RegisterModelApi(env, exports);
    RegisterGenerateApi(env, exports);
    RegisterServeApi(env, exports);
    napi_add_env_cleanup_hook(env, CleanupNapiEnvironment, nullptr);
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
