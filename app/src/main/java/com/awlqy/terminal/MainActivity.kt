ackage com.awlqy.terminal

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
import com.awlqy.terminal.core.AutoUpdateManager
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

    // ─── Banner / Status ─────────────────────────────────

    private fun printBanner() {
        appendLine("==========================================")
        appendLine("  awlqy Terminal & IDE  v$appVersionName")
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
        appendLine("[system] جرّب: ls · pwd · id · echo hello · date")
        appendLine("")
    }

    private fun clearConsole() {
        buffer.setLength(0)
        binding.consoleText.text = ""
        printSystemStatus()
    }

    // ─── Buffer ──────────────────────────────────────────

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

    // ─── Execution ───────────────────────────────────────

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

            val diag = ShellExecutor.diagnose(result.stderr, result.stdout)
            if (diag != null) appendLine("[auto-heal] ⚕ $diag")

            val fix = ShellExecutor.autoHealCommand(result.stderr, result.stdout)
            if (fix != null) appendLine("[auto-fix]  » $fix")

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

    // ─── Input helpers ───────────────────────────────────

    private fun insertIntoInput(s: String) {
        val cur = binding.inputEdit.text?.toString().orEmpty()
        val sel = binding.inputEdit.selectionStart.coerceAtLeast(0)
        val next = cur.substring(0, sel) + s + cur.substring(sel)
        binding.inputEdit.setText(next)
        binding.inputEdit.setSelection(sel + s.length)
    }

    private fun navigateHistory(direction: Int) {
        if (history.isEmpty()) return
        if (historyIndex == -1) historyIndex = history.size
        historyIndex = (historyIndex + direction).coerceIn(0, history.size)
        val cmd = if (historyIndex >= history.size) "" else history[historyIndex]
        binding.inputEdit.setText(cmd)
        binding.inputEdit.setSelection(cmd.length)
    }

    // ─── Menu ────────────────────────────────────────────

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
            appendLine("الإصدار: $appVersionName")
            appendLine("المطوّر: حسين الخلاقي")
            appendLine("GitHub: alwaqyhsyn752-eng")
            appendLine("الحالة: Active · Auto-Healing Ready")
            appendLine("Package: $packageName")
            appendLine("عدد الأوامر في السجل: ${history.size}")
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
                    if (pct in intArrayOf(25, 50, 75, 100)) {
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
