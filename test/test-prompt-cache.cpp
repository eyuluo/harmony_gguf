#include "testing.h"
#include "prompt_cache.h"
#include "conversation_slots.h"

int main() {
    testing t;
    t.test("输出超过窗口后多次腾出空间继续解码", [](testing & t) {
        std::vector<llama_token> tokens{1, 2, 3, 4, 5, 6, 7};
        int shifts = 0;
        for (int output = 0; output < 100; ++output) {
            const auto discard = GenerationWindowDiscard(static_cast<llama_pos>(tokens.size()), 8);
            if (discard > 0) {
                TrimGenerationWindow(tokens, discard);
                ++shifts;
            }
            t.assert_true("每次 decode 前都有空闲位置", tokens.size() < 8);
            t.assert_equal("保留起始 token", llama_token(1), tokens.front());
            tokens.push_back(100 + output);
        }
        t.assert_true("输出远超输入窗口仍继续", shifts > 10);
        t.assert_equal("保留最新生成内容", llama_token(199), tokens.back());
        t.assert_equal("窗口未满不提前位移", int32_t(0), GenerationWindowDiscard(7, 8));
        std::vector<llama_token> tiny{1, 2};
        TrimGenerationWindow(tiny, GenerationWindowDiscard(2, 2));
        t.assert_equal("最小窗口仍保留起始 token", size_t(1), tiny.size());
    });
    t.test("对话保留上下文并切换执行队列", [](testing & t) {
        std::vector<bool> busy{false, false, false, false};
        std::vector<uint64_t> owners{101, 202, 0, 0};
        std::vector<uint64_t> recency{8, 2, 0, 0};
        t.assert_equal("同一对话优先返回原槽位", size_t(0),
            SelectConversationSlot(busy, owners, recency, 0, 2, 101));
        t.assert_equal("新对话回收最旧空闲缓存", size_t(1),
            SelectConversationSlot(busy, owners, recency, 0, 2, 303));
        busy[0] = true;
        t.assert_equal("同一对话活跃时等待而非重复分配", size_t(4),
            SelectConversationSlot(busy, owners, recency, 0, 2, 101));
        busy[1] = true;
        t.assert_equal("执行容量满时等待", size_t(4),
            SelectConversationSlot(busy, owners, recency, 0, 2, 303));
        t.assert_equal("NAPI 忙碌不占用 Serve 池", size_t(2),
            SelectConversationSlot(busy, owners, recency, 2, 4, 0));
        busy[0] = false;
        t.assert_equal("任务结束可切到新对话", size_t(0),
            SelectConversationSlot(busy, owners, recency, 0, 2, 303));
    });
    t.test("多轮历史复用匹配前缀", [](testing & t) {
        t.assert_equal("新一轮只处理新增后缀", size_t(4),
            ReusablePromptTokens({1, 2, 3, 4}, {1, 2, 3, 4, 5, 6}));
        t.assert_equal("分歧处停止复用", size_t(2),
            ReusablePromptTokens({1, 2, 3, 4}, {1, 2, 8, 9}));
        t.assert_equal("相同 prompt 重算末 token 获取 logits", size_t(3),
            ReusablePromptTokens({1, 2, 3, 4}, {1, 2, 3, 4}));
        t.assert_equal("切换对话不复用不匹配历史", size_t(0),
            ReusablePromptTokens({1, 2}, {8, 9}));
        t.assert_equal("空输入不发生下溢", size_t(0), ReusablePromptTokens({1}, {}));
    });
    t.test("长历史保留起始 token 与最近内容", [](testing & t) {
        std::vector<llama_token> prompt{1, 2, 3, 4, 5, 6, 7, 8};
        t.assert_true("超长历史触发窗口", FitPromptContext(prompt, 5));
        t.assert_equal("为生成预留空间", size_t(4), prompt.size());
        t.assert_equal("保留起始 token", llama_token(1), prompt.front());
        t.assert_equal("保留最近内容", llama_token(6), prompt[1]);
        t.assert_equal("保留最新 token", llama_token(8), prompt.back());
        t.assert_true("短输入不修改", !FitPromptContext(prompt, 5));
        t.assert_true("等于上下文也预留生成空间", FitPromptContext(prompt, 4));
    });
    t.test("输入与输出长度相互独立", [](testing & t) {
        std::vector<llama_token> prompt(1024, 7);
        prompt[0] = 1;
        t.assert_true("输入长于常见输出上限 512 但未超上下文不裁剪", !FitPromptContext(prompt, 4096));
        t.assert_equal("完整保留 1024 个输入 token", size_t(1024), prompt.size());
        t.assert_true("恰好填满上下文时预留生成位置", FitPromptContext(prompt, 1024));
        t.assert_equal("保留上下文减一", size_t(1023), prompt.size());
        t.assert_true("极小上下文处理边界", FitPromptContext(prompt, 2));
        t.assert_equal("保留一个起始 token", size_t(1), prompt.size());
        t.assert_true("自动配置值不执行下溢裁剪", !FitPromptContext(prompt, 0));
        t.assert_true("容量为一不执行下溢裁剪", !FitPromptContext(prompt, 1));
    });
    return t.summary();
}
