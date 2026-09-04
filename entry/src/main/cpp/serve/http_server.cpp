#include "http_server.h"

#include <cstdint>
#include <mutex>
#include <string>
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

// 生成串行锁：单模型实例，同一时刻只处理一个生成任务
std::mutex g_generate_mutex;

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

// 用 chatml 模板把 messages 组装为 prompt
std::string BuildChatPrompt(const json & messages) {
    std::vector<std::string> roles;
    std::vector<std::string> contents;
    std::vector<llama_chat_message> msgs;

    for (const auto & m : messages) {
        if (!m.contains("role") || !m.contains("content")) {
            continue;
        }
        roles.emplace_back(m["role"].get<std::string>());
        contents.emplace_back(m["content"].get<std::string>());
        llama_chat_message msg;
        msg.role = roles.back().c_str();
        msg.content = contents.back().c_str();
        msgs.push_back(msg);
    }

    if (msgs.empty()) {
        return "";
    }

    // 预估 buffer（2 倍消息总长 + 2048），不足时按返回值扩展
    size_t total = 2048;
    for (const auto & c : contents) {
        total += c.size() * 2;
    }

    std::vector<char> buf(total);
    int32_t len = llama_chat_apply_template("chatml", msgs.data(), static_cast<size_t>(msgs.size()), true,
                                            buf.data(), static_cast<int32_t>(buf.size()));
    if (len < 0) {
        buf.resize(static_cast<size_t>(-len));
        len = llama_chat_apply_template("chatml", msgs.data(), static_cast<size_t>(msgs.size()), true,
                                        buf.data(), static_cast<int32_t>(buf.size()));
    }

    if (len <= 0) {
        return "";
    }
    return std::string(buf.data(), static_cast<size_t>(len));
}

// 是否应停止生成
bool ShouldStop() {
    return EngineState::Instance().StopRequested() || !HttpServer::Instance().IsRunning();
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
            { "total_tokens", stats.prompt_tokens + stats.generated_tokens }
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

        std::string prompt = body["prompt"].get<std::string>();
        GenerateParams params = ParseGenerateParams(body, prompt);
        bool stream = body.value("stream", false);
        std::string model_id = CurrentModelId();

        if (stream) {
            res.set_chunked_content_provider("text/event-stream",
                [params](size_t, httplib::DataSink & sink) -> bool {
                    std::lock_guard<std::mutex> gen_lock(g_generate_mutex);

                    GenerateStats stats;
                    std::string token_text;
                    bool ok = inference::RunGeneration(
                        params,
                        [&sink, &token_text](const char * text) {
                            token_text = text;
                            json chunk = {
                                { "choices", json::array({
                                    { { "index", 0 }, { "text", token_text } }
                                }) }
                            };
                            std::string data = "data: " + chunk.dump() + "\n\n";
                            sink.write(data.data(), data.size());
                        },
                        ShouldStop,
                        stats);

                    if (!ok) {
                        std::string err = "data: {\"error\":\"generation failed\"}\n\n";
                        sink.write(err.data(), err.size());
                    }
                    std::string done = "data: [DONE]\n\n";
                    sink.write(done.data(), done.size());
                    return true;
                });
        } else {
            std::lock_guard<std::mutex> gen_lock(g_generate_mutex);

            std::string text;
            GenerateStats stats;
            bool ok = inference::RunGeneration(
                params,
                [&text](const char * t) { text += t; },
                ShouldStop,
                stats);

            if (!ok) {
                res.status = 500;
                res.set_content("{\"error\":\"generation failed\"}", "application/json");
                return;
            }

            json resp = BuildCompletionResponse(text, stats, model_id);
            res.set_content(resp.dump(), "application/json");
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
            prompt = BuildChatPrompt(body["messages"]);
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
                    std::lock_guard<std::mutex> gen_lock(g_generate_mutex);

                    GenerateStats stats;
                    std::string token_text;
                    bool ok = inference::RunGeneration(
                        params,
                        [&sink, &token_text](const char * text) {
                            token_text = text;
                            json chunk = {
                                { "choices", json::array({
                                    { { "index", 0 }, { "delta", { { "content", token_text } } } }
                                }) }
                            };
                            std::string data = "data: " + chunk.dump() + "\n\n";
                            sink.write(data.data(), data.size());
                        },
                        ShouldStop,
                        stats);

                    if (!ok) {
                        std::string err = "data: {\"error\":\"generation failed\"}\n\n";
                        sink.write(err.data(), err.size());
                    }
                    std::string done = "data: [DONE]\n\n";
                    sink.write(done.data(), done.size());
                    return true;
                });
        } else {
            std::lock_guard<std::mutex> gen_lock(g_generate_mutex);

            std::string text;
            GenerateStats stats;
            bool ok = inference::RunGeneration(
                params,
                [&text](const char * t) { text += t; },
                ShouldStop,
                stats);

            if (!ok) {
                res.status = 500;
                res.set_content("{\"error\":\"generation failed\"}", "application/json");
                return;
            }

            json resp = {
                { "id", "chatcmpl-" + std::to_string(llama_time_us()) },
                { "object", "chat.completion" },
                { "model", model_id },
                { "choices", json::array({
                    {
                        { "index", 0 },
                        { "message", { { "role", "assistant" }, { "content", text } } },
                        { "finish_reason", "stop" }
                    }
                }) },
                { "usage", {
                    { "prompt_tokens", stats.prompt_tokens },
                    { "completion_tokens", stats.generated_tokens },
                    { "total_tokens", stats.prompt_tokens + stats.generated_tokens }
                } }
            };
            res.set_content(resp.dump(), "application/json");
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
    info.lan_address = (config_.host == "0.0.0.0") ? std::string() : config_.host;
    return info;
}

bool HttpServer::IsRunning() const {
    return running_.load(std::memory_order_relaxed);
}
