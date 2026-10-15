#include "testing.h"
#include "llama.h"
#include "llama-chat.h"

int main() {
    testing t;
    t.test("识别 Gemma4 真实模板标记", [](testing & t) {
        t.assert_true("识别模板名称", llm_chat_detect_template("gemma4") == LLM_CHAT_TEMPLATE_GEMMA_4);
        t.assert_true("识别 GGUF Jinja 标记", llm_chat_detect_template(
            "{{ bos_token }}{{ '<|turn>' + role + '\\n' }}{{ '<turn|>\\n' }}") == LLM_CHAT_TEMPLATE_GEMMA_4);
        t.assert_true("旧 Gemma 保持原模板", llm_chat_detect_template("<start_of_turn>") == LLM_CHAT_TEMPLATE_GEMMA);
    });
    t.test("Gemma4 多轮保留角色并移除历史思考通道", [](testing & t) {
        llama_chat_message system{"system", "  系统提示  "};
        llama_chat_message user{"user", "  问题一  "};
        llama_chat_message assistant{"assistant", "<|channel>analysis\n思考<channel|> 答案一 "};
        llama_chat_message next{"user", "问题二"};
        std::vector<const llama_chat_message *> messages{&system, &user, &assistant, &next};
        std::string result;
        llm_chat_apply_template(LLM_CHAT_TEMPLATE_GEMMA_4, messages, result, true);
        t.assert_equal("完整多轮格式", std::string(
            "<|turn>system\n系统提示<turn|>\n<|turn>user\n问题一<turn|>\n"
            "<|turn>model\n答案一<turn|>\n<|turn>user\n问题二<turn|>\n<|turn>model\n"), result);
        llm_chat_apply_template(LLM_CHAT_TEMPLATE_GEMMA_4, messages, result, false);
        t.assert_true("关闭生成前缀", result.size() >= 8 && result.substr(result.size() - 8) == "<turn|>\n");
    });
    t.test("首轮图片标记保留且不重复添加 BOS", [](testing & t) {
        llama_chat_message user{"user", "<__media__>\n描述图片"};
        std::string result;
        llm_chat_apply_template(LLM_CHAT_TEMPLATE_GEMMA_4, {&user}, result, true);
        t.assert_equal("媒体标记交给 mtmd 处理", std::string(
            "<|turn>user\n<__media__>\n描述图片<turn|>\n<|turn>model\n"), result);
    });
    return t.summary();
}
