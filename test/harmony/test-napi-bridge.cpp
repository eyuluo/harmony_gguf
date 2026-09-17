#include "testing.h"
#include "engine_state.h"
#include "error_code.h"
#include "llama_inference.h"

#include <future>
#include <thread>

using namespace std::chrono_literals;

struct ModelFixture {
    ~ModelFixture() { EngineState::Instance().UnloadModel(); }

    bool load(testing & t, uint32_t parallel = 2, const char * file = "ggml-vocab-llama-bpe.gguf") {
        LoadConfig config;
        config.vocab_only = true;
        config.parallel = parallel;
        config.context_length = 512;
        return t.assert_equal("加载成功", 0,
            EngineState::Instance().LoadModel(std::string("models/") + file, config));
    }
};

struct RequestFixture {
    uint64_t id = 0;
    llama_seq_id seq = -1;
    std::shared_ptr<std::atomic_bool> stop;

    bool begin(testing & t, SlotPool pool = SlotPool::Napi) {
        id = EngineState::Instance().BeginGenerate(pool, seq, stop);
        return t.assert_true("分配有效 requestId、seq_id 和停止标志", id > 0 && seq >= 0 && stop != nullptr);
    }

    void end() {
        if (id != 0) {
            EngineState::Instance().EndGenerate(id, seq);
            id = 0;
        }
    }

    ~RequestFixture() { end(); }
};

int main(int argc, char ** argv) {
    std::cout.setf(std::ios::unitbuf);
    testing t;
    if (argc > 1) { t.set_filter(argv[1]); }

    t.test("模型加载卸载与上下文配置", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t)) { return; }
        auto & state = EngineState::Instance();
        t.assert_true("已加载", state.IsLoaded());
        t.assert_equal("每槽位上下文", uint32_t(512), state.slot_context());
        state.UnloadModel();
        t.assert_true("已卸载", !state.IsLoaded());
        t.assert_equal("卸载清除上下文", uint32_t(0), state.slot_context());
        state.UnloadModel();
        RequestFixture request;
        request.id = state.BeginGenerate(SlotPool::Napi, request.seq, request.stop);
        t.assert_equal("未加载不能分配", uint64_t(0), request.id);
    });

    t.test("切换模型与失败加载清理", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t) || !model.load(t, 1, "ggml-vocab-qwen2.gguf")) { return; }
        char arch[64] = {};
        llama_model_meta_val_str(EngineState::Instance().model(), "general.architecture", arch, sizeof(arch));
        t.assert_equal("当前模型为 qwen2", std::string("qwen2"), std::string(arch));
        t.assert_equal("不存在文件返回 1003", error_code_value(ErrorCode::ModelLoadFailed),
            EngineState::Instance().LoadModel("models/M2-missing.gguf", LoadConfig{}));
        t.assert_true("失败后无模型", !EngineState::Instance().IsLoaded());
    });

    t.test("默认双槽位与独立池上限", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t)) { return; }
        RequestFixture a, b, c, d;
        if (!a.begin(t) || !b.begin(t) || !c.begin(t, SlotPool::Serve) || !d.begin(t, SlotPool::Serve)) { return; }
        t.assert_true("四个序列互不重叠", a.seq != b.seq && a.seq != c.seq && a.seq != d.seq &&
            b.seq != c.seq && b.seq != d.seq && c.seq != d.seq);
        t.assert_true("请求编号唯一", a.id != b.id && b.id != c.id && c.id != d.id && a.id != d.id && a.id != c.id && b.id != d.id);
        for (auto pool : {SlotPool::Napi, SlotPool::Serve}) {
            RequestFixture extra;
            extra.id = EngineState::Instance().BeginGenerate(pool, extra.seq, extra.stop);
            t.assert_equal("满池返回 0", uint64_t(0), extra.id);
        }
    });

    t.test("单槽位释放复用与旧请求隔离", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t, 1)) { return; }
        RequestFixture first, second;
        if (!first.begin(t)) { return; }
        const auto old_id = first.id;
        const auto old_seq = first.seq;
        first.end();
        if (!second.begin(t)) { return; }
        t.assert_equal("复用空闲序列", old_seq, second.seq);
        t.assert_true("requestId 不复用", old_id != second.id);
        EngineState::Instance().RequestStop(old_id);
        t.assert_true("旧请求停止不影响新请求", !second.stop->load());
    });

    t.test("按请求停止不影响另一请求", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t)) { return; }
        RequestFixture a, b;
        if (!a.begin(t) || !b.begin(t)) { return; }
        EngineState::Instance().RequestStop(a.id);
        t.assert_true("指定请求停止", a.stop->load());
        t.assert_true("另一请求继续", !b.stop->load());
        t.assert_true("未触发全局停止", !EngineState::Instance().StopAllRequested());
        EngineState::Instance().RequestStop(0);
        EngineState::Instance().RequestStop(UINT64_MAX);
        t.assert_true("未知请求不影响活跃请求", !b.stop->load());
    });

    t.test("停止全部覆盖两个池", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t)) { return; }
        RequestFixture a, b;
        if (!a.begin(t) || !b.begin(t, SlotPool::Serve)) { return; }
        EngineState::Instance().RequestStopAll();
        t.assert_true("两个请求均停止", a.stop->load() && b.stop->load());
        a.end();
        b.end();
        EngineState::Instance().WaitGenerateEnd();
        t.assert_true("等待全部结束返回", true);
        EngineState::Instance().ClearStopAll();
        RequestFixture next;
        next.begin(t);
        t.assert_true("清除停止状态后可重新分配", next.id > 0);
    });

    t.test("全局停止期间拒绝新请求", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t, 1)) { return; }
        EngineState::Instance().RequestStopAll();
        RequestFixture blocked;
        blocked.id = EngineState::Instance().BeginGenerate(SlotPool::Napi, blocked.seq, blocked.stop);
        t.assert_equal("停止状态返回 0", uint64_t(0), blocked.id);
        EngineState::Instance().ClearStopAll();
        RequestFixture accepted;
        accepted.begin(t);
    });

    t.test("重复结束请求不破坏活跃计数", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t, 1)) { return; }
        RequestFixture request;
        if (!request.begin(t)) { return; }
        const auto id = request.id;
        const auto seq = request.seq;
        request.end();
        EngineState::Instance().EndGenerate(id, seq);
        EngineState::Instance().EndGenerate(0, -1);
        EngineState::Instance().WaitGenerateEnd();
        EngineState::Instance().UnloadModel();
        t.assert_true("重复结束后仍可卸载", !EngineState::Instance().IsLoaded());
    });

    t.test("生成结束后卸载回归", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t, 1)) { return; }
        RequestFixture request;
        if (!request.begin(t)) { return; }
        request.end();
        EngineState::Instance().UnloadModel();
        t.assert_true("卸载返回且清除模型", !EngineState::Instance().IsLoaded());
    });

    t.test("卸载通知工作线程并等待结束", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t, 1)) { return; }
        RequestFixture request;
        if (!request.begin(t)) { return; }
        auto stop = request.stop;
        const auto id = request.id;
        const auto seq = request.seq;
        std::atomic_bool observed{false};
        std::thread worker([&]() {
            const auto deadline = std::chrono::steady_clock::now() + 5s;
            while (!stop->load() && std::chrono::steady_clock::now() < deadline) {
                std::this_thread::sleep_for(1ms);
            }
            observed.store(stop->load());
            EngineState::Instance().EndGenerate(id, seq);
        });
        request.id = 0;
        EngineState::Instance().UnloadModel();
        worker.join();
        t.assert_true("工作线程收到停止信号", observed.load());
        t.assert_true("工作线程结束后模型已卸载", !EngineState::Instance().IsLoaded());
    });

    t.test("异步推理失败回调与槽位释放", [&](testing & t) {
        ModelFixture model;
        if (!model.load(t, 1)) { return; }
        RequestFixture request;
        if (!request.begin(t)) { return; }
        std::promise<inference::GenResult> completed;
        auto result = completed.get_future();
        std::atomic_int tokens{0};
        GenerateParams params;
        params.prompt = "你好";
        const bool started = inference::RunGenerationAsync(request.id, request.seq, request.stop, params,
            [&](const char *) { tokens++; },
            [&](inference::GenResult value, const GenerateStats &) { completed.set_value(value); },
            []() { return false; });
        if (!t.assert_true("异步任务启动", started)) { return; }
        request.id = 0;
        t.assert_true("无权重上下文返回失败", result.get() == inference::GenResult::Failed);
        t.assert_equal("失败不产生 token", 0, tokens.load());
        RequestFixture next;
        next.begin(t);
    });

    const int result = t.summary();
    llama_backend_free();
    return result;
}
