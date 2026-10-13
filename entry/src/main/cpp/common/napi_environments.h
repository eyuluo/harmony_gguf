#ifndef HARMONY_GGUF_NAPI_ENVIRONMENTS_H
#define HARMONY_GGUF_NAPI_ENVIRONMENTS_H

#include <mutex>
#include <unordered_set>

class NapiEnvironments {
public:
    void Attach(void * env) {
        std::lock_guard<std::mutex> lock(mutex_);
        environments_.insert(env);
    }

    template <typename Cleanup>
    void Detach(void * env, Cleanup cleanup) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (environments_.erase(env) > 0 && environments_.empty()) {
            cleanup();
        }
    }

private:
    std::mutex mutex_;
    std::unordered_set<void *> environments_;
};

#endif
