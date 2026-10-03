#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · fix2.sh — إصلاح CMake FetchContent + CRLF
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [fix2] إعادة كتابة CMakeLists.txt باستخدام GIT_REPOSITORY"

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

# ═══ FriBidi 1.0.15 (عبر git لتفادي bug الـ URL في CMake 3.22) ═══
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
target_include_directories(fribidi PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${fribidi_src_SOURCE_DIR}/lib)
target_compile_definitions(fribidi PRIVATE
    HAVE_CONFIG_H=0
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
    ${CMAKE_CURRENT_SOURCE_DIR})

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

echo "▶ [fix2] تنظيف كل \r من ملفات المشروع"
find . -type f \( -name "*.sh" -o -name "*.kt" -o -name "*.cpp" -o -name "*.h" \
    -o -name "*.txt" -o -name "*.xml" -o -name "*.gradle" -o -name "*.pro" \
    -o -name "*.yml" -o -name "*.properties" \) -not -path "./.git/*" \
    -exec sed -i 's/\r$//' {} + 2>/dev/null || true

echo "▶ [fix2] إضافة .gitattributes لمنع CRLF مستقبلاً"
cat > .gitattributes <<'AWLQY_GA_EOF'
* text=auto eol=lf
*.sh    text eol=lf
*.kt    text eol=lf
*.cpp   text eol=lf
*.h     text eol=lf
*.txt   text eol=lf
*.xml   text eol=lf
*.gradle text eol=lf
*.pro   text eol=lf
*.yml   text eol=lf
*.properties text eol=lf
*.png   binary
*.jpg   binary
*.jar   binary
*.apk   binary
AWLQY_GA_EOF

echo ""
echo "✔ [fix2] تم الإصلاح."
echo ""
echo "الخطوة التالية:"
echo "  git add ."
echo "  git commit -m 'fix: CMake GIT_REPOSITORY + .gitattributes'"
echo "  git push"
