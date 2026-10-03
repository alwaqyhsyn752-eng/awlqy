package com.awlqy.terminal.core

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

/**
 * محرّك أدوات APK على الجهاز.
 * يغلّف: aapt2 · d8 · apktool · jadx · apksigner · zipalign
 * ثبّت الأدوات في: filesDir/usr/bin/  (اسم التنفيذي كما هو)
 * أو اجعلها في PATH.
 */
class ApkBuilderEngine(private val appContext: Context) {

    data class ToolResult(
        val tool: String,
        val exitCode: Int,
        val stdout: String,
        val stderr: String,
        val durationMs: Long
    ) {
        val ok: Boolean get() = exitCode == 0
    }

    val toolsDir: File = File(appContext.filesDir, "usr/bin").apply { mkdirs() }
    val workDir: File  = File(appContext.filesDir, "apk-work").apply { mkdirs() }

    private val knownTools = listOf(
        "aapt2", "d8", "dx", "apktool", "jadx", "apksigner", "zipalign", "keytool"
    )

    fun toolPath(name: String): String {
        val local = File(toolsDir, name)
        return if (local.exists() && local.canExecute()) local.absolutePath else name
    }

    fun availability(): Map<String, Boolean> = knownTools.associateWith { name ->
        val local = File(toolsDir, name)
        if (local.exists() && local.canExecute()) true
        else {
            try {
                ProcessBuilder("sh", "-c", "command -v $name")
                    .redirectErrorStream(true)
                    .start().waitFor() == 0
            } catch (_: Exception) {
                false
            }
        }
    }

    private suspend fun exec(tool: String, args: List<String>, timeoutMs: Long = 600_000L): ToolResult =
        withContext(Dispatchers.IO) {
            val start = System.currentTimeMillis()
            val out = StringBuilder()
            val err = StringBuilder()
            var code = -1
            var proc: Process? = null
            try {
                val cmd = ArrayList<String>().apply {
                    add("sh")
                    add("-c")
                    add(buildShellLine(tool, args))
                }
                val pb = ProcessBuilder(cmd)
                pb.directory(workDir)
                pb.environment().apply {
                    this["PATH"] = "${toolsDir.absolutePath}:/system/bin:/system/xbin"
                }
                proc = pb.start()
                val p = proc

                val tOut = Thread {
                    try {
                        BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                            var line = r.readLine()
                            while (line != null) { out.append(line).append('\n'); line = r.readLine() }
                        }
                    } catch (_: Exception) {}
                }
                val tErr = Thread {
                    try {
                        BufferedReader(InputStreamReader(p.errorStream)).use { r ->
                            var line = r.readLine()
                            while (line != null) { err.append(line).append('\n'); line = r.readLine() }
                        }
                    } catch (_: Exception) {}
                }
                tOut.start(); tErr.start()

                val finished = p.waitFor()
                tOut.join(2000)
                tErr.join(2000)
                code = finished
            } catch (e: Exception) {
                err.append(e.message ?: e.javaClass.simpleName).append('\n')
            } finally {
                try { proc?.destroy() } catch (_: Exception) {}
            }

            ToolResult(
                tool = tool,
                exitCode = code,
                stdout = out.toString(),
                stderr = err.toString(),
                durationMs = System.currentTimeMillis() - start
            )
        }

    private fun buildShellLine(tool: String, args: List<String>): String {
        val sb = StringBuilder()
        sb.append(shellQuote(toolPath(tool)))
        for (a in args) {
            sb.append(' ').append(shellQuote(a))
        }
        return sb.toString()
    }

    private fun shellQuote(s: String): String {
        if (s.isEmpty()) return "''"
        val safe = s.all { it.isLetterOrDigit() || it in "._-/@:=," }
        if (safe) return s
        return "'" + s.replace("'", "'\\''") + "'"
    }

    // ─── Operations ──────────────────────────────────────

    suspend fun decode(apk: File, outDir: File): ToolResult {
        outDir.mkdirs()
        return exec("apktool", listOf("d", "-f", "-o", outDir.absolutePath, apk.absolutePath))
    }

    suspend fun build(decodedDir: File, outApk: File): ToolResult {
        outApk.parentFile?.mkdirs()
        return exec("apktool", listOf("b", "-o", outApk.absolutePath, decodedDir.absolutePath))
    }

    suspend fun sign(
        apk: File,
        keystore: File,
        alias: String,
        storePass: String,
        keyPass: String
    ): ToolResult {
        return exec(
            "apksigner",
            listOf(
                "sign",
                "--ks", keystore.absolutePath,
                "--ks-key-alias", alias,
                "--ks-pass", "pass:$storePass",
                "--key-pass", "pass:$keyPass",
                apk.absolutePath
            )
        )
    }

    suspend fun zipalign(input: File, output: File): ToolResult {
        output.parentFile?.mkdirs()
        return exec("zipalign", listOf("-f", "4", input.absolutePath, output.absolutePath))
    }

    suspend fun decompileToJava(apk: File, outDir: File): ToolResult {
        outDir.mkdirs()
        return exec("jadx", listOf("-d", outDir.absolutePath, apk.absolutePath))
    }

    suspend fun dumpBadging(apk: File): ToolResult {
        return exec("aapt2", listOf("dump", "badging", apk.absolutePath))
    }

    suspend fun dexToSmali(decodedDir: File, outDir: File): ToolResult {
        outDir.mkdirs()
        return exec(
            "d8",
            listOf(
                "--output", outDir.absolutePath,
                "--debug",
                decodedDir.absolutePath
            )
        )
    }

    suspend fun generateKeystore(
        keystore: File,
        alias: String,
        storePass: String,
        keyPass: String,
        dname: String = "CN=awlqy, OU=حسين الخلاقي, O=awlqy, L=Yemen, C=YE"
    ): ToolResult {
        keystore.parentFile?.mkdirs()
        return exec(
            "keytool",
            listOf(
                "-genkeypair",
                "-v",
                "-keystore", keystore.absolutePath,
                "-alias", alias,
                "-keyalg", "RSA",
                "-keysize", "2048",
                "-validity", "10000",
                "-storepass", storePass,
                "-keypass", keyPass,
                "-dname", dname
            )
        )
    }

    fun describe(tool: String): String = when (tool) {
        "aapt2"     -> "أداة قراءة/تحليل ملفات الموارد في APK"
        "d8"        -> "محوّل DEX من Java bytecode (Android 8+)"
        "dx"        -> "محوّل DEX قديم (Android <8)"
        "apktool"   -> "فك وإعادة بناء APK مع الموارد والـ manifest"
        "jadx"      -> "مفكّك DEX إلى كود Java قابل للقراءة"
        "apksigner" -> "توقيع APK بشهادة رقمية"
        "zipalign"  -> "محاذاة APK لأداء أمثل"
        "keytool"   -> "إنشاء وإدارة مفاتيح التوقيع"
        else        -> tool
    }
}
