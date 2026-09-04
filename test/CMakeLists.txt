# ============================================================================
# test/CMakeLists.txt — C++ 引擎测试构建系统
# 角色 C（质量保障）维护
# 用法：
#   cd test && mkdir build && cd build
#   cmake .. -DCMAKE_BUILD_TYPE=Debug
#   cmake --build . --target test-ggml-ops
#   ./test-ggml-ops
# ============================================================================

cmake_minimum_required(VERSION 3.14)
project(harmony_gguf_tests C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---- 源码根路径 ----
set(CPP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../entry/src/main/cpp")

# ---- ggml 源文件 ----
file(GLOB GGML_SRC
    ${CPP_ROOT}/ggml/src/*.c
    ${CPP_ROOT}/ggml/src/*.cpp)

file(GLOB GGML_CPU_SRC
    ${CPP_ROOT}/ggml/src/ggml-cpu/*.c
    ${CPP_ROOT}/ggml/src/ggml-cpu/*.cpp)

# 架构 SIMD 源文件
if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|ARM64|armv8")
    set(GGML_ARCH_SRC
        ${CPP_ROOT}/ggml/src/ggml-cpu/arch/arm/quants.c
        ${CPP_ROOT}/ggml/src/ggml-cpu/arch/arm/repack.cpp)
    set(GGML_ARCH_FLAGS -march=armv8.2-a+dotprod+fp16)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
    set(GGML_ARCH_SRC
        ${CPP_ROOT}/ggml/src/ggml-cpu/arch/x86/quants.c
        ${CPP_ROOT}/ggml/src/ggml-cpu/arch/x86/repack.cpp)
    set(GGML_ARCH_FLAGS -mavx2 -mfma -mf16c -msse4.2)
else()
    set(GGML_ARCH_SRC "")
    set(GGML_ARCH_FLAGS "")
endif()

# ---- llama 引擎源文件 ----
file(GLOB LLAMA_SRC
    ${CPP_ROOT}/engine/*.cpp
    ${CPP_ROOT}/engine/models/*.cpp)

# ---- include 目录 ----
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/harmony
    ${CPP_ROOT}
    ${CPP_ROOT}/ggml/include
    ${CPP_ROOT}/ggml/src
    ${CPP_ROOT}/ggml/src/ggml-cpu
    ${CPP_ROOT}/engine
    ${CPP_ROOT}/engine/models)

# ---- ggml + llama 静态库 ----
add_library(engine_test_lib STATIC
    ${GGML_SRC}
    ${GGML_CPU_SRC}
    ${GGML_ARCH_SRC}
    ${LLAMA_SRC})

target_compile_options(engine_test_lib PRIVATE -fexceptions -frtti -Wno-unused-command-line-argument ${GGML_ARCH_FLAGS})
target_compile_definitions(engine_test_lib PRIVATE
    _GNU_SOURCE
    GGML_USE_CPU
    GGML_VERSION="0.3.0"
    GGML_COMMIT="dev"
    LLAMA_VERSION="0.3.0")

# ---- 测试可执行文件 ----

# ggml 基础算子单测
add_executable(test-ggml-ops harmony/test-ggml-ops.cpp)
target_link_libraries(test-ggml-ops PRIVATE engine_test_lib)
target_compile_options(test-ggml-ops PRIVATE -fexceptions -frtti)

# GGUF 解析单测
add_executable(test-gguf-parse harmony/test-gguf-parse.cpp)
target_link_libraries(test-gguf-parse PRIVATE engine_test_lib)
target_compile_options(test-gguf-parse PRIVATE -fexceptions -frtti)

# 模型加载冒烟测试
add_executable(test-model-load harmony/test-model-load.cpp)
target_link_libraries(test-model-load PRIVATE engine_test_lib)
target_compile_options(test-model-load PRIVATE -fexceptions -frtti)

# 主路径生成冒烟测试
add_executable(test-smoke-generate harmony/test-smoke-generate.cpp)
target_link_libraries(test-smoke-generate PRIVATE engine_test_lib)
target_compile_options(test-smoke-generate PRIVATE -fexceptions -frtti)
# tokenizer 编码/解码往返测试
add_executable(test-tokenizer-roundtrip harmony/test-tokenizer-roundtrip.cpp)
target_link_libraries(test-tokenizer-roundtrip PRIVATE engine_test_lib)
target_compile_options(test-tokenizer-roundtrip PRIVATE -fexceptions -frtti)
# 生成循环内存检查
add_executable(test-memory-check harmony/test-memory-check.cpp)
target_link_libraries(test-memory-check PRIVATE engine_test_lib)
target_compile_options(test-memory-check PRIVATE -fexceptions -frtti)