#include "napi/native_api.h"

// 各模块的导出注册
void RegisterModelApi(napi_env env, napi_value exports);
void RegisterGenerateApi(napi_env env, napi_value exports);

// 模板示例：两数相加（保留以兼容模板页面，待 UI 重写后移除）
static napi_value Add(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    double value0 = 0;
    napi_get_value_double(env, args[0], &value0);

    double value1 = 0;
    napi_get_value_double(env, args[1], &value1);

    napi_value sum = nullptr;
    napi_create_double(env, value0 + value1, &sum);
    return sum;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

    RegisterModelApi(env, exports);
    RegisterGenerateApi(env, exports);
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
