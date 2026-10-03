#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · phase4.sh — Auto-Healing + APK Builder + Automation
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [phase4] إنشاء المجلدات"
mkdir -p app/src/main/java/com/awlqy/terminal/core
mkdir -p app/src/main/res/{menu,values,layout}

# ═════════════════════════════════════════════════════════════
# 1. AutoHealingEngine.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/core/AutoHealingEngine.kt <<'KOT_1'
package com.awlqy.terminal.core

/**
 * محرّك الإصلاح الذكي.
 * يحلّل مخرجات الأخطاء ويولّد خطة إصلاح قابلة للتنفيذ.
 */
object AutoHealingEngine {

    data class HealPlan(
        val summary: String,
        val suggestion: String?,
        val autoRetryCommand: String?
    )

    private data class Rule(
        val regex: Regex,
        val summarize: (MatchResult) -> String,
        val suggestion: (MatchResult) -> String,
        val retry: (MatchResult) -> String?
    )

    private val rules: List<Rule> = listOf(

        Rule(
            Regex("ModuleNotFoundError: No module named '([A-Za-z0-9_\\-.]+)'"),
            { "مكتبة Python مفقودة: ${it.groupValues[1]}" },
            { "شغّل: python -m pip install ${it.groupValues[1]}" },
            { "python -m pip install --no-input ${it.groupValues[1]}" }
        ),

        Rule(
            Regex("ImportError: cannot import name '([A-Za-z0-9_\\-.]+)'"),
            { "استيراد فاشل: ${it.groupValues[1]}" },
            { "تحقق من الاسم، أو: python -m pip install --upgrade ${it.groupValues[1]}" },
            { null }
        ),

        Rule(
            Regex("Cannot find module '([^']+)'"),
            { "حزمة Node.js مفقودة: ${it.groupValues[1]}" },
            { "شغّل: npm install ${it.groupValues[1]}" },
            { "npm install ${it.groupValues[1]}" }
        ),

        Rule(
            Regex("([^\\s:]+): not found"),
            { "أمر غير معروف: ${it.groupValues[1]}" },
            { "ليس في PATH. ثبّته أو صحّح الاسم." },
            { null }
        ),

        Rule(
            Regex("command not found"),
            { "الأمر غير موجود في النظام" },
            { "تحقق من الإملاء أو ثبّت الحزمة المطلوبة." },
            { null }
        ),

        Rule(
            Regex("No such file or directory"),
            { "الملف أو المجلد غير موجود" },
            { "تحقق من المسار بـ ls ثم أعد المحاولة." },
            { null }
        ),

        Rule(
            Regex("Permission denied"),
            { "صلاحية مرفوضة" },
            { "جرّب: chmod +x <file> أو شغّل المسار المصرّح به." },
            { null }
        ),

        Rule(
            Regex("SyntaxError: (.+)"),
            { "خطأ بنيوي: ${it.groupValues[1]}" },
            { "راجع علامات الاقتباس، الأقواس، والمسافات البادئة." },
            { null }
        ),

        Rule(
            Regex("is a directory"),
            { "المسار مجلد وليس ملفاً" },
            { "استخدم ls لاستعراض المحتوى." },
            { null }
        ),

        Rule(
            Regex("No space left on device"),
            { "المساحة ممتلئة" },
            { "احذف ملفات cache: rm -rf \$HOME/.cache/*" },
            { "rm -rf \$HOME/.cache/* 2>/dev/null; echo cleaned" }
        ),

        Rule(
            Regex("Could not resolve host|Cannot resolve host|Network is unreachable"),
            { "تعذّر الوصول إلى الشبكة" },
            { "تحقق من الاتصال بالإنترنت." },
            { null }
        ),

        Rule(
            Regex("EACCES \\(Permission denied\\)"),
            { "صلاحية مرفوضة على الملف/المسار" },
            { "chmod +x أو غيّر مسار الكتابة." },
            { null }
        ),

        Rule(
            Regex("Killed"),
            { "تم إنهاء العملية (نفاد ذاكرة أو إشارة SIGKILL)" },
            { "جرّب أمراً أخف، أو زد الذاكرة المتاحة." },
            { null }
        ),

        Rule(
            Regex("git: command not found"),
            { "git غير مثبت" },
            { "ثبّت git عبر مدير الحزم أو استخدم نسخة مدمجة." },
            { null }
        ),

        Rule(
            Regex("fatal: not a git repository"),
            { "هذا المجلد ليس مستودع git" },
            { "شغّل: git init ثم أعد الأمر." },
            { "git init" }
        ),

        Rule(
            Regex("fatal: refusing to merge unrelated histories"),
            { "فروع git غير متصلة" },
            { "استخدم: git pull --allow-unrelated-histories" },
            { "git pull --allow-unrelated-histories" }
        ),

        Rule(
            Regex("error: failed to push some refs"),
            { "رفض git push" },
            { "شغّل: git pull --rebase ثم push." },
            { "git pull --rebase" }
        ),

        Rule(
            Regex("javac: not found|java: not found"),
            { "أدوات Java غير متوفرة" },
            { "ثبّت JDK أو استخدم مساراً بديلاً." },
            { null }
        ),

        Rule(
            Regex("pip: command not found|pip3: not found"),
            { "pip غير متوفر" },
            { "جرّب: python -m ensurepip ثم python -m pip install --upgrade pip" },
            { "python -m ensurepip && python -m pip install --upgrade pip" }
        ),

        Rule(
            Regex("npm: command not found"),
            { "npm غير متوفر" },
            { "ثبّت Node.js، أو استخدم node مباشرة." },
            { null }
        )
    )

    fun analyze(exitCode: Int, stdout: String, stderr: String): HealPlan? {
        if (exitCode == 0) return null
        val s = "$stderr\n$stdout"
        if (s.isBlank()) return null

        for (rule in rules) {
            val m = rule.regex.find(s) ?: continue
            return HealPlan(
                summary = rule.summarize(m),
                suggestion = rule.suggestion(m),
                autoRetryCommand = rule.retry(m)
            )
        }

        return HealPlan(
            summary = "فشل التنفيذ (exit=$exitCode)",
            suggestion = "راجع المخرجات، جرّب تشغيل الأمر يدوياً.",
            autoRetryCommand = null
        )
    }
}
KOT_1

# ═════════════════════════════════════════════════════════════
# 2. ApkBuilderEngine.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/core/ApkBuilderEngine.kt <<'KOT_2'
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
KOT_2

# ═════════════════════════════════════════════════════════════
# 3. AutomationManager.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/core/AutomationManager.kt <<'KOT_3'
package com.awlqy.terminal.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * مدير أتمتة الحسابات المتعددة.
 * - تسجيل حسابات (منصة، توكن، نقطة وصول).
 * - إرسال طلبات POST آمنة عبر HttpURLConnection.
 * - تشغيل سكربتات shell في الخلفية.
 * - سجل نتائج لكل عملية.
 */
object AutomationManager {

    data class Account(
        val id: String,
        val platform: String,
        val token: String,
        val endpoint: String
    )

    data class DispatchResult(
        val accountId: String,
        val httpCode: Int,
        val responseBody: String,
        val error: String?
    ) {
        val ok: Boolean get() = error == null && httpCode in 200..299
    }

    private val accounts = LinkedHashMap<String, Account>()
    private val log = ArrayDeque<String>()
    private const val MAX_LOG = 500

    @Synchronized
    fun register(account: Account) {
        accounts[account.id] = account
        record("register", account.id, "platform=${account.platform}")
    }

    @Synchronized
    fun remove(id: String): Boolean {
        val removed = accounts.remove(id) != null
        if (removed) record("remove", id, "ok")
        return removed
    }

    @Synchronized
    fun list(): List<Account> = accounts.values.toList()

    @Synchronized
    fun size(): Int = accounts.size

    @Synchronized
    private fun record(op: String, subject: String, detail: String) {
        val entry = "[$op] $subject · $detail"
        log.addLast(entry)
        while (log.size > MAX_LOG) log.removeFirst()
    }

    @Synchronized
    fun history(): List<String> = log.toList()

    suspend fun post(accountId: String, jsonPayload: String): DispatchResult = withContext(Dispatchers.IO) {
        val account = accounts[accountId]
            ?: return@withContext DispatchResult(accountId, -1, "", "الحساب غير مسجّل")
        try {
            val url = URL(account.endpoint)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 20000
            conn.readTimeout = 45000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            conn.setRequestProperty("Authorization", "Bearer ${account.token}")
            conn.setRequestProperty("User-Agent", "awlqy-automation/1.0")

            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { w ->
                w.write(jsonPayload)
                w.flush()
            }

            val code = conn.responseCode
            val body = try {
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                BufferedReader(InputStreamReader(stream)).use { it.readText() }
            } catch (_: Exception) { "" }

            conn.disconnect()
            record("post", accountId, "code=$code")
            DispatchResult(accountId, code, body, null)
        } catch (e: Exception) {
            record("post", accountId, "error=${e.message}")
            DispatchResult(accountId, -1, "", e.message ?: e.javaClass.simpleName)
        }
    }

    suspend fun postAll(jsonPayload: String): List<DispatchResult> = withContext(Dispatchers.IO) {
        val ids = accounts.keys.toList()
        val results = ArrayList<DispatchResult>(ids.size)
        for (id in ids) {
            results.add(post(id, jsonPayload))
        }
        results
    }

    suspend fun webhook(url: String, jsonPayload: String): DispatchResult = withContext(Dispatchers.IO) {
        try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 15000
            conn.readTimeout = 30000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            conn.setRequestProperty("User-Agent", "awlqy-automation/1.0")

            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { w ->
                w.write(jsonPayload)
                w.flush()
            }
            val code = conn.responseCode
            val body = try {
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                BufferedReader(InputStreamReader(stream)).use { it.readText() }
            } catch (_: Exception) { "" }
            conn.disconnect()
            record("webhook", url, "code=$code")
            DispatchResult("webhook", code, body, null)
        } catch (e: Exception) {
            record("webhook", url, "error=${e.message}")
            DispatchResult("webhook", -1, "", e.message ?: e.javaClass.simpleName)
        }
    }

    /**
     * تشغيل سكربت shell في الخلفية دون حجب الواجهة.
     */
    suspend fun runScript(
        script: String,
        workDir: File,
        env: Map<String, String> = emptyMap()
    ): ShellResult = ShellExecutor.run(script, workDir, env)

    /**
     * بناء حمولة JSON موحّدة.
     */
    fun payload(action: String, fields: Map<String, String> = emptyMap()): String {
        val obj = JSONObject()
        obj.put("action", action)
        obj.put("ts", System.currentTimeMillis())
        val extras = JSONObject()
        for ((k, v) in fields) extras.put(k, v)
        obj.put("data", extras)
        return obj.toString()
    }
}
KOT_3

# ═════════════════════════════════════════════════════════════
# 4. main_menu.xml (مع أدوات APK والأتمتة)
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/menu/main_menu.xml <<'XML_1'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto">
    <item
        android:id="@+id/action_apk_tools"
        android:title="@string/menu_apk_tools"
        app:showAsAction="never"/>
    <item
        android:id="@+id/action_automation"
        android:title="@string/menu_automation"
        app:showAsAction="never"/>
    <item
        android:id="@+id/action_update"
        android:title="@string/menu_update"
        app:showAsAction="never"/>
    <item
        android:id="@+id/action_settings"
        android:title="@string/menu_settings"
        app:showAsAction="never"/>
    <item
        android:id="@+id/action_about"
        android:title="@string/menu_about"
        app:showAsAction="never"/>
</menu>
XML_1

# ═════════════════════════════════════════════════════════════
# 5. strings.xml (مع النصوص الجديدة)
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/values/strings.xml <<'XML_2'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">awlqy</string>
    <string name="app_tagline">طرفية ذكية · بيئة تطوير · إصلاح ذاتي</string>
    <string name="developer_name">حسين الخلاقي</string>
    <string name="developer_role">المطوّر / المنشئ</string>
    <string name="github_handle">alwaqyhsyn752-eng</string>
    <string name="notification_channel_session">جلسة awlqy</string>
    <string name="notification_session_active">جلسة الطرفية نشطة</string>
    <string name="hint_command">اكتب أمراً…</string>
    <string name="action_run">تشغيل</string>
    <string name="action_clear">مسح</string>
    <string name="action_send">إرسال</string>
    <string name="menu_update">التحقق من التحديثات</string>
    <string name="menu_settings">الإعدادات</string>
    <string name="menu_about">حول التطبيق</string>
    <string name="menu_apk_tools">أدوات APK</string>
    <string name="menu_automation">الأتمتة</string>
</resources>
XML_2

# ═════════════════════════════════════════════════════════════
# 6. MainActivity.kt (محدّث — دمج المحركات الثلاثة)
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/MainActivity.kt <<'KOT_MAIN'
package com.awlqy.terminal

import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.text.method.ScrollingMovementMethod
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.awlqy.terminal.core.ApkBuilderEngine
import com.awlqy.terminal.core.AutoHealingEngine
import com.awlqy.terminal.core.AutoUpdateManager
import com.awlqy.terminal.core.AutomationManager
import com.awlqy.terminal.core.ShellExecutor
import com.awlqy.terminal.databinding.ActivityMainBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val buffer = StringBuilder()
    private val timeFmt = SimpleDateFormat("HH:mm:ss", Locale.US)

    @Volatile private var busy = false

    private val history = ArrayList<String>()
    private var historyIndex = -1

    private val apkEngine by lazy { ApkBuilderEngine(applicationContext) }

    private val appVersionName: String by lazy {
        try {
            val pi: PackageManager = packageManager
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pi.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                pi.getPackageInfo(packageName, 0)
            }
            info.versionName ?: "1.0.0"
        } catch (_: Exception) {
            "1.0.0"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)

        binding.consoleText.movementMethod = ScrollingMovementMethod()

        printBanner()
        printSystemStatus()

        binding.runButton.setOnClickListener { runCommand() }
        binding.clearButton.setOnClickListener { clearConsole() }

        binding.inputEdit.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND ||
                actionId == EditorInfo.IME_ACTION_DONE) {
                runCommand()
                true
            } else false
        }

        binding.btnCtrlC.setOnClickListener { handleCtrlC() }
        binding.btnTab.setOnClickListener   { insertIntoInput("\t") }
        binding.btnEsc.setOnClickListener   { binding.inputEdit.setText("") }
        binding.btnUp.setOnClickListener    { navigateHistory(-1) }
        binding.btnDown.setOnClickListener  { navigateHistory(+1) }

        lifecycleScope.launch { silentUpdateCheck() }
    }

    private fun printBanner() {
        appendLine("==========================================")
        appendLine("  awlqy Terminal & IDE  v$appVersionName")
        appendLine("  المطوّر: حسين الخلاقي")
        appendLine("  PHASE 4 · Fully Functional")
        appendLine("==========================================")
        appendLine("")
    }

    private fun printSystemStatus() {
        appendLine("[system] الاسم: awlqy Terminal & IDE")
        appendLine("[system] المطوّر: حسين الخلاقي")
        appendLine("[system] الحالة: Phase 4 - Fully Functional / Auto-Healing Active")
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "?"
        appendLine("[system] API: ${Build.VERSION.SDK_INT} · ABI: $abi")
        appendLine("[system] اكتب أمراً ثم اضغط تشغيل.")
        appendLine("[system] جرّب: ls · pwd · id · echo hello · date")
        appendLine("[system] أدوات APK: من القائمة → أدوات APK")
        appendLine("[system] الأتمتة: من القائمة → الأتمتة")
        appendLine("")
    }

    private fun clearConsole() {
        buffer.setLength(0)
        binding.consoleText.text = ""
        printSystemStatus()
    }

    private fun appendLine(line: String) {
        buffer.append(line).append('\n')
        render()
    }

    private fun appendRaw(text: String) {
        if (text.isEmpty()) return
        buffer.append(text)
        if (!text.endsWith('\n')) buffer.append('\n')
        render()
    }

    private fun render() {
        binding.consoleText.text = buffer.toString()
        binding.consoleScroll.post {
            binding.consoleScroll.fullScroll(View.FOCUS_DOWN)
        }
    }

    private fun runCommand() {
        if (busy) {
            Toast.makeText(this, "أمر قيد التنفيذ… (Ctrl+C للإلغاء)", Toast.LENGTH_SHORT).show()
            return
        }
        val cmd = binding.inputEdit.text.toString().trim()
        if (cmd.isEmpty()) return
        binding.inputEdit.setText("")

        if (history.isEmpty() || history.last() != cmd) {
            history.add(cmd)
            if (history.size > 200) history.removeAt(0)
        }
        historyIndex = -1

        val ts = timeFmt.format(Date())
        appendLine("--- [$ts] \$ $cmd")
        busy = true
        binding.runButton.isEnabled = false

        lifecycleScope.launch {
            val home = File(filesDir, "home").apply { mkdirs() }
            val result = ShellExecutor.run(cmd, home)

            if (result.stdout.isNotBlank()) appendRaw(result.stdout)
            if (result.stderr.isNotBlank()) appendRaw("[stderr]\n" + result.stderr)

            val plan = AutoHealingEngine.analyze(result.exitCode, result.stdout, result.stderr)
            if (plan != null) {
                appendLine("[auto-heal] \u2695 ${plan.summary}")
                if (plan.suggestion != null) {
                    appendLine("[auto-heal]   ${plan.suggestion}")
                }
                if (plan.autoRetryCommand != null) {
                    appendLine("[auto-fix]  \u00BB ${plan.autoRetryCommand}")
                }
            }

            appendLine("--- exit=${result.exitCode} · ${result.durationMs}ms")
            appendLine("")
            busy = false
            binding.runButton.isEnabled = true
        }
    }

    private fun handleCtrlC() {
        if (busy) {
            val ok = ShellExecutor.killCurrent()
            appendLine("^C" + if (ok) " (signal sent)" else " (no active process)")
            busy = false
            binding.runButton.isEnabled = true
        } else {
            binding.inputEdit.setText("")
        }
    }

    private fun insertIntoInput(s: String) {
        val cur = binding.inputEdit.text?.toString().orEmpty()
        val sel = binding.inputEdit.selectionStart.coerceAtLeast(0)
        val safe = sel.coerceAtMost(cur.length)
        val next = cur.substring(0, safe) + s + cur.substring(safe)
        binding.inputEdit.setText(next)
        binding.inputEdit.setSelection(safe + s.length)
    }

    private fun navigateHistory(direction: Int) {
        if (history.isEmpty()) return
        if (historyIndex == -1) historyIndex = history.size
        historyIndex = (historyIndex + direction).coerceIn(0, history.size)
        val cmd = if (historyIndex >= history.size) "" else history[historyIndex]
        binding.inputEdit.setText(cmd)
        binding.inputEdit.setSelection(cmd.length)
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.main_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_apk_tools  -> { showApkToolsDialog(); true }
            R.id.action_automation -> { showAutomationDialog(); true }
            R.id.action_settings   -> { showSettings(); true }
            R.id.action_update     -> { checkUpdatesManually(); true }
            R.id.action_about      -> { showAbout(); true }
            else -> super.onOptionsItemSelected(item)
        }
    }

    // ─── APK Tools ───────────────────────────────────────

    private fun showApkToolsDialog() {
        val avail = apkEngine.availability()
        val sb = StringBuilder()
        sb.append("مسار الأدوات: ").append(apkEngine.toolsDir.absolutePath).append("\n\n")
        for ((tool, ok) in avail) {
            val mark = if (ok) "[✓]" else "[ ]"
            sb.append(mark).append(' ').append(tool)
                .append(" — ").append(apkEngine.describe(tool)).append('\n')
        }
        sb.append('\n').append("ثبّت الأدوات في المجلد أعلاه لتفعيلها.")

        MaterialAlertDialogBuilder(this)
            .setTitle("أدوات APK على الجهاز")
            .setMessage(sb.toString())
            .setPositiveButton("حسناً", null)
            .setNeutralButton("عرض availability") { _, _ ->
                appendLine("[apk-tools] متاح الآن: " +
                    avail.filter { it.value }.keys.joinToString(", ").ifEmpty { "لا شيء" })
                binding.consoleScroll.post {
                    binding.consoleScroll.fullScroll(View.FOCUS_DOWN)
                }
            }
            .show()
    }

    // ─── Automation ──────────────────────────────────────

    private fun showAutomationDialog() {
        val n = AutomationManager.size()
        val msg = buildString {
            appendLine("عدد الحسابات المسجّلة: $n")
            appendLine("سجل العمليات: ${AutomationManager.history().size} عنصر")
            appendLine()
            appendLine("لتسجيل حساب برمجياً:")
            appendLine("AutomationManager.register(")
            appendLine("  Account(id, platform, token, endpoint)")
            appendLine(")")
            appendLine()
            appendLine("إرسال: AutomationManager.post(id, payload)")
            appendLine("إلى الكل: AutomationManager.postAll(payload)")
            appendLine("Webhook: AutomationManager.webhook(url, payload)")
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("مدير الأتمتة")
            .setMessage(msg)
            .setPositiveButton("حسناً", null)
            .setNeutralButton("سجل العمليات") { _, _ ->
                val h = AutomationManager.history()
                if (h.isEmpty()) {
                    appendLine("[automation] السجل فارغ.")
                } else {
                    appendLine("[automation] سجل العمليات:")
                    for (line in h.takeLast(20)) appendLine("  $line")
                }
            }
            .show()
    }

    // ─── Settings / About ────────────────────────────────

    private fun showSettings() {
        val msg = buildString {
            appendLine("التطبيق: awlqy Terminal & IDE")
            appendLine("الإصدار: $appVersionName")
            appendLine("المطوّر: حسين الخلاقي")
            appendLine("GitHub: alwaqyhsyn752-eng")
            appendLine("الحالة: Phase 4 - Fully Functional / Auto-Healing Active")
            appendLine("Package: $packageName")
            appendLine("سجل الأوامر: ${history.size}")
            appendLine("حسابات الأتمتة: ${AutomationManager.size()}")
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("الإعدادات")
            .setMessage(msg)
            .setPositiveButton("حسناً", null)
            .setNeutralButton("التحقق من التحديثات") { _, _ -> checkUpdatesManually() }
            .show()
    }

    private fun showAbout() {
        MaterialAlertDialogBuilder(this)
            .setTitle("حول التطبيق")
            .setMessage(
                "awlqy — طرفية ذكية وبيئة تطوير متكاملة.\n" +
                "مبنية بـ Kotlin + Android Runtime.\n" +
                "© 2025 حسين الخلاقي\n" +
                "رخصة MIT"
            )
            .setPositiveButton("إغلاق", null)
            .show()
    }

    // ─── Auto-update ─────────────────────────────────────

    private suspend fun silentUpdateCheck() {
        val info = withContext(Dispatchers.IO) {
            AutoUpdateManager.checkLatest(this@MainActivity, appVersionName)
        }
        if (info != null && info.hasUpdate) {
            appendLine("[update] إصدار جديد متوفر: ${info.tag} — افتح القائمة → التحقق من التحديثات.")
        }
    }

    private fun checkUpdatesManually() {
        lifecycleScope.launch {
            appendLine("[update] جاري التحقق من GitHub Releases...")
            val info = withContext(Dispatchers.IO) {
                AutoUpdateManager.checkLatest(this@MainActivity, appVersionName)
            }
            if (info == null) {
                appendLine("[update] تعذر الاتصال بـ GitHub.")
                return@launch
            }
            if (!info.hasUpdate) {
                appendLine("[update] أنت على أحدث إصدار ($appVersionName).")
                return@launch
            }
            appendLine("[update] إصدار جديد: ${info.tag}")
            MaterialAlertDialogBuilder(this@MainActivity)
                .setTitle("تحديث متوفر: ${info.tag}")
                .setMessage(info.notes.ifBlank { "لا توجد ملاحظات." })
                .setPositiveButton("تحديث الآن") { _, _ -> downloadAndInstall(info) }
                .setNegativeButton("لاحقاً", null)
                .show()
        }
    }

    private fun downloadAndInstall(info: AutoUpdateManager.UpdateInfo) {
        lifecycleScope.launch {
            appendLine("[update] جاري التنزيل: ${info.apkName}")
            val apk = withContext(Dispatchers.IO) {
                AutoUpdateManager.downloadApk(this@MainActivity, info) { pct ->
                    if (pct == 25 || pct == 50 || pct == 75 || pct == 100) {
                        runOnUiThread { appendLine("[update] ... $pct%") }
                    }
                }
            }
            if (apk == null) {
                appendLine("[update] فشل التنزيل.")
                return@launch
            }
            appendLine("[update] تم التنزيل (${apk.length() / 1024} KB). فتح المثبّت...")
            val ok = AutoUpdateManager.installApk(this@MainActivity, apk)
            if (!ok) appendLine("[update] فشل فتح المثبّت. تحقق من صلاحية تثبيت المصادر.")
        }
    }
}
KOT_MAIN

# ═════════════════════════════════════════════════════════════
# التحقق
# ═════════════════════════════════════════════════════════════
echo ""
echo "▶ [phase4] التحقق من التطابق"
echo ""
echo "─── ملفات Kotlin في core:"
ls -1 app/src/main/java/com/awlqy/terminal/core/*.kt | sed 's|.*/||'
echo ""
echo "─── R.id المستخدمة في MainActivity:"
grep -o "R\.id\.[a-z_A-Z]*" app/src/main/java/com/awlqy/terminal/MainActivity.kt | sort -u
echo ""
echo "─── id= في main_menu.xml:"
grep -o 'android:id="@+id/[a-z_A-Z]*"' app/src/main/res/menu/main_menu.xml | sed 's/android:id="@+id\///; s/"//' | sort -u
echo ""
echo "─── مفاتيح strings.xml المستخدمة:"
grep -o 'R\.string\.[a-z_A-Z]*' app/src/main/java/com/awlqy/terminal/MainActivity.kt | sort -u | head -n 20
echo ""

# تحقق ذكي
MISSING=$(grep -o 'R\.id\.[a-z_A-Z]*' app/src/main/java/com/awlqy/terminal/MainActivity.kt | sort -u | \
    sed 's/R\.id\.//' | while read id; do
        grep -q "id/$id" app/src/main/res/menu/main_menu.xml || echo "  ⚠ ناقص: $id"
    done)
if [ -n "$MISSING" ]; then
    echo "─── عناصر مفقودة:"
    echo "$MISSING"
else
    echo "✔ كل R.id متطابقة مع main_menu.xml"
fi
echo ""
echo "✔ [phase4] انتهى. الآن:"
echo "   git add -A"
echo "   git commit -m 'phase-4: auto-healing + apk builder + automation'"
echo "   git push"
