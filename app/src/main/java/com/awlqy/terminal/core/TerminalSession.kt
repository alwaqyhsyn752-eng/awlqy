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
