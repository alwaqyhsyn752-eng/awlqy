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
