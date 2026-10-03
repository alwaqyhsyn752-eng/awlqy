cmake_minimum_required(VERSION 3.22.1)
project(awlqy LANGUAGES C CXX)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_ANDROID_STL_TYPE c++_shared)
include(FetchContent)

FetchContent_Declare(fribidi_src
    URL https://github.com/fribidi/fribidi/archive/refs/tags/v1.0.15.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_MakeAvailable(fribidi_src)
file(GLOB FRIBIDI_SOURCES CONFIGURE_DEPENDS "${fribidi_src_SOURCE_DIR}/lib/*.c")
list(FILTER FRIBIDI_SOURCES EXCLUDE REGEX "fribidi-main\\.c$")
add_library(fribidi STATIC ${FRIBIDI_SOURCES})
target_include_directories(fribidi PUBLIC ${CMAKE_CURRENT_SOURCE_DIR} ${fribidi_src_SOURCE_DIR}/lib)
target_compile_definitions(fribidi PRIVATE HAVE_CONFIG_H=0 FRIBIDI_ENTRY=)

set(HB_BUILD_UTILS OFF CACHE BOOL "" FORCE)
set(HB_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(HB_BUILD_SUBSET OFF CACHE BOOL "" FORCE)
set(HB_HAVE_FREETYPE OFF CACHE BOOL "" FORCE)
set(HB_HAVE_GLIB OFF CACHE BOOL "" FORCE)
set(HB_HAVE_ICU OFF CACHE BOOL "" FORCE)
set(HB_HAVE_GRAPHITE2 OFF CACHE BOOL "" FORCE)
set(HB_HAVE_CAIRO OFF CACHE BOOL "" FORCE)
set(HB_HAVE_GOBJECT OFF CACHE BOOL "" FORCE)
set(HB_HAVE_UNISCRIBE OFF CACHE BOOL "" FORCE)
set(HB_HAVE_DIRECTWRITE OFF CACHE BOOL "" FORCE)
set(HB_HAVE_CORETEXT OFF CACHE BOOL "" FORCE)

FetchContent_Declare(harfbuzz_src
    URL https://github.com/harfbuzz/harfbuzz/archive/refs/tags/8.5.0.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_MakeAvailable(harfbuzz_src)

add_library(awlqy_engine SHARED pty_bridge.cpp arabic_shaper.cpp harfbuzz_render.cpp)
target_include_directories(awlqy_engine PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
find_library(log-lib log)
target_link_libraries(awlqy_engine PRIVATE fribidi harfbuzz android ${log-lib})
target_compile_options(awlqy_engine PRIVATE -O2 -fvisibility=hidden -ffunction-sections -fdata-sections)
