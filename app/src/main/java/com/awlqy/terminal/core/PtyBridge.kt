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
