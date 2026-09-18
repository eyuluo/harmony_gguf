# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(Harmony_gguf)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---- 源文件收集 ----

# ggml 基础库（张量核心 + backend 抽象 + gguf）
file(GLOB GGML_SRC
    ${NATIVERENDER_ROOT_PATH}/ggml/src/*.c
    ${NATIVERENDER_ROOT_PATH}/ggml/src/*.cpp)

# ggml CPU 后端（根目录，不含 amx 等子目录，GLOB 非递归）
file(GLOB GGML_CPU_SRC
    ${NATIVERENDER_ROOT_PATH}/ggml/src/ggml-cpu/*.c
    ${NATIVERENDER_ROOT_PATH}/ggml/src/ggml-cpu/*.cpp)

# 架构 SIMD 源（真机 ARM / 模拟器 x86）
if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|ARM64|armv8")
    set(GGML_ARCH_SRC
        ${NATIVERENDER_ROOT_PATH}/ggml/src/ggml-cpu/arch/arm/quants.c
        ${NATIVERENDER_ROOT_PATH}/ggml/src/ggml-cpu/arch/arm/repack.cpp)
    set(GGML_ARCH_FLAGS -march=armv8.2-a+dotprod+fp16)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64|i686|x86")
    set(GGML_ARCH_SRC
        ${NATIVERENDER_ROOT_PATH}/ggml/src/ggml-cpu/arch/x86/quants.c
        ${NATIVERENDER_ROOT_PATH}/ggml/src/ggml-cpu/arch/x86/repack.cpp)
    set(GGML_ARCH_FLAGS -mavx2 -mfma -mf16c -msse4.2)
else()
    message(WARNING "unknown processor: ${CMAKE_SYSTEM_PROCESSOR}, fallback to ARM")
    set(GGML_ARCH_SRC
        ${NATIVERENDER_ROOT_PATH}/ggml/src/ggml-cpu/arch/arm/quants.c
        ${NATIVERENDER_ROOT_PATH}/ggml/src/ggml-cpu/arch/arm/repack.cpp)
    set(GGML_ARCH_FLAGS "")
endif()

# llama 引擎（核心 + 全部架构）
file(GLOB LLAMA_SRC
    ${NATIVERENDER_ROOT_PATH}/engine/*.cpp
    ${NATIVERENDER_ROOT_PATH}/engine/models/*.cpp)

# NAPI 桥接 + 公共工具
file(GLOB NAPI_SRC
    ${NATIVERENDER_ROOT_PATH}/napi/*.cpp
    ${NATIVERENDER_ROOT_PATH}/common/*.cpp)

# Serve 服务（cpp-httplib + OpenAI 兼容路由）
file(GLOB SERVE_SRC
    ${NATIVERENDER_ROOT_PATH}/serve/*.cpp)

# 多模态（mtmd / mmproj 视觉推理，移植自 llama.cpp tools/mtmd）
file(GLOB MTMD_SRC
    ${NATIVERENDER_ROOT_PATH}/mtmd/*.cpp
    ${NATIVERENDER_ROOT_PATH}/mtmd/models/*.cpp)

# 第三方 vendor（stb_image/miniaudio/sheredom 为 header-only；hash 需编译 .c/.cpp）
file(GLOB VENDOR_SRC
    ${NATIVERENDER_ROOT_PATH}/vendor/hash/hash.cpp
    ${NATIVERENDER_ROOT_PATH}/vendor/hash/xxhash/xxhash.c
    ${NATIVERENDER_ROOT_PATH}/vendor/hash/sha256/sha256.c
    ${NATIVERENDER_ROOT_PATH}/vendor/hash/sha1/sha1.cpp)

# ---- include 目录 ----
include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
    ${NATIVERENDER_ROOT_PATH}/ggml/include
    ${NATIVERENDER_ROOT_PATH}/ggml/src
    ${NATIVERENDER_ROOT_PATH}/ggml/src/ggml-cpu
    ${NATIVERENDER_ROOT_PATH}/engine
    ${NATIVERENDER_ROOT_PATH}/engine/models
    ${NATIVERENDER_ROOT_PATH}/mtmd
    ${NATIVERENDER_ROOT_PATH}/mtmd/models
    ${NATIVERENDER_ROOT_PATH}/mtmd/debug
    ${NATIVERENDER_ROOT_PATH}/vendor
    ${NATIVERENDER_ROOT_PATH}/vendor/hash
    ${NATIVERENDER_ROOT_PATH}/napi
    ${NATIVERENDER_ROOT_PATH}/common
    ${NATIVERENDER_ROOT_PATH}/serve)

# ---- 目标 ----
add_library(entry SHARED
    napi_init.cpp
    ${GGML_SRC}
    ${GGML_CPU_SRC}
    ${GGML_ARCH_SRC}
    ${LLAMA_SRC}
    ${MTMD_SRC}
    ${VENDOR_SRC}
    ${NAPI_SRC}
    ${SERVE_SRC})

# sha1.cpp 使用 C++ namespace（vendor_hash），保留 .cpp 扩展名以 C++ 编译

target_link_libraries(entry PUBLIC libace_napi.z.so)

target_compile_options(entry PRIVATE -fexceptions -frtti -Wno-unused-command-line-argument ${GGML_ARCH_FLAGS})

target_compile_definitions(entry PRIVATE
    _GNU_SOURCE
    GGML_USE_CPU
    GGML_VERSION="0.3.0"
    GGML_COMMIT="dev"
    LLAMA_VERSION="0.3.0")
