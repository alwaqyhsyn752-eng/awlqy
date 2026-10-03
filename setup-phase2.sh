#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · setup-phase2.sh — Terminal + Auto-Healing + Updater
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [phase2] إنشاء المجلدات..."
mkdir -p app/src/main/java/com/awlqy/terminal/core
mkdir -p app/src/main/java/com/awlqy/terminal/update
mkdir -p app/src/main/res/layout
mkdir -p app/src/main/res/menu
mkdir -p app/src/main/res/xml

# ─── 1. ArabicShaper.kt ─────────────────────────────────────
cat > app/src/main/java/com/awlqy/terminal/core/ArabicShaper.kt <<'EOF_AR'
package com.awlqy.terminal.core

import java.text.Bidi

/**
 * محرك معالجة النص العربي عبر java.text.Bidi المدمج في Android.
 * - يكشف الأسطر التي تحتاج bidi.
 * - يعيد ترتيب الحروف بصرياً عند الحاجة.
 * - تشكيل الحروف (connecting) يقوم به خط النظام تلقائياً.
 */
object ArabicShaper {

    fun needsBidi(text: String): Boolean {
        if (text.isEmpty()) return false
        return Bidi.requiresBidi(text.toCharArray(), 0, text.length)
    }

    fun reorderLine(line: String): String {
        if (line.isEmpty()) return line
        if (!needsBidi(line)) return line
        val chars = line.toCharArray()
        val bidi = Bidi(chars, 0, chars.size, Bidi.DIRECTION_DEFAULT_LEFT_TO_RIGHT)
        if (bidi.isLeftToRight) return line
        val levels = ByteArray(chars.size)
        bidi.getLevels(levels, chars.size)
        Bidi.reorderVisually(levels, 0, chars, 0, chars.size)
        return String(chars)
    }

    fun shape(text: String): String {
        if (text.isEmpty()) return text
        val sb = StringBuilder(text.length + 8)
        var i = 0
        var lineStart = 0
        while (i <= text.length) {
            if (i == text.length || text[i] == '\n') {
                val line = text.substring(lineStart, i)
                sb.append(reorderLine(line))
                if (i < text.length) sb.append('\n')
                lineStart = i + 1
            }
            i++
        }
        return sb.toString()
    }
}
EOF_AR

# ─── 2. ShellExecutor.kt ────────────────────────────────────
cat > app/src/main/java/com/awlqy/terminal/core/ShellExecutor.kt <<'EOF_SH'
package com.awlqy.terminal.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

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

    suspend fun run(
        command: String,
        workDir: File,
        extraEnv: Map<String, String> = emptyMap()
    ): ShellResult = withContext(Dispatchers.IO) {
        val start = System.currentTimeMillis()
        var exit = -1
        val out = StringBuilder()
        val err = StringBuilder()
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

            val p = pb.start()

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
            tOut.join(3000)
            tErr.join(3000)
        } catch (e: Exception) {
            err.append(e.message ?: e.javaClass.simpleName).append('\n')
        }
        ShellResult(exit, out.toString(), err.toString(), System.currentTimeMillis() - start)
    }

    /**
     * محرّك التشخيص الذكي: يقرأ stderr/stdout ويقترح حلاً فورياً.
     */
    fun diagnose(stderr: String, stdout: String): String? {
        val s = "$stderr\n$stdout"
        if (s.isBlank()) return null

        Regex("ModuleNotFoundError: No module named '([^']+)'").find(s)?.let {
            return "مكتبة Python مفقودة '${it.groupValues[1]}'. جرّب: pip install ${it.groupValues[1]}"
        }
        Regex("ImportError: cannot import name '([^']+)'").find(s)?.let {
            return "استيراد فاشل لـ '${it.groupValues[1]}'. تحقق من التثبيت أو اسم الوحدة."
        }
        Regex("Cannot find module '([^']+)'").find(s)?.let {
            return "حزمة Node.js مفقودة '${it.groupValues[1]}'. جرّب: npm install ${it.groupValues[1]}"
        }
        Regex("command not found|([^:\\s]+): not found").find(s)?.let {
            val name = it.groupValues.getOrNull(1).orEmpty().ifBlank { "الأمر" }
            return "'$name' غير مثبت. جرّب: pkg install ${'$'}name (عبر Termux) أو تحقق من PATH."
        }
        if (s.contains("No such file or directory")) {
            return "الملف/المجلد غير موجود. تحقق من المسار أو أنشئه."
        }
        if (s.contains("Permission denied")) {
            return "صلاحية مرفوضة. جرّب: chmod +x على الملف، أو شغّل بأمر مختلف."
        }
        if (s.contains("SyntaxError")) {
            return "خطأ بنيوي. تحقق من علامات الاقتباس، الأقواس، والمسافات البادئة."
        }
        if (s.contains("is a directory")) {
            return "هذا مسار مجلد، ليس ملفاً. استخدم ls لعرض المحتوى."
        }
        if (s.contains("No space left on device")) {
            return "المساحة ممتلئة. احذف الملفات غير الضرورية من cache/files."
        }
        if (s.contains("Cannot resolve host") || s.contains("Could not resolve host")) {
            return "تعذر الاتصال بالشبكة. تحقق من الإنترنت."
        }
        return null
    }

    /**
     * يعيد الإصلاح المقترح كأمر قابل للتنفيذ (أو null).
     */
    fun autoHealCommand(stderr: String, stdout: String): String? {
        val s = "$stderr\n$stdout"
        Regex("ModuleNotFoundError: No module named '([^']+)'").find(s)?.let {
            return "python -m pip install --no-input ${it.groupValues[1]} 2>&1 || echo 'pip غير متاح'"
        }
        Regex("Cannot find module '([^']+)'").find(s)?.let {
            return "npm install ${it.groupValues[1]} 2>&1 || echo 'npm غير متاح'"
        }
        return null
    }
}
EOF_SH

# ─── 3. AutoUpdateManager.kt ────────────────────────────────
cat > app/src/main/java/com/awlqy/terminal/update/AutoUpdateManager.kt <<'EOF_AU'
package com.awlqy.terminal.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.awlqy.terminal.BuildConfig
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * مدير التحديثات من GitHub Releases.
 * - يقرأ https://api.github.com/repos/{owner}/awlqy/releases/latest
 * - يقارن tag_name مع BuildConfig.VERSION_NAME
 * - ينزّل ملف APK إلى cacheDir ثم يفتح المثبّت عبر FileProvider
 */
object AutoUpdateManager {

    private const val OWNER = "alwaqyhsyn752-eng"
    private const val REPO = "awlqy"
    private const val API_URL = "https://api.github.com/repos/$OWNER/$REPO/releases/latest"
    private const val UA = "awlqy-updater-android"

    data class UpdateInfo(
        val tag: String,
        val notes: String,
        val apkUrl: String,
        val apkName: String,
        val hasUpdate: Boolean
    )

    fun checkLatest(ctx: Context): UpdateInfo? {
        var conn: HttpURLConnection? = null
        return try {
            val u = URL(API_URL)
            conn = u.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.setRequestProperty("User-Agent", UA)
            conn.setRequestProperty("Accept", "application/vnd.github+json")
            if (conn.responseCode != 200) return null

            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            val tag = json.optString("tag_name", "").trim()
            val notes = json.optString("body", "")
            val assets = json.optJSONArray("assets")

            var apkUrl = ""
            var apkName = "awlqy.apk"
            if (assets != null) {
                var i = 0
                while (i < assets.length()) {
                    val a = assets.getJSONObject(i)
                    val name = a.optString("name", "")
                    if (name.endsWith(".apk", ignoreCase = true)) {
                        apkUrl = a.optString("browser_download_url", "")
                        apkName = name
                        break
                    }
                    i++
                }
            }

            val current = BuildConfig.VERSION_NAME.trimStart('v', 'V')
            val latest = tag.trimStart('v', 'V')
            val hasUpdate = apkUrl.isNotBlank() && compareVersions(latest, current) > 0

            UpdateInfo(tag.ifBlank { "v?" }, notes, apkUrl, apkName, hasUpdate)
        } catch (_: Exception) {
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) { }
        }
    }

    fun compareVersions(a: String, b: String): Int {
        val pa = a.split('.').map { it.filter { c -> c.isDigit() }.toIntOrNull() ?: 0 }
        val pb = b.split('.').map { it.filter { c -> c.isDigit() }.toIntOrNull() ?: 0 }
        val n = maxOf(pa.size, pb.size)
        for (i in 0 until n) {
            val x = pa.getOrElse(i) { 0 }
            val y = pb.getOrElse(i) { 0 }
            if (x != y) return if (x > y) 1 else -1
        }
        return 0
    }

    fun downloadApk(ctx: Context, info: UpdateInfo, onProgress: (Int) -> Unit): File? {
        val dest = File(ctx.cacheDir, info.apkName)
        if (dest.exists()) dest.delete()
        var conn: HttpURLConnection? = null
        return try {
            val u = URL(info.apkUrl)
            conn = u.openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = true
            conn.connectTimeout = 20000
            conn.readTimeout = 60000
            conn.setRequestProperty("User-Agent", UA)
            val code = conn.responseCode
            if (code !in 200..299) return null

            val total = conn.contentLengthLong
            conn.inputStream.use { input ->
                dest.outputStream().use { output ->
                    val buf = ByteArray(64 * 1024)
                    var sum = 0L
                    var read = input.read(buf)
                    while (read > 0) {
                        output.write(buf, 0, read)
                        sum += read
                        if (total > 0) onProgress(((sum * 100L) / total).toInt())
                        read = input.read(buf)
                    }
                }
            }
            if (dest.length() < 1024L) return null
            dest
        } catch (_: Exception) {
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) { }
        }
    }

    fun installApk(ctx: Context, apk: File): Boolean {
        return try {
            val uri: Uri = FileProvider.getUriForFile(
                ctx,
                "${ctx.packageName}.fileprovider",
                apk
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
EOF_AU

# ─── 4. MainActivity.kt ─────────────────────────────────────
cat > app/src/main/java/com/awlqy/terminal/MainActivity.kt <<'EOF_MA'
package com.awlqy.terminal

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
import com.awlqy.terminal.core.ArabicShaper
import com.awlqy.terminal.core.ShellExecutor
import com.awlqy.terminal.databinding.ActivityMainBinding
import com.awlqy.terminal.update.AutoUpdateManager
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
    private var busy = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)

        binding.consoleText.movementMethod = ScrollingMovementMethod()

        printBanner()
        printSystemStatus()

        binding.runButton.setOnClickListener { runCommand() }
        binding.clearButton.setOnClickListener {
            buffer.setLength(0)
            binding.consoleText.text = ""
            printSystemStatus()
        }
        binding.inputEdit.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND ||
                actionId == EditorInfo.IME_ACTION_DONE) {
                runCommand()
                true
            } else false
        }

        lifecycleScope.launch { silentUpdateCheck() }
    }

    private fun printBanner() {
        appendLine("==========================================")
        appendLine("  awlqy Terminal & IDE  v${BuildConfig.VERSION_NAME}")
        appendLine("  المطوّر: حسين الخلاقي")
        appendLine("==========================================")
        appendLine("")
    }

    private fun printSystemStatus() {
        appendLine("[system] الاسم: awlqy Terminal & IDE")
        appendLine("[system] المطوّر: حسين الخلاقي")
        appendLine("[system] الحالة: Active · Auto-Healing Ready")
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "?"
        appendLine("[system] API: ${Build.VERSION.SDK_INT} · ABI: $abi")
        appendLine("[system] اكتب أمراً ثم اضغط تشغيل.")
        appendLine("")
    }

    private fun appendLine(line: String) {
        val shaped = ArabicShaper.shape(line)
        buffer.append(shaped).append('\n')
        render()
    }

    private fun appendRaw(text: String) {
        if (text.isEmpty()) return
        val shaped = ArabicShaper.shape(text)
        buffer.append(shaped)
        if (!shaped.endsWith('\n')) buffer.append('\n')
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
            Toast.makeText(this, "أمر قيد التنفيذ...", Toast.LENGTH_SHORT).show()
            return
        }
        val cmd = binding.inputEdit.text.toString().trim()
        if (cmd.isEmpty()) return
        binding.inputEdit.setText("")

        val ts = timeFmt.format(Date())
        appendLine("--- [$ts] \$ $cmd")
        busy = true
        binding.runButton.isEnabled = false

        lifecycleScope.launch {
            val home = File(filesDir, "home").apply { mkdirs() }
            val result = ShellExecutor.run(cmd, home)
            if (result.stdout.isNotBlank()) appendRaw(result.stdout)
            if (result.stderr.isNotBlank()) appendRaw("[stderr]\n" + result.stderr)

            val diag = ShellExecutor.diagnose(result.stderr, result.stdout)
            if (diag != null) appendLine("[auto-heal] $diag")

            appendLine("--- exit=${result.exitCode} · ${result.durationMs}ms")
            appendLine("")
            busy = false
            binding.runButton.isEnabled = true
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.main_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_settings -> { showSettings(); true }
            R.id.action_update   -> { checkUpdatesManually(); true }
            R.id.action_about    -> { showAbout(); true }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun showSettings() {
        val msg = buildString {
            appendLine("التطبيق: awlqy Terminal & IDE")
            appendLine("الإصدار: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            appendLine("المطوّر: حسين الخلاقي")
            appendLine("GitHub: alwaqyhsyn752-eng")
            appendLine("الحالة: Active · Auto-Healing Ready")
            appendLine("نوع البناء: ${BuildConfig.BUILD_TYPE}")
            appendLine("Package: $packageName")
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("الإعدادات")
            .setMessage(ArabicShaper.shape(msg))
            .setPositiveButton("حسناً", null)
            .setNeutralButton("التحقق من التحديثات") { _, _ -> checkUpdatesManually() }
            .show()
    }

    private fun showAbout() {
        val msg = buildString {
            appendLine("awlqy — طرفية ذكية وبيئة تطوير متكاملة.")
            appendLine("مبنية بـ Kotlin + Android Runtime.")
            appendLine("© 2025 حسين الخلاقي")
            appendLine("رخصة MIT")
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("حول التطبيق")
            .setMessage(ArabicShaper.shape(msg))
            .setPositiveButton("إغلاق", null)
            .show()
    }

    private suspend fun silentUpdateCheck() {
        val info = withContext(Dispatchers.IO) {
            AutoUpdateManager.checkLatest(this@MainActivity)
        }
        if (info != null && info.hasUpdate) {
            appendLine("[update] إصدار جديد متوفر: ${info.tag} — من القائمة افتح (تحقق من التحديثات).")
        }
    }

    private fun checkUpdatesManually() {
        lifecycleScope.launch {
            appendLine("[update] جاري التحقق من GitHub Releases...")
            val info = withContext(Dispatchers.IO) {
                AutoUpdateManager.checkLatest(this@MainActivity)
            }
            if (info == null) {
                appendLine("[update] تعذر الاتصال بـ GitHub.")
                return@launch
            }
            if (!info.hasUpdate) {
                appendLine("[update] أنت على أحدث إصدار (${BuildConfig.VERSION_NAME}).")
                return@launch
            }
            appendLine("[update] إصدار جديد: ${info.tag}")
            MaterialAlertDialogBuilder(this@MainActivity)
                .setTitle("تحديث متوفر: ${info.tag}")
                .setMessage(ArabicShaper.shape(info.notes.ifBlank { "لا توجد ملاحظات." }))
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
                    if (pct % 25 == 0) {
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
EOF_MA

# ─── 5. activity_main.xml ───────────────────────────────────
cat > app/src/main/res/layout/activity_main.xml <<'EOF_LAY'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/awlqy_bg"
    android:orientation="vertical"
    android:fitsSystemWindows="true">

    <com.google.android.material.appbar.MaterialToolbar
        android:id="@+id/toolbar"
        android:layout_width="match_parent"
        android:layout_height="?attr/actionBarSize"
        android:background="@color/awlqy_surface"
        app:title="@string/app_name"
        app:titleTextColor="@color/awlqy_accent"/>

    <ScrollView
        android:id="@+id/consoleScroll"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:background="@color/awlqy_terminal_bg"
        android:fillViewport="true"
        android:padding="8dp"
        android:scrollbars="vertical">

        <TextView
            android:id="@+id/consoleText"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:fontFamily="monospace"
            android:text=""
            android:textColor="@color/awlqy_terminal_text"
            android:textIsSelectable="true"
            android:textSize="12sp"/>
    </ScrollView>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="@color/awlqy_surface"
        android:orientation="horizontal"
        android:padding="6dp">

        <EditText
            android:id="@+id/inputEdit"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:background="@color/awlqy_glass"
            android:hint="@string/hint_command"
            android:imeOptions="actionSend|flagNoFullscreen"
            android:inputType="text|textNoSuggestions|textVisiblePassword|textMultiLine"
            android:maxLines="3"
            android:padding="10dp"
            android:textColor="@color/awlqy_terminal_text"
            android:textColorHint="@color/awlqy_text_dim"
            android:textDirection="locale"/>

        <Button
            android:id="@+id/clearButton"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="4dp"
            android:backgroundTint="@color/awlqy_glass"
            android:text="@string/action_clear"
            android:textColor="@color/awlqy_text"/>

        <Button
            android:id="@+id/runButton"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="4dp"
            android:backgroundTint="@color/awlqy_accent"
            android:text="@string/action_run"
            android:textColor="@color/awlqy_bg"/>
    </LinearLayout>
</LinearLayout>
EOF_LAY

# ─── 6. main_menu.xml ───────────────────────────────────────
cat > app/src/main/res/menu/main_menu.xml <<'EOF_MENU'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto">
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
EOF_MENU

# ─── 7. file_paths.xml ──────────────────────────────────────
cat > app/src/main/res/xml/file_paths.xml <<'EOF_FP'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="updates" path="."/>
    <files-path name="files" path="."/>
    <external-cache-path name="ext_updates" path="."/>
    <external-files-path name="ext_files" path="."/>
</paths>
EOF_FP

# ─── 8. strings.xml ─────────────────────────────────────────
cat > app/src/main/res/values/strings.xml <<'EOF_STR'
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
</resources>
EOF_STR

# ─── 9. colors.xml ──────────────────────────────────────────
cat > app/src/main/res/values/colors.xml <<'EOF_COL'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="awlqy_bg">#020617</color>
    <color name="awlqy_surface">#0F172A</color>
    <color name="awlqy_glass">#1E293B</color>
    <color name="awlqy_accent">#22D3EE</color>
    <color name="awlqy_accent_dim">#0E7490</color>
    <color name="awlqy_text">#E2E8F0</color>
    <color name="awlqy_text_dim">#94A3B8</color>
    <color name="awlqy_error">#F87171</color>
    <color name="awlqy_terminal_bg">#000000</color>
    <color name="awlqy_terminal_text">#4ADE80</color>
    <color name="ic_launcher_background">#020617</color>
</resources>
EOF_COL

# ─── 10. themes.xml ─────────────────────────────────────────
cat > app/src/main/res/values/themes.xml <<'EOF_THM'
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.Awlqy" parent="Theme.Material3.Dark.NoActionBar">
        <item name="colorPrimary">@color/awlqy_accent</item>
        <item name="colorOnPrimary">@color/awlqy_bg</item>
        <item name="colorSurface">@color/awlqy_surface</item>
        <item name="colorOnSurface">@color/awlqy_text</item>
        <item name="android:colorBackground">@color/awlqy_bg</item>
        <item name="android:statusBarColor">@color/awlqy_surface</item>
        <item name="android:navigationBarColor">@color/awlqy_bg</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowLightNavigationBar" tools:targetApi="27">false</item>
        <item name="android:windowBackground">@color/awlqy_bg</item>
    </style>
</resources>
EOF_THM

# ─── 11. AndroidManifest.xml (مع FileProvider) ──────────────
cat > app/src/main/AndroidManifest.xml <<'EOF_MAN'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28" tools:ignore="ScopedStorage"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>

    <application
        android:name=".AwlqyApp"
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:requestLegacyExternalStorage="true"
        android:roundIcon="@mipmap/ic_launcher"
        android:supportsRtl="true"
        android:usesCleartextTraffic="true"
        android:largeHeap="true"
        android:theme="@style/Theme.Awlqy"
        tools:targetApi="34">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|keyboardHidden|uiMode"
            android:windowSoftInputMode="adjustResize"
            android:launchMode="singleTask">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths"/>
        </provider>

        <meta-data
            android:name="com.awlqy.DEVELOPER"
            android:value="حسين الخلاقي"/>
        <meta-data
            android:name="com.awlqy.GITHUB"
            android:value="alwaqyhsyn752-eng"/>
    </application>
</manifest>
EOF_MAN

# ─── 12. verification ───────────────────────────────────────
echo ""
echo "▶ [phase2] الملفات:"
find app/src/main/java -name "*.kt" | sort
find app/src/main/res/layout -name "*.xml" | sort
find app/src/main/res/menu -name "*.xml" | sort
find app/src/main/res/xml -name "*.xml" | sort
echo ""
echo "✔ [phase2] انتهى — Terminal + Auto-Healing + Updater جاهزون."
