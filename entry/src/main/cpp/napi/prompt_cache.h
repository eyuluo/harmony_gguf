#ifndef HARMONY_GGUF_PROMPT_CACHE_H
#define HARMONY_GGUF_PROMPT_CACHE_H

#include <algorithm>
#include <vector>
#include "llama.h"

inline size_t ReusablePromptTokens(const std::vector<llama_token> & cached,
                                  const std::vector<llama_token> & prompt) {
    if (prompt.empty()) {
        return 0;
    }
    const size_t limit = std::min(cached.size(), prompt.size() - 1);
    size_t count = 0;
    while (count < limit && cached[count] == prompt[count]) {
        ++count;
    }
    return count;
}

inline bool FitPromptContext(std::vector<llama_token> & prompt, uint32_t context) {
    if (context <= 1 || prompt.size() < context) {
        return false;
    }
    const size_t keep = context - 1;
    prompt.erase(prompt.begin() + 1, prompt.end() - (keep - 1));
    return true;
}

#endif
