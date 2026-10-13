#include "testing.h"
#include "napi_environments.h"

#include <atomic>
#include <thread>

int main() {
    testing t;
    t.test("工作线程回收不停止仍在运行的主环境", [](testing & t) {
        NapiEnvironments environments;
        int main_env = 0;
        int worker_env = 0;
        int shutdowns = 0;
        environments.Attach(&main_env);
        for (int round = 0; round < 20; ++round) {
            environments.Attach(&worker_env);
            environments.Detach(&worker_env, [&]() { ++shutdowns; });
            t.assert_equal("后续对话仍可使用全局引擎", 0, shutdowns);
        }
        environments.Detach(&main_env, [&]() { ++shutdowns; });
        t.assert_equal("最后一个环境退出时清理全局资源", 1, shutdowns);
    });
    t.test("主环境先退出时等待其余环境结束", [](testing & t) {
        NapiEnvironments environments;
        int main_env = 0;
        int worker_env = 0;
        int shutdowns = 0;
        environments.Attach(&main_env);
        environments.Attach(&worker_env);
        environments.Detach(&main_env, [&]() { ++shutdowns; });
        t.assert_equal("工作环境存活时保留引擎", 0, shutdowns);
        environments.Detach(&worker_env, [&]() { ++shutdowns; });
        environments.Detach(&worker_env, [&]() { ++shutdowns; });
        t.assert_equal("重复退出不重复清理", 1, shutdowns);
    });
    t.test("并发回收仅清理一次", [](testing & t) {
        NapiEnvironments environments;
        int first = 0;
        int second = 0;
        std::atomic_int shutdowns{0};
        environments.Attach(&first);
        environments.Attach(&second);
        std::thread a([&]() { environments.Detach(&first, [&]() { ++shutdowns; }); });
        std::thread b([&]() { environments.Detach(&second, [&]() { ++shutdowns; }); });
        a.join();
        b.join();
        t.assert_equal("并发退出只触发一次全局清理", 1, shutdowns.load());
    });
    return t.summary();
}
