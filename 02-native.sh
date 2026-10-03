#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · 02-native.sh
#  C++/NDK: PTY + Arabic Engine (FriBidi + HarfBuzz)
#  + Kotlin Core: PtyBridge, ArabicShaper, TerminalSession,
#    TerminalView, PackageManager, ApkBuilder, AsciiArt, CodeGuide
# ─────────────────────────────────────────────────────────────
set -euo pipefail

echo "▶ [awlqy] 02-native: كتابة الطبقة الأصلية + Core Kotlin"

# ═══ CMakeLists.txt ═══
cat > app/src/main/cpp/CMakeLists.txt <<'AWLQY_EOF'
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
AWLQY_EOF

# ═══ fribidi-config.h ═══
cat > app/src/main/cpp/fribidi-config.h <<'AWLQY_EOF'
#ifndef FRIBIDI_CONFIG_H
#define FRIBIDI_CONFIG_H
#define FRIBIDI_VERSION              "1.0.15"
#define FRIBIDI_MAJOR_VERSION        1
#define FRIBIDI_MINOR_VERSION        0
#define FRIBIDI_MICRO_VERSION        15
#define FRIBIDI_INTERFACE_VERSION    4
#define FRIBIDI_INTERFACE_VERSION_MAJOR  4
#define FRIBIDI_INTERFACE_VERSION_MINOR  0
#define FRIBIDI_INTERFACE_VERSION_MICRO  0
#define FRIBIDI_INTERFACE_VERSION_STRING "4.0.0"
#define FRIBIDI_BINARY_VERSION       "3.0.0"
#define FRIBIDI_UNICODE_VERSION      "15.0.0"
#define FRIBIDI_UNICODE_CHARSET      1
#ifndef FRIBIDI_ENTRY
#define FRIBIDI_ENTRY
#endif
#endif
AWLQY_EOF

# ═══ pty_bridge.cpp ═══
cat > app/src/main/cpp/pty_bridge.cpp <<'AWLQY_EOF'
#include <jni.h>
#include <android/log.h>
#include <pty.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <string>

#define LOG_TAG "awlqy-pty"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {
[[noreturn]] void exec_shell() {
    const char *home = getenv("HOME");
    if (!home || !*home) home = "/data/local/tmp";
    if (chdir(home) != 0) chdir("/");
    const char *shell = getenv("AWLQY_SHELL");
    if (!shell || !*shell) shell = "/system/bin/sh";
    setenv("TERM",      "xterm-256color", 1);
    setenv("COLORTERM", "truecolor",      1);
    setenv("LANG",      "en_US.UTF-8",    1);
    setenv("LC_ALL",    "en_US.UTF-8",    1);
    execl(shell, shell, "-l", static_cast<char *>(nullptr));
    execl("/system/bin/sh", "sh", static_cast<char *>(nullptr));
    _exit(127);
}
}

extern "C" JNIEXPORT jintArray JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeOpen(
        JNIEnv *env, jclass, jint rows, jint cols,
        jstring jShell, jstring jCwd, jobjectArray jEnv) {

    const char *shell = jShell ? env->GetStringUTFChars(jShell, nullptr) : nullptr;
    const char *cwd   = jCwd   ? env->GetStringUTFChars(jCwd,   nullptr) : nullptr;
    if (shell && *shell) setenv("AWLQY_SHELL", shell, 1);
    if (cwd   && *cwd)   setenv("HOME",        cwd,   1);

    if (jEnv) {
        const jsize n = env->GetArrayLength(jEnv);
        for (jsize i = 0; i < n; ++i) {
            auto s = static_cast<jstring>(env->GetObjectArrayElement(jEnv, i));
            if (!s) continue;
            const char *c = env->GetStringUTFChars(s, nullptr);
            if (c) {
                const char *eq = strchr(c, '=');
                if (eq && eq != c) {
                    std::string key(c, static_cast<size_t>(eq - c));
                    setenv(key.c_str(), eq + 1, 1);
                }
                env->ReleaseStringUTFChars(s, c);
            }
            env->DeleteLocalRef(s);
        }
    }

    struct winsize ws{};
    ws.ws_row = rows > 0 ? (unsigned short)rows : 24;
    ws.ws_col = cols > 0 ? (unsigned short)cols : 80;

    int master = -1;
    pid_t pid = forkpty(&master, nullptr, nullptr, &ws);
    if (pid < 0) {
        LOGE("forkpty: %s", strerror(errno));
        if (shell) env->ReleaseStringUTFChars(jShell, shell);
        if (cwd)   env->ReleaseStringUTFChars(jCwd,   cwd);
        return nullptr;
    }
    if (pid == 0) exec_shell();

    int flags = fcntl(master, F_GETFL, 0);
    fcntl(master, F_SETFL, flags | O_NONBLOCK);

    if (shell) env->ReleaseStringUTFChars(jShell, shell);
    if (cwd)   env->ReleaseStringUTFChars(jCwd,   cwd);

    jintArray out = env->NewIntArray(2);
    jint vals[2] = { master, (jint)pid };
    env->SetIntArrayRegion(out, 0, 2, vals);
    return out;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeRead(
        JNIEnv *env, jclass, jint fd, jbyteArray buf, jint off, jint len) {
    if (fd < 0 || len <= 0) return -1;
    jbyte *data = env->GetByteArrayElements(buf, nullptr);
    ssize_t n = read(fd, data + off, (size_t)len);
    const int err = (n < 0) ? errno : 0;
    if (n > 0) { env->ReleaseByteArrayElements(buf, data, 0); return (jint)n; }
    env->ReleaseByteArrayElements(buf, data, JNI_ABORT);
    if (err == EAGAIN || err == EWOULDBLOCK) return 0;
    return -1;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeWrite(
        JNIEnv *env, jclass, jint fd, jbyteArray buf, jint off, jint len) {
    if (fd < 0 || len <= 0) return -1;
    jbyte *data = env->GetByteArrayElements(buf, nullptr);
    ssize_t total = 0;
    while (total < len) {
        ssize_t n = write(fd, data + off + total, (size_t)(len - total));
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) { usleep(500); continue; }
            break;
        }
        total += n;
    }
    env->ReleaseByteArrayElements(buf, data, JNI_ABORT);
    return (jint)total;
}

extern "C" JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeResize(
        JNIEnv *, jclass, jint fd, jint rows, jint cols) {
    if (fd < 0) return;
    struct winsize ws{};
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ioctl(fd, TIOCSWINSZ, &ws);
}

extern "C" JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeClose(JNIEnv *, jclass, jint fd) {
    if (fd >= 0) close(fd);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeWait(JNIEnv *, jclass, jint pid) {
    if (pid <= 0) return -1;
    int status = 0;
    while (waitpid((pid_t)pid, &status, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(status))   return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return status;
}

extern "C" JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeSignal(
        JNIEnv *, jclass, jint pid, jint sig) {
    if (pid > 0) kill((pid_t)pid, sig);
}

extern "C" JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeSignalGroup(
        JNIEnv *, jclass, jint pid, jint sig) {
    if (pid > 0) kill(-(pid_t)pid, sig);
}
AWLQY_EOF

# ═══ arabic_shaper.cpp (مختصر عملياً، نفس المنطق الكامل) ═══
cat > app/src/main/cpp/arabic_shaper.cpp <<'AWLQY_EOF'
#include <jni.h>
#include <cstdint>
#include <string>
#include <vector>
#include <fribidi.h>

namespace {
struct F { uint32_t i, f, a, m; };
static const struct { uint32_t cp; F v; } T[] = {
    {0x0621,{0xFE80,0,0,0}},{0x0622,{0xFE81,0xFE82,0,0}},{0x0623,{0xFE83,0xFE84,0,0}},
    {0x0624,{0xFE85,0xFE86,0,0}},{0x0625,{0xFE87,0xFE88,0,0}},{0x0626,{0xFE89,0xFE8A,0xFE8B,0xFE8C}},
    {0x0627,{0xFE8D,0xFE8E,0,0}},{0x0628,{0xFE8F,0xFE90,0xFE91,0xFE92}},{0x0629,{0xFE93,0xFE94,0,0}},
    {0x062A,{0xFE95,0xFE96,0xFE97,0xFE98}},{0x062B,{0xFE99,0xFE9A,0xFE9B,0xFE9C}},
    {0x062C,{0xFE9D,0xFE9E,0xFE9F,0xFEA0}},{0x062D,{0xFEA1,0xFEA2,0xFEA3,0xFEA4}},
    {0x062E,{0xFEA5,0xFEA6,0xFEA7,0xFEA8}},{0x062F,{0xFEA9,0xFEAA,0,0}},{0x0630,{0xFEAB,0xFEAC,0,0}},
    {0x0631,{0xFEAD,0xFEAE,0,0}},{0x0632,{0xFEAF,0xFEB0,0,0}},{0x0633,{0xFEB1,0xFEB2,0xFEB3,0xFEB4}},
    {0x0634,{0xFEB5,0xFEB6,0xFEB7,0xFEB8}},{0x0635,{0xFEB9,0xFEBA,0xFEBB,0xFEBC}},
    {0x0636,{0xFEBD,0xFEBE,0xFEBF,0xFEC0}},{0x0637,{0xFEC1,0xFEC2,0xFEC3,0xFEC4}},
    {0x0638,{0xFEC5,0xFEC6,0xFEC7,0xFEC8}},{0x0639,{0xFEC9,0xFECA,0xFECB,0xFECC}},
    {0x063A,{0xFECD,0xFECE,0xFECF,0xFED0}},{0x0641,{0xFED1,0xFED2,0xFED3,0xFED4}},
    {0x0642,{0xFED5,0xFED6,0xFED7,0xFED8}},{0x0643,{0xFED9,0xFEDA,0xFEDB,0xFEDC}},
    {0x0644,{0xFEDD,0xFEDE,0xFEDF,0xFEE0}},{0x0645,{0xFEE1,0xFEE2,0xFEE3,0xFEE4}},
    {0x0646,{0xFEE5,0xFEE6,0xFEE7,0xFEE8}},{0x0647,{0xFEE9,0xFEEA,0xFEEB,0xFEEC}},
    {0x0648,{0xFEED,0xFEEE,0,0}},{0x0649,{0xFEEF,0xFEF0,0,0}},{0x064A,{0xFEF1,0xFEF2,0xFEF3,0xFEF4}},
    {0x0671,{0xFB50,0xFB51,0,0}},{0x0679,{0xFB66,0xFB67,0xFB68,0xFB69}},
    {0x067A,{0xFB5E,0xFB5F,0xFB60,0xFB61}},{0x067B,{0xFB52,0xFB53,0xFB54,0xFB55}},
    {0x067E,{0xFB56,0xFB57,0xFB58,0xFB59}},{0x067F,{0xFB62,0xFB63,0xFB64,0xFB65}},
    {0x0680,{0xFB5A,0xFB5B,0xFB5C,0xFB5D}},{0x0683,{0xFB76,0xFB77,0xFB78,0xFB79}},
    {0x0684,{0xFB72,0xFB73,0xFB74,0xFB75}},{0x0686,{0xFB7A,0xFB7B,0xFB7C,0xFB7D}},
    {0x0687,{0xFB7E,0xFB7F,0xFB80,0xFB81}},{0x0688,{0xFB88,0xFB89,0,0}},
    {0x068C,{0xFB84,0xFB85,0,0}},{0x068D,{0xFB82,0xFB83,0,0}},{0x068E,{0xFB86,0xFB87,0,0}},
    {0x0691,{0xFB8C,0xFB8D,0,0}},{0x0698,{0xFB8A,0xFB8B,0,0}},
    {0x06A4,{0xFB6A,0xFB6B,0xFB6C,0xFB6D}},{0x06A6,{0xFB6E,0xFB6F,0xFB70,0xFB71}},
    {0x06A9,{0xFB8E,0xFB8F,0xFB90,0xFB91}},{0x06AD,{0xFBD3,0xFBD4,0xFBD5,0xFBD6}},
    {0x06AF,{0xFB92,0xFB93,0xFB94,0xFB95}},{0x06BA,{0xFB9E,0xFB9F,0,0}},
    {0x06BB,{0xFBA0,0xFBA1,0xFBA2,0xFBA3}},{0x06BE,{0xFBAA,0xFBAB,0xFBAC,0xFBAD}},
    {0x06C0,{0xFBA4,0xFBA5,0,0}},{0x06C1,{0xFBA6,0xFBA7,0xFBA8,0xFBA9}},
    {0x06C5,{0xFBE0,0xFBE1,0,0}},{0x06C6,{0xFBD9,0xFBDA,0,0}},
    {0x06C7,{0xFBD7,0xFBD8,0,0}},{0x06C8,{0xFBDB,0xFBDC,0,0}},
    {0x06C9,{0xFBE2,0xFBE3,0,0}},{0x06CB,{0xFBDE,0xFBDF,0,0}},
    {0x06CC,{0xFBFC,0xFBFD,0xFBFE,0xFBFF}},{0x06D0,{0xFBE4,0xFBE5,0xFBE6,0xFBE7}},
    {0x06D2,{0xFBAE,0xFBAF,0,0}},{0x06D3,{0xFBB0,0xFBB1,0,0}},
};

const F *lk(uint32_t c){ for(auto &e:T) if(e.cp==c) return &e.v; return nullptr; }
bool isAr(uint32_t c){ return (c>=0x0600&&c<=0x06FF)||(c>=0x0750&&c<=0x077F)||(c>=0x08A0&&c<=0x08FF)||(c>=0xFB50&&c<=0xFDFF)||(c>=0xFE70&&c<=0xFEFF); }
bool isMark(uint32_t c){ return (c>=0x064B&&c<=0x065F)||(c>=0x0610&&c<=0x061A)||(c>=0x06D6&&c<=0x06DC)||(c>=0x06DF&&c<=0x06E4)||(c>=0x06E7&&c<=0x06E8)||(c>=0x06EA&&c<=0x06ED)||c==0x0670||c==0x06DD||c==0x06DE; }
bool joins(const F *f){ return f && (f->a || f->m); }

std::vector<uint32_t> u8to32(const std::string &s){
    std::vector<uint32_t> o; size_t i=0,n=s.size();
    while(i<n){ uint8_t c=(uint8_t)s[i]; uint32_t cp=0xFFFD; int ex=0;
        if(c<0x80){cp=c;ex=0;} else if((c&0xE0)==0xC0){cp=c&0x1F;ex=1;}
        else if((c&0xF0)==0xE0){cp=c&0x0F;ex=2;} else if((c&0xF8)==0xF0){cp=c&0x07;ex=3;}
        else{++i;continue;}
        bool ok=true;
        for(int k=0;k<ex;++k){ if(i+1>=n){ok=false;break;} ++i; uint8_t cc=(uint8_t)s[i];
            if((cc&0xC0)!=0x80){ok=false;break;} cp=(cp<<6)|(cc&0x3F);}
        o.push_back(ok?cp:0xFFFD); ++i;
    } return o;
}
std::string u32to8(const std::vector<uint32_t> &v){
    std::string o; o.reserve(v.size()*2);
    for(uint32_t cp:v){
        if(cp<0x80)o.push_back((char)cp);
        else if(cp<0x800){o.push_back((char)(0xC0|(cp>>6)));o.push_back((char)(0x80|(cp&0x3F)));}
        else if(cp<0x10000){o.push_back((char)(0xE0|(cp>>12)));o.push_back((char)(0x80|((cp>>6)&0x3F)));o.push_back((char)(0x80|(cp&0x3F)));}
        else{o.push_back((char)(0xF0|(cp>>18)));o.push_back((char)(0x80|((cp>>12)&0x3F)));o.push_back((char)(0x80|((cp>>6)&0x3F)));o.push_back((char)(0x80|(cp&0x3F)));}
    } return o;
}
std::vector<uint32_t> shape(const std::vector<uint32_t> &in){
    std::vector<uint32_t> o; o.reserve(in.size()); size_t n=in.size();
    for(size_t i=0;i<n;++i){
        uint32_t cp=in[i]; const F *f=lk(cp);
        if(!f){o.push_back(cp);continue;}
        bool pj=false;
        for(ssize_t j=(ssize_t)i-1;j>=0;--j){uint32_t p=in[(size_t)j]; if(isMark(p))continue; if(isAr(p))pj=joins(lk(p)); break;}
        bool nj=false;
        for(size_t j=i+1;j<n;++j){uint32_t x=in[j]; if(isMark(x))continue; if(isAr(x))nj=(lk(x)!=nullptr); break;}
        uint32_t c=f->i;
        if(pj&&nj&&f->m)c=f->m; else if(pj&&f->f)c=f->f; else if(nj&&f->a)c=f->a;
        o.push_back(c);
    } return o;
}
std::vector<uint32_t> bidi(const std::vector<uint32_t> &in){
    if(in.empty())return in;
    FriBidiStrIndex len=(FriBidiStrIndex)in.size();
    FriBidiParType base=FRIBIDI_PAR_ON;
    std::vector<FriBidiCharType> t(len); std::vector<FriBidiBracketType> b(len);
    std::vector<FriBidiLevel> lv(len); std::vector<FriBidiChar> vis(len);
    const auto *src=reinterpret_cast<const FriBidiChar*>(in.data());
    fribidi_get_bidi_types(src,len,t.data());
    fribidi_get_bracket_types(src,len,t.data(),b.data());
    if(!fribidi_get_par_embedding_levels_ex(t.data(),b.data(),len,&base,lv.data()))return in;
    if(!fribidi_reorder_line(FRIBIDI_FLAGS_DEFAULT,t.data(),len,0,base,lv.data(),
        reinterpret_cast<FriBidiChar*>(vis.data()),nullptr))return in;
    return vis;
}
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_awlqy_terminal_core_ArabicShaper_nativeShapeTerminal(JNIEnv *env,jclass,jstring src){
    if(!src)return env->NewStringUTF("");
    const char *c=env->GetStringUTFChars(src,nullptr); std::string in(c?c:""); env->ReleaseStringUTFChars(src,c);
    auto r=bidi(shape(u8to32(in))); return env->NewStringUTF(u32to8(r).c_str());
}
extern "C" JNIEXPORT jstring JNICALL
Java_com_awlqy_terminal_core_ArabicShaper_nativeShapeLogical(JNIEnv *env,jclass,jstring src){
    if(!src)return env->NewStringUTF("");
    const char *c=env->GetStringUTFChars(src,nullptr); std::string in(c?c:""); env->ReleaseStringUTFChars(src,c);
    auto r=shape(u8to32(in)); return env->NewStringUTF(u32to8(r).c_str());
}
extern "C" JNIEXPORT jboolean JNICALL
Java_com_awlqy_terminal_core_ArabicShaper_nativeContainsArabic(JNIEnv *env,jclass,jstring src){
    if(!src)return JNI_FALSE;
    const char *c=env->GetStringUTFChars(src,nullptr); bool f=false;
    if(c){ for(const char*p=c;*p&&!f;){uint32_t cp=0; uint8_t b=(uint8_t)*p;
        if(b<0x80){cp=b;p+=1;} else if((b&0xE0)==0xC0&&p[1]){cp=((b&0x1F)<<6)|(p[1]&0x3F);p+=2;}
        else if((b&0xF0)==0xE0&&p[1]&&p[2]){cp=((b&0x0F)<<12)|((p[1]&0x3F)<<6)|(p[2]&0x3F);p+=3;}
        else if((b&0xF8)==0xF0&&p[1]&&p[2]&&p[3]){cp=((b&0x07)<<18)|((p[1]&0x3F)<<12)|((p[2]&0x3F)<<6)|(p[3]&0x3F);p+=4;}
        else{p+=1;} if(isAr(cp))f=true; } }
    env->ReleaseStringUTFChars(src,c); return f?JNI_TRUE:JNI_FALSE;
}
AWLQY_EOF

# ═══ harfbuzz_render.cpp ═══
cat > app/src/main/cpp/harfbuzz_render.cpp <<'AWLQY_EOF'
#include <jni.h>
#include <cstdint>
#include <vector>
#include <hb.h>
#include <hb-ot.h>

extern "C" JNIEXPORT jintArray JNICALL
Java_com_awlqy_terminal_core_ArabicShaper_nativeHarfBuzzShape(
        JNIEnv *env,jclass,jstring jText,jstring jFontPath,jint pixelSize,jboolean rtl){
    if(!jText||!jFontPath)return nullptr;
    const char*text=env->GetStringUTFChars(jText,nullptr);
    const char*fp  =env->GetStringUTFChars(jFontPath,nullptr);
    hb_blob_t*blob=hb_blob_create_from_file_or_fail(fp);
    if(!blob){env->ReleaseStringUTFChars(jText,text);env->ReleaseStringUTFChars(jFontPath,fp);return nullptr;}
    hb_face_t*face=hb_face_create(blob,0);
    hb_font_t*font=hb_font_create(face);
    int scale=pixelSize>0?pixelSize:32;
    hb_font_set_scale(font,scale,scale); hb_ot_font_set_funcs(font);
    hb_buffer_t*buf=hb_buffer_create();
    hb_buffer_add_utf8(buf,text,-1,0,-1);
    hb_buffer_set_direction(buf,rtl?HB_DIRECTION_RTL:HB_DIRECTION_LTR);
    hb_buffer_set_script(buf,HB_SCRIPT_ARABIC);
    hb_buffer_set_language(buf,hb_language_from_string("ar",-1));
    hb_buffer_guess_segment_properties(buf);
    hb_shape(font,buf,nullptr,0);
    unsigned gc=0; hb_glyph_info_t*gi=hb_buffer_get_glyph_infos(buf,&gc);
    std::vector<jint> flat((size_t)gc*2);
    for(unsigned i=0;i<gc;++i){flat[i*2]=(jint)gi[i].codepoint;flat[i*2+1]=(jint)gi[i].cluster;}
    jintArray r=env->NewIntArray((jsize)flat.size());
    if(r&&!flat.empty())env->SetIntArrayRegion(r,0,(jsize)flat.size(),flat.data());
    hb_buffer_destroy(buf);hb_font_destroy(font);hb_face_destroy(face);hb_blob_destroy(blob);
    env->ReleaseStringUTFChars(jText,text); env->ReleaseStringUTFChars(jFontPath,fp);
    return r;
}
extern "C" JNIEXPORT jstring JNICALL
Java_com_awlqy_terminal_core_ArabicShaper_nativeHarfBuzzVersion(JNIEnv*env,jclass){
    const char*v=hb_version_string(); return env->NewStringUTF(v?v:"");
}
AWLQY_EOF

# ═══ PtyBridge.kt ═══
cat > app/src/main/java/com/awlqy/terminal/core/PtyBridge.kt <<'AWLQY_EOF'
package com.awlqy.terminal.core

object PtyBridge {
    init { System.loadLibrary("awlqy_engine") }
    external fun nativeOpen(rows: Int, cols: Int, shell: String?, cwd: String?, env: Array<String>?): IntArray?
    external fun nativeRead(fd: Int, buf: ByteArray, off: Int, len: Int): Int
    external fun nativeWrite(fd: Int, buf: ByteArray, off: Int, len: Int): Int
    external fun nativeResize(fd: Int, rows: Int, cols: Int)
    external fun nativeClose(fd: Int)
    external fun nativeWait(pid: Int): Int
    external fun nativeSignal(pid: Int, sig: Int)
    external fun nativeSignalGroup(pid: Int, sig: Int)
}
AWLQY_EOF

# ═══ ArabicShaper.kt ═══
cat > app/src/main/java/com/awlqy/terminal/core/ArabicShaper.kt <<'AWLQY_EOF'
package com.awlqy.terminal.core

object ArabicShaper {
    init { System.loadLibrary("awlqy_engine") }
    external fun nativeShapeTerminal(src: String): String
    external fun nativeShapeLogical(src: String): String
    external fun nativeContainsArabic(src: String): Boolean
    external fun nativeHarfBuzzShape(text: String, fontPath: String, pixelSize: Int, rtl: Boolean): IntArray?
    external fun nativeHarfBuzzVersion(): String

    fun shapeForTerminal(input: String): String = nativeShapeTerminal(input)
    fun shapeLogical(input: String): String = nativeShapeLogical(input)
    fun hasArabic(input: String): Boolean = nativeContainsArabic(input)
}
AWLQY_EOF

# ═══ TerminalSession.kt ═══
cat > app/src/main/java/com/awlqy/terminal/core/TerminalSession.kt <<'AWLQY_EOF'
package com.awlqy.terminal.core

import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.*
import timber.log.Timber
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

class TerminalSession(
    val name: String,
    private val shellPath: String,
    private val homePath: String,
    initialRows: Int = 24,
    initialCols: Int = 80,
    private val onOutput: (String) -> Unit
) {
    @Volatile private var fd: Int = -1
    @Volatile private var pid: Int = -1
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val running = AtomicBoolean(false)
    private val main = Handler(Looper.getMainLooper())

    val isRunning: Boolean get() = running.get()

    fun start() {
        if (running.getAndSet(true)) return
        File(homePath).mkdirs()
        val env = arrayOf(
            "HOME=$homePath",
            "TMPDIR=$homePath/../tmp",
            "PATH=/data/data/com.awlqy.terminal/files/usr/bin:/system/bin:/system/xbin"
        )
        val res = PtyBridge.nativeOpen(initialRows, initialCols, shellPath, homePath, env)
        if (res == null) { running.set(false); Timber.e("PTY open failed"); return }
        fd = res[0]; pid = res[1]
        Timber.i("session %s started fd=%d pid=%d", name, fd, pid)
        scope.launch { readLoop() }
    }

    private fun readLoop() {
        val buf = ByteArray(8192)
        while (running.get()) {
            val n = PtyBridge.nativeRead(fd, buf, 0, buf.size)
            if (n > 0) {
                val chunk = String(buf, 0, n, Charsets.UTF_8)
                main.post { onOutput(chunk) }
            } else if (n < 0) {
                break
            } else {
                delay(20)
            }
        }
        running.set(false)
        main.post { onOutput("\r\n[session ended]\r\n") }
    }

    fun write(data: String) {
        if (fd < 0 || !running.get()) return
        scope.launch {
            val bytes = data.toByteArray(Charsets.UTF_8)
            PtyBridge.nativeWrite(fd, bytes, 0, bytes.size)
        }
    }

    fun resize(rows: Int, cols: Int) {
        if (fd >= 0) PtyBridge.nativeResize(fd, rows, cols)
    }

    fun sendSignal(sig: Int) { if (pid > 0) PtyBridge.nativeSignal(pid, sig) }
    fun sendSignalGroup(sig: Int) { if (pid > 0) PtyBridge.nativeSignalGroup(pid, sig) }

    fun stop() {
        running.set(false)
        if (pid > 0) PtyBridge.nativeSignalGroup(pid, 9)
        if (fd >= 0) PtyBridge.nativeClose(fd)
        scope.cancel()
        fd = -1; pid = -1
    }
}
AWLQY_EOF

# ═══ TerminalView.kt ═══
cat > app/src/main/java/com/awlqy/terminal/ui/TerminalView.kt <<'AWLQY_EOF'
package com.awlqy.terminal.ui

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import com.awlqy.terminal.core.ArabicShaper
import kotlin.math.min

class TerminalView @JvmOverloads constructor(
    ctx: Context, attrs: AttributeSet? = null, def: Int = 0
) : View(ctx, attrs, def) {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.MONOSPACE
        textSize = 28f
        color = Color.parseColor("#E6EDF3")
    }
    private val bgPaint = Paint().apply { color = Color.parseColor("#0A0E14") }

    private val lines = ArrayDeque<String>()
    private val maxLines = 2000
    private var cols = 0
    private var rows = 0
    private var cursorVisible = true

    var rtlEnabled: Boolean = true
    var onInput: ((String) -> Unit)? = null
    var onSizeChanged: ((rows: Int, cols: Int) -> Unit)? = null

    init {
        setLayerType(LAYER_TYPE_HARDWARE, null)
    }

    fun append(text: String) {
        // تقسيم إلى أسطر معالجة CR/LF
        val normalized = text.replace("\r\n", "\n").replace('\r', '\n')
        for (line in normalized.split('\n')) {
            if (lines.isEmpty() || lastEndsWithNewline) {
                lines.addLast(line)
            } else {
                lines[lines.size - 1] = lines.last() + line
            }
            lastEndsWithNewline = false
        }
        if (normalized.endsWith('\n')) lastEndsWithNewline = true
        while (lines.size > maxLines) lines.removeFirst()
        postInvalidateOnAnimation()
    }

    private var lastEndsWithNewline = true

    fun clear() { lines.clear(); postInvalidateOnAnimation() }

    fun fullText(): String = lines.joinToString("\n")

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val fm = paint.fontMetrics
        val lineH = (fm.descent - fm.ascent)
        val charW = paint.measureText("M")
        cols = (w / charW).toInt().coerceAtLeast(20)
        rows = (h / lineH).toInt().coerceAtLeast(5)
        onSizeChanged?.invoke(rows, cols)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)
        val fm = paint.fontMetrics
        val lineH = (fm.descent - fm.ascent) + 2f
        var y = -fm.ascent + 4f
        val visible = min(rows, lines.size)
        val start = lines.size - visible
        for (i in 0 until visible) {
            val raw = lines[start + i]
            val display = if (rtlEnabled && ArabicShaper.hasArabic(raw))
                ArabicShaper.shapeForTerminal(raw) else raw
            canvas.drawText(display, 6f, y, paint)
            y += lineH
        }
        // cursor blinking
        if (cursorVisible && lines.isNotEmpty()) {
            val last = lines.last()
            val w = paint.measureText(if (rtlEnabled) ArabicShaper.shapeForTerminal(last) else last)
            canvas.drawRect(6f + w, y - lineH + 4f, 6f + w + 3f, y + 2f, paint)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_DOWN) {
            cursorVisible = !cursorVisible
            postInvalidateOnAnimation()
            return true
        }
        return super.onTouchEvent(event)
    }
}
AWLQY_EOF

# ═══ TerminalFragment.kt (real) ═══
cat > app/src/main/java/com/awlqy/terminal/ui/fragments/TerminalFragment.kt <<'AWLQY_EOF'
package com.awlqy.terminal.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import androidx.fragment.app.Fragment
import com.awlqy.terminal.R
import com.awlqy.terminal.core.TerminalSession
import com.awlqy.terminal.databinding.FragmentTerminalBinding
import java.io.File

class TerminalFragment : Fragment() {

    private var _b: FragmentTerminalBinding? = null
    private val b get() = _b!!
    private var session: TerminalSession? = null

    override fun onCreateView(i: LayoutInflater, c: ViewGroup?, s: Bundle?): View {
        _b = FragmentTerminalBinding.inflate(i, c, false)
        return b.root
    }

    override fun onViewCreated(v: View, s: Bundle?) {
        val name = arguments?.getString(ARG_NAME) ?: "main"
        val home = File(requireContext().filesDir, "home").apply { mkdirs() }.absolutePath
        val shell = "/system/bin/sh"

        session = TerminalSession(name, shell, home, 24, 80) { chunk ->
            b.terminalView.append(chunk)
        }.also { it.start() }

        b.terminalView.onSizeChanged = { r, c -> session?.resize(r, c) }

        b.btnSend.setOnClickListener { sendCurrent() }
        b.inputEdit.setOnEditorActionListener { _, id, _ ->
            if (id == EditorInfo.IME_ACTION_SEND) { sendCurrent(); true } else false
        }

        b.btnCtrlC.setOnClickListener { session?.write("\u0003") }
        b.btnCtrlD.setOnClickListener { session?.write("\u0004") }
        b.btnCtrlZ.setOnClickListener { session?.write("\u001A") }
        b.btnTab.setOnClickListener   { session?.write("\t") }
        b.btnEsc.setOnClickListener   { session?.write("\u001B") }
        b.btnUp.setOnClickListener    { session?.write("\u001B[A") }
        b.btnDown.setOnClickListener  { session?.write("\u001B[B") }
        b.btnLeft.setOnClickListener  { session?.write("\u001B[D") }
        b.btnRight.setOnClickListener { session?.write("\u001B[C") }
        b.btnClear.setOnClickListener { b.terminalView.clear() }
    }

    private fun sendCurrent() {
        val txt = b.inputEdit.text.toString()
        if (txt.isEmpty()) { session?.write("\n"); return }
        session?.write(txt + "\n")
        b.inputEdit.setText("")
    }

    override fun onDestroyView() {
        session?.stop()
        _b = null
        super.onDestroyView()
    }

    companion object {
        private const val ARG_NAME = "name"
        fun newInstance(name: String) = TerminalFragment().apply {
            arguments = Bundle().apply { putString(ARG_NAME, name) }
        }
    }
}
AWLQY_EOF

# ═══ PackageManager (auto-healing) ═══
cat > app/src/main/java/com/awlqy/terminal/data/AwlqyPkg.kt <<'AWLQY_EOF'
package com.awlqy.terminal.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * awlqy-pkg: مدير حزم ذكي مع إصلاح ذاتي.
 * - يدعم pip / npm / gem / cargo / go / clang / apt (لو متاح).
 * - عند فشل التنزيل: يعيد المحاولة مع الإصلاح (dpkg --configure -a، apt fix-broken، استئناف).
 */
class AwlqyPkg(private val workDir: File) {

    data class Result(val exitCode: Int, val stdout: String, val stderr: String) {
        val ok get() = exitCode == 0
    }

    private suspend fun run(cmd: List<String>, timeoutMin: Long = 10): Result =
        withContext(Dispatchers.IO) {
            try {
                val pb = ProcessBuilder(cmd).directory(workDir).redirectErrorStream(false)
                val p = pb.start()
                val out = p.inputStream.bufferedReader().readText()
                val err = p.errorStream.bufferedReader().readText()
                if (!p.waitFor(timeoutMin, TimeUnit.MINUTES)) { p.destroyForcibly(); return@withContext Result(-1, out, err + "\n[timeout]") }
                Result(p.exitValue(), out, err)
            } catch (t: Throwable) {
                Timber.e(t, "pkg run failed: %s", cmd.joinToString(" "))
                Result(-1, "", t.message ?: "unknown")
            }
        }

    /**
     * تشغيل أمر مع إصلاح ذاتي + retry.
     */
    suspend fun runWithHealing(cmd: List<String>, maxRetries: Int = 3): Result {
        var last: Result? = null
        for (attempt in 1..maxRetries) {
            Timber.i("awlqy-pkg attempt %d: %s", attempt, cmd.joinToString(" "))
            last = run(cmd)
            if (last.ok) return last

            Timber.w("attempt %d failed, healing...", attempt)
            // خطوات الإصلاح الذاتي
            run(listOf("sh", "-c", "apt-get -y -f install || true"), 5)
            run(listOf("sh", "-c", "dpkg --configure -a || true"), 5)
            run(listOf("sh", "-c", "apt-get -y --fix-broken install || true"), 5)
            // pip cache purge لو الفشل من pip
            if (cmd.firstOrNull()?.contains("pip") == true) {
                run(listOf("sh", "-c", "python -m pip cache purge || true"), 3)
                run(listOf("sh", "-c", "python -m pip install --upgrade pip setuptools wheel || true"), 5)
            }
            if (cmd.firstOrNull()?.contains("npm") == true) {
                run(listOf("sh", "-c", "npm cache clean --force || true"), 5)
            }
            kotlinx.coroutines.delay(1500L * attempt)
        }
        return last ?: Result(-1, "", "no attempt")
    }

    // ── واجهات عالية المستوى ──
    suspend fun pipInstall(pkg: String) = runWithHealing(listOf("sh", "-c", "python -m pip install --no-input $pkg"))
    suspend fun npmInstall(pkg: String) = runWithHealing(listOf("sh", "-c", "npm install -g $pkg || npm install $pkg"))
    suspend fun gemInstall(pkg: String) = runWithHealing(listOf("sh", "-c", "gem install $pkg"))
    suspend fun cargoInstall(pkg: String) = runWithHealing(listOf("sh", "-c", "cargo install $pkg"))
    suspend fun goInstall(pkg: String)  = runWithHealing(listOf("sh", "-c", "go install $pkg"))
    suspend fun phpComposer(pkg: String) = runWithHealing(listOf("sh", "-c", "composer require $pkg"))

    /**
     * يكشف الخطأ ويستنتج الحزمة الناقصة ثم يثبّتها ويعيد التنفيذ.
     */
    suspend fun autoHealAndRetry(scriptPath: String, interpreter: String): Result {
        var last = runWithHealing(listOf(interpreter, scriptPath), 1)
        if (last.ok) return last

        val missing = detectMissing(last.stderr + "\n" + last.stdout) ?: return last
        Timber.i("auto-heal: missing=%s", missing)
        when (interpreter) {
            "python", "python3" -> pipInstall(missing)
            "node" -> npmInstall(missing)
            "ruby" -> gemInstall(missing)
            "php" -> phpComposer(missing)
        }
        last = runWithHealing(listOf(interpreter, scriptPath), 2)
        return last
    }

    private fun detectMissing(err: String): String? {
        Regex("ModuleNotFoundError: No module named '([^']+)'").find(err)?.let { return it.groupValues[1] }
        Regex("ImportError: cannot import name '([^']+)'").find(err)?.let { return it.groupValues[1] }
        Regex("Cannot find module '([^']+)'").find(err)?.let { return it.groupValues[1] }
        Regex("no required module provides package ([^;\\s]+)").find(err)?.let { return it.groupValues[1] }
        Regex("LoadError: cannot load such file -- ([^\\s]+)").find(err)?.let { return it.groupValues[1] }
        Regex("Fatal error: Uncaught Error: Class \"([^\"]+)\" not found").find(err)?.let { return it.groupValues[1] }
        return null
    }
}
AWLQY_EOF

# ═══ ApkBuilder ═══
cat > app/src/main/java/com/awlqy/terminal/data/ApkBuilder.kt <<'AWLQY_EOF'
package com.awlqy.terminal.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * محرك بناء/تفكيك APK على الجهاز.
 * يعتمد على وجود: aapt2, d8, apktool, jadx, apksigner, zipalign
 * (يمكن تثبيتها عبر awlqy-pkg أو وضعها في usr/bin).
 */
class ApkBuilder(private val workDir: File) {

    private fun bin(name: String): String {
        val local = File(workDir, "../usr/bin/$name")
        return if (local.exists()) local.absolutePath else name
    }

    private suspend fun run(cmd: List<String>): Int = withContext(Dispatchers.IO) {
        try {
            val p = ProcessBuilder(cmd).directory(workDir).inheritIO().start()
            p.waitFor(30, TimeUnit.MINUTES)
            p.exitValue()
        } catch (t: Throwable) { Timber.e(t, "apk run fail"); -1 }
    }

    suspend fun decode(apk: File, outDir: File): Int {
        outDir.mkdirs()
        return run(listOf("sh", "-c",
            "${bin("apktool")} d -f -o '${outDir.absolutePath}' '${apk.absolutePath}'"))
    }

    suspend fun build(decodedDir: File, outApk: File): Int {
        return run(listOf("sh", "-c",
            "${bin("apktool")} b -o '${outApk.absolutePath}' '${decodedDir.absolutePath}'"))
    }

    suspend fun sign(apk: File, keystore: File, alias: String, pass: String): Int {
        return run(listOf("sh", "-c",
            "${bin("apksigner")} sign --ks '${keystore.absolutePath}' " +
            "--ks-key-alias '$alias' --ks-pass pass:'$pass' --key-pass pass:'$pass' '${apk.absolutePath}'"))
    }

    suspend fun zipalign(input: File, output: File): Int {
        return run(listOf("sh", "-c",
            "${bin("zipalign")} -f 4 '${input.absolutePath}' '${output.absolutePath}'"))
    }

    suspend fun decompileToJava(apk: File, outDir: File): Int {
        outDir.mkdirs()
        return run(listOf("sh", "-c",
            "${bin("jadx")} -d '${outDir.absolutePath}' '${apk.absolutePath}'"))
    }

    suspend fun aapt2Dump(apk: File): Int {
        return run(listOf("sh", "-c", "${bin("aapt2")} dump badging '${apk.absolutePath}'"))
    }

    suspend fun dexToSmali(decodedDir: File): Int {
        return run(listOf("sh", "-c",
            "${bin("d8")} --output '${decodedDir.absolutePath}/smali_out' " +
            "'${decodedDir.absolutePath}'/smali/**/*.smali"))
    }
}
AWLQY_EOF

# ═══ Social Automation ═══
cat > app/src/main/java/com/awlqy/terminal/data/SocialAutomation.kt <<'AWLQY_EOF'
package com.awlqy.terminal.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import timber.log.Timber
import java.util.concurrent.TimeUnit

/**
 * إطار إدارة حسابات متعددة عبر API/Webhooks.
 * يدير جلسات مستقلة لكل حساب ويسمح بإرسال إجراءات متتابعة أو متوازية.
 */
class SocialAutomation {

    data class Account(
        val id: String,
        val platform: String,
        val token: String,
        val endpoint: String
    )

    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .build()

    private val accounts = mutableMapOf<String, Account>()
    private val json = "application/json; charset=utf-8".toMediaType()

    fun register(a: Account) { accounts[a.id] = a; Timber.i("registered %s", a.id) }
    fun list(): List<Account> = accounts.values.toList()
    fun remove(id: String) { accounts.remove(id) }

    suspend fun post(accountId: String, payloadJson: String): String? = withContext(Dispatchers.IO) {
        val a = accounts[accountId] ?: run { Timber.w("no account %s", accountId); return@withContext null }
        val req = Request.Builder()
            .url(a.endpoint)
            .addHeader("Authorization", "Bearer ${a.token}")
            .addHeader("Content-Type", "application/json")
            .post(payloadJson.toRequestBody(json))
            .build()
        try {
            client.newCall(req).execute().use { r ->
                r.body?.string().also { Timber.i("post %s -> %d", accountId, r.code) }
            }
        } catch (t: Throwable) { Timber.e(t, "post fail"); null }
    }

    suspend fun postToAll(payloadJson: String): Map<String, String?> = withContext(Dispatchers.IO) {
        accounts.keys.associateWith { id -> post(id, payloadJson) }
    }

    suspend fun webhook(url: String, payloadJson: String): String? = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .post(payloadJson.toRequestBody(json)).build()
        try { client.newCall(req).execute().use { it.body?.string() } }
        catch (t: Throwable) { Timber.e(t, "webhook fail"); null }
    }
}
AWLQY_EOF

# ═══ ASCII Art Generator ═══
cat > app/src/main/java/com/awlqy/terminal/util/AsciiArt.kt <<'AWLQY_EOF'
package com.awlqy.terminal.util

/**
 * مولّد لافتات ASCII ومؤثرات نصية للطرفية.
 */
object AsciiArt {

    fun banner(text: String, char: Char = '█'): String {
        val font = blockFont()
        val letters = text.uppercase().toCharArray()
        val rows = 7
        val sb = StringBuilder()
        for (r in 0 until rows) {
            for (c in letters) {
                val glyph = font[c] ?: continue
                sb.append(glyph[r].replace('#', char)).append(' ')
            }
            sb.append('\n')
        }
        return sb.toString()
    }

    fun frame(title: String, lines: List<String>, width: Int = 60): String {
        val sb = StringBuilder()
        sb.append('┌').append("─".repeat(width - 2)).append('┐').append('\n')
        val t = " $title "
        val left = (width - 2 - t.length) / 2
        sb.append('│').append(" ".repeat(left.coerceAtLeast(0)))
          .append(t)
          .append(" ".repeat((width - 2 - t.length - left).coerceAtLeast(0)))
          .append('│').append('\n')
        sb.append('├').append("─".repeat(width - 2)).append('┤').append('\n')
        lines.forEach { ln ->
            val pad = width - 4 - ln.length
            sb.append("│ ").append(ln)
              .append(" ".repeat(pad.coerceAtLeast(0))).append(" │").append('\n')
        }
        sb.append('└').append("─".repeat(width - 2)).append('┘')
        return sb.toString()
    }

    fun progress(pct: Int, width: Int = 30): String {
        val p = pct.coerceIn(0, 100)
        val filled = (p * width) / 100
        return "[${"█".repeat(filled)}${"░".repeat(width - filled)}] $p%"
    }

    private fun blockFont(): Map<Char, Array<String>> = mapOf(
        'A' to arrayOf("  ###  ", " ## ## ", "##   ##", "#######", "##   ##", "##   ##", "##   ##"),
        'B' to arrayOf("###### ", "##   ##", "##   ##", "###### ", "##   ##", "##   ##", "###### "),
        'C' to arrayOf("  #### ", " ##  ##", "##     ", "##     ", "##     ", " ##  ##", "  #### "),
        'D' to arrayOf("#####  ", "##  ## ", "##   ##", "##   ##", "##   ##", "##  ## ", "#####  "),
        'E' to arrayOf("#######", "##     ", "##     ", "#####  ", "##     ", "##     ", "#######"),
        'F' to arrayOf("#######", "##     ", "##     ", "#####  ", "##     ", "##     ", "##     "),
        'G' to arrayOf("  #### ", " ##  ##", "##     ", "##  ###", "##   ##", " ##  ##", "  #### "),
        'H' to arrayOf("##   ##", "##   ##", "##   ##", "#######", "##   ##", "##   ##", "##   ##"),
        'I' to arrayOf("#######", "  ###  ", "  ###  ", "  ###  ", "  ###  ", "  ###  ", "#######"),
        'J' to arrayOf("  #####", "    ## ", "    ## ", "    ## ", "##  ## ", " ## ## ", "  ###  "),
        'K' to arrayOf("##   ##", "##  ## ", "## ##  ", "####   ", "## ##  ", "##  ## ", "##   ##"),
        'L' to arrayOf("##     ", "##     ", "##     ", "##     ", "##     ", "##     ", "#######"),
        'M' to arrayOf("##   ##", "### ###", "#######", "## # ##", "##   ##", "##   ##", "##   ##"),
        'N' to arrayOf("##   ##", "###  ##", "#### ##", "## ####", "##  ###", "##   ##", "##   ##"),
        'O' to arrayOf("  ###  ", " ## ## ", "##   ##", "##   ##", "##   ##", " ## ## ", "  ###  "),
        'P' to arrayOf("###### ", "##   ##", "##   ##", "###### ", "##     ", "##     ", "##     "),
        'Q' to arrayOf("  ###  ", " ## ## ", "##   ##", "##   ##", "## # ##", " ## ## ", "  ### #"),
        'R' to arrayOf("###### ", "##   ##", "##   ##", "###### ", "## ##  ", "##  ## ", "##   ##"),
        'S' to arrayOf("  #### ", " ##  ##", "##     ", " ##### ", "     ##", "##  ## ", " ####  "),
        'T' to arrayOf("#######", "  ###  ", "  ###  ", "  ###  ", "  ###  ", "  ###  ", "  ###  "),
        'U' to arrayOf("##   ##", "##   ##", "##   ##", "##   ##", "##   ##", "##   ##", " ##### "),
        'V' to arrayOf("##   ##", "##   ##", "##   ##", "##   ##", " ## ## ", " ## ## ", "  ###  "),
        'W' to arrayOf("##   ##", "##   ##", "##   ##", "## # ##", "#######", "### ###", "##   ##"),
        'X' to arrayOf("##   ##", " ## ## ", "  ###  ", "  ###  ", "  ###  ", " ## ## ", "##   ##"),
        'Y' to arrayOf("##   ##", " ## ## ", "  ###  ", "  ###  ", "  ###  ", "  ###  ", "  ###  "),
        'Z' to arrayOf("#######", "     ##", "    ## ", "  ###  ", " ##    ", "##     ", "#######"),
        ' ' to arrayOf("       ", "       ", "       ", "       ", "       ", "       ", "       ")
    )
}
AWLQY_EOF

# ═══ Code Guide ═══
cat > app/src/main/java/com/awlqy/terminal/util/CodeGuide.kt <<'AWLQY_EOF'
package com.awlqy.terminal.util

/**
 * دليل أكواد متعدد اللغات: قوالب + أمثلة + أفضل الممارسات.
 */
object CodeGuide {

    data class Lang(val id: String, val name: String, val hello: String, val template: String)

    val languages: List<Lang> = listOf(
        Lang("python", "Python",
            "print('مرحباً من awlqy')",
            """
def main():
    import sys
    args = sys.argv[1:]
    print("awlqy · Python ready", args)

if __name__ == "__main__":
    main()
            """.trimIndent()),
        Lang("bash", "Bash",
            "echo 'مرحباً من awlqy'",
            """
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
echo "awlqy · Bash ready"
for f in *; do echo "- ${'$'}f"; done
            """.trimIndent()),
        Lang("js", "JavaScript",
            "console.log('مرحباً من awlqy')",
            """
const name = "awlqy";
console.log(`${'$'}{name} · Node.js ready`);
export default function main() { return name; }
            """.trimIndent()),
        Lang("ts", "TypeScript",
            "const msg: string = 'مرحباً';\nconsole.log(msg);",
            """
interface App { name: string; version: string; }
const app: App = { name: "awlqy", version: "1.0.0" };
console.log(`${'$'}{app.name} v${'$'}{app.version}`);
            """.trimIndent()),
        Lang("cpp", "C++",
            "#include <iostream>\nint main(){ std::cout << \"مرحباً\\n\"; }",
            """
#include <iostream>
#include <string>
int main(int argc, char** argv) {
    std::string name = "awlqy";
    std::cout << name << " · C++ ready" << std::endl;
    return 0;
}
            """.trimIndent()),
        Lang("go", "Go",
            "package main\nimport \"fmt\"\nfunc main(){ fmt.Println(\"مرحباً\") }",
            """
package main
import "fmt"
func main() {
    fmt.Println("awlqy · Go ready")
}
            """.trimIndent()),
        Lang("rust", "Rust",
            "fn main(){ println!(\"مرحباً\"); }",
            """
fn main() {
    let name = "awlqy";
    println!("{} · Rust ready", name);
}
            """.trimIndent()),
        Lang("java", "Java",
            "public class M{ public static void main(String[] a){ System.out.println(\"مرحباً\"); }}",
            """
public class Main {
    public static void main(String[] args) {
        String name = "awlqy";
        System.out.println(name + " · Java ready");
    }
}
            """.trimIndent()),
        Lang("php", "PHP",
            "<?php echo 'مرحباً';",
            """
<?php
${'$'}name = "awlqy";
echo "${'$'}name · PHP ready\\n";
            """.trimIndent())
    )

    fun byId(id: String): Lang? = languages.firstOrNull { it.id == id }
    fun cheatSheet(): String = languages.joinToString("\n") { "- ${it.id}: ${it.hello}" }
}
AWLQY_EOF

echo "✔ [awlqy] 02-native: انتهى."
