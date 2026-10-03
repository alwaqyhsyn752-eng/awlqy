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
