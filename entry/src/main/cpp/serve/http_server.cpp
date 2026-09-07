#include "http_server.h"

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netinet/in.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "engine_state.h"
#include "engine_types.h"
#include "error_code.h"
#include "httplib.h"
#include "json.hpp"
#include "llama.h"
#include "llama_inference.h"

using json = nlohmann::json;

namespace {

// 并发槽位守卫：构造时阻塞获取一个空闲槽位（服务停止时失败），析构时自动释放。
class SlotGuard {
public:
    SlotGuard()
        : id_(EngineState::Instance().BeginGenerateBlocking(seq_id_, stop_flag_,
                                                            []() { return !HttpServer::Instance().IsRunning(); })) {}
    ~SlotGuard() {
        if (id_ != 0) {
            EngineState::Instance().EndGenerate(id_, seq_id_);
        }
    }
    bool acquired() const { return id_ != 0; }
    llama_seq_id seq_id() const { return seq_id_; }
    const std::shared_ptr<std::atomic_bool> & stop_flag() const { return stop_flag_; }

private:
    uint64_t id_ = 0;
    llama_seq_id seq_id_ = -1;
    std::shared_ptr<std::atomic_bool> stop_flag_;
};

// 从请求 JSON 提取生成参数
GenerateParams ParseGenerateParams(const json & body, const std::string & prompt) {
    GenerateParams params;
    params.prompt = prompt;

    if (body.contains("temperature") && body["temperature"].is_number()) {
        params.temperature = body["temperature"].get<float>();
    }
    if (body.contains("top_k") && body["top_k"].is_number()) {
        params.top_k = body["top_k"].get<int32_t>();
    }
    if (body.contains("top_p") && body["top_p"].is_number()) {
        params.top_p = body["top_p"].get<float>();
    }
    if (body.contains("repeat_penalty") && body["repeat_penalty"].is_number()) {
        params.repeat_penalty = body["repeat_penalty"].get<float>();
    }
    if (body.contains("max_tokens") && body["max_tokens"].is_number()) {
        params.max_tokens = body["max_tokens"].get<int32_t>();
    }

    return params;
}

// 架构 → 聊天模板名映射（与 registry/models.json 的 chatTemplate 字段对齐）
const char * ChatTemplateForArch(const std::string & arch) {
    static const std::unordered_map<std::string, const char *> kArchTemplates = {
        { "llama", "llama3" },
        { "qwen2", "chatml" },
        { "qwen2moe", "chatml" },
        { "qwen3", "chatml" },
        { "gemma", "gemma" },
        { "gemma2", "gemma" },
        { "mistral", "mistral-v7" },
        { "deepseek", "deepseek3" },
        { "deepseek2", "deepseek2" },
        { "chatglm", "chatglm3" },
        { "glm4", "chatglm4" },
    };
    auto it = kArchTemplates.find(arch);
    return it != kArchTemplates.end() ? it->second : "chatml";
}

// 解析当前模型应使用的聊天模板：优先 GGUF 内置模板，其次按架构匹配，最终回退 chatml
std::string ResolveChatTemplate() {
    llama_model * model = EngineState::Instance().model();
    if (model != nullptr) {
        const char * builtin = llama_model_chat_template(model, nullptr);
        if (builtin != nullptr && builtin[0] != '\0') {
            return std::string(builtin);
        }
        char arch[128] = {0};
        int32_t len = llama_model_meta_val_str(model, "general.architecture", arch, sizeof(arch));
        if (len > 0) {
            return ChatTemplateForArch(std::string(arch, static_cast<size_t>(len)));
        }
    }
    return "chatml";
}

// 用指定聊天模板把 messages 组装为 prompt
std::string BuildChatPrompt(const std::string & tmpl, const json & messages) {
    std::vector<std::string> roles;
    std::vector<std::string> contents;

    for (const auto & m : messages) {
        if (!m.contains("role") || !m.contains("content")) {
            continue;
        }
        roles.emplace_back(m["role"].get<std::string>());
        contents.emplace_back(m["content"].get<std::string>());
    }

    if (roles.empty()) {
        return "";
    }

    // 字符串全部就位后再取指针，避免后续扩容导致悬空
    std::vector<llama_chat_message> msgs;
    msgs.reserve(roles.size());
    for (size_t i = 0; i < roles.size(); ++i) {
        llama_chat_message msg;
        msg.role = roles[i].c_str();
        msg.content = contents[i].c_str();
        msgs.push_back(msg);
    }

    // 预估 buffer（2 倍消息总长 + 2048），不足时按返回值扩展
    size_t total = 2048;
    for (const auto & c : contents) {
        total += c.size() * 2;
    }

    std::vector<char> buf(total);
    int32_t len = llama_chat_apply_template(tmpl.c_str(), msgs.data(), static_cast<size_t>(msgs.size()), true,
                                            buf.data(), static_cast<int32_t>(buf.size()));
    if (len < 0) {
        buf.resize(static_cast<size_t>(-len));
        len = llama_chat_apply_template(tmpl.c_str(), msgs.data(), static_cast<size_t>(msgs.size()), true,
                                        buf.data(), static_cast<int32_t>(buf.size()));
    }

    if (len <= 0) {
        return "";
    }
    return std::string(buf.data(), static_cast<size_t>(len));
}

// 获取本机局域网 IPv4 地址（跳过回环，取第一个非 127.0.0.1 地址）
std::string GetLocalIPv4() {
    std::string result;
    struct ifaddrs * ifap = nullptr;
    if (getifaddrs(&ifap) != 0) {
        return result;
    }
    for (struct ifaddrs * ifa = ifap; ifa != nullptr; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == nullptr || ifa->ifa_addr->sa_family != AF_INET) {
            continue;
        }
        auto * addr = reinterpret_cast<struct sockaddr_in *>(ifa->ifa_addr);
        char buf[INET_ADDRSTRLEN] = {0};
        if (inet_ntop(AF_INET, &addr->sin_addr, buf, sizeof(buf)) == nullptr) {
            continue;
        }
        std::string ip(buf);
        if (ip == "127.0.0.1") {
            continue;
        }
        result = ip;
        break;
    }
    freeifaddrs(ifap);
    return result;
}

// 是否应停止生成
bool ShouldStop() {
    return !HttpServer::Instance().IsRunning();
}

// 构造 OpenAI 风格完成响应
json BuildCompletionResponse(const std::string & text, const GenerateStats & stats, const std::string & model_id) {
    return {
        { "id", "cmpl-" + std::to_string(llama_time_us()) },
        { "object", "text_completion" },
        { "model", model_id },
        { "choices", json::array({
            {
                { "index", 0 },
                { "text", text },
                { "finish_reason", "stop" }
            }
        }) },
        { "usage", {
            { "prompt_tokens", stats.prompt_tokens },
            { "completion_tokens", stats.generated_tokens },
            { "total_tokens", stats.prompt_tokens + stats.generated_tokens },
            { "time_to_first_token_ms", stats.ttft_ms },
            { "tokens_per_second", stats.tokens_per_second }
        } }
    };
}

// 当前加载模型的 id（architecture）
std::string CurrentModelId() {
    llama_model * model = EngineState::Instance().model();
    if (model == nullptr) {
        return "";
    }
    char buf[128] = {0};
    int32_t len = llama_model_meta_val_str(model, "general.architecture", buf, sizeof(buf));
    if (len <= 0) {
        return "model";
    }
    return std::string(buf, static_cast<size_t>(len));
}

// 鉴权校验，失败返回 true（需要拒绝）
bool AuthFailed(const ServerConfig & config, const httplib::Request & req, httplib::Response & res) {
    if (config.api_key.empty()) {
        return false;
    }
    auto it = req.headers.find("Authorization");
    const std::string expected = "Bearer " + config.api_key;
    if (it == req.headers.end() || it->second != expected) {
        res.status = 401;
        res.set_content("{\"error\":{\"message\":\"unauthorized\",\"type\":\"authentication_error\"}}", "application/json");
        return true;
    }
    return false;
}

// 流式生成：逐 token 写 SSE，chunk 结构由 make_chunk 决定
void RunStreamGeneration(const GenerateParams & params, httplib::DataSink & sink,
                         const std::function<json(const std::string &)> & make_chunk) {
    SlotGuard guard;
    if (!guard.acquired()) {
        return;
    }

    GenerateStats stats;
    inference::GenResult result = inference::RunGeneration(
        guard.seq_id(),
        guard.stop_flag(),
        params,
        [&sink, &make_chunk](const char * text) {
            std::string data = "data: " + make_chunk(text).dump() + "\n\n";
            sink.write(data.data(), data.size());
        },
        ShouldStop,
        stats);

    if (result == inference::GenResult::Failed) {
        std::string err = "data: {\"error\":\"generation failed\"}\n\n";
        sink.write(err.data(), err.size());
    }

    json usage_chunk = {
        { "usage", {
            { "prompt_tokens", stats.prompt_tokens },
            { "completion_tokens", stats.generated_tokens },
            { "total_tokens", stats.prompt_tokens + stats.generated_tokens },
            { "time_to_first_token_ms", stats.ttft_ms },
            { "tokens_per_second", stats.tokens_per_second }
        } }
    };
    std::string usage = "data: " + usage_chunk.dump() + "\n\n";
    sink.write(usage.data(), usage.size());

    std::string done = "data: [DONE]\n\n";
    sink.write(done.data(), done.size());
}

// 非流式生成：一次性生成并写回响应，响应结构由 make_response 决定
void RunSyncGeneration(const GenerateParams & params, httplib::Response & res,
                       const std::function<json(const std::string &, const GenerateStats &)> & make_response) {
    SlotGuard guard;
    if (!guard.acquired()) {
        res.status = 503;
        res.set_content("{\"error\":\"server shutting down\"}", "application/json");
        return;
    }

    std::string text;
    GenerateStats stats;
    inference::GenResult result = inference::RunGeneration(
        guard.seq_id(),
        guard.stop_flag(),
        params,
        [&text](const char * t) { text += t; },
        ShouldStop,
        stats);

    if (result == inference::GenResult::Failed) {
        res.status = 500;
        res.set_content("{\"error\":\"generation failed\"}", "application/json");
        return;
    }

    res.set_content(make_response(text, stats).dump(), "application/json");
}

} // namespace

HttpServer & HttpServer::Instance() {
    static HttpServer instance;
    return instance;
}

int32_t HttpServer::Start(const ServerConfig & config) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (running_) {
        return error_code_value(ErrorCode::InvalidState);
    }

    config_ = config;

    auto * svr = new httplib::Server();

    // GET /health
    svr->Get("/health", [](const httplib::Request &, httplib::Response & res) {
        res.set_content("{\"status\":\"ok\"}", "application/json");
    });

    // GET /v1/models
    svr->Get("/v1/models", [this](const httplib::Request & req, httplib::Response & res) {
        if (AuthFailed(config_, req, res)) {
            return;
        }
        std::string model_id = CurrentModelId();
        json body = {
            { "object", "list" },
            { "data", json::array({
                {
                    { "id", model_id },
                    { "object", "model" },
                    { "owned_by", "local" }
                }
            }) }
        };
        res.set_content(body.dump(), "application/json");
    });

    // POST /v1/completions
    svr->Post("/v1/completions", [this](const httplib::Request & req, httplib::Response & res) {
        if (AuthFailed(config_, req, res)) {
            return;
        }

        json body;
        try {
            body = json::parse(req.body);
        } catch (...) {
            res.status = 400;
            res.set_content("{\"error\":\"invalid json\"}", "application/json");
            return;
        }

        if (!body.contains("prompt") || !body["prompt"].is_string()) {
            res.status = 400;
            res.set_content("{\"error\":\"prompt is required\"}", "application/json");
            return;
        }

        GenerateParams params = ParseGenerateParams(body, body["prompt"].get<std::string>());
        bool stream = body.value("stream", false);
        std::string model_id = CurrentModelId();

        if (stream) {
            res.set_chunked_content_provider("text/event-stream",
                [params](size_t, httplib::DataSink & sink) -> bool {
                    RunStreamGeneration(params, sink, [](const std::string & t) {
                        return json{ { "choices", json::array({ { { "index", 0 }, { "text", t } } }) } };
                    });
                    return true;
                });
        } else {
            RunSyncGeneration(params, res, [model_id](const std::string & text, const GenerateStats & stats) {
                return BuildCompletionResponse(text, stats, model_id);
            });
        }
    });

    // POST /v1/chat/completions
    svr->Post("/v1/chat/completions", [this](const httplib::Request & req, httplib::Response & res) {
        if (AuthFailed(config_, req, res)) {
            return;
        }

        json body;
        try {
            body = json::parse(req.body);
        } catch (...) {
            res.status = 400;
            res.set_content("{\"error\":\"invalid json\"}", "application/json");
            return;
        }

        std::string prompt;
        if (body.contains("messages") && body["messages"].is_array()) {
            prompt = BuildChatPrompt(ResolveChatTemplate(), body["messages"]);
        } else if (body.contains("prompt") && body["prompt"].is_string()) {
            prompt = body["prompt"].get<std::string>();
        }

        if (prompt.empty()) {
            res.status = 400;
            res.set_content("{\"error\":\"messages or prompt is required\"}", "application/json");
            return;
        }

        GenerateParams params = ParseGenerateParams(body, prompt);
        bool stream = body.value("stream", false);
        std::string model_id = CurrentModelId();

        if (stream) {
            res.set_chunked_content_provider("text/event-stream",
                [params](size_t, httplib::DataSink & sink) -> bool {
                    RunStreamGeneration(params, sink, [](const std::string & t) {
                        return json{ { "choices", json::array({ { { "index", 0 }, { "delta", { { "content", t } } } } }) } };
                    });
                    return true;
                });
        } else {
            RunSyncGeneration(params, res, [model_id](const std::string & text, const GenerateStats & stats) {
                return json{
                    { "id", "chatcmpl-" + std::to_string(llama_time_us()) },
                    { "object", "chat.completion" },
                    { "model", model_id },
                    { "choices", json::array({ {
                        { "index", 0 },
                        { "message", { { "role", "assistant" }, { "content", text } } },
                        { "finish_reason", "stop" }
                    } }) },
                    { "usage", {
                        { "prompt_tokens", stats.prompt_tokens },
                        { "completion_tokens", stats.generated_tokens },
                        { "total_tokens", stats.prompt_tokens + stats.generated_tokens },
                        { "time_to_first_token_ms", stats.ttft_ms },
                        { "tokens_per_second", stats.tokens_per_second }
                    } }
                };
            });
        }
    });

    // listen 线程
    const std::string host = config_.host;
    const int port = config_.port;
    thread_ = std::thread([svr, host, port]() {
        svr->listen(host.c_str(), port);
    });

    server_ = svr;
    running_ = true;

    return error_code_value(ErrorCode::Ok);
}

void HttpServer::Stop() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_) {
        return;
    }

    running_ = false;

    auto * svr = static_cast<httplib::Server *>(server_);
    if (svr != nullptr) {
        svr->stop();
    }
    if (thread_.joinable()) {
        thread_.join();
    }
    if (svr != nullptr) {
        delete svr;
    }
    server_ = nullptr;
}

ServerInfo HttpServer::GetStatus() const {
    std::lock_guard<std::mutex> lock(mutex_);
    ServerInfo info;
    info.host = config_.host;
    info.port = config_.port;
    info.running = running_;
    info.lan_address.clear();
    if (running_ && config_.host == "0.0.0.0") {
        std::string ip = GetLocalIPv4();
        if (!ip.empty()) {
            info.lan_address = "http://" + ip + ":" + std::to_string(config_.port);
        }
    }
    return info;
}

bool HttpServer::IsRunning() const {
    return running_.load(std::memory_order_relaxed);
}
