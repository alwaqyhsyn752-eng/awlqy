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
