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
set(CMAKE_CXX_STANDARD 20)
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
    if(MSVC)
        set(GGML_ARCH_FLAGS "")
    else()
        set(GGML_ARCH_FLAGS -march=armv8.2-a+dotprod+fp16)
    endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
    set(GGML_ARCH_SRC
        ${CPP_ROOT}/ggml/src/ggml-cpu/arch/x86/quants.c
        ${CPP_ROOT}/ggml/src/ggml-cpu/arch/x86/repack.cpp)
    if(MSVC)
        set(GGML_ARCH_FLAGS /arch:AVX2)
    else()
        set(GGML_ARCH_FLAGS -mavx2 -mfma -mf16c -msse4.2)
    endif()
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
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CPP_ROOT}
    ${CPP_ROOT}/ggml/include
    ${CPP_ROOT}/ggml/src
    ${CPP_ROOT}/ggml/src/ggml-cpu
    ${CPP_ROOT}/engine
    ${CPP_ROOT}/engine/models)

# ---- 编译选项辅助宏 ----
if(MSVC)
    set(CXX_FLAGS /utf-8 /Zc:char8_t- /EHsc /GR /W3 /wd4267 /wd4244 /wd4305 /wd4996)
    set(ENGINE_DEFS GGML_USE_CPU _CRT_SECURE_NO_WARNINGS _WINSOCK_DEPRECATED_NO_WARNINGS)
else()
    set(CXX_FLAGS -fexceptions -frtti -Wno-unused-command-line-argument)
    set(ENGINE_DEFS _GNU_SOURCE GGML_USE_CPU)
endif()

# ---- ggml + llama 静态库 ----
add_library(engine_test_lib STATIC
    ${GGML_SRC}
    ${GGML_CPU_SRC}
    ${GGML_ARCH_SRC}
    ${LLAMA_SRC})

target_compile_options(engine_test_lib PRIVATE ${CXX_FLAGS} ${GGML_ARCH_FLAGS})
target_compile_definitions(engine_test_lib PRIVATE
    ${ENGINE_DEFS}
    GGML_VERSION="0.3.0"
    GGML_COMMIT="dev"
    LLAMA_VERSION="0.3.0")

# ---- 测试辅助函数 ----
function(add_engine_test name src)
    add_executable(${name} ${src})
    target_link_libraries(${name} PRIVATE engine_test_lib)
    target_compile_options(${name} PRIVATE ${CXX_FLAGS})
endfunction()

# ---- 测试可执行文件 ----
add_engine_test(test-ggml-ops harmony/test-ggml-ops.cpp)
add_engine_test(test-gguf-parse harmony/test-gguf-parse.cpp)
add_engine_test(test-model-load harmony/test-model-load.cpp)
add_engine_test(test-smoke-generate harmony/test-smoke-generate.cpp)
add_engine_test(test-tokenizer-roundtrip harmony/test-tokenizer-roundtrip.cpp)
add_engine_test(test-memory-check harmony/test-memory-check.cpp)
