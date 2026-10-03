#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p app/src/main/cpp
mkdir -p app/src/main/java/com/awlqy/terminal/core

# ═════════════════════════════════════════════════════════════
# 1. CMakeLists.txt — بسيط، مضمون
# ═════════════════════════════════════════════════════════════
cat > app/src/main/cpp/CMakeLists.txt <<'CM_EOF'
cmake_minimum_required(VERSION 3.22.1)
project(awlqy_pty C)
set(CMAKE_C_STANDARD 17)
add_library(awlqy_pty SHARED pty_bridge.c)
find_library(log-lib log)
target_link_libraries(awlqy_pty ${log-lib})
CM_EOF

# ═════════════════════════════════════════════════════════════
# 2. pty_bridge.c
# ═════════════════════════════════════════════════════════════
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
    if (pts < 0) { LOGE("open %s: %s", slave_path, strerror(errno)); close(ptm); return -1; }
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
        if (envp) for (int i = 0; i < env_n; i++)
            if (envp[i] && strchr(envp[i], '=')) putenv(envp[i]);
        execvp(argv[0], argv);
        _exit(127);
    }

    close(pts);
    int flags = fcntl(ptm, F_GETFL, 0);
    fcntl(ptm, F_SETFL, flags | O_NONBLOCK);
    if (cmd) (*env)->ReleaseStringUTFChars(env, jCmd, cmd);
    if (cwd) (*env)->ReleaseStringUTFChars(env, jCwd, cwd);

    jint pair[2]; pair[0] = ptm; pair[1] = (jint)pid;
    jintArray out = (*env)->NewIntArray(env, 2);
    (*env)->SetIntArrayRegion(env, out, 0, 2, pair);
    return out;
}

JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_read(JNIEnv *env, jclass c, jint fd, jbyteArray buf, jint off, jint len) {
    if (fd < 0 || len <= 0) return -1;
    jbyte *b = (*env)->GetByteArrayElements(env, buf, NULL);
    ssize_t n = read(fd, b + off, (size_t)len);
    int e = (n < 0) ? errno : 0;
    if (n > 0) { (*env)->ReleaseByteArrayElements(env, buf, b, 0); return (jint)n; }
    (*env)->ReleaseByteArrayElements(env, buf, b, JNI_ABORT);
    if (e == EAGAIN || e == EWOULDBLOCK) return 0;
    return -1;
}

JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_write(JNIEnv *env, jclass c, jint fd, jbyteArray buf, jint off, jint len) {
    if (fd < 0 || len <= 0) return -1;
    jbyte *b = (*env)->GetByteArrayElements(env, buf, NULL);
    ssize_t t = 0;
    while (t < len) {
        ssize_t n = write(fd, b + off + t, (size_t)(len - t));
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) { usleep(500); continue; }
            break;
        }
        t += n;
    }
    (*env)->ReleaseByteArrayElements(env, buf, b, JNI_ABORT);
    return (jint)t;
}

JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_resize(JNIEnv *e, jclass c, jint fd, jint r, jint co) {
    if (fd < 0) return;
    struct winsize ws; memset(&ws, 0, sizeof(ws));
    ws.ws_row = (unsigned short)r; ws.ws_col = (unsigned short)co;
    ioctl(fd, TIOCSWINSZ, &ws);
}

JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_close(JNIEnv *e, jclass c, jint fd) {
    if (fd >= 0) close(fd);
}

JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_waitFor(JNIEnv *e, jclass c, jint pid) {
    if (pid <= 0) return -1;
    int s = 0;
    while (waitpid((pid_t)pid, &s, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(s))   return WEXITSTATUS(s);
    if (WIFSIGNALED(s)) return 128 + WTERMSIG(s);
    return s;
}

JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_signal(JNIEnv *e, jclass c, jint pid, jint s) {
    if (pid > 0) kill((pid_t)pid, s);
}

JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_signalGroup(JNIEnv *e, jclass c, jint pid, jint s) {
    if (pid > 0) kill(-(pid_t)pid, s);
}
C_EOF

# ═════════════════════════════════════════════════════════════
# 3. PtyBridge.kt — مع حماية loadLibrary
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/core/PtyBridge.kt <<'KT_EOF'
package com.awlqy.terminal.core

import android.util.Log

object PtyBridge {

    @Volatile var nativeAvailable: Boolean = false
        private set

    init {
        nativeAvailable = try {
            System.loadLibrary("awlqy_pty")
            Log.i("awlqy", "libawlqy_pty.so loaded")
            true
        } catch (t: Throwable) {
            Log.w("awlqy", "native PTY unavailable, falling back to ProcessBuilder: ${t.message}")
            false
        }
    }

    external fun createSubprocess(
        cmd: String, cwd: String?,
        args: Array<String>?, env: Array<String>?,
        rows: Int, cols: Int
    ): IntArray?

    external fun read(fd: Int, buf: ByteArray, off: Int, len: Int): Int
    external fun write(fd: Int, buf: ByteArray, off: Int, len: Int): Int
    external fun resize(fd: Int, rows: Int, cols: Int)
    external fun close(fd: Int)
    external fun waitFor(pid: Int): Int
    external fun signal(pid: Int, sig: Int)
    external fun signalGroup(pid: Int, sig: Int)
}
KT_EOF

# ═════════════════════════════════════════════════════════════
# 4. TerminalSession.kt — مع fallback
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/core/TerminalSession.kt <<'KT_EOF'
package com.awlqy.terminal.core

import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter

class TerminalSession(
    val name: String,
    private val shellPath: String = "/system/bin/sh",
    val cwd: File,
    var rows: Int = 24,
    var cols: Int = 80
) {

    interface Listener {
        fun onOutput(session: TerminalSession, data: String)
        fun onExited(session: TerminalSession, exitCode: Int)
    }

    @Volatile var listener: Listener? = null
    @Volatile var usingPty: Boolean = false
        private set

    @Volatile private var fd: Int = -1
    @Volatile private var pid: Int = -1
    @Volatile private var proc: Process? = null
    @Volatile var running: Boolean = false
        private set

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var readJob: Job? = null
    private val main = Handler(Looper.getMainLooper())

    private val env: Array<String> = arrayOf(
        "HOME=${cwd.absolutePath}",
        "TERM=xterm-256color",
        "COLORTERM=truecolor",
        "LANG=en_US.UTF-8",
        "PATH=/data/data/com.awlqy.terminal/files/usr/bin:/system/bin:/system/xbin"
    )

    fun start() {
        if (running) return
        if (!cwd.exists()) cwd.mkdirs()
        if (PtyBridge.nativeAvailable) startPty() else startFallback()
    }

    private fun startPty() {
        val pair = PtyBridge.createSubprocess(
            cmd = shellPath, cwd = cwd.absolutePath,
            args = arrayOf(), env = env, rows = rows, cols = cols
        )
        if (pair == null || pair.size < 2) { startFallback(); return }
        fd = pair[0]; pid = pair[1]; running = true; usingPty = true
        readJob = scope.launch { readPtyLoop() }
    }

    private fun startFallback() {
        try {
            val pb = ProcessBuilder(shellPath)
            pb.directory(cwd)
            pb.redirectErrorStream(true)
            pb.environment()["HOME"] = cwd.absolutePath
            pb.environment()["PATH"] = "/system/bin:/system/xbin"
            val p = pb.start()
            proc = p; pid = -1; running = true; usingPty = false
            readJob = scope.launch { readFallbackLoop(p) }
        } catch (e: Exception) {
            notifyOutput("[awlqy] تعذّر تشغيل الطرفية: ${e.message}\n")
        }
    }

    private suspend fun readPtyLoop() {
        val buf = ByteArray(8192)
        while (running) {
            val n = PtyBridge.read(fd, buf, 0, buf.size)
            if (n > 0) {
                val chunk = String(buf, 0, n, Charsets.UTF_8)
                main.post { listener?.onOutput(this, chunk) }
            } else if (n == 0) delay(16) else break
        }
        val code = if (pid > 0) PtyBridge.waitFor(pid) else -1
        running = false
        main.post { listener?.onExited(this, code) }
    }

    private suspend fun readFallbackLoop(p: Process) {
        try {
            BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                var line = r.readLine()
                while (running && line != null) {
                    val out = line + "\n"
                    main.post { listener?.onOutput(this, out) }
                    line = r.readLine()
                }
            }
        } catch (_: Exception) {}
        val code = try { p.waitFor() } catch (_: Exception) { -1 }
        running = false
        main.post { listener?.onExited(this, code) }
    }

    fun writeBytes(data: ByteArray) {
        if (!running) return
        val localFd = fd
        val localProc = proc
        scope.launch {
            try {
                if (usingPty && localFd >= 0) PtyBridge.write(localFd, data, 0, data.size)
                else if (localProc != null) {
                    OutputStreamWriter(localProc.outputStream, Charsets.UTF_8).apply {
                        write(String(data, Charsets.UTF_8)); flush()
                    }
                }
            } catch (_: Exception) {}
        }
    }

    fun writeText(s: String) = writeBytes(s.toByteArray(Charsets.UTF_8))
    fun writeCode(code: Int) = writeBytes(byteArrayOf(code.toByte()))

    fun resize(newRows: Int, newCols: Int) {
        rows = newRows; cols = newCols
        if (usingPty && fd >= 0) PtyBridge.resize(fd, newRows, newCols)
    }

    fun sendSignal(sig: Int) {
        if (usingPty && pid > 0) PtyBridge.signal(pid, sig)
        else try { proc?.destroy() } catch (_: Exception) {}
    }

    fun sendSignalGroup(sig: Int) {
        if (usingPty && pid > 0) PtyBridge.signalGroup(pid, sig)
        else try { proc?.destroy() } catch (_: Exception) {}
    }

    fun stop() {
        running = false
        try { sendSignalGroup(9) } catch (_: Exception) {}
        if (fd >= 0) PtyBridge.close(fd)
        try { proc?.destroy() } catch (_: Exception) {}
        scope.cancel()
        fd = -1; pid = -1; proc = null
    }

    private fun notifyOutput(msg: String) {
        main.post { listener?.onOutput(this, msg) }
    }
}
KT_EOF

# ═════════════════════════════════════════════════════════════
# 5. build.gradle.kts — externalNativeBuild غير مشروط
# ═════════════════════════════════════════════════════════════
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

        externalNativeBuild {
            cmake {
                cppFlags += "-O2"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
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
        jniLibs { useLegacyPackaging = true }
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

# ═════════════════════════════════════════════════════════════
# التحقق
# ═════════════════════════════════════════════════════════════
echo ""
echo "▶ [final-fix] الملفات:"
for f in \
    app/src/main/cpp/CMakeLists.txt \
    app/src/main/cpp/pty_bridge.c \
    app/src/main/java/com/awlqy/terminal/core/PtyBridge.kt \
    app/src/main/java/com/awlqy/terminal/core/TerminalSession.kt \
    app/build.gradle.kts
do
    if [ -f "$f" ]; then echo "  ✔ $(basename $f)"; else echo "  ✗ $f مفقود"; fi
done

echo ""
echo "▶ [final-fix] PtyBridge.nativeAvailable موجود:"
grep -n "nativeAvailable" app/src/main/java/com/awlqy/terminal/core/PtyBridge.kt | head -2

echo ""
echo "▶ [final-fix] TerminalSession fallback موجود:"
grep -n "startFallback\|startPty" app/src/main/java/com/awlqy/terminal/core/TerminalSession.kt | head -4

echo ""
echo "▶ [final-fix] build.gradle.kts — externalNativeBuild غير مشروط:"
grep -n "externalNativeBuild" app/build.gradle.kts

echo ""
echo "✔ [final-fix] انتهى."
echo ""
echo "   git add -A"
echo "   git commit -m 'fix: PTY fallback + unconditional CMake build'"
echo "   git push"
