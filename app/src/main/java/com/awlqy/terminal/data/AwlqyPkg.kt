package com.awlqy.terminal.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * awlqy-pkg: مدير حزم ذكي مع إصلاح ذاتي.
 * - يدعم pip / npm / gem / cargo / go / clang / apt (لو متاح).
 * - عند فشل التنزيل: يعيد المحاولة مع الإصلاح (dpkg --configure -a، apt fix-broken، استئناف).
 */
class AwlqyPkg(private val workDir: File) {

    data class Result(val exitCode: Int, val stdout: String, val stderr: String) {
        val ok get() = exitCode == 0
    }

    private suspend fun run(cmd: List<String>, timeoutMin: Long = 10): Result =
        withContext(Dispatchers.IO) {
            try {
                val pb = ProcessBuilder(cmd).directory(workDir).redirectErrorStream(false)
                val p = pb.start()
                val out = p.inputStream.bufferedReader().readText()
                val err = p.errorStream.bufferedReader().readText()
                if (!p.waitFor(timeoutMin, TimeUnit.MINUTES)) { p.destroyForcibly(); return@withContext Result(-1, out, err + "\n[timeout]") }
                Result(p.exitValue(), out, err)
            } catch (t: Throwable) {
                Timber.e(t, "pkg run failed: %s", cmd.joinToString(" "))
                Result(-1, "", t.message ?: "unknown")
            }
        }

    /**
     * تشغيل أمر مع إصلاح ذاتي + retry.
     */
    suspend fun runWithHealing(cmd: List<String>, maxRetries: Int = 3): Result {
        var last: Result? = null
        for (attempt in 1..maxRetries) {
            Timber.i("awlqy-pkg attempt %d: %s", attempt, cmd.joinToString(" "))
            last = run(cmd)
            if (last.ok) return last

            Timber.w("attempt %d failed, healing...", attempt)
            // خطوات الإصلاح الذاتي
            run(listOf("sh", "-c", "apt-get -y -f install || true"), 5)
            run(listOf("sh", "-c", "dpkg --configure -a || true"), 5)
            run(listOf("sh", "-c", "apt-get -y --fix-broken install || true"), 5)
            // pip cache purge لو الفشل من pip
            if (cmd.firstOrNull()?.contains("pip") == true) {
                run(listOf("sh", "-c", "python -m pip cache purge || true"), 3)
                run(listOf("sh", "-c", "python -m pip install --upgrade pip setuptools wheel || true"), 5)
            }
            if (cmd.firstOrNull()?.contains("npm") == true) {
                run(listOf("sh", "-c", "npm cache clean --force || true"), 5)
            }
            kotlinx.coroutines.delay(1500L * attempt)
        }
        return last ?: Result(-1, "", "no attempt")
    }

    // ── واجهات عالية المستوى ──
    suspend fun pipInstall(pkg: String) = runWithHealing(listOf("sh", "-c", "python -m pip install --no-input $pkg"))
    suspend fun npmInstall(pkg: String) = runWithHealing(listOf("sh", "-c", "npm install -g $pkg || npm install $pkg"))
    suspend fun gemInstall(pkg: String) = runWithHealing(listOf("sh", "-c", "gem install $pkg"))
    suspend fun cargoInstall(pkg: String) = runWithHealing(listOf("sh", "-c", "cargo install $pkg"))
    suspend fun goInstall(pkg: String)  = runWithHealing(listOf("sh", "-c", "go install $pkg"))
    suspend fun phpComposer(pkg: String) = runWithHealing(listOf("sh", "-c", "composer require $pkg"))

    /**
     * يكشف الخطأ ويستنتج الحزمة الناقصة ثم يثبّتها ويعيد التنفيذ.
     */
    suspend fun autoHealAndRetry(scriptPath: String, interpreter: String): Result {
        var last = runWithHealing(listOf(interpreter, scriptPath), 1)
        if (last.ok) return last

        val missing = detectMissing(last.stderr + "\n" + last.stdout) ?: return last
        Timber.i("auto-heal: missing=%s", missing)
        when (interpreter) {
            "python", "python3" -> pipInstall(missing)
            "node" -> npmInstall(missing)
            "ruby" -> gemInstall(missing)
            "php" -> phpComposer(missing)
        }
        last = runWithHealing(listOf(interpreter, scriptPath), 2)
        return last
    }

    private fun detectMissing(err: String): String? {
        Regex("ModuleNotFoundError: No module named '([^']+)'").find(err)?.let { return it.groupValues[1] }
        Regex("ImportError: cannot import name '([^']+)'").find(err)?.let { return it.groupValues[1] }
        Regex("Cannot find module '([^']+)'").find(err)?.let { return it.groupValues[1] }
        Regex("no required module provides package ([^;\\s]+)").find(err)?.let { return it.groupValues[1] }
        Regex("LoadError: cannot load such file -- ([^\\s]+)").find(err)?.let { return it.groupValues[1] }
        Regex("Fatal error: Uncaught Error: Class \"([^\"]+)\" not found").find(err)?.let { return it.groupValues[1] }
        return null
    }
}
