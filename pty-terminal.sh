#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · pty-terminal.sh — True PTY + Modifier Keys
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p app/src/main/cpp
mkdir -p app/src/main/java/com/awlqy/terminal/core
mkdir -p app/src/main/res/layout
mkdir -p .github/workflows

# ═════════════════════════════════════════════════════════════
# 1. CMakeLists.txt — بسيط، بدون FetchContent
# ═════════════════════════════════════════════════════════════
cat > app/src/main/cpp/CMakeLists.txt <<'CM_EOF'
cmake_minimum_required(VERSION 3.22.1)
project(awlqy_pty C)

add_library(awlqy_pty SHARED pty_bridge.c)
find_library(log-lib log)
target_link_libraries(awlqy_pty ${log-lib})
CM_EOF

# ═════════════════════════════════════════════════════════════
# 2. pty_bridge.c — forkpty + read/write/resize/signal
# ═════════════════════════════════════════════════════════════
cat > app/src/main/cpp/pty_bridge.c <<'C_EOF'
#include <jni.h>
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
#include <android/log.h>

#define LOG_TAG "awlqy-pty"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

JNIEXPORT jintArray JNICALL
Java_com_awlqy_terminal_core_PtyBridge_createSubprocess(
        JNIEnv *env, jclass clazz,
        jstring jCmd, jstring jCwd,
        jobjectArray jArgs, jobjectArray jEnv,
        jint rows, jint cols) {

    const char *cmd = (*env)->GetStringUTFChars(env, jCmd, NULL);
    const char *cwd = jCwd ? (*env)->GetStringUTFChars(env, jCwd, NULL) : NULL;

    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = (unsigned short)(rows > 0 ? rows : 24);
    ws.ws_col = (unsigned short)(cols > 0 ? cols : 80);

    int ptm = -1;
    pid_t pid = forkpty(&ptm, NULL, NULL, &ws);
    if (pid < 0) {
        LOGE("forkpty: %s", strerror(errno));
        if (cmd) (*env)->ReleaseStringUTFChars(env, jCmd, cmd);
        if (cwd) (*env)->ReleaseStringUTFChars(env, jCwd, cwd);
        return NULL;
    }

    if (pid == 0) {
        /* ─── CHILD ─── */
        if (cwd && *cwd) {
            if (chdir(cwd) != 0) chdir("/");
        }

        setenv("TERM",      "xterm-256color", 1);
        setenv("COLORTERM", "truecolor",      1);
        setenv("LANG",      "en_US.UTF-8",    1);
        setenv("LC_ALL",    "en_US.UTF-8",    1);

        if (jEnv) {
            jsize n = (*env)->GetArrayLength(env, jEnv);
            for (jsize i = 0; i < n; i++) {
                jstring js = (jstring)(*env)->GetObjectArrayElement(env, jEnv, i);
                if (!js) continue;
                const char *cs = (*env)->GetStringUTFChars(env, js, NULL);
                if (cs) {
                    putenv(strdup(cs));
                    (*env)->ReleaseStringUTFChars(env, js, cs);
                }
                (*env)->DeleteLocalRef(env, js);
            }
        }

        int argc = 1;
        if (jArgs) argc = (int)(*env)->GetArrayLength(env, jArgs) + 1;
        char **argv = (char **) calloc((size_t)argc + 1, sizeof(char *));
        if (!argv) _exit(127);
        argv[0] = strdup(cmd);
        if (jArgs) {
            jsize n = (*env)->GetArrayLength(env, jArgs);
            for (jsize i = 0; i < n; i++) {
                jstring js = (jstring)(*env)->GetObjectArrayElement(env, jArgs, i);
                if (!js) { argv[i + 1] = strdup(""); continue; }
                const char *cs = (*env)->GetStringUTFChars(env, js, NULL);
                argv[i + 1] = strdup(cs ? cs : "");
                if (cs) (*env)->ReleaseStringUTFChars(env, js, cs);
                (*env)->DeleteLocalRef(env, js);
            }
        }
        execvp(cmd, argv);
        _exit(127);
    }

    /* ─── PARENT ─── */
    if (cmd) (*env)->ReleaseStringUTFChars(env, jCmd, cmd);
    if (cwd) (*env)->ReleaseStringUTFChars(env, jCwd, cwd);

    int flags = fcntl(ptm, F_GETFL, 0);
    fcntl(ptm, F_SETFL, flags | O_NONBLOCK);

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
    if (n > 0) {
        (*env)->ReleaseByteArrayElements(env, buf, b, 0);
        return (jint)n;
    }
    (*env)->ReleaseByteArrayElements(env, buf, b, JNI_ABORT);
    if (err == EAGAIN || err == EWOULDBLOCK) return 0;
    if (err == EIO) return -1;
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
Java_com_awlqy_terminal_core_PtyBridge_close(
        JNIEnv *env, jclass clazz, jint fd) {
    if (fd >= 0) close(fd);
}

JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_waitFor(
        JNIEnv *env, jclass clazz, jint pid) {
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

# ═════════════════════════════════════════════════════════════
# 3. PtyBridge.kt — JNI declarations
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/core/PtyBridge.kt <<'KT_PTY'
package com.awlqy.terminal.core

object PtyBridge {

    init { System.loadLibrary("awlqy_pty") }

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
KT_PTY

# ═════════════════════════════════════════════════════════════
# 4. TerminalSession.kt — PTY session wrapper + read loop
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/core/TerminalSession.kt <<'KT_SESS'
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
import java.io.File

class TerminalSession(
    val name: String,
    private val shellPath: String = "/system/bin/sh",
    val cwd: File,
    rows: Int = 24,
    cols: Int = 80
) {

    interface Listener {
        fun onOutput(session: TerminalSession, data: String)
        fun onExited(session: TerminalSession, exitCode: Int)
    }

    @Volatile var listener: Listener? = null

    @Volatile private var fd: Int = -1
    @Volatile private var pid: Int = -1
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
        "LC_ALL=en_US.UTF-8",
        "PATH=/data/data/com.awlqy.terminal/files/usr/bin:/system/bin:/system/xbin"
    )

    fun start() {
        if (running) return
        if (!cwd.exists()) cwd.mkdirs()
        val args = arrayOf<String>()  // sh without -c, we just open interactive shell
        val pair = PtyBridge.createSubprocess(
            cmd = shellPath,
            cwd = cwd.absolutePath,
            args = args,
            env = env,
            rows = rows,
            cols = cols
        )
        if (pair == null || pair.size < 2) {
            notifyOutput("[awlqy] فشل فتح PTY.\n")
            return
        }
        fd = pair[0]
        pid = pair[1]
        running = true
        readJob = scope.launch { readLoop() }
    }

    private suspend fun readLoop() {
        val buf = ByteArray(8192)
        while (running) {
            val n = PtyBridge.read(fd, buf, 0, buf.size)
            if (n > 0) {
                val chunk = String(buf, 0, n, Charsets.UTF_8)
                main.post { listener?.onOutput(this, chunk) }
            } else if (n == 0) {
                delay(16)
            } else {
                break
            }
        }
        val code = if (pid > 0) PtyBridge.waitFor(pid) else -1
        running = false
        main.post { listener?.onExited(this, code) }
    }

    fun writeBytes(data: ByteArray) {
        if (!running || fd < 0) return
        val localFd = fd
        scope.launch { PtyBridge.write(localFd, data, 0, data.size) }
    }

    fun writeText(s: String) = writeBytes(s.toByteArray(Charsets.UTF_8))

    fun writeCode(code: Int) {
        writeBytes(byteArrayOf(code.toByte()))
    }

    fun resize(rows: Int, cols: Int) {
        if (fd >= 0) PtyBridge.resize(fd, rows, cols)
    }

    fun sendSignal(sig: Int) {
        if (pid > 0) PtyBridge.signal(pid, sig)
    }

    fun sendSignalGroup(sig: Int) {
        if (pid > 0) PtyBridge.signalGroup(pid, sig)
    }

    fun stop() {
        running = false
        try { sendSignalGroup(9) } catch (_: Exception) {}
        if (fd >= 0) PtyBridge.close(fd)
        scope.cancel()
        fd = -1
        pid = -1
    }

    private fun notifyOutput(msg: String) {
        main.post { listener?.onOutput(this, msg) }
    }
}
KT_SESS

# ═════════════════════════════════════════════════════════════
# 5. TerminalBuffer.kt — معالج ANSI مبسط + Spannable
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/core/TerminalBuffer.kt <<'KT_BUF'
package com.awlqy.terminal.core

import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import java.util.ArrayDeque

/**
 * معالج ANSI بسيط:
 * - SGR (ألوان) → Spannable
 * - \r → عودة إلى بداية السطر
 * - \n → سطر جديد
 * - \b → حذف حرف
 * - ESC[2J → مسح الشاشة
 * - ESC[H → home
 * - ESC[K → مسح السطر
 * - باقي ESC → تُحذف
 */
class TerminalBuffer(private val maxChars: Int = 200_000) {

    class Style(var fg: Int = DEFAULT_FG) {
        fun copy(): Style = Style(fg)
        companion object { const val DEFAULT_FG = 0xFFE2E8F0.toInt() }
    }

    private val sb = SpannableStringBuilder()
    private var curStyle = Style()
    private var escapeBuf = StringBuilder()
    private var inEscape = false
    private var inCsi = false
    private var csiBuf = StringBuilder()

    private val ansiColors = intArrayOf(
        0xFF000000.toInt(), 0xFFEF4444.toInt(), 0xFF4ADE80.toInt(), 0xFFFACC15.toInt(),
        0xFF3B82F6.toInt(), 0xFFA855F7.toInt(), 0xFF22D3EE.toInt(), 0xFFE2E8F0.toInt(),
        0xFF64748B.toInt(), 0xFFF87171.toInt(), 0xFF86EFAC.toInt(), 0xFFFDE047.toInt(),
        0xFF60A5FA.toInt(), 0xFFC084FC.toInt(), 0xFF67E8F9.toInt(), 0xFFFFFFFF.toInt()
    )

    fun append(text: String) {
        var i = 0
        val n = text.length
        while (i < n) {
            val c = text[i]
            if (inEscape) {
                handleEscape(c)
                i++
                continue
            }
            when (c) {
                '\u001B' -> { inEscape = true; escapeBuf.setLength(0); i++ }
                '\n'      -> { sb.append('\n'); i++ }
                '\r'      -> { returnToLineStart(); i++ }
                '\b'      -> { backspace(); i++ }
                '\t'      -> { sb.append("        ".take(8 - (currentCol() % 8))); i++ }
                '\u0007'  -> { i++ } // bell - ignore
                else      -> { appendChar(c); i++ }
            }
        }
        trim()
    }

    private fun handleEscape(c: Char) {
        if (!inCsi && c == '[') { inCsi = true; csiBuf.setLength(0); return }
        if (inCsi) {
            if (c in '0'..'9' || c == ';' || c == '?') { csiBuf.append(c); return }
            // final char
            applyCsi(csiBuf.toString(), c)
            inCsi = false
            inEscape = false
            csiBuf.setLength(0)
            return
        }
        // Two-char escape (e.g., ESC c, ESC 7, ESC 8)
        // We simply ignore.
        inEscape = false
    }

    private fun applyCsi(params: String, final: Char) {
        when (final) {
            'm' -> applySgr(params)
            'J' -> {
                val p = params.toIntOrNull() ?: 0
                if (p == 2 || p == 3) sb.clear()
            }
            'H', 'f' -> { /* home - ignore for now */ }
            'K' -> {
                val p = params.toIntOrNull() ?: 0
                if (p == 0) clearToEndOfLine() else if (p == 2) clearLine()
            }
            'A' -> { /* cursor up */ }
            'B' -> { /* cursor down */ }
            'C' -> { /* cursor right */ }
            'D' -> { /* cursor left */ }
            else -> { /* ignore */ }
        }
    }

    private fun applySgr(params: String) {
        val parts = params.split(';').mapNotNull { it.toIntOrNull() }
        if (parts.isEmpty()) { curStyle = Style(); return }
        var i = 0
        while (i < parts.size) {
            val p = parts[i]
            when {
                p == 0  -> curStyle = Style()
                p in 30..37 -> curStyle.fg = ansiColors[p - 30]
                p in 90..97 -> curStyle.fg = ansiColors[p - 90 + 8]
                p == 39 -> curStyle.fg = Style.DEFAULT_FG
                p == 1  -> { /* bold - keep color */ }
                p == 22 -> { /* normal - keep color */ }
                p == 38 && i + 4 < parts.size && parts[i + 1] == 5 -> {
                    val idx = parts[i + 2]
                    if (idx in 0..15) curStyle.fg = ansiColors[idx]
                    i += 2
                }
            }
            i++
        }
    }

    private fun appendChar(c: Char) {
        val start = sb.length
        sb.append(c)
        sb.setSpan(
            ForegroundColorSpan(curStyle.fg),
            start, sb.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }

    private fun currentCol(): Int {
        val nl = sb.indexOf("\n", sb.length - 1)
        val lineStart = if (nl < 0) 0 else nl + 1
        return sb.length - lineStart
    }

    private fun returnToLineStart() {
        val nl = sb.lastIndexOf("\n")
        val lineStart = nl + 1
        if (lineStart < sb.length) sb.delete(lineStart, sb.length)
    }

    private fun backspace() {
        if (sb.isEmpty()) return
        sb.delete(sb.length - 1, sb.length)
    }

    private fun clearToEndOfLine() {
        val nl = sb.indexOf("\n", sb.length - 1)
        if (nl < 0) sb.delete(sb.length, sb.length)
    }

    private fun clearLine() {
        val nl = sb.lastIndexOf("\n")
        val start = nl + 1
        if (start < sb.length) sb.delete(start, sb.length)
    }

    private fun trim() {
        if (sb.length <= maxChars) return
        val cut = sb.length - maxChars
        val nl = sb.indexOf("\n", cut)
        val drop = if (nl > 0) nl + 1 else cut
        sb.delete(0, drop)
    }

    fun snapshot(): CharSequence = sb
    fun clear() { sb.clear(); curStyle = Style() }
}
KT_BUF

# ═════════════════════════════════════════════════════════════
# 6. build.gradle.kts — مع NDK
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

        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c17 -O2"
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
# 7. activity_main.xml — 3 صفوف accessory bar
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/layout/activity_main.xml <<'XML_MAIN'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000"
    android:fitsSystemWindows="true">

    <TextView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:alpha="0.05"
        android:fontFamily="monospace"
        android:gravity="center"
        android:letterSpacing="0.25"
        android:shadowColor="#22D3EE"
        android:shadowDx="0"
        android:shadowDy="0"
        android:shadowRadius="30"
        android:text="Q · W"
        android:textColor="#22D3EE"
        android:textSize="120sp"
        android:textStyle="bold"/>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="vertical">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="36dp"
            android:background="#0A0E14"
            android:gravity="center_vertical"
            android:orientation="horizontal">

            <HorizontalScrollView
                android:layout_width="0dp"
                android:layout_height="match_parent"
                android:layout_weight="1"
                android:scrollbars="none">

                <LinearLayout
                    android:id="@+id/sessionTabs"
                    android:layout_width="wrap_content"
                    android:layout_height="match_parent"
                    android:gravity="center_vertical"
                    android:orientation="horizontal"
                    android:paddingStart="6dp"
                    android:paddingEnd="6dp"/>
            </HorizontalScrollView>

            <TextView
                android:id="@+id/gearBtn"
                android:layout_width="40dp"
                android:layout_height="match_parent"
                android:gravity="center"
                android:text="⚙"
                android:textColor="#22D3EE"
                android:textSize="18sp"/>
        </LinearLayout>

        <ScrollView
            android:id="@+id/consoleScroll"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:background="#000000"
            android:fillViewport="true"
            android:padding="6dp"
            android:scrollbars="vertical">

            <TextView
                android:id="@+id/consoleText"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:fontFamily="monospace"
                android:text=""
                android:textColor="#E2E8F0"
                android:textIsSelectable="true"
                android:textSize="12sp"/>
        </ScrollView>

        <LinearLayout
            android:id="@+id/accessoryContainer"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="#0A0E14"
            android:orientation="vertical"
            android:paddingTop="2dp"
            android:paddingBottom="2dp"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="#0A0E14"
            android:orientation="horizontal"
            android:padding="4dp">

            <EditText
                android:id="@+id/inputEdit"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:background="#1E293B"
                android:fontFamily="monospace"
                android:hint="soft keyboard"
                android:imeOptions="flagNoEnterAction|flagNoExtractUi"
                android:inputType="text|textNoSuggestions|textVisiblePassword|textMultiLine"
                android:maxLines="4"
                android:minLines="1"
                android:padding="8dp"
                android:textColor="#E2E8F0"
                android:textColorHint="#64748B"
                android:textSize="12sp"/>

            <Button
                android:id="@+id/sendButton"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_marginStart="4dp"
                android:backgroundTint="#22D3EE"
                android:fontFamily="monospace"
                android:minWidth="0dp"
                android:paddingStart="10dp"
                android:paddingEnd="10dp"
                android:text="↵"
                android:textColor="#000000"
                android:textSize="16sp"/>
        </LinearLayout>
    </LinearLayout>
</FrameLayout>
XML_MAIN

# ═════════════════════════════════════════════════════════════
# 8. MainActivity.kt — PTY + Modifier Keys
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/MainActivity.kt <<'KOT_MAIN'
package com.awlqy.terminal

import android.content.Context
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.awlqy.terminal.core.TerminalBuffer
import com.awlqy.terminal.core.TerminalSession
import com.awlqy.terminal.databinding.ActivityMainBinding
import com.google.android.material.button.MaterialButton
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import java.io.File

class MainActivity : AppCompatActivity(), TerminalSession.Listener {

    private lateinit var binding: ActivityMainBinding

    private val sessions = ArrayList<TerminalSession>()
    private val buffers = HashMap<String, TerminalBuffer>()
    private var activeIdx = 0

    // Modifier state
    private var ctrlLatched = false
    private var altLatched = false

    // Widgets
    private lateinit var ctrlButton: MaterialButton
    private lateinit var altButton: MaterialButton
    private var pendingInput = StringBuilder()
    private var suppressInput = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.consoleText.typeface = Typeface.MONOSPACE
        binding.consoleText.textSize = 12f

        binding.gearBtn.setOnClickListener { showSettings() }

        buildAccessoryBar()
        wireSoftKeyboard()
        newSession()
    }

    override fun onDestroy() {
        for (s in sessions) s.stop()
        super.onDestroy()
    }

    // ─── Session management ──────────────────────────────

    private fun newSession() {
        val home = File(filesDir, "home").apply { mkdirs() }
        val name = "session-${sessions.size + 1}"
        val s = TerminalSession(
            name = name,
            shellPath = "/system/bin/sh",
            cwd = home,
            rows = 24,
            cols = 80
        )
        s.listener = this
        sessions.add(s)
        buffers[s.name] = TerminalBuffer()
        activeIdx = sessions.size - 1
        s.start()
        renderTabs()
        renderConsole()
    }

    private fun closeCurrent() {
        if (sessions.size <= 1) {
            toast("لا يمكن إغلاق الجلسة الأخيرة")
            return
        }
        val idx = activeIdx
        val s = sessions[idx]
        s.stop()
        sessions.removeAt(idx)
        buffers.remove(s.name)
        if (activeIdx >= sessions.size) activeIdx = sessions.size - 1
        renderTabs()
        renderConsole()
    }

    private fun activeSession(): TerminalSession? = sessions.getOrNull(activeIdx)
    private fun activeBuffer(): TerminalBuffer? = activeSession()?.let { buffers[it.name] }

    private fun renderTabs() {
        val bar = binding.sessionTabs
        bar.removeAllViews()
        for (i in sessions.indices) {
            val s = sessions[i]
            val tv = TextView(this).apply {
                text = "[${i + 1}]"
                typeface = Typeface.MONOSPACE
                textSize = 12f
                gravity = Gravity.CENTER
                setPadding(28, 12, 28, 12)
                setTextColor(if (i == activeIdx) 0xFF22D3EE.toInt() else 0xFF64748B.toInt())
                setBackgroundColor(if (i == activeIdx) 0xFF1E293B.toInt() else 0xFF0A0E14.toInt())
                setOnClickListener {
                    activeIdx = i
                    renderTabs()
                    renderConsole()
                    focusTerminal()
                }
                setOnLongClickListener {
                    if (i == activeIdx) closeCurrent()
                    else {
                        MaterialAlertDialogBuilder(this@MainActivity)
                            .setTitle("إغلاق الجلسة")
                            .setMessage("إغلاق ${s.name}؟")
                            .setPositiveButton("إغلاق") { _, _ ->
                                s.stop()
                                sessions.removeAt(i)
                                buffers.remove(s.name)
                                if (activeIdx >= sessions.size) activeIdx = sessions.size - 1
                                renderTabs()
                                renderConsole()
                            }
                            .setNegativeButton("إلغاء", null)
                            .show()
                    }
                    true
                }
            }
            bar.addView(tv)
        }
        val add = TextView(this).apply {
            text = "[+]"
            typeface = Typeface.MONOSPACE
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(28, 12, 28, 12)
            setTextColor(0xFF4ADE80.toInt())
            setOnClickListener { newSession() }
        }
        bar.addView(add)
    }

    private fun renderConsole() {
        val b = activeBuffer() ?: return
        binding.consoleText.text = b.snapshot()
        binding.consoleScroll.post { binding.consoleScroll.fullScroll(View.FOCUS_DOWN) }
    }

    // ─── TerminalSession.Listener ───────────────────────

    override fun onOutput(session: TerminalSession, data: String) {
        if (buffers[session.name] == null) buffers[session.name] = TerminalBuffer()
        buffers[session.name]!!.append(data)
        if (sessions.getOrNull(activeIdx) === session) {
            binding.consoleText.text = buffers[session.name]!!.snapshot()
            binding.consoleScroll.post { binding.consoleScroll.fullScroll(View.FOCUS_DOWN) }
        }
    }

    override fun onExited(session: TerminalSession, exitCode: Int) {
        onOutput(session, "\n[session exited: $exitCode]\n")
    }

    // ─── Accessory bar (3 rows) ──────────────────────────

    private fun buildAccessoryBar() {
        val container = binding.accessoryContainer

        // Row 1: KEYBOARD | NEW SESSION
        val row1 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        row1.addView(makeKey("KEYBOARD", 0xFF1E293B.toInt()) { toggleSoftKeyboard() })
        row1.addView(makeKey("NEW SESSION", 0xFF4ADE80.toInt()) { newSession() })
        row1.addView(makeKey("CLOSE", 0xFFEF4444.toInt()) { closeCurrent() })
        container.addView(row1)

        // Row 2: ESC | ≡ | ↕ | HOME | ↑ | END | PGUP
        val row2 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        row2.addView(makeKey("ESC") { sendBytes(byteArrayOf(0x1B)) })
        row2.addView(makeKey("TAB") { sendBytes(byteArrayOf(0x09)) })
        row2.addView(makeKey("CTRL", 0xFF1E293B.toInt()) { toggleCtrl() })
        row2.addView(makeKey("ALT",  0xFF1E293B.toInt()) { toggleAlt() })
        row2.addView(makeKey("HOME") { sendSeq("\u001B[H") })
        row2.addView(makeKey("↑") { sendSeq("\u001B[A") })
        row2.addView(makeKey("END") { sendSeq("\u001B[F") })
        row2.addView(makeKey("PGUP") { sendSeq("\u001B[5~") })
        container.addView(row2)

        // Row 3: ↹ | | | ← | ↓ | → | PGDN | MENU
        val row3 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        row3.addView(makeKey("|") { sendSeq("|") })
        row3.addView(makeKey("/") { sendSeq("/") })
        row3.addView(makeKey("-") { sendSeq("-") })
        row3.addView(makeKey("←") { sendSeq("\u001B[D") })
        row3.addView(makeKey("↓") { sendSeq("\u001B[B") })
        row3.addView(makeKey("→") { sendSeq("\u001B[C") })
        row3.addView(makeKey("PGDN") { sendSeq("\u001B[6~") })
        container.addView(row3)
    }

    private fun makeKey(
        label: String,
        bg: Int = 0xFF1E293B.toInt(),
        action: () -> Unit
    ): MaterialButton {
        val density = resources.displayMetrics.density
        val lp = LinearLayout.LayoutParams(
            0,
            (38 * density).toInt(),
            1f
        ).apply { marginStart = (2 * density).toInt(); marginEnd = (2 * density).toInt() }

        val btn = MaterialButton(this).apply {
            text = label
            textSize = 11f
            typeface = Typeface.MONOSPACE
            minWidth = 0
            minHeight = 0
            insetTop = 0
            insetBottom = 0
            layoutParams = lp
            setTextColor(0xFFE2E8F0.toInt())
            setBackgroundColor(bg)
            setOnClickListener { action() }
        }
        return btn
    }

    private fun toggleCtrl() {
        ctrlLatched = !ctrlLatched
        if (ctrlLatched && altLatched) altLatched = false
        refreshModifierVisuals()
    }

    private fun toggleAlt() {
        altLatched = !altLatched
        if (altLatched && ctrlLatched) ctrlLatched = false
        refreshModifierVisuals()
    }

    private fun refreshModifierVisuals() {
        val container = binding.accessoryContainer
        val row2 = container.getChildAt(1) as? LinearLayout ?: return
        for (i in 0 until row2.childCount) {
            val v = row2.getChildAt(i) as? MaterialButton ?: continue
            when (v.text.toString()) {
                "CTRL" -> v.setBackgroundColor(
                    if (ctrlLatched) 0xFFEF4444.toInt() else 0xFF1E293B.toInt()
                )
                "ALT" -> v.setBackgroundColor(
                    if (altLatched) 0xFFFACC15.toInt() else 0xFF1E293B.toInt()
                )
            }
        }
    }

    // ─── Input routing ───────────────────────────────────

    private fun wireSoftKeyboard() {
        binding.inputEdit.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) {
                if (suppressInput) return
                val text = s?.toString() ?: return
                if (text.isEmpty()) return
                handleTypedText(text)
                suppressInput = true
                binding.inputEdit.setText("")
                suppressInput = false
            }
        })

        binding.inputEdit.setOnKeyListener { _, keyCode, event ->
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DEL, KeyEvent.KEYCODE_FORWARD_DEL -> {
                        sendBytes(byteArrayOf(0x7F)); true
                    }
                    KeyEvent.KEYCODE_ENTER -> {
                        sendBytes(byteArrayOf(0x0D)); true
                    }
                    KeyEvent.KEYCODE_TAB -> {
                        sendBytes(byteArrayOf(0x09)); true
                    }
                    KeyEvent.KEYCODE_ESCAPE -> {
                        sendBytes(byteArrayOf(0x1B)); true
                    }
                    else -> false
                }
            } else false
        }

        binding.sendButton.setOnClickListener {
            sendBytes(byteArrayOf(0x0D))
        }
    }

    private fun handleTypedText(text: String) {
        val s = activeSession() ?: return
        for (ch in text) {
            var byte = ch.code
            if (altLatched) {
                s.writeBytes(byteArrayOf(0x1B))
                altLatched = false
                refreshModifierVisuals()
            }
            if (ctrlLatched) {
                val code = if (byte in 'a'.code..'z'.code) byte - 0x60
                else if (byte in 'A'.code..'Z'.code) byte - 0x40
                else if (byte == ' '.code) 0
                else byte
                s.writeBytes(byteArrayOf(code.toByte()))
                ctrlLatched = false
                refreshModifierVisuals()
            } else {
                val bytes = ch.toString().toByteArray(Charsets.UTF_8)
                s.writeBytes(bytes)
            }
        }
    }

    private fun sendBytes(bytes: ByteArray) {
        val s = activeSession() ?: return
        var payload = bytes
        if (altLatched && bytes.isNotEmpty() && bytes[0] != 0x1B.toByte()) {
            payload = byteArrayOf(0x1B.toByte()) + bytes
            altLatched = false
            refreshModifierVisuals()
        }
        if (ctrlLatched && bytes.size == 1) {
            val b = bytes[0].toInt() and 0xFF
            val code = when {
                b in 0x61..0x7A -> b - 0x60
                b in 0x41..0x5A -> b - 0x40
                b == 0x20 -> 0
                b == 0x3F -> 0x7F
                else -> b
            }
            payload = byteArrayOf(code.toByte())
            ctrlLatched = false
            refreshModifierVisuals()
        }
        s.writeBytes(payload)
        focusTerminal()
    }

    private fun sendSeq(s: String) {
        val s = activeSession() ?: return
        s.writeText(s)
        focusTerminal()
    }

    private fun toggleSoftKeyboard() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (binding.inputEdit.hasFocus()) {
            imm.hideSoftInputFromWindow(binding.inputEdit.windowToken, 0)
        } else {
            focusTerminal()
        }
    }

    private fun focusTerminal() {
        binding.inputEdit.requestFocus()
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.showSoftInput(binding.inputEdit, InputMethodManager.SHOW_IMPLICIT)
    }

    // ─── Settings ────────────────────────────────────────

    private fun showSettings() {
        val msg = buildString {
            append("التطبيق: awlqy Terminal & IDE\n")
            append("الإصدار: 1.0.0\n")
            append("المطوّر: حسين الخلاقي\n")
            append("GitHub: alwaqyhsyn752-eng\n")
            append("المحرّك: Native PTY (forkpty)\n")
            append("API: ").append(Build.VERSION.SDK_INT).append("\n")
            append("الجلسات: ").append(sessions.size).append("\n")
            append("VIP: ").append(if (isVipUnlocked()) "مفعّل" else "مقفل")
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("الإعدادات")
            .setMessage(msg)
            .setPositiveButton("حسناً", null)
            .show()
    }

    private fun isVipUnlocked(): Boolean =
        getSharedPreferences("awlqy", Context.MODE_PRIVATE)
            .getBoolean("vip", false)

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
}
KOT_MAIN

# ═════════════════════════════════════════════════════════════
# 9. .github/workflows/build.yml — مع NDK
# ═════════════════════════════════════════════════════════════
cat > .github/workflows/build.yml <<'YML_EOF'
name: Build awlqy APK

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: awlqy-build-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    name: Build Debug APK
    runs-on: ubuntu-22.04
    timeout-minutes: 40

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 1

      - name: Setup JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Setup Android SDK
        uses: android-actions/setup-android@v3
        with:
          packages: >-
            platform-tools
            platforms;android-34
            build-tools;34.0.0
            ndk;26.1.10909125
            cmake;3.22.1

      - name: Export NDK env
        run: |
          echo "ANDROID_NDK_HOME=$ANDROID_SDK_ROOT/ndk/26.1.10909125" >> "$GITHUB_ENV"
          echo "ANDROID_NDK=$ANDROID_SDK_ROOT/ndk/26.1.10909125"      >> "$GITHUB_ENV"
          echo "ANDROID_NDK_ROOT=$ANDROID_SDK_ROOT/ndk/26.1.10909125"  >> "$GITHUB_ENV"

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v3
        with:
          gradle-version: '8.7'

      - name: Cache Gradle
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: awlqy-gradle-${{ runner.os }}-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: |
            awlqy-gradle-${{ runner.os }}-

      - name: Build Debug APK
        run: gradle :app:assembleDebug --no-daemon --stacktrace

      - name: Collect APK
        run: |
          set -e
          mkdir -p out
          APK="app/build/outputs/apk/debug/app-debug.apk"
          if [ ! -f "$APK" ]; then
            echo "APK not found at $APK"
            find app/build/outputs -type f -name "*.apk" || true
            exit 1
          fi
          cp "$APK" out/awlqy.apk
          sha256sum out/awlqy.apk > out/awlqy.apk.sha256
          ls -la out

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: awlqy-apk
          path: |
            out/awlqy.apk
            out/awlqy.apk.sha256
          if-no-files-found: error
          retention-days: 30
YML_EOF

# ═════════════════════════════════════════════════════════════
# 10. التحقق
# ═════════════════════════════════════════════════════════════
echo ""
echo "▶ [pty-terminal] الملفات:"
ls -la app/src/main/cpp/
echo ""
echo "▶ [pty-terminal] Kotlin core:"
ls -1 app/src/main/java/com/awlqy/terminal/core/*.kt
echo ""
echo "▶ [pty-terminal] MainActivity أول سطر:"
head -n 1 app/src/main/java/com/awlqy/terminal/MainActivity.kt
echo ""
echo "▶ [pty-terminal] CMake نظيف:"
cat app/src/main/cpp/CMakeLists.txt
echo ""
echo "✔ [pty-terminal] انتهى."
echo "   git add -A"
echo "   git commit -m 'true PTY engine + modifier keys + 3-row accessory bar'"
echo "   git push"
