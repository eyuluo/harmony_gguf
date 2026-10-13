#include "napi/native_api.h"

#include "engine_state.h"
#include "http_server.h"
#include "napi_environments.h"

// 各模块的导出注册
void RegisterModelApi(napi_env env, napi_value exports);
void RegisterGenerateApi(napi_env env, napi_value exports);
void RegisterServeApi(napi_env env, napi_value exports);

static NapiEnvironments environments;

static void CleanupNapiEnvironment(void * env)
{
    environments.Detach(env, []() {
        EngineState::Instance().RequestStopAll();
        HttpServer::Instance().Stop();
        EngineState::Instance().WaitGenerateEnd();
    });
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    RegisterModelApi(env, exports);
    RegisterGenerateApi(env, exports);
    RegisterServeApi(env, exports);
    if (napi_add_env_cleanup_hook(env, CleanupNapiEnvironment, env) != napi_ok) {
        napi_throw_error(env, "1004", "无法注册原生运行环境清理钩子");
        return nullptr;
    }
    environments.Attach(env);
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
