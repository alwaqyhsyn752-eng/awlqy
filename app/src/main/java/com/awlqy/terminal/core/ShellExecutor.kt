package com.awlqy.terminal.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.concurrent.atomic.AtomicReference

data class ShellResult(
    val exitCode: Int,
    val stdout: String,
    val stderr: String,
    val durationMs: Long
) {
    val ok: Boolean get() = exitCode == 0
}

object ShellExecutor {

    private const val SHELL = "/system/bin/sh"
    private val currentProc = AtomicReference<Process?>(null)

    fun killCurrent(): Boolean {
        val p = currentProc.get() ?: return false
        return try {
            p.destroy()
            true
        } catch (_: Exception) {
            false
        }
    }

    suspend fun run(
        command: String,
        workDir: File,
        extraEnv: Map<String, String> = emptyMap()
    ): ShellResult = withContext(Dispatchers.IO) {
        val start = System.currentTimeMillis()
        var exit = -1
        val out = StringBuilder()
        val err = StringBuilder()
        var proc: Process? = null
        try {
            if (!workDir.exists()) workDir.mkdirs()
            val pb = ProcessBuilder(SHELL, "-c", command)
            pb.directory(workDir)
            val env = pb.environment()
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "truecolor"
            env["HOME"] = workDir.absolutePath
            env["LANG"] = "en_US.UTF-8"
            env["LC_ALL"] = "en_US.UTF-8"
            env["PATH"] = "/data/data/com.awlqy.terminal/files/usr/bin:/system/bin:/system/xbin"
            env.putAll(extraEnv)

            proc = pb.start()
            currentProc.set(proc)

            val p = proc
            val tOut = Thread {
                try {
                    BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                        var line = r.readLine()
                        while (line != null) {
                            out.append(line).append('\n')
                            line = r.readLine()
                        }
                    }
                } catch (_: Exception) { }
            }
            val tErr = Thread {
                try {
                    BufferedReader(InputStreamReader(p.errorStream)).use { r ->
                        var line = r.readLine()
                        while (line != null) {
                            err.append(line).append('\n')
                            line = r.readLine()
                        }
                    }
                } catch (_: Exception) { }
            }
            tOut.start(); tErr.start()
            exit = p.waitFor()
            tOut.join(2000)
            tErr.join(2000)
        } catch (e: Exception) {
            err.append(e.message ?: e.javaClass.simpleName).append('\n')
        } finally {
            currentProc.set(null)
            try { proc?.destroy() } catch (_: Exception) { }
        }
        ShellResult(exit, out.toString(), err.toString(), System.currentTimeMillis() - start)
    }

    fun diagnose(stderr: String, stdout: String): String? {
        val s = "$stderr\n$stdout"
        if (s.isBlank()) return null

        Regex("ModuleNotFoundError: No module named '([^']+)'").find(s)?.let {
            return "مكتبة Python مفقودة '${it.groupValues[1]}'."
        }
        Regex("ImportError: cannot import name '([^']+)'").find(s)?.let {
            return "استيراد فاشل لـ '${it.groupValues[1]}'. تحقق من التثبيت."
        }
        Regex("Cannot find module '([^']+)'").find(s)?.let {
            return "حزمة Node.js مفقودة '${it.groupValues[1]}'."
        }
        if (s.contains("command not found") || s.contains(": not found")) {
            return "الأمر غير مثبت أو غير موجود في PATH. تحقق من الاسم."
        }
        if (s.contains("No such file or directory")) {
            return "الملف/المجلد غير موجود. تحقق من المسار."
        }
        if (s.contains("Permission denied")) {
            return "صلاحية مرفوضة. جرّب: chmod +x على الملف."
        }
        if (s.contains("SyntaxError")) {
            return "خطأ بنيوي. تحقق من علامات الاقتباس، الأقواس، والمسافات البادئة."
        }
        if (s.contains("is a directory")) {
            return "هذا مسار مجلد، ليس ملفاً. استخدم ls لعرض المحتوى."
        }
        if (s.contains("No space left on device")) {
            return "المساحة ممتلئة. احذف ملفات غير ضرورية."
        }
        if (s.contains("Cannot resolve host") || s.contains("Could not resolve host")) {
            return "تعذر الاتصال بالشبكة. تحقق من الإنترنت."
        }
        return null
    }

    fun autoHealCommand(stderr: String, stdout: String): String? {
        val s = "$stderr\n$stdout"
        Regex("ModuleNotFoundError: No module named '([^']+)'").find(s)?.let {
            return "python -m pip install ${it.groupValues[1]}"
        }
        Regex("Cannot find module '([^']+)'").find(s)?.let {
            return "npm install ${it.groupValues[1]}"
        }
        if (s.contains("Permission denied")) {
            return "chmod +x <file> ثم أعد التشغيل"
        }
        return null
    }
}
