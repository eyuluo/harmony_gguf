#ifndef HARMONY_GGUF_CALL_GUIDE_H
#define HARMONY_GGUF_CALL_GUIDE_H

#include "httplib.h"

inline void RegisterCallGuide(httplib::Server & server) {
    server.Get("/", [](const httplib::Request &, httplib::Response & response) {
        response.set_content(R"GUIDE(<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>服务调用指南 · Harmony-GGUF</title>
<style>
:root{color-scheme:dark;font-family:system-ui,sans-serif;background:#18191d;color:#e6e6e6;line-height:1.7}
body{max-width:960px;margin:auto;padding:24px}h1{line-height:1.3}h2{color:#b9b1ff;margin-top:32px}
a{color:#b9b1ff}p{color:#c2c2c8}nav{display:flex;flex-wrap:wrap;gap:8px 20px;padding:16px;background:#1e1f24;border-radius:12px}
pre{background:#121212;padding:16px;overflow:auto;border-radius:10px;line-height:1.5}code{font-family:monospace}
table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:10px;border-bottom:1px solid #34353b;overflow-wrap:anywhere}
.address{color:#78d891}section{scroll-margin-top:16px}@media(max-width:600px){body{padding:16px}pre{font-size:12px}td,th{padding:8px}}
</style>
</head>
<body>
<header>
<h1>服务调用指南</h1>
<p class="address">服务地址：http://localhost:5160<br>OpenAI 客户端 Base URL：http://localhost:5160/v1</p>
<p>先在应用中加载 GGUF 并启动服务。当前应用仅监听 127.0.0.1，端口固定为 5160，适用于本机应用调用；服务停止后，本指南和 API 均不可用。</p>
<p>localhost 和 127.0.0.1 指运行服务的鸿蒙设备自身。在电脑上打开这些地址会连接电脑自身，不能直接访问手机。当前应用未开放局域网监听配置。下方示例必须在能访问设备服务的环境中执行；如使用其他监听端口，请替换示例地址。</p>
</header>
<nav aria-label="指南目录">
<a href="#endpoints">接口与鉴权</a><a href="#health">检查服务</a><a href="#models">模型</a><a href="#chat">聊天</a><a href="#stream">流式响应</a><a href="#completion">文本补全</a><a href="#params">参数</a><a href="#python">Python</a><a href="#errors">错误</a><a href="#history">多轮历史</a><a href="#powershell">PowerShell</a><a href="#concurrency">并发与停止</a>
</nav>
<section id="endpoints"><h2>接口总览与鉴权</h2>
<table><thead><tr><th>用途</th><th>方法与路径</th></tr></thead><tbody>
<tr><td>调用指南</td><td><code>GET /</code></td></tr>
<tr><td>健康检查</td><td><code>GET /health</code></td></tr>
<tr><td>模型列表</td><td><code>GET /v1/models</code></td></tr>
<tr><td>模型详情</td><td><code>GET /v1/models/{model}</code></td></tr>
<tr><td>聊天对话</td><td><code>POST /v1/chat/completions</code></td></tr>
<tr><td>文本补全</td><td><code>POST /v1/completions</code></td></tr>
</tbody></table>
<p>当前应用未配置 API Key，请求无需 Authorization。若启动服务时配置了 API Key，请在 API 请求中增加以下请求头；本指南始终可直接打开。</p>
<pre><code>Authorization: Bearer YOUR_API_KEY</code></pre></section>
<section id="health"><h2>1. 检查服务</h2>
<pre><code>curl http://localhost:5160/health</code></pre>
<pre><code>{"status":"ok"}</code></pre></section>
<section id="models"><h2>2. 获取模型</h2>
<pre><code>curl http://localhost:5160/v1/models</code></pre>
<pre><code>{
  "object": "list",
  "data": [{"id": "qwen2", "object": "model", "owned_by": "local"}]
}</code></pre>
<p>模型标识使用当前 GGUF 的架构名，例如 qwen2、llama 或 gemma。请求中的 model 字段不会加载或切换模型，服务使用设备上已加载的唯一模型。qwen2 仅为示例，查询详情时请使用模型列表返回的 id。</p>
<pre><code>curl http://localhost:5160/v1/models/qwen2</code></pre></section>
<section id="chat"><h2>3. 非流式聊天</h2>
<p>Content-Type 使用 application/json。messages 至少包含一条消息；role 支持 system、user、assistant 和 tool，content 必须为字符串。</p>
<pre><code>curl http://localhost:5160/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "system", "content": "你是一个简洁的助手。"},
      {"role": "user", "content": "你好，请介绍一下自己。"}
    ],
    "temperature": 0.8,
    "top_k": 40,
    "top_p": 0.95,
    "repeat_penalty": 1.0,
    "max_tokens": 512
  }'</code></pre>
<pre><code>{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "model": "qwen2",
  "choices": [{
    "index": 0,
    "message": {"role": "assistant", "content": "..."},
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 30,
    "total_tokens": 50,
    "time_to_first_token_ms": 120,
    "tokens_per_second": 8.5
  }
}</code></pre></section>
<section id="stream"><h2>4. 流式聊天</h2>
<p>设置 stream 为 true，服务以 Server-Sent Events 返回 data: 消息，持续读取直到 data: [DONE]。curl 的 -N 关闭输出缓冲。聊天内容位于 choices[0].delta.content；文本补全内容位于 choices[0].text。SSE 事件以空行结束，一次网络读取可能包含不完整事件或多个事件。</p>
<pre><code>curl -N http://localhost:5160/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "请分三点说明离线推理的优点。"}],
    "stream": true,
    "max_tokens": 256
  }'</code></pre>
<pre><code>data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":"第一点"}}]}

data: {"choices":[{"index":0,"delta":{"content":"..."}}]}

data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: {"usage":{...}}

data: [DONE]</code></pre>
<p>示例中省略了部分字段。HTTP 响应头发出后发生的推理错误可能通过 data: 中的 error 对象报告，不能只判断 HTTP 200。收到 error 应记录错误；usage 是统计信息。当前 finish_reason 通常为 stop，不能仅凭它判断是否达到 max_tokens。</p></section>
<section id="completion"><h2>5. 文本补全</h2>
<p>使用 prompt 字符串，无需 messages。省略 stream 或设置 false 返回完整 JSON；设置 true 返回 SSE。</p>
<pre><code>curl http://localhost:5160/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "请完成这句话：本地 AI 的优点是",
    "temperature": 0.7,
    "max_tokens": 128
  }'</code></pre></section>
<section id="params"><h2>6. 生成参数</h2>
<table><thead><tr><th>字段</th><th>取值</th><th>默认值</th></tr></thead><tbody>
<tr><td><code>temperature</code></td><td>有限非负数，通常使用 0 到 2</td><td>0.8</td></tr>
<tr><td><code>top_k</code></td><td>正整数</td><td>40</td></tr>
<tr><td><code>top_p</code></td><td>大于 0 且不超过 1</td><td>0.95</td></tr>
<tr><td><code>repeat_penalty</code></td><td>大于 0</td><td>1.0</td></tr>
<tr><td><code>max_tokens</code></td><td>正整数，最大 8192</td><td>512</td></tr>
<tr><td><code>stream</code></td><td>布尔值</td><td>false</td></tr>
</tbody></table>
<p>字段使用下划线命名，聊天与文本补全接口通用。temperature 越低通常越确定；top_k 控制候选数量，top_p 控制累计概率范围，repeat_penalty 控制重复惩罚。max_tokens 是输出 token 上限，并非字符数；输入和输出仍受上下文和设备内存限制。Serve 默认参数独立于应用对话页设置，建议显式传入所需参数。</p></section>
<section id="python"><h2>7. Python 调用</h2>
<p>使用 Python 标准库，无需额外依赖。</p>
<pre><code>import json
import urllib.request

body = {
    "messages": [{"role": "user", "content": "你好"}],
    "max_tokens": 128
}
request = urllib.request.Request(
    "http://localhost:5160/v1/chat/completions",
    data=json.dumps(body).encode("utf-8"),
    headers={"Content-Type": "application/json"},
    method="POST"
)
with urllib.request.urlopen(request) as response:
    print(json.loads(response.read().decode("utf-8")))</code></pre></section>
<section id="errors"><h2>8. 常见错误</h2>
<table><thead><tr><th>HTTP 状态码</th><th>说明</th></tr></thead><tbody>
<tr><td>400</td><td>JSON 无效、prompt 为空或参数不合法</td></tr>
<tr><td>401</td><td>鉴权失败，检查 Bearer API Key</td></tr>
<tr><td>404</td><td>模型标识或接口不存在</td></tr>
<tr><td>413</td><td>请求体超过 4 MB</td></tr>
<tr><td>499</td><td>生成被停止或服务关闭</td></tr>
<tr><td>500</td><td>推理失败或无法创建生成线程</td></tr>
<tr><td>503</td><td>模型未加载或服务停止，无法获取槽位</td></tr>
</tbody></table>
<p>返回 model not loaded 时，先在应用模型页面加载 GGUF，再启动服务。无法连接时，确认服务运行中、端口为 5160，并检查客户端是否运行在设备本机。</p></section>
<section id="history"><h2>9. 多轮历史</h2>
<p>HTTP 请求无状态，服务不会保存上一轮消息。下一轮需按顺序传回 system、user、assistant 历史和新的 user 消息。当前 Serve 不支持图片、音频或 OpenAI 多模态内容数组。</p>
<pre><code>{
  "messages": [
    {"role":"system","content":"请用中文回答。"},
    {"role":"user","content":"什么是 GGUF？"},
    {"role":"assistant","content":"GGUF 是一种模型文件格式。"},
    {"role":"user","content":"它适合离线推理吗？"}
  ],
  "max_tokens": 256
}</code></pre>
<p>聊天接口应用当前模型的聊天模板；文本补全直接处理 prompt。tool 可作为文本角色传入，但服务未实现工具调用协议、工具执行或 tool_calls。</p></section>
<section id="powershell"><h2>10. PowerShell 调用</h2>
<pre><code>$body = @{
  messages = @(@{ role = "user"; content = "你好" })
  max_tokens = 128
} | ConvertTo-Json -Depth 8
$result = Invoke-RestMethod -Uri "http://localhost:5160/v1/chat/completions" -Method Post -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
$result.choices[0].message.content</code></pre>
<p>上方多行 curl 示例使用 POSIX Shell 的反斜杠续行，不能直接作为 PowerShell 多行命令执行。在 PowerShell 中可使用此示例或单行 curl.exe 命令。</p></section>
<section id="concurrency"><h2>11. 并发与停止</h2>
<p>同一时刻只运行一个已加载模型。Serve 与应用内对话使用各自的槽位池；Serve 槽位满时请求持续排队，不保证固定等待时长。CPU 推理首字可能较慢，客户端应设置适当的读取超时。</p>
<p>停止服务或切换模型可能中断请求。流式客户端关闭连接后，服务在写入失败时请求停止生成；非流式连接关闭不能作为可靠的立即取消方式。当前没有 HTTP 按 requestId 停止生成的端点。</p>
<p>当前未提供 /v1/responses、/v1/embeddings、模型下载、工具执行或文件上传。未知请求字段可能被忽略，调用时请使用本指南列出的字段。</p></section>
</body>
</html>)GUIDE", "text/html; charset=utf-8");
    });
}

#endif
