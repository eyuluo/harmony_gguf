#ifndef HARMONY_GGUF_REQUEST_SLOT_H
#define HARMONY_GGUF_REQUEST_SLOT_H

#include "engine_state.h"

class RequestSlotGuard {
public:
    RequestSlotGuard(uint64_t id, llama_seq_id seq_id) : id_(id), seq_id_(seq_id) {}
    ~RequestSlotGuard() {
        if (id_ != 0) {
            EngineState::Instance().EndGenerate(id_, seq_id_);
        }
    }
    RequestSlotGuard(const RequestSlotGuard &) = delete;
    RequestSlotGuard & operator=(const RequestSlotGuard &) = delete;
    void TransferToWorker() { id_ = 0; }

private:
    uint64_t id_;
    llama_seq_id seq_id_;
};

#endif
