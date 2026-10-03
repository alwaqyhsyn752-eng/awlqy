#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · terminal-ui.sh — Terminal UI كامل في ملف واحد
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [terminal-ui] كتابة الملفين..."

mkdir -p app/src/main/java/com/awlqy/terminal
mkdir -p app/src/main/res/layout

# ═════════════════════════════════════════════════════════════
# 1. activity_main.xml
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/layout/activity_main.xml <<'XML_MAIN'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000"
    android:fitsSystemWindows="true">

    <TextView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:alpha="0.05"
        android:fontFamily="monospace"
        android:gravity="center"
        android:letterSpacing="0.25"
        android:shadowColor="#22D3EE"
        android:shadowDx="0"
        android:shadowDy="0"
        android:shadowRadius="30"
        android:text="Q · W"
        android:textColor="#22D3EE"
        android:textSize="120sp"
        android:textStyle="bold"/>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="vertical">

        <com.google.android.material.appbar.MaterialToolbar
            android:id="@+id/toolbar"
            android:layout_width="match_parent"
            android:layout_height="?attr/actionBarSize"
            android:background="#000000"
            app:title="awlqy"
            app:titleTextColor="#22D3EE"/>

        <HorizontalScrollView
            android:layout_width="match_parent"
            android:layout_height="40dp"
            android:background="#0A0E14"
            android:scrollbars="none">

            <LinearLayout
                android:id="@+id/sessionTabs"
                android:layout_width="wrap_content"
                android:layout_height="match_parent"
                android:gravity="center_vertical"
                android:orientation="horizontal"
                android:paddingStart="6dp"
                android:paddingEnd="6dp"/>
        </HorizontalScrollView>

        <ScrollView
            android:id="@+id/consoleScroll"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:background="#000000"
            android:fillViewport="true"
            android:padding="8dp"
            android:scrollbars="vertical">

            <TextView
                android:id="@+id/consoleText"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:fontFamily="monospace"
                android:text=""
                android:textColor="#E2E8F0"
                android:textIsSelectable="true"
                android:textSize="12sp"/>
        </ScrollView>

        <HorizontalScrollView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="#0A0E14"
            android:scrollbars="none">

            <LinearLayout
                android:id="@+id/accessoryBar"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:gravity="center_vertical"
                android:orientation="horizontal"
                android:padding="4dp"/>
        </HorizontalScrollView>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="#0A0E14"
            android:orientation="horizontal"
            android:padding="6dp">

            <TextView
                android:id="@+id/promptLabel"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center_vertical"
                android:fontFamily="monospace"
                android:paddingEnd="6dp"
                android:text="awlqy@android:~$ "
                android:textColor="#4ADE80"
                android:textSize="12sp"/>

            <EditText
                android:id="@+id/inputEdit"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:background="#1E293B"
                android:fontFamily="monospace"
                android:hint="اكتب أمراً…"
                android:imeOptions="actionSend|flagNoFullscreen"
                android:inputType="text|textNoSuggestions|textVisiblePassword|textMultiLine"
                android:maxLines="3"
                android:padding="10dp"
                android:textColor="#E2E8F0"
                android:textColorHint="#64748B"
                android:textSize="12sp"/>

            <Button
                android:id="@+id/runButton"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_marginStart="6dp"
                android:backgroundTint="#22D3EE"
                android:fontFamily="monospace"
                android:minWidth="0dp"
                android:paddingStart="12dp"
                android:paddingEnd="12dp"
                android:text="RUN"
                android:textColor="#000000"/>
        </LinearLayout>
    </LinearLayout>
</FrameLayout>
XML_MAIN

# ═════════════════════════════════════════════════════════════
# 2. MainActivity.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/MainActivity.kt <<'KOT_MAIN'
package com.awlqy.terminal

import android.content.Context
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.method.ScrollingMovementMethod
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.awlqy.terminal.databinding.ActivityMainBinding
import com.google.android.material.button.MaterialButton
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    private val C_CYAN   = 0xFF22D3EE.toInt()
    private val C_GREEN  = 0xFF4ADE80.toInt()
    private val C_AMBER  = 0xFFFBBF24.toInt()
    private val C_RED    = 0xFFEF4444.toInt()
    private val C_TEXT   = 0xFFE2E8F0.toInt()
    private val C_DIM    = 0xFF64748B.toInt()
    private val C_YELLOW = 0xFFFACC15.toInt()
    private val C_WHITE  = 0xFFFFFFFF.toInt()

    class Session(val name: String, var cwd: File) {
        val buffer = SpannableStringBuilder()
        val history = ArrayList<String>()
        var historyIndex = -1
        @Volatile var busy = false
    }

    private val sessions = ArrayList<Session>()
    private var activeIdx = 0
    private var vipUnlocked = false

    @Volatile private var proc: Process? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)

        binding.consoleText.movementMethod = ScrollingMovementMethod()
        binding.consoleText.typeface = Typeface.MONOSPACE
        binding.consoleText.textSize = 12f

        val home = File(filesDir, "home").apply { mkdirs() }
        sessions.add(Session("main", home))

        buildAccessoryBar()
        wireInput()
        renderTabs()
        showMotd(sessions[0])
        renderConsole()
    }

    override fun onResume() {
        super.onResume()
        vipUnlocked = getSharedPreferences("awlqy", Context.MODE_PRIVATE)
            .getBoolean("vip", false)
    }

    override fun onPause() {
        super.onPause()
        getSharedPreferences("awlqy", Context.MODE_PRIVATE).edit()
            .putBoolean("vip", vipUnlocked).apply()
    }

    private fun showMotd(s: Session) {
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "?"
        val motd = buildString {
            append("\n")
            append("  +==========================================+\n")
            append("  |   a w l q y   ·   S m a r t   T e r m    |\n")
            append("  |   v1.0.0  |  Q-W  |  حسين الخلاقي        |\n")
            append("  +==========================================+\n")
            append("\n")
            append("  [system]  Android API : ").append(Build.VERSION.SDK_INT).append("\n")
            append("  [system]  ABI         : ").append(abi).append("\n")
            append("  [system]  HOME        : ").append(s.cwd.absolutePath).append("\n")
            append("  [system]  Storage     : ").append(freeSpaceText()).append("\n")
            append("\n")
            append("  [guides]  root-repo   : termux root-repo\n")
            append("  [guides]  x11-repo    : termux x11-repo\n")
            append("  [guides]  aapt2/d8    : files/usr/bin\n")
            append("\n")
            append("  اكتب 'help' للأوامر، أو 'حسين الخلاقي' للوضع الخاص.\n")
            append("\n")
        }
        appendColored(s, motd, C_TEXT)
        appendPromptLine(s)
    }

    private fun freeSpaceText(): String {
        return try {
            val st = android.os.StatFs(filesDir.absolutePath)
            val mb = st.availableBytes / (1024L * 1024L)
            if (mb > 1024) "${mb / 1024} GB free" else "$mb MB free"
        } catch (_: Exception) { "n/a" }
    }

    private fun appendPromptLine(s: Session) {
        val prompt = "awlqy@android:~$ "
        val start = s.buffer.length
        s.buffer.append(prompt)
        span(s.buffer, start, start + 5, C_CYAN)
        span(s.buffer, start + 5, start + 6, C_WHITE)
        span(s.buffer, start + 6, start + 13, C_GREEN)
        span(s.buffer, start + 13, start + 14, C_AMBER)
        span(s.buffer, start + 14, start + 15, C_WHITE)
    }

    private fun appendColored(s: Session, text: String, color: Int) {
        val start = s.buffer.length
        s.buffer.append(text)
        span(s.buffer, start, s.buffer.length, color)
    }

    private fun appendStreamed(s: Session, text: String) {
        val start = s.buffer.length
        s.buffer.append(text)
        val err = Regex("(?i)\\b(error|failed|denied|not found|fatal|exception)\\b")
        val ok  = Regex("(?i)\\b(ok|success|done|installed|finished|ready)\\b")
        err.findAll(text).forEach {
            span(s.buffer, start + it.range.first, start + it.range.last + 1, C_RED)
        }
        ok.findAll(text).forEach {
            span(s.buffer, start + it.range.first, start + it.range.last + 1, C_GREEN)
        }
    }

    private fun span(b: SpannableStringBuilder, a: Int, c: Int, color: Int) {
        if (a < 0 || c > b.length || a >= c) return
        b.setSpan(ForegroundColorSpan(color), a, c, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    }

    private fun renderConsole() {
        val s = sessions.getOrNull(activeIdx) ?: return
        binding.consoleText.text = s.buffer
        binding.consoleScroll.post { binding.consoleScroll.fullScroll(View.FOCUS_DOWN) }
    }

    private fun renderTabs() {
        val bar = binding.sessionTabs
        bar.removeAllViews()
        for (i in sessions.indices) {
            val s = sessions[i]
            val tv = TextView(this).apply {
                text = s.name
                typeface = Typeface.MONOSPACE
                textSize = 11f
                gravity = Gravity.CENTER
                setPadding(28, 12, 28, 12)
                setTextColor(if (i == activeIdx) C_CYAN else C_DIM)
                setBackgroundColor(if (i == activeIdx) 0xFF1E293B.toInt() else 0xFF0A0E14.toInt())
                setOnClickListener {
                    activeIdx = i
                    renderTabs()
                    renderConsole()
                }
                setOnLongClickListener {
                    if (sessions.size <= 1) {
                        Toast.makeText(this@MainActivity, "لا يمكن إغلاق الجلسة الأخيرة", Toast.LENGTH_SHORT).show()
                        true
                    } else {
                        MaterialAlertDialogBuilder(this@MainActivity)
                            .setTitle("إغلاق الجلسة")
                            .setMessage("هل تريد إغلاق '${s.name}'؟")
                            .setPositiveButton("إغلاق") { _, _ ->
                                sessions.removeAt(i)
                                if (activeIdx >= sessions.size) activeIdx = sessions.size - 1
                                renderTabs()
                                renderConsole()
                            }
                            .setNegativeButton("إلغاء", null)
                            .show()
                        true
                    }
                }
            }
            bar.addView(tv)
        }
        val add = TextView(this).apply {
            text = "+ NEW"
            typeface = Typeface.MONOSPACE
            textSize = 11f
            gravity = Gravity.CENTER
            setPadding(28, 12, 28, 12)
            setTextColor(C_GREEN)
            setBackgroundColor(0xFF0A0E14.toInt())
            setOnClickListener { newSession() }
        }
        bar.addView(add)
    }

    private fun newSession() {
        val home = File(filesDir, "home").apply { mkdirs() }
        val s = Session("s${sessions.size + 1}", home)
        sessions.add(s)
        activeIdx = sessions.size - 1
        showMotd(s)
        renderTabs()
        renderConsole()
    }

    private fun buildAccessoryBar() {
        val bar = binding.accessoryBar
        val items: List<Pair<String, () -> Unit>> = listOf(
            "NEW"    to { newSession() },
            "KB"     to { toggleKeyboard() },
            "CTRL+C" to { killCurrent() },
            "ALT"    to { Toast.makeText(this, "Alt modifier", Toast.LENGTH_SHORT).show() },
            "TAB"    to { insertInput("\t") },
            "ESC"    to { binding.inputEdit.setText("") },
            "$"      to { insertInput("$") },
            "/"      to { insertInput("/") },
            "|"      to { insertInput("|") },
            "~"      to { insertInput("~") },
            "_"      to { insertInput("_") },
            "^"      to { historyMove(-1) },
            "v"      to { historyMove(+1) },
            "<"      to { moveCursor(-1) },
            ">"      to { moveCursor(+1) }
        )
        val density = resources.displayMetrics.density
        val w = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            (38 * density).toInt()
        ).apply { marginEnd = (4 * density).toInt() }
        val pad = (12 * density).toInt()
        for ((label, act) in items) {
            val btn = MaterialButton(this).apply {
                text = label
                textSize = 11f
                typeface = Typeface.MONOSPACE
                minWidth = 0
                minHeight = 0
                insetTop = 0
                insetBottom = 0
                setPadding(pad, 0, pad, 0)
                layoutParams = w
                setTextColor(C_CYAN)
                setBackgroundColor(0xFF1E293B.toInt())
                setOnClickListener { act() }
            }
            bar.addView(btn)
        }
    }

    private fun toggleKeyboard() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (binding.inputEdit.hasFocus()) {
            imm.hideSoftInputFromWindow(binding.inputEdit.windowToken, 0)
        } else {
            binding.inputEdit.requestFocus()
            imm.showSoftInput(binding.inputEdit, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun insertInput(s: String) {
        val e = binding.inputEdit
        val cur = e.text?.toString().orEmpty()
        val sel = e.selectionStart.coerceIn(0, cur.length)
        e.setText(cur.substring(0, sel) + s + cur.substring(sel))
        e.setSelection(sel + s.length)
    }

    private fun moveCursor(d: Int) {
        val e = binding.inputEdit
        val max = e.text?.length ?: 0
        e.setSelection((e.selectionStart + d).coerceIn(0, max))
    }

    private fun historyMove(dir: Int) {
        val s = sessions.getOrNull(activeIdx) ?: return
        if (s.history.isEmpty()) return
        if (s.historyIndex == -1) s.historyIndex = s.history.size
        s.historyIndex = (s.historyIndex + dir).coerceIn(0, s.history.size)
        val cmd = if (s.historyIndex >= s.history.size) "" else s.history[s.historyIndex]
        binding.inputEdit.setText(cmd)
        binding.inputEdit.setSelection(cmd.length)
    }

    private fun killCurrent() {
        val s = sessions.getOrNull(activeIdx) ?: return
        if (s.busy) {
            try { proc?.destroy() } catch (_: Exception) {}
            appendColored(s, "\n^C (signal sent)\n", C_RED)
            s.busy = false
            renderConsole()
        } else {
            binding.inputEdit.setText("")
        }
    }

    private fun wireInput() {
        binding.runButton.setOnClickListener { runFromInput() }
        binding.inputEdit.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND || actionId == EditorInfo.IME_ACTION_DONE) {
                runFromInput(); true
            } else false
        }
    }

    private fun runFromInput() {
        val cmd = binding.inputEdit.text.toString().trim()
        if (cmd.isEmpty()) return
        binding.inputEdit.setText("")
        executeCommand(cmd)
    }

    private fun executeCommand(cmd: String) {
        val s = sessions.getOrNull(activeIdx) ?: return
        if (s.busy) {
            Toast.makeText(this, "قيد التنفيذ… CTRL+C للإلغاء", Toast.LENGTH_SHORT).show()
            return
        }

        appendColored(s, "$cmd\n", C_WHITE)

        if (s.history.isEmpty() || s.history.last() != cmd) s.history.add(cmd)
        if (s.history.size > 300) s.history.removeAt(0)
        s.historyIndex = -1

        if (!vipUnlocked && (cmd == "حسين الخلاقي" || cmd.equals("gemini", true))) {
            triggerVip(s)
            appendPromptLine(s)
            renderConsole()
            return
        }

        when (cmd) {
            "help"  -> { printHelp(s); appendPromptLine(s); renderConsole(); return }
            "clear" -> { s.buffer.clear(); appendPromptLine(s); renderConsole(); return }
            "motd"  -> { showMotd(s); renderConsole(); return }
            "vip"   -> {
                appendColored(s, if (vipUnlocked) "VIP mode is already active\n"
                                       else "لم يتم تفعيله بعد. جرّب: حسين الخلاقي\n",
                              if (vipUnlocked) C_GREEN else C_DIM)
                appendPromptLine(s); renderConsole(); return
            }
        }

        s.busy = true

        lifecycleScope.launch {
            val code = withContext(Dispatchers.IO) {
                runShell(cmd, s.cwd) { line ->
                    runOnUiThread {
                        appendStreamed(s, line + "\n")
                        renderConsole()
                    }
                }
            }
            if (code != 0) {
                val hint = when (code) {
                    127 -> "الأمر غير موجود. تحقق من الاسم أو ثبّته."
                    126 -> "صلاحية مرفوضة. جرّب: chmod +x <file>"
                    130 -> "تم الإلغاء بإشارة SIGINT."
                    else -> "فشل التنفيذ (exit=$code). راجع المخرجات."
                }
                appendColored(s, "[auto-heal] $hint\n", C_YELLOW)
            }
            s.busy = false
            appendPromptLine(s)
            renderConsole()
        }
    }

    private fun runShell(cmd: String, cwd: File, onLine: (String) -> Unit): Int {
        return try {
            val pb = ProcessBuilder("/system/bin/sh", "-c", cmd)
            pb.directory(cwd)
            pb.redirectErrorStream(true)
            val env = pb.environment()
            env["HOME"] = cwd.absolutePath
            env["TERM"] = "xterm-256color"
            env["PATH"] = "${filesDir.absolutePath}/usr/bin:/system/bin:/system/xbin"
            val p = pb.start()
            proc = p
            BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                var line = r.readLine()
                while (line != null) {
                    onLine(line)
                    line = r.readLine()
                }
            }
            p.waitFor()
        } catch (e: Exception) {
            onLine("Error: ${e.message ?: e.javaClass.simpleName}")
            -1
        } finally {
            proc = null
        }
    }

    private fun triggerVip(s: Session) {
        vipUnlocked = true
        val art = "\n" +
            "       ####  #   # ### ####\n" +
            "       #   # #   #  #  #   #\n" +
            "       #   # #   #  #  ####\n" +
            "       #   # #   #  #  #\n" +
            "       ####   ###  ### #\n" +
            "\n" +
            "       V I P   M O D E   ·   U N L O C K E D\n" +
            "       ---------------------------------\n" +
            "       [+] Unrestricted root simulation\n" +
            "       [+] Advanced APK tools enabled\n" +
            "       [+] Multi-thread execution\n" +
            "       [+] AI copilot online\n" +
            "       ---------------------------------\n" +
            "       developed by حسين الخلاقي\n\n"
        appendColored(s, art, C_GREEN)
    }

    private fun printHelp(s: Session) {
        val h = "awlqy -- commands\n" +
            "---------------------------------\n" +
            "  help              هذه القائمة\n" +
            "  clear             مسح الشاشة\n" +
            "  motd              عرض البانر\n" +
            "  vip               حالة الوضع الخاص\n" +
            "  ls / pwd / id     أوامر النظام\n" +
            "  echo ...          طباعة\n" +
            "  <أي أمر shell>    يُنفّذ عبر /system/bin/sh\n\n" +
            "اختصارات:\n" +
            "  ^ v               سجل الأوامر\n" +
            "  < >               حركة المؤشر\n" +
            "  CTRL+C            إلغاء العملية الحالية\n\n" +
            "الوضع الخاص: اكتب 'حسين الخلاقي' أو 'gemini'\n\n"
        appendColored(s, h, C_TEXT)
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menu.add(0, 1, 0, "محرر الكود")
        menu.add(0, 2, 1, "الإعدادات")
        menu.add(0, 3, 2, "حول التطبيق")
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            1 -> { openEditor(); true }
            2 -> { showSettings(); true }
            3 -> { showAbout(); true }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun openEditor() {
        val editor = EditText(this).apply {
            typeface = Typeface.MONOSPACE
            textSize = 13f
            setTextColor(C_TEXT)
            setBackgroundColor(0xFF0A0E14.toInt())
            setPadding(24, 24, 24, 24)
            gravity = Gravity.TOP or Gravity.START
            minLines = 12
            inputType = android.text.InputType.TYPE_CLASS_TEXT or
                        android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                        android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            hint = "# اكتب كودك هنا"
            setText("#!/system/bin/sh\necho hello from awlqy editor\n")
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("محرر الكود")
            .setView(editor)
            .setPositiveButton("حفظ") { _, _ -> saveEditorFile(editor.text.toString(), false) }
            .setNeutralButton("تشغيل الآن") { _, _ -> saveEditorFile(editor.text.toString(), true) }
            .setNegativeButton("إلغاء", null)
            .show()
    }

    private fun saveEditorFile(content: String, run: Boolean) {
        val name = "script_${System.currentTimeMillis()}.sh"
        val f = File(sessions[activeIdx].cwd, name)
        try {
            f.writeText(content)
            f.setExecutable(true)
            if (run) executeCommand("sh ${f.absolutePath}")
            else Toast.makeText(this, "حُفظ: $name", Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Toast.makeText(this, "فشل: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    private fun showSettings() {
        val msg = "التطبيق: awlqy Terminal & IDE\n" +
            "الإصدار: 1.0.0\n" +
            "المطوّر: حسين الخلاقي\n" +
            "GitHub: alwaqyhsyn752-eng\n" +
            "Auto-Healing: مفعّل\n" +
            "Background Service: Phase 3\n" +
            "عدد الجلسات: ${sessions.size}\n" +
            "VIP: " + (if (vipUnlocked) "مفعّل" else "مقفل") + "\n"
        MaterialAlertDialogBuilder(this)
            .setTitle("الإعدادات")
            .setMessage(msg)
            .setPositiveButton("حسناً", null)
            .show()
    }

    private fun showAbout() {
        MaterialAlertDialogBuilder(this)
            .setTitle("حول التطبيق")
            .setMessage("awlqy -- طرفية ذكية وبيئة تطوير متكاملة.\n(c) 2025 حسين الخلاقي -- MIT")
            .setPositiveButton("إغلاق", null)
            .show()
    }
}
KOT_MAIN

echo ""
echo "▶ [terminal-ui] التحقق:"
echo "  layout : $(wc -l < app/src/main/res/layout/activity_main.xml) سطر"
echo "  kotlin : $(wc -l < app/src/main/java/com/awlqy/terminal/MainActivity.kt) سطر"
echo ""
echo "▶ [terminal-ui] أول سطر من MainActivity.kt:"
head -n 1 app/src/main/java/com/awlqy/terminal/MainActivity.kt
echo ""
echo "▶ [terminal-ui] لا وجود لـ ViewPager2 / Fragment / Service:"
grep -c "ViewPager2\|Fragment\|TerminalService" \
    app/src/main/java/com/awlqy/terminal/MainActivity.kt || echo "  نظيف"
echo ""
echo "✔ [terminal-ui] انتهى."
echo ""
echo "   git add -A"
echo "   git commit -m 'phase-2: full interactive terminal UI'"
echo "   git push"
