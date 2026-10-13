#ifndef HARMONY_GGUF_CONVERSATION_SLOTS_H
#define HARMONY_GGUF_CONVERSATION_SLOTS_H

#include <cstdint>
#include <vector>

inline size_t SelectConversationSlot(const std::vector<bool> & busy,
                                    const std::vector<uint64_t> & owners,
                                    const std::vector<uint64_t> & recency,
                                    size_t begin, size_t end, uint64_t conversation) {
    size_t selected = busy.size();
    for (size_t i = begin; i < end && i < busy.size(); ++i) {
        if (conversation != 0 && owners[i] == conversation) {
            return busy[i] ? busy.size() : i;
        }
        if (!busy[i] && (selected == busy.size() || recency[i] < recency[selected])) {
            selected = i;
        }
    }
    return selected;
}

#endif
