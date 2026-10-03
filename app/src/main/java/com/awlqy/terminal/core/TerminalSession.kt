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
