#include <napi/native_api.h>

#include <cstdint>
#include <string>

#include "error_code.h"
#include "http_server.h"
#include "napi_util.h"

// startServer(config: { host, port, apiKey }): void
static napi_value StartServer(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    ServerConfig config;
    if (argc >= 1) {
        std::string host;
        if (napi_util::GetOptionalString(env, args[0], "host", host) && !host.empty()) {
            config.host = host;
        }
        int32_t port = config.port;
        if (napi_util::GetOptionalInt32(env, args[0], "port", port)) {
            config.port = port;
        }
        std::string api_key;
        if (napi_util::GetOptionalString(env, args[0], "apiKey", api_key)) {
            config.api_key = api_key;
        }
    }

    int32_t code = HttpServer::Instance().Start(config);
    if (code != error_code_value(ErrorCode::Ok)) {
        napi_util::ThrowError(env, code, "failed to start server");
        return nullptr;
    }

    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

// stopServer(): void
static napi_value StopServer(napi_env env, napi_callback_info info) {
    HttpServer::Instance().Stop();

    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

// getServerStatus(): ServerInfo
static napi_value GetServerStatus(napi_env env, napi_callback_info info) {
    ServerInfo server_info = HttpServer::Instance().GetStatus();

    napi_value obj = napi_util::NewObject(env);
    napi_util::SetProperty(env, obj, "host", napi_util::NewString(env, server_info.host));
    napi_util::SetProperty(env, obj, "port", napi_util::NewInt32(env, server_info.port));
    napi_util::SetProperty(env, obj, "lanAddress", napi_util::NewString(env, server_info.lan_address));
    napi_util::SetProperty(env, obj, "running", napi_util::NewBool(env, server_info.running));
    return obj;
}

// 注册 Serve 相关接口
void RegisterServeApi(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "startServer", nullptr, StartServer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopServer", nullptr, StopServer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getServerStatus", nullptr, GetServerStatus, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
