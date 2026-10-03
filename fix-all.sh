#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · fix-all.sh — إصلاح شامل لكل الأخطاء المتبقية
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [fix-all] التأكد من وجود المجلدات"
mkdir -p app/src/main/cpp
mkdir -p app/src/main/java/com/awlqy/terminal/core
mkdir -p app/src/main/res/layout

# ═════════════════════════════════════════════════════════════
# 1. CMakeLists.txt — مضمون الوجود
# ═════════════════════════════════════════════════════════════
echo "▶ [fix-all] كتابة CMakeLists.txt"
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

# ═════════════════════════════════════════════════════════════
# 2. pty_bridge.c — نسخة POSIX نظيفة
# ═════════════════════════════════════════════════════════════
echo "▶ [fix-all] كتابة pty_bridge.c"
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

# ═════════════════════════════════════════════════════════════
# 3. PtyBridge.kt
# ═════════════════════════════════════════════════════════════
echo "▶ [fix-all] كتابة PtyBridge.kt"
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
# 4. TerminalSession.kt — مع rows/cols كـ var properties
# ═════════════════════════════════════════════════════════════
echo "▶ [fix-all] كتابة TerminalSession.kt (rows/cols = var)"
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
    var rows: Int = 24,
    var cols: Int = 80
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

        val args = arrayOf<String>()
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

    fun resize(newRows: Int, newCols: Int) {
        rows = newRows
        cols = newCols
        if (fd >= 0) PtyBridge.resize(fd, newRows, newCols)
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
# 5. TerminalBuffer.kt
# ═════════════════════════════════════════════════════════════
echo "▶ [fix-all] كتابة TerminalBuffer.kt"
cat > app/src/main/java/com/awlqy/terminal/core/TerminalBuffer.kt <<'KT_BUF'
package com.awlqy.terminal.core

import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan

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
            if (inEscape) { handleEscape(c); i++; continue }
            when (c) {
                '\u001B' -> { inEscape = true; escapeBuf.setLength(0); i++ }
                '\n'      -> { sb.append('\n'); i++ }
                '\r'      -> { returnToLineStart(); i++ }
                '\b'      -> { backspace(); i++ }
                '\t'      -> { sb.append("        ".take(8 - (currentCol() % 8))); i++ }
                '\u0007'  -> { i++ }
                else      -> { appendChar(c); i++ }
            }
        }
        trim()
    }

    private fun handleEscape(c: Char) {
        if (!inCsi && c == '[') { inCsi = true; csiBuf.setLength(0); return }
        if (inCsi) {
            if (c in '0'..'9' || c == ';' || c == '?') { csiBuf.append(c); return }
            applyCsi(csiBuf.toString(), c)
            inCsi = false; inEscape = false; csiBuf.setLength(0)
            return
        }
        inEscape = false
    }

    private fun applyCsi(params: String, final: Char) {
        when (final) {
            'm' -> applySgr(params)
            'J' -> { if ((params.toIntOrNull() ?: 0) in 2..3) sb.clear() }
            'K' -> {
                val p = params.toIntOrNull() ?: 0
                if (p == 0) clearToEndOfLine() else if (p == 2) clearLine()
            }
            else -> {}
        }
    }

    private fun applySgr(params: String) {
        val parts = params.split(';').mapNotNull { it.toIntOrNull() }
        if (parts.isEmpty()) { curStyle = Style(); return }
        var i = 0
        while (i < parts.size) {
            val p = parts[i]
            when {
                p == 0 -> curStyle = Style()
                p in 30..37 -> curStyle.fg = ansiColors[p - 30]
                p in 90..97 -> curStyle.fg = ansiColors[p - 90 + 8]
                p == 39 -> curStyle.fg = Style.DEFAULT_FG
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
        val nl = sb.lastIndexOf("\n")
        return sb.length - (nl + 1)
    }

    private fun returnToLineStart() {
        val nl = sb.lastIndexOf("\n")
        val lineStart = nl + 1
        if (lineStart < sb.length) sb.delete(lineStart, sb.length)
    }

    private fun backspace() {
        if (sb.isNotEmpty()) sb.delete(sb.length - 1, sb.length)
    }

    private fun clearToEndOfLine() {
        val nl = sb.lastIndexOf("\n")
        sb.delete(nl + 1, sb.length)
    }

    private fun clearLine() {
        val nl = sb.lastIndexOf("\n")
        if (nl + 1 < sb.length) sb.delete(nl + 1, sb.length)
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
# 6. MainActivity.kt — إصلاح sendSeq shadowing
# ═════════════════════════════════════════════════════════════
echo "▶ [fix-all] كتابة MainActivity.kt (sendSeq بدون shadowing)"
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

    private var ctrlLatched = false
    private var altLatched = false
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
        val s = TerminalSession(
            name = "session-${sessions.size + 1}",
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
        if (sessions.size <= 1) { toast("لا يمكن إغلاق الجلسة الأخيرة"); return }
        val s = sessions[activeIdx]
        s.stop()
        sessions.removeAt(activeIdx)
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

    // ─── Accessory bar ──────────────────────────────────

    private fun buildAccessoryBar() {
        val container = binding.accessoryContainer

        val row1 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        row1.addView(makeKey("KEYBOARD", 0xFF1E293B.toInt()) { toggleSoftKeyboard() })
        row1.addView(makeKey("NEW", 0xFF4ADE80.toInt()) { newSession() })
        row1.addView(makeKey("CLOSE", 0xFFEF4444.toInt()) { closeCurrent() })
        container.addView(row1)

        val row2 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        row2.addView(makeKey("ESC")  { sendBytes(byteArrayOf(0x1B)) })
        row2.addView(makeKey("TAB")  { sendBytes(byteArrayOf(0x09)) })
        row2.addView(makeKey("CTRL", 0xFF1E293B.toInt()) { toggleCtrl() })
        row2.addView(makeKey("ALT",  0xFF1E293B.toInt()) { toggleAlt() })
        row2.addView(makeKey("HOME") { sendSeq("\u001B[H") })
        row2.addView(makeKey("UP")   { sendSeq("\u001B[A") })
        row2.addView(makeKey("END")  { sendSeq("\u001B[F") })
        row2.addView(makeKey("PGUP") { sendSeq("\u001B[5~") })
        container.addView(row2)

        val row3 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        row3.addView(makeKey("|")    { sendSeq("|") })
        row3.addView(makeKey("/")    { sendSeq("/") })
        row3.addView(makeKey("-")    { sendSeq("-") })
        row3.addView(makeKey("LEFT") { sendSeq("\u001B[D") })
        row3.addView(makeKey("DOWN") { sendSeq("\u001B[B") })
        row3.addView(makeKey("RGHT") { sendSeq("\u001B[C") })
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
            0, (38 * density).toInt(), 1f
        ).apply {
            marginStart = (2 * density).toInt()
            marginEnd = (2 * density).toInt()
        }
        return MaterialButton(this).apply {
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
    }

    private fun toggleCtrl() {
        ctrlLatched = !ctrlLatched
        if (ctrlLatched) altLatched = false
        refreshModifierVisuals()
    }

    private fun toggleAlt() {
        altLatched = !altLatched
        if (altLatched) ctrlLatched = false
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
                    KeyEvent.KEYCODE_ENTER -> { sendBytes(byteArrayOf(0x0D)); true }
                    KeyEvent.KEYCODE_TAB   -> { sendBytes(byteArrayOf(0x09)); true }
                    KeyEvent.KEYCODE_ESCAPE-> { sendBytes(byteArrayOf(0x1B)); true }
                    else -> false
                }
            } else false
        }

        binding.sendButton.setOnClickListener { sendBytes(byteArrayOf(0x0D)) }
    }

    private fun handleTypedText(text: String) {
        val session = activeSession() ?: return
        for (ch in text) {
            val byte = ch.code
            if (altLatched) {
                session.writeBytes(byteArrayOf(0x1B))
                altLatched = false
                refreshModifierVisuals()
            }
            if (ctrlLatched) {
                val code = when {
                    byte in 'a'.code..'z'.code -> byte - 0x60
                    byte in 'A'.code..'Z'.code -> byte - 0x40
                    byte == ' '.code -> 0
                    else -> byte
                }
                session.writeBytes(byteArrayOf(code.toByte()))
                ctrlLatched = false
                refreshModifierVisuals()
            } else {
                session.writeBytes(ch.toString().toByteArray(Charsets.UTF_8))
            }
        }
    }

    private fun sendBytes(bytes: ByteArray) {
        val session = activeSession() ?: return
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
        session.writeBytes(payload)
        focusTerminal()
    }

    private fun sendSeq(seq: String) {
        val session = activeSession() ?: return
        session.writeText(seq)
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
            append("المحرّك: Native PTY\n")
            append("API: ").append(Build.VERSION.SDK_INT).append("\n")
            append("الجلسات: ").append(sessions.size)
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("الإعدادات")
            .setMessage(msg)
            .setPositiveButton("حسناً", null)
            .show()
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
}
KOT_MAIN

# ═════════════════════════════════════════════════════════════
# التحقق النهائي
# ═════════════════════════════════════════════════════════════
echo ""
echo "▶ [fix-all] فحص الملفات:"
echo "  CMakeLists.txt : $([ -f app/src/main/cpp/CMakeLists.txt ] && echo موجود || echo مفقود)"
echo "  pty_bridge.c   : $([ -f app/src/main/cpp/pty_bridge.c ] && echo موجود || echo مفقود)"
echo "  PtyBridge.kt   : $([ -f app/src/main/java/com/awlqy/terminal/core/PtyBridge.kt ] && echo موجود || echo مفقود)"
echo "  TerminalSession: $([ -f app/src/main/java/com/awlqy/terminal/core/TerminalSession.kt ] && echo موجود || echo مفقود)"
echo "  TerminalBuffer : $([ -f app/src/main/java/com/awlqy/terminal/core/TerminalBuffer.kt ] && echo موجود || echo مفقود)"
echo "  MainActivity   : $([ -f app/src/main/java/com/awlqy/terminal/MainActivity.kt ] && echo موجود || echo مفقود)"
echo ""
echo "▶ [fix-all] فحص النقاط الحساسة:"
echo "  sendSeq:"
grep -n "private fun sendSeq" app/src/main/java/com/awlqy/terminal/MainActivity.kt
echo ""
echo "  TerminalSession rows/cols:"
grep -n "var rows\|var cols" app/src/main/java/com/awlqy/terminal/core/TerminalSession.kt
echo ""
echo "  pty_bridge.c لا forkpty:"
grep -c "forkpty\|pty.h" app/src/main/cpp/pty_bridge.c || echo "  نظيف"
echo ""
echo "✔ [fix-all] انتهى."
echo ""
echo "   git add -A"
echo "   git commit -m 'fix: sendSeq shadowing + TerminalSession rows/cols + full C/C++/Kotlin'" 
echo "   git push"
