#include "testing.h"
#include "llama.h"
#include "llama-chat.h"

static std::string render(const std::string & tmpl, const std::vector<llama_chat_message> & messages, bool generation = true) {
    std::vector<const llama_chat_message *> refs;
    for (const auto & m : messages) { refs.push_back(&m); }
    std::string result;
    if (llm_chat_apply_template(llm_chat_detect_template(tmpl), refs, result, generation) < 0) { return ""; }
    return result;
}

int main() {
    testing t;
    t.test("常见架构缺失模板时共用生产解析器", [](testing & t) {
        for (const std::string arch : {"qwen", "qwen2", "qwen2moe", "qwen2vl", "qwen3", "qwen3moe",
            "qwen3next", "qwen3vl", "qwen3vlmoe", "qwen35", "qwen35moe"}) {
            t.assert_equal("Qwen 家族基础回退", std::string("chatml"), llm_chat_resolve_template("", arch, {}));
        }
        for (const std::string arch : {"gemma", "gemma2", "gemma3", "gemma3n"}) {
            t.assert_equal("旧 Gemma 使用原轮次协议", std::string("gemma"), llm_chat_resolve_template("", arch, {}));
        }
        t.assert_equal("Gemma4 使用新协议", std::string("gemma4"), llm_chat_resolve_template("", "gemma4", {}));
        t.assert_equal("MiniMax-M2 使用专用协议", std::string("minimax-m2"), llm_chat_resolve_template("", "minimax-m2", {}));
        t.assert_true("未知 iris 不伪造模板", llm_chat_resolve_template("", "iris", {}).empty());
    });
    t.test("优先模型模板并拒绝跨家族猜测", [](testing & t) {
        t.assert_equal("Llama 架构的蒸馏模型尊重 DeepSeek 模板", std::string("deepseek3"),
            llm_chat_resolve_template("deepseek3", "llama", {"<|im_start|>", "<|im_end|>"}));
        t.assert_true("存在未知 Jinja 时不能用架构掩盖错误",
            llm_chat_resolve_template("{{ unknown_protocol }}", "qwen3", {}).empty());
        t.assert_true("Llama 缺少证据不假定为第三代", llm_chat_resolve_template("", "llama", {}).empty());
        t.assert_equal("词表证明 Llama3 协议", std::string("llama3"),
            llm_chat_resolve_template("", "llama", {"<|start_header_id|>", "<|end_header_id|>"}));
        t.assert_equal("词表证明 Llama2 协议", std::string("llama2"),
            llm_chat_resolve_template("", "llama", {"[INST]", "[/INST]"}));
        t.assert_equal("Nemotron 新模型由词表识别 ChatML", std::string("chatml"),
            llm_chat_resolve_template("", "nemotron_h_moe", {"<|im_start|>", "<|im_end|>"}));
        t.assert_true("Nemotron 无证据不假定 Llama3", llm_chat_resolve_template("", "nemotron_h", {}).empty());
    });
    t.test("所有注册模板都可处理普通多轮文本", [](testing & t) {
        for (const std::string tmpl : {"chatml", "llama2", "llama3", "llama4", "gemma", "gemma4",
            "deepseek", "deepseek2", "deepseek3", "chatglm3", "chatglm4", "glm4-think",
            "minimax-m2", "nemotron3", "mistral-v7"}) {
            const auto result = render(tmpl, {{"system", "系统提示"}, {"user", "问题一"},
                {"assistant", "回答一"}, {"user", "问题二"}});
            t.assert_true("模板返回非空", !result.empty());
            t.assert_true("保留历史回答", result.find("回答一") != std::string::npos);
            t.assert_true("保留最新输入", result.find("问题二") != std::string::npos);
        }
    });
    t.test("MiniMax-M2 使用官方轮次标记与思考前缀", [](testing & t) {
        const auto result = render("]~b][e~[<minimax:tool_call>", {{"system", "系统"}, {"user", "问题一"},
            {"assistant", "<think>思考</think>回答一"}, {"user", "问题二"}});
        t.assert_equal("完整消息格式", std::string(
            "]~!b[]~b]system\n系统[e~[\n]~b]user\n问题一[e~[\n]~b]ai\n回答一[e~[\n"
            "]~b]user\n问题二[e~[\n]~b]ai\n<think>\n"), result);
        t.assert_true("没有工具调用对象不能渲染工具响应", render("minimax-m2", {{"tool", "内容"}}).empty());
    });
    t.test("Nemotron3 思考模板不能退化成普通 ChatML", [](testing & t) {
        const auto result = render("<|im_start|> truncate_history_thinking <|im_end|>",
            {{"user", "问题一"}, {"assistant", "<think>思考</think>回答一"}, {"user", "问题二"}});
        t.assert_equal("历史思考裁剪和生成前缀", std::string(
            "<|im_start|>system\n<|im_end|>\n<|im_start|>user\n问题一<|im_end|>\n"
            "<|im_start|>assistant\n<think></think>回答一<|im_end|>\n"
            "<|im_start|>user\n问题二<|im_end|>\n<|im_start|>assistant\n<think>\n"), result);
    });
    t.test("GLM 思考模板正确区分 ChatGLM4", [](testing & t) {
        t.assert_true("识别新版 GLM", llm_chat_detect_template("[gMASK]<sop> <think>") == LLM_CHAT_TEMPLATE_GLM_4_THINK);
        t.assert_true("旧 GLM 不改变协议", llm_chat_detect_template("[gMASK]<sop>") == LLM_CHAT_TEMPLATE_CHATGLM_4);
        t.assert_equal("历史移除思考，保留生成边界", std::string(
            "[gMASK]<sop><|user|>\n问题一<|assistant|>\n<think></think>\n回答一<|user|>\n问题二<|assistant|>"),
            render("glm4-think", {{"user", "问题一"}, {"assistant", "<think>思考</think>回答一"}, {"user", "问题二"}}));
    });
    t.test("Qwen3 历史思考和连续工具响应边界", [](testing & t) {
        const auto result = render("<|im_start|> last_query_index </think>",
            {{"user", "问题一"}, {"assistant", "<think>思考</think>\n\n回答一"}, {"user", "问题二"}});
        t.assert_equal("仅旧轮次裁剪思考，不强加思考前缀", std::string(
            "<|im_start|>user\n问题一<|im_end|>\n<|im_start|>assistant\n回答一<|im_end|>\n"
            "<|im_start|>user\n问题二<|im_end|>\n<|im_start|>assistant\n"), result);
        t.assert_equal("连续工具响应合并为一轮", std::string(
            "<|im_start|>user\n<tool_response>\n结果一\n</tool_response>\n"
            "<tool_response>\n结果二\n</tool_response><|im_end|>\n<|im_start|>assistant\n"),
            render("qwen3", {{"tool", "结果一"}, {"tool", "结果二"}}));
    });
    return t.summary();
}
