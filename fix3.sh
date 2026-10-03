#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · fix3.sh — إزالة HAVE_CONFIG_H من بناء FriBidi
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [fix3] إعادة كتابة CMakeLists.txt بدون HAVE_CONFIG_H"

cat > app/src/main/cpp/CMakeLists.txt <<'AWLQY_CMAKE_EOF'
cmake_minimum_required(VERSION 3.22.1)
project(awlqy LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_ANDROID_STL_TYPE c++_shared)

include(FetchContent)
set(FETCHCONTENT_QUIET OFF)
set(FETCHCONTENT_UPDATES_DISCONNECTED ON)

# ═══ FriBidi 1.0.15 (عبر git) ═══
FetchContent_Declare(
    fribidi_src
    GIT_REPOSITORY https://github.com/fribidi/fribidi.git
    GIT_TAG        v1.0.15
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(fribidi_src)

file(GLOB FRIBIDI_SOURCES CONFIGURE_DEPENDS
    "${fribidi_src_SOURCE_DIR}/lib/*.c")
list(FILTER FRIBIDI_SOURCES EXCLUDE REGEX "fribidi-main\\.c$")

add_library(fribidi STATIC ${FRIBIDI_SOURCES})

# ⚠️ لا نضع HAVE_CONFIG_H هنا إطلاقاً
target_include_directories(fribidi PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${fribidi_src_SOURCE_DIR}/lib)

target_compile_definitions(fribidi PRIVATE
    FRIBIDI_ENTRY=
    FRIBIDI_USE_GLIB=0)

# ═══ HarfBuzz 8.5.0 (عبر git) ═══
set(HB_BUILD_UTILS      OFF CACHE BOOL "" FORCE)
set(HB_BUILD_TESTS      OFF CACHE BOOL "" FORCE)
set(HB_BUILD_SUBSET     OFF CACHE BOOL "" FORCE)
set(HB_HAVE_FREETYPE    OFF CACHE BOOL "" FORCE)
set(HB_HAVE_GLIB        OFF CACHE BOOL "" FORCE)
set(HB_HAVE_ICU         OFF CACHE BOOL "" FORCE)
set(HB_HAVE_GRAPHITE2   OFF CACHE BOOL "" FORCE)
set(HB_HAVE_CAIRO       OFF CACHE BOOL "" FORCE)
set(HB_HAVE_GOBJECT     OFF CACHE BOOL "" FORCE)
set(HB_HAVE_UNISCRIBE   OFF CACHE BOOL "" FORCE)
set(HB_HAVE_DIRECTWRITE OFF CACHE BOOL "" FORCE)
set(HB_HAVE_CORETEXT    OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    harfbuzz_src
    GIT_REPOSITORY https://github.com/harfbuzz/harfbuzz.git
    GIT_TAG        8.5.0
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(harfbuzz_src)

# ═══ awlqy engine ═══
add_library(awlqy_engine SHARED
    pty_bridge.cpp
    arabic_shaper.cpp
    harfbuzz_render.cpp)

target_include_directories(awlqy_engine PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${fribidi_src_SOURCE_DIR}/lib)

find_library(log-lib log)

target_link_libraries(awlqy_engine
    PRIVATE
    fribidi
    harfbuzz
    android
    ${log-lib})

target_compile_options(awlqy_engine PRIVATE
    -O2 -fvisibility=hidden -ffunction-sections -fdata-sections)
AWLQY_CMAKE_EOF

echo "▶ [fix3] تنظيف .cxx cache القديم (محلياً)"
rm -rf app/.cxx 2>/dev/null || true

echo "▶ [fix3] التحقق"
grep -n "HAVE_CONFIG_H" app/src/main/cpp/CMakeLists.txt && echo "⚠ لا يزال موجود!" || echo "✔ نظيف تماماً"

echo ""
echo "الخطوة التالية:"
echo "  git add ."
echo "  git commit -m 'fix: remove HAVE_CONFIG_H to avoid missing config.h'"
echo "  git push"
