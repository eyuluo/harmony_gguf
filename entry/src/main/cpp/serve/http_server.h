#ifndef HARMONY_GGUF_HTTP_SERVER_H
#define HARMONY_GGUF_HTTP_SERVER_H

#include <atomic>
#include <mutex>
#include <string>
#include <thread>

// 服务器配置（对应 NAPI ServerConfig）
struct ServerConfig {
    std::string host = "127.0.0.1";
    int port = 5160;
    std::string api_key; // 空 = 不鉴权
};

// 服务器状态（对应 NAPI ServerInfo）
struct ServerInfo {
    std::string host;
    int port = 0;
    std::string lan_address;
    bool running = false;
};

class HttpServer {
public:
    static HttpServer & Instance();

    HttpServer(const HttpServer &) = delete;
    HttpServer & operator=(const HttpServer &) = delete;

    // 启动本地 HTTP 服务（OpenAI 兼容），成功返回 0，失败返回错误码
    int32_t Start(const ServerConfig & config);
    // 停止服务
    void Stop();
    // 获取状态
    ServerInfo GetStatus() const;

    // 是否正在运行（供生成循环检查停止）
    bool IsRunning() const;

private:
    HttpServer() = default;

    ServerConfig config_;
    std::atomic_bool running_{false};
    mutable std::mutex mutex_;
    void * server_ = nullptr; // httplib::Server *（PIMPL，避免头文件暴露 httplib）
    std::thread thread_;      // listen 线程
};

#endif // HARMONY_GGUF_HTTP_SERVER_H
