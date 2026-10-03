#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [ensure-cmake] التأكد من المجلدات"
mkdir -p app/src/main/cpp

echo "▶ [ensure-cmake] كتابة CMakeLists.txt"
cat > app/src/main/cpp/CMakeLists.txt <<'CM_EOF'
cmake_minimum_required(VERSION 3.22.1)
project(awlqy_pty C)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_library(awlqy_pty SHARED pty_bridge.c)

find_library(log-lib log)
target_link_libraries(awlqy_pty ${log-lib})

target_compile_options(awlqy_pty PRIVATE -O2 -fvisibility=hidden)
CM_EOF

echo "▶ [ensure-cmake] كتابة pty_bridge.c إذا مفقود"
if [ ! -f app/src/main/cpp/pty_bridge.c ]; then
cat > app/src/main/cpp/pty_bridge.c <<'C_EOF'
#include <jni.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <android/log.h>

#define LOG_TAG "awlqy-pty"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#ifndef TIOCSPTLCK
#define TIOCSPTLCK 0x40045431
#endif
#ifndef TIOCGPTN
#define TIOCGPTN   0x80045430
#endif
#ifndef TIOCSCTTY
#define TIOCSCTTY  0x540E
#endif

static int create_pty(int *master_out, int *slave_out, int rows, int cols) {
    int ptm = open("/dev/ptmx", O_RDWR | O_NOCTTY);
    if (ptm < 0) { LOGE("open /dev/ptmx: %s", strerror(errno)); return -1; }
    int unlock = 0;
    if (ioctl(ptm, TIOCSPTLCK, &unlock) < 0) {
        LOGE("TIOCSPTLCK: %s", strerror(errno)); close(ptm); return -1;
    }
    int ptsn = 0;
    if (ioctl(ptm, TIOCGPTN, &ptsn) < 0) {
        LOGE("TIOCGPTN: %s", strerror(errno)); close(ptm); return -1;
    }
    char slave_path[64];
    snprintf(slave_path, sizeof(slave_path), "/dev/pts/%d", ptsn);
    int pts = open(slave_path, O_RDWR | O_NOCTTY);
    if (pts < 0) {
        LOGE("open %s: %s", slave_path, strerror(errno)); close(ptm); return -1;
    }
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = (unsigned short)(rows > 0 ? rows : 24);
    ws.ws_col = (unsigned short)(cols > 0 ? cols : 80);
    ioctl(ptm, TIOCSWINSZ, &ws);
    *master_out = ptm;
    *slave_out = pts;
    return 0;
}

JNIEXPORT jintArray JNICALL
Java_com_awlqy_terminal_core_PtyBridge_createSubprocess(
        JNIEnv *env, jclass clazz,
        jstring jCmd, jstring jCwd,
        jobjectArray jArgs, jobjectArray jEnv,
        jint rows, jint cols) {

    const char *cmd = (*env)->GetStringUTFChars(env, jCmd, NULL);
    const char *cwd = jCwd ? (*env)->GetStringUTFChars(env, jCwd, NULL) : NULL;

    int ptm = -1, pts = -1;
    if (create_pty(&ptm, &pts, rows, cols) != 0) {
        if (cmd) (*env)->ReleaseStringUTFChars(env, jCmd, cmd);
        if (cwd) (*env)->ReleaseStringUTFChars(env, jCwd, cwd);
        return NULL;
    }

    int argc = 1;
    if (jArgs) argc += (int)(*env)->GetArrayLength(env, jArgs);
    char **argv = (char **) calloc((size_t)argc + 1, sizeof(char *));
    if (!argv) { close(ptm); close(pts); return NULL; }
    argv[0] = strdup(cmd ? cmd : "/system/bin/sh");
    if (jArgs) {
        jsize n = (*env)->GetArrayLength(env, jArgs);
        for (jsize i = 0; i < n; i++) {
            jstring js = (jstring)(*env)->GetObjectArrayElement(env, jArgs, i);
            const char *cs = js ? (*env)->GetStringUTFChars(env, js, NULL) : NULL;
            argv[i + 1] = strdup(cs ? cs : "");
            if (cs) (*env)->ReleaseStringUTFChars(env, js, cs);
            if (js) (*env)->DeleteLocalRef(env, js);
        }
    }

    int env_n = 0;
    char **envp = NULL;
    if (jEnv) {
        env_n = (int)(*env)->GetArrayLength(env, jEnv);
        envp = (char **) calloc((size_t)env_n + 1, sizeof(char *));
        for (int i = 0; i < env_n; i++) {
            jstring js = (jstring)(*env)->GetObjectArrayElement(env, jEnv, i);
            const char *cs = js ? (*env)->GetStringUTFChars(env, js, NULL) : NULL;
            envp[i] = strdup(cs ? cs : "");
            if (cs) (*env)->ReleaseStringUTFChars(env, js, cs);
            if (js) (*env)->DeleteLocalRef(env, js);
        }
        envp[env_n] = NULL;
    }

    pid_t pid = fork();
    if (pid < 0) {
        LOGE("fork: %s", strerror(errno));
        close(ptm); close(pts);
        if (cmd) (*env)->ReleaseStringUTFChars(env, jCmd, cmd);
        if (cwd) (*env)->ReleaseStringUTFChars(env, jCwd, cwd);
        return NULL;
    }

    if (pid == 0) {
        close(ptm);
        setsid();
        ioctl(pts, TIOCSCTTY, 0);
        dup2(pts, 0); dup2(pts, 1); dup2(pts, 2);
        if (pts > 2) close(pts);

        if (cwd && *cwd && chdir(cwd) != 0) chdir("/");
        setenv("TERM",      "xterm-256color", 1);
        setenv("COLORTERM", "truecolor",      1);
        setenv("LANG",      "en_US.UTF-8",    1);
        setenv("LC_ALL",    "en_US.UTF-8",    1);

        if (envp) {
            for (int i = 0; i < env_n; i++) {
                if (envp[i] && strchr(envp[i], '=')) putenv(envp[i]);
            }
        }
        execvp(argv[0], argv);
        _exit(127);
    }

    close(pts);
    int flags = fcntl(ptm, F_GETFL, 0);
    fcntl(ptm, F_SETFL, flags | O_NONBLOCK);

    if (cmd) (*env)->ReleaseStringUTFChars(env, jCmd, cmd);
    if (cwd) (*env)->ReleaseStringUTFChars(env, jCwd, cwd);

    jint pair[2];
    pair[0] = ptm;
    pair[1] = (jint)pid;
    jintArray out = (*env)->NewIntArray(env, 2);
    (*env)->SetIntArrayRegion(env, out, 0, 2, pair);
    return out;
}

JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_read(
        JNIEnv *env, jclass clazz, jint fd, jbyteArray buf, jint off, jint len) {
    if (fd < 0 || len <= 0) return -1;
    jbyte *b = (*env)->GetByteArrayElements(env, buf, NULL);
    ssize_t n = read(fd, b + off, (size_t)len);
    int err = (n < 0) ? errno : 0;
    if (n > 0) { (*env)->ReleaseByteArrayElements(env, buf, b, 0); return (jint)n; }
    (*env)->ReleaseByteArrayElements(env, buf, b, JNI_ABORT);
    if (err == EAGAIN || err == EWOULDBLOCK) return 0;
    return -1;
}

JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_write(
        JNIEnv *env, jclass clazz, jint fd, jbyteArray buf, jint off, jint len) {
    if (fd < 0 || len <= 0) return -1;
    jbyte *b = (*env)->GetByteArrayElements(env, buf, NULL);
    ssize_t total = 0;
    while (total < len) {
        ssize_t n = write(fd, b + off + total, (size_t)(len - total));
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) { usleep(500); continue; }
            break;
        }
        total += n;
    }
    (*env)->ReleaseByteArrayElements(env, buf, b, JNI_ABORT);
    return (jint)total;
}

JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_resize(
        JNIEnv *env, jclass clazz, jint fd, jint rows, jint cols) {
    if (fd < 0) return;
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ioctl(fd, TIOCSWINSZ, &ws);
}

JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_close(JNIEnv *env, jclass clazz, jint fd) {
    if (fd >= 0) close(fd);
}

JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_waitFor(JNIEnv *env, jclass clazz, jint pid) {
    if (pid <= 0) return -1;
    int status = 0;
    while (waitpid((pid_t)pid, &status, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(status))   return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return status;
}

JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_signal(
        JNIEnv *env, jclass clazz, jint pid, jint sig) {
    if (pid > 0) kill((pid_t)pid, sig);
}

JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_signalGroup(
        JNIEnv *env, jclass clazz, jint pid, jint sig) {
    if (pid > 0) kill(-(pid_t)pid, sig);
}
C_EOF
fi

echo "▶ [ensure-cmake] تحديث app/build.gradle.kts ليكون externalNativeBuild مشروطاً"

cat > app/build.gradle.kts <<'GRADLE_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.awlqy.terminal"
    compileSdk = 34
    ndkVersion = "26.1.10909125"

    defaultConfig {
        applicationId = "com.awlqy.terminal"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    val cmakeFile = file("src/main/cpp/CMakeLists.txt")
    if (cmakeFile.exists()) {
        externalNativeBuild {
            cmake {
                path = cmakeFile
                version = "3.22.1"
            }
        }
        defaultConfig {
            externalNativeBuild {
                cmake {
                    cppFlags += "-O2"
                }
            }
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isDebuggable = true
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { viewBinding = true; buildConfig = true }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/*.kotlin_module",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*"
            )
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.jakewharton.timber:timber:5.0.1")
}
GRADLE_EOF

echo ""
echo "▶ [ensure-cmake] التحقق:"
echo "  CMakeLists.txt: $(ls -la app/src/main/cpp/CMakeLists.txt 2>/dev/null || echo 'مفقود!')"
echo "  pty_bridge.c  : $(ls -la app/src/main/cpp/pty_bridge.c 2>/dev/null || echo 'مفقود!')"
echo ""
echo "▶ [ensure-cmake] قائمة cpp/"
ls -la app/src/main/cpp/
echo ""
echo "▶ [ensure-cmake] build.gradle.kts أول 5 أسطر:"
head -n 5 app/build.gradle.kts
echo ""
echo "✔ [ensure-cmake] انتهى."
echo "   git add -A"
echo "   git commit -m 'fix: ensure CMakeLists.txt + conditional externalNativeBuild'"
echo "   git push"
