#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · fix5b.sh — اعتماديات + SessionManager + Highlighter
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [fix5b] تحديث app/build.gradle.kts — إضافة ViewPager2 + Fragment-KTX"

cat > app/build.gradle.kts <<'GRADLE_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.awlqy.terminal"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.awlqy.terminal"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isDebuggable = true
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/*.kotlin_module",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*"
            )
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.fragment:fragment-ktx:1.8.2")
    implementation("androidx.viewpager2:viewpager2:1.1.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.jakewharton.timber:timber:5.0.1")
}
GRADLE_EOF

echo "▶ [fix5b] إعادة كتابة SessionManager.kt (StringBuilder بدل Spannable)"

cat > app/src/main/java/com/awlqy/terminal/core/SessionManager.kt <<'KOT_1'
package com.awlqy.terminal.core

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

object SessionManager {

    class Session(
        val id: String,
        val name: String,
        var cwd: File
    ) {
        val buffer: StringBuilder = StringBuilder()
        val history: MutableList<String> = ArrayList()
        @Volatile var historyIndex: Int = -1
        @Volatile var busy: Boolean = false
        @Volatile var lastExit: Int = 0
    }

    interface Listener {
        fun onSessionChanged(id: String)
        fun onSessionsListChanged()
        fun onActiveChanged(id: String)
    }

    private val sessions = ArrayList<Session>()
    private val listeners = LinkedHashSet<Listener>()

    @Volatile private var activeId: String = ""
    @Volatile private var homeDir: File? = null
    @Volatile private var appContext: Context? = null

    fun attachHome(home: File) {
        homeDir = home
        if (!home.exists()) home.mkdirs()
    }

    fun attachContext(ctx: Context) {
        appContext = ctx.applicationContext
    }

    fun home(): File = homeDir ?: File("/data/local/tmp")

    @Synchronized fun addListener(l: Listener) { listeners.add(l) }
    @Synchronized fun removeListener(l: Listener) { listeners.remove(l) }

    @Synchronized fun list(): List<Session> = ArrayList(sessions)

    @Synchronized fun active(): Session? =
        sessions.firstOrNull { it.id == activeId } ?: sessions.firstOrNull()

    @Synchronized fun setActive(id: String) {
        if (activeId == id) return
        activeId = id
        notifyActive(id)
    }

    @Synchronized fun create(name: String? = null, cwd: File? = null): Session {
        val n = (name ?: "session-${System.currentTimeMillis() % 100000}").trim()
        val s = Session(
            id = UUID.randomUUID().toString().take(8),
            name = n,
            cwd = (cwd ?: home()).apply { mkdirs() }
        )
        sessions.add(s)
        if (activeId.isEmpty()) activeId = s.id
        notifyList()
        notifyActive(activeId)
        return s
    }

    @Synchronized fun close(id: String) {
        sessions.removeAll { it.id == id }
        if (activeId == id) activeId = sessions.firstOrNull()?.id ?: ""
        notifyList()
        notifyActive(activeId)
        persist()
    }

    @Synchronized fun append(sessionId: String, text: CharSequence) {
        val s = sessions.firstOrNull { it.id == sessionId } ?: return
        s.buffer.append(text)
        trim(s.buffer, 200_000)
        notifyChanged(sessionId)
    }

    private fun trim(b: StringBuilder, max: Int) {
        if (b.length <= max) return
        val cut = b.length - max
        val nl = b.indexOf("\n", cut)
        val drop = if (nl > 0) nl + 1 else cut
        b.delete(0, drop)
    }

    private fun notifyChanged(id: String) {
        val snap = ArrayList<Listener>(listeners)
        for (l in snap) try { l.onSessionChanged(id) } catch (_: Exception) { }
    }
    private fun notifyList() {
        val snap = ArrayList<Listener>(listeners)
        for (l in snap) try { l.onSessionsListChanged() } catch (_: Exception) { }
    }
    private fun notifyActive(id: String) {
        val snap = ArrayList<Listener>(listeners)
        for (l in snap) try { l.onActiveChanged(id) } catch (_: Exception) { }
    }

    // ─── Persistence ────────────────────────────────────

    fun persist() {
        val ctx = appContext ?: return
        try {
            val root = JSONObject()
            val arr = JSONArray()
            val snapshot = list()
            for (s in snapshot) {
                val o = JSONObject()
                o.put("id", s.id)
                o.put("name", s.name)
                o.put("cwd", s.cwd.absolutePath)
                o.put("buffer", s.buffer.toString())
                val h = JSONArray()
                for (item in s.history) h.put(item)
                o.put("history", h)
                arr.put(o)
            }
            root.put("sessions", arr)
            root.put("active", activeId)
            ctx.openFileOutput("sessions.json", Context.MODE_PRIVATE)
                .use { it.write(root.toString().toByteArray(Charsets.UTF_8)) }
        } catch (_: Exception) { }
    }

    fun restore(ctx: Context) {
        appContext = ctx.applicationContext
        try {
            val f = File(ctx.filesDir, "sessions.json")
            if (!f.exists()) return
            val root = JSONObject(f.readText())
            val arr = root.optJSONArray("sessions") ?: JSONArray()
            synchronized(this) {
                sessions.clear()
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val s = Session(
                        id = o.optString("id", UUID.randomUUID().toString().take(8)),
                        name = o.optString("name", "session"),
                        cwd = File(o.optString("cwd", home().absolutePath))
                    )
                    s.buffer.append(o.optString("buffer", ""))
                    val h = o.optJSONArray("history")
                    if (h != null) for (j in 0 until h.length()) s.history.add(h.getString(j))
                    sessions.add(s)
                }
                val act = root.optString("active", "")
                activeId = if (act.isNotEmpty()) act else (sessions.firstOrNull()?.id ?: "")
            }
        } catch (_: Exception) { }
    }
}
KOT_1

echo "▶ [fix5b] إعادة كتابة SyntaxHighlighter.kt (نسخة نظيفة بلا inline معقّد)"

cat > app/src/main/java/com/awlqy/terminal/core/SyntaxHighlighter.kt <<'KOT_2'
package com.awlqy.terminal.core

import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import java.util.regex.Pattern

object SyntaxHighlighter {

    const val C_PROMPT_AWLQY = 0xFF22D3EE.toInt()
    const val C_PROMPT_HOST  = 0xFF4ADE80.toInt()
    const val C_PROMPT_PATH  = 0xFFFBBF24.toInt()
    const val C_PROMPT_DOLLAR= 0xFFFFFFFF.toInt()
    const val C_KEYWORD      = 0xFFA78BFA.toInt()
    const val C_STRING       = 0xFF4ADE80.toInt()
    const val C_NUMBER       = 0xFFFACC15.toInt()
    const val C_PATH         = 0xFF22D3EE.toInt()
    const val C_ERROR        = 0xFFEF4444.toInt()
    const val C_OK           = 0xFF10B981.toInt()
    const val C_DEFAULT      = 0xFFE2E8F0.toInt()

    private val KW = Pattern.compile(
        "\\b(if|else|elif|for|while|do|def|class|return|import|from|as|try|except|finally|raise|with|lambda|yield|pass|break|continue|global|nonlocal|assert|in|is|not|and|or|async|await|public|private|protected|static|final|void|int|long|float|double|bool|String|new|this|super|null|None|True|False|true|false|function|var|let|const|interface|extends|implements|package|namespace|using|struct|enum|fn|mut|impl|trait|match|pub|println|print|echo|export|source)\\b"
    )
    private val STR  = Pattern.compile("'[^'\\n]*'|\"[^\"\\n]*\"|`[^`\\n]*`")
    private val NUM  = Pattern.compile("\\b\\d+(\\.\\d+)?\\b")
    private val PATH = Pattern.compile("(/[\\w.\\-@/]+)+")
    private val PROMPT = Pattern.compile("awlqy@android:([^\\$]*)\\$ ")
    private val ERROR = Pattern.compile(
        "(?i)\\b(error|failed|fatal|denied|not found|exception|traceback)\\b"
    )
    private val OK = Pattern.compile(
        "(?i)\\b(ok|success|done|ready|installed|finished)\\b"
    )

    fun highlight(text: CharSequence): SpannableStringBuilder {
        val sb = SpannableStringBuilder(text)
        apply(sb)
        return sb
    }

    fun highlightInPlace(sb: Spannable) {
        apply(sb)
    }

    private fun apply(sb: Spannable) {
        val s = sb.toString()
        mark(sb, PROMPT.matcher(s)) { m ->
            val a = m.start()
            val b = m.end()
            span(sb, a, a + 5, C_PROMPT_AWLQY)
            span(sb, a + 5, a + 6, C_DEFAULT)
            span(sb, a + 6, a + 13, C_PROMPT_HOST)
            span(sb, a + 13, b - 2, C_PROMPT_PATH)
            span(sb, b - 2, b - 1, C_PROMPT_DOLLAR)
        }
        mark(sb, STR.matcher(s))  { m -> span(sb, m.start(), m.end(), C_STRING) }
        mark(sb, KW.matcher(s))   { m -> span(sb, m.start(), m.end(), C_KEYWORD) }
        mark(sb, NUM.matcher(s))  { m -> span(sb, m.start(), m.end(), C_NUMBER) }
        mark(sb, PATH.matcher(s)) { m ->
            if (m.end() - m.start() > 1) span(sb, m.start(), m.end(), C_PATH)
        }
        mark(sb, ERROR.matcher(s)) { m -> span(sb, m.start(), m.end(), C_ERROR) }
        mark(sb, OK.matcher(s))    { m -> span(sb, m.start(), m.end(), C_OK) }
    }

    private fun mark(
        sb: Spannable,
        m: java.util.regex.Matcher,
        block: (java.util.regex.Matcher) -> Unit
    ) {
        while (m.find()) block(m)
    }

    private fun span(sb: Spannable, start: Int, end: Int, color: Int) {
        if (start < 0 || end > sb.length || start >= end) return
        sb.setSpan(
            ForegroundColorSpan(color),
            start, end,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }
}
KOT_2

echo "▶ [fix5b] إعادة كتابة MainActivity.kt (نسخة نظيفة كاملة)"

cat > app/src/main/java/com/awlqy/terminal/MainActivity.kt <<'KOT_MAIN'
package com.awlqy.terminal

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.viewpager2.adapter.FragmentStateAdapter
import androidx.viewpager2.widget.ViewPager2
import com.awlqy.terminal.core.AutoUpdateManager
import com.awlqy.terminal.core.SessionManager
import com.awlqy.terminal.databinding.ActivityMainBinding
import com.awlqy.terminal.service.TerminalService
import com.awlqy.terminal.ui.TerminalFragment
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.tabs.TabLayoutMediator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : AppCompatActivity(), SessionManager.Listener {

    private lateinit var binding: ActivityMainBinding
    private var mediator: TabLayoutMediator? = null

    private val appVersionName: String by lazy {
        try {
            val pi: PackageManager = packageManager
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                pi.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0L))
            else {
                @Suppress("DEPRECATION")
                pi.getPackageInfo(packageName, 0)
            }
            info.versionName ?: "1.0.0"
        } catch (_: Exception) { "1.0.0" }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)

        SessionManager.attachContext(this)
        SessionManager.attachHome(File(filesDir, "home").apply { mkdirs() })
        SessionManager.restore(this)
        SessionManager.addListener(this)

        if (SessionManager.list().isEmpty()) SessionManager.create("main")

        startTerminalService()

        setupPager()
        wireAccessoryBar()
        wireInputRow()
        renderActive()
    }

    override fun onPause() {
        super.onPause()
        SessionManager.persist()
    }

    override fun onDestroy() {
        SessionManager.removeListener(this)
        mediator?.detach()
        SessionManager.persist()
        super.onDestroy()
    }

    // ─── Service ─────────────────────────────────────

    private fun startTerminalService() {
        val i = Intent(this, TerminalService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(i)
        } else {
            startService(i)
        }
    }

    // ─── Pager ───────────────────────────────────────

    private fun setupPager() {
        binding.pager.adapter = object : FragmentStateAdapter(this) {
            override fun getItemCount(): Int = SessionManager.list().size
            override fun createFragment(position: Int): Fragment {
                val list = SessionManager.list()
                val s = list.getOrNull(position) ?: return Fragment()
                return TerminalFragment.new(s.id)
            }
        }
        attachMediator()
        binding.pager.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                val list = SessionManager.list()
                val s = list.getOrNull(position) ?: return
                SessionManager.setActive(s.id)
                renderActive()
            }
        })
    }

    private fun attachMediator() {
        mediator?.detach()
        mediator = TabLayoutMediator(binding.tabBar, binding.pager) { tab, pos ->
            tab.text = SessionManager.list().getOrNull(pos)?.name ?: "session"
        }.also { it.attach() }
    }

    private fun refreshSessionsUi() {
        binding.pager.adapter?.notifyDataSetChanged()
        attachMediator()
        val idx = SessionManager.list().indexOfFirst { it.id == SessionManager.active()?.id }
        if (idx >= 0) binding.pager.setCurrentItem(idx, true)
    }

    private fun activeFragment(): TerminalFragment? {
        val idx = binding.pager.currentItem
        val fragmentTag = "f$idx"
        return supportFragmentManager.findFragmentByTag(fragmentTag) as? TerminalFragment
    }

    private fun renderActive() {
        val s = SessionManager.active() ?: return
        binding.promptLabel.text = "awlqy@android:${s.cwd.absolutePath}\$ "
    }

    // ─── Accessory bar ──────────────────────────────

    private fun wireAccessoryBar() {
        binding.keyNewSession.setOnClickListener { newSession() }
        binding.keyKeyboard.setOnClickListener { toggleKeyboard() }
        binding.keyCtrl.setOnClickListener { activeFragment()?.kill() }
        binding.keyAlt.setOnClickListener {
            Toast.makeText(this, "Alt modifier غير مفعّل", Toast.LENGTH_SHORT).show()
        }
        binding.keyTab.setOnClickListener        { insertInput("\t") }
        binding.keyEsc.setOnClickListener        { insertInput("\u001B") }
        binding.keyDollar.setOnClickListener     { insertInput("$") }
        binding.keySlash.setOnClickListener      { insertInput("/") }
        binding.keyPipe.setOnClickListener       { insertInput("|") }
        binding.keyTilde.setOnClickListener      { insertInput("~") }
        binding.keyUnderscore.setOnClickListener { insertInput("_") }
        binding.keyUp.setOnClickListener         { inputFromHistory(-1) }
        binding.keyDown.setOnClickListener       { inputFromHistory(+1) }
        binding.keyLeft.setOnClickListener       { moveCursor(-1) }
        binding.keyRight.setOnClickListener      { moveCursor(+1) }
        binding.keyEditor.setOnClickListener     { openEditor() }
    }

    private fun insertInput(s: String) {
        val e = binding.inputEdit
        val cur = e.text?.toString().orEmpty()
        val sel = e.selectionStart.coerceIn(0, cur.length)
        val next = cur.substring(0, sel) + s + cur.substring(sel)
        e.setText(next)
        e.setSelection(sel + s.length)
    }

    private fun moveCursor(d: Int) {
        val e = binding.inputEdit
        val max = e.text?.length ?: 0
        e.setSelection((e.selectionStart + d).coerceIn(0, max))
    }

    private fun inputFromHistory(dir: Int) {
        val f = activeFragment() ?: return
        val cmd = f.historyMove(dir)
        binding.inputEdit.setText(cmd)
        binding.inputEdit.setSelection(cmd.length)
    }

    private fun toggleKeyboard() {
        val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        if (binding.inputEdit.hasFocus()) {
            imm.hideSoftInputFromWindow(binding.inputEdit.windowToken, 0)
        } else {
            binding.inputEdit.requestFocus()
            imm.showSoftInput(binding.inputEdit, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    // ─── Input row ──────────────────────────────────

    private fun wireInputRow() {
        binding.runButton.setOnClickListener { runCurrent() }
        binding.inputEdit.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND ||
                actionId == EditorInfo.IME_ACTION_DONE) {
                runCurrent(); true
            } else false
        }
    }

    private fun runCurrent() {
        val cmd = binding.inputEdit.text.toString()
        if (cmd.isBlank()) return
        binding.inputEdit.setText("")
        activeFragment()?.sendCommand(cmd)
    }

    // ─── Menu ───────────────────────────────────────

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.main_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_new_session   -> { newSession(); true }
            R.id.action_close_session -> { closeCurrent(); true }
            R.id.action_open_editor   -> { openEditor(); true }
            R.id.action_install_hub   -> { installHub(); true }
            R.id.action_settings      -> { showSettings(); true }
            R.id.action_update        -> { checkUpdates(); true }
            R.id.action_about         -> { showAbout(); true }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun newSession() {
        SessionManager.create("session-${SessionManager.list().size + 1}")
        refreshSessionsUi()
        binding.pager.post {
            val idx = SessionManager.list().size - 1
            if (idx >= 0) binding.pager.setCurrentItem(idx, true)
        }
    }

    private fun closeCurrent() {
        val s = SessionManager.active() ?: return
        if (SessionManager.list().size <= 1) {
            Toast.makeText(this, "لا يمكن إغلاق الجلسة الأخيرة", Toast.LENGTH_SHORT).show()
            return
        }
        SessionManager.close(s.id)
        refreshSessionsUi()
    }

    private fun openEditor() {
        val s = SessionManager.active() ?: return
        val i = Intent(this, CodeEditorActivity::class.java)
        i.putExtra("cwd", s.cwd.absolutePath)
        startActivity(i)
    }

    private fun installHub() {
        val items = arrayOf(
            "تثبيت Python3 + pip",
            "تثبيت Node.js + npm",
            "تثبيت Clang / GCC",
            "تهيئة git",
            "تهيئة أدوات APK"
        )
        MaterialAlertDialogBuilder(this)
            .setTitle("مركز الأدوات السريعة")
            .setItems(items) { _, which ->
                val cmd = when (which) {
                    0 -> "echo 'يحتاج Termux: pkg install python'"
                    1 -> "echo 'يحتاج Termux: pkg install nodejs-lts'"
                    2 -> "echo 'يحتاج Termux: pkg install clang make'"
                    3 -> "git --version; git init 2>/dev/null; echo done"
                    4 -> "mkdir -p usr/bin; echo 'ضع aapt2 d8 apksigner zipalign في usr/bin'"
                    else -> "echo hello"
                }
                activeFragment()?.sendCommand(cmd)
            }
            .setNegativeButton("إلغاء", null)
            .show()
    }

    private fun showSettings() {
        val msg = buildString {
            appendLine("التطبيق: awlqy Terminal & IDE")
            appendLine("الإصدار: $appVersionName")
            appendLine("المطوّر: حسين الخلاقي")
            appendLine("GitHub: alwaqyhsyn752-eng")
            appendLine("الحالة: Phase 5 · Multi-Session")
            appendLine("عدد الجلسات: ${SessionManager.list().size}")
            appendLine("Package: $packageName")
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("الإعدادات")
            .setMessage(msg)
            .setPositiveButton("حسناً", null)
            .setNeutralButton("التحقق من التحديثات") { _, _ -> checkUpdates() }
            .show()
    }

    private fun showAbout() {
        MaterialAlertDialogBuilder(this)
            .setTitle("حول التطبيق")
            .setMessage("awlqy — طرفية هكر حديثة وبيئة تطوير متكاملة.\n© 2025 حسين الخلاقي — MIT")
            .setPositiveButton("إغلاق", null)
            .show()
    }

    private fun checkUpdates() {
        lifecycleScope.launch {
            Toast.makeText(this@MainActivity, "جارٍ التحقق...", Toast.LENGTH_SHORT).show()
            val info = withContext(Dispatchers.IO) {
                AutoUpdateManager.checkLatest(this@MainActivity, appVersionName)
            }
            if (info == null) {
                Toast.makeText(this@MainActivity, "تعذّر الاتصال بـ GitHub", Toast.LENGTH_LONG).show()
                return@launch
            }
            if (!info.hasUpdate) {
                Toast.makeText(this@MainActivity, "أحدث إصدار مثبّت ($appVersionName)", Toast.LENGTH_LONG).show()
                return@launch
            }
            MaterialAlertDialogBuilder(this@MainActivity)
                .setTitle("تحديث متوفر: ${info.tag}")
                .setMessage(info.notes.ifBlank { "لا توجد ملاحظات." })
                .setPositiveButton("تحديث الآن") { _, _ ->
                    lifecycleScope.launch {
                        val apk = withContext(Dispatchers.IO) {
                            AutoUpdateManager.downloadApk(this@MainActivity, info) { }
                        }
                        if (apk != null) AutoUpdateManager.installApk(this@MainActivity, apk)
                    }
                }
                .setNegativeButton("لاحقاً", null)
                .show()
        }
    }

    // ─── SessionManager.Listener ───────────────────

    override fun onSessionChanged(id: String) { }
    override fun onSessionsListChanged() { }
    override fun onActiveChanged(id: String) { renderActive() }
}
KOT_MAIN

echo "▶ [fix5b] إعادة كتابة TerminalFragment.kt (مرتبط بـ String buffer)"

cat > app/src/main/java/com/awlqy/terminal/ui/TerminalFragment.kt <<'KOT_FRAG'
package com.awlqy.terminal.ui

import android.graphics.Typeface
import android.os.Bundle
import android.text.method.ScrollingMovementMethod
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.awlqy.terminal.core.AutoHealingEngine
import com.awlqy.terminal.core.SessionManager
import com.awlqy.terminal.core.ShellExecutor
import com.awlqy.terminal.core.SyntaxHighlighter
import com.awlqy.terminal.databinding.FragmentTerminalBinding
import kotlinx.coroutines.launch

class TerminalFragment : Fragment(), SessionManager.Listener {

    private var _b: FragmentTerminalBinding? = null
    private val b get() = _b!!
    private var sessionId: String = ""

    override fun onCreateView(i: LayoutInflater, c: ViewGroup?, s: Bundle?): View {
        _b = FragmentTerminalBinding.inflate(i, c, false)
        return b.root
    }

    override fun onViewCreated(v: View, s: Bundle?) {
        b.consoleText.movementMethod = ScrollingMovementMethod()
        b.consoleText.typeface = Typeface.MONOSPACE
        b.consoleText.textSize = 12f
        sessionId = arguments?.getString(ARG_ID).orEmpty()
        SessionManager.addListener(this)
        renderFull()
    }

    override fun onDestroyView() {
        SessionManager.removeListener(this)
        _b = null
        super.onDestroyView()
    }

    private fun currentSession() = SessionManager.list().firstOrNull { it.id == sessionId }

    private fun renderFull() {
        val s = currentSession() ?: return
        val sp = SyntaxHighlighter.highlight(s.buffer.toString())
        b.consoleText.text = sp
        b.consoleScroll.post { b.consoleScroll.fullScroll(View.FOCUS_DOWN) }
    }

    override fun onSessionChanged(id: String) {
        if (id != sessionId) return
        val s = currentSession() ?: return
        val sp = SyntaxHighlighter.highlight(s.buffer.toString())
        b.consoleText.text = sp
        b.consoleScroll.post { b.consoleScroll.fullScroll(View.FOCUS_DOWN) }
    }

    override fun onSessionsListChanged() { }
    override fun onActiveChanged(id: String) { }

    fun sendCommand(cmd: String) {
        val s = currentSession() ?: return
        if (s.busy) return
        val prompt = "awlqy@android:${s.cwd.absolutePath}\$ "
        SessionManager.append(s.id, "$prompt$cmd\n")

        s.history.add(cmd)
        if (s.history.size > 300) s.history.removeAt(0)
        s.historyIndex = -1
        s.busy = true

        viewLifecycleOwner.lifecycleScope.launch {
            val result = ShellExecutor.run(cmd, s.cwd)
            if (result.stdout.isNotEmpty()) SessionManager.append(s.id, result.stdout)
            if (result.stderr.isNotEmpty()) SessionManager.append(s.id, result.stderr)

            val plan = AutoHealingEngine.analyze(result.exitCode, result.stdout, result.stderr)
            if (plan != null) {
                SessionManager.append(s.id, "[auto-heal] \u2695 ${plan.summary}\n")
                plan.suggestion?.let { SessionManager.append(s.id, "[auto-heal]   $it\n") }
                plan.autoRetryCommand?.let { SessionManager.append(s.id, "[auto-fix]  \u00BB $it\n") }
            }
            s.lastExit = result.exitCode
            s.busy = false
            SessionManager.persist()
        }
    }

    fun kill() {
        val s = currentSession() ?: return
        val ok = ShellExecutor.killCurrent()
        SessionManager.append(s.id, "^C ${if (ok) "(signal sent)" else "(no active process)"}\n")
        s.busy = false
    }

    fun historyMove(dir: Int): String {
        val s = currentSession() ?: return ""
        if (s.history.isEmpty()) return ""
        if (s.historyIndex == -1) s.historyIndex = s.history.size
        s.historyIndex = (s.historyIndex + dir).coerceIn(0, s.history.size)
        return if (s.historyIndex >= s.history.size) "" else s.history[s.historyIndex]
    }

    companion object {
        const val ARG_ID = "session_id"
        fun new(id: String) = TerminalFragment().apply {
            arguments = Bundle().apply { putString(ARG_ID, id) }
        }
    }
}
KOT_FRAG

echo "▶ [fix5b] إعادة كتابة CodeEditorActivity.kt (نسخة نظيفة)"

cat > app/src/main/java/com/awlqy/terminal/CodeEditorActivity.kt <<'KOT_ED'
package com.awlqy.terminal

import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.Menu
import android.view.MenuItem
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.awlqy.terminal.core.SyntaxHighlighter
import com.awlqy.terminal.databinding.ActivityCodeEditorBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import java.io.File

class CodeEditorActivity : AppCompatActivity() {

    private lateinit var binding: ActivityCodeEditorBinding
    private var currentFile: File? = null
    private var highlightLock = false

    private val saver = Handler(Looper.getMainLooper())
    private val saveRunnable = Runnable { persist() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityCodeEditorBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        binding.toolbar.setNavigationOnClickListener { finish() }

        binding.editorInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) { }
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) { }
            override fun afterTextChanged(s: Editable?) {
                if (s == null) return
                if (!highlightLock) {
                    highlightLock = true
                    SyntaxHighlighter.highlightInPlace(s)
                    highlightLock = false
                }
                syncLineNumbers()
                saver.removeCallbacks(saveRunnable)
                saver.postDelayed(saveRunnable, 800)
            }
        })

        binding.editorScroll.setOnScrollChangeListener { _, _, _, _, _ -> syncGutterScroll() }

        binding.btnOpen.setOnClickListener { openPicker() }
        binding.btnNew.setOnClickListener  { newFile() }
        binding.btnSave.setOnClickListener {
            persist()
            Toast.makeText(this, "حُفظ", Toast.LENGTH_SHORT).show()
        }
        binding.btnFind.setOnClickListener { findDialog() }
        binding.btnRun.setOnClickListener  { runInTerminal() }

        binding.toolbar.subtitle = intent.getStringExtra("cwd") ?: filesDir.absolutePath
        syncLineNumbers()
    }

    override fun onPause() { super.onPause(); persist() }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.editor_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            android.R.id.home            -> { finish(); true }
            R.id.action_editor_save      -> { persist(); true }
            R.id.action_editor_run       -> { runInTerminal(); true }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun syncGutterScroll() {
        binding.lineNumbers.scrollTo(0, binding.editorScroll.scrollY)
    }

    private fun syncLineNumbers() {
        val lines = binding.editorInput.lineCount.coerceAtLeast(1)
        val gut = binding.lineNumbers
        while (gut.childCount < lines) {
            val t = TextView(this).apply {
                typeface = Typeface.MONOSPACE
                textSize = 12f
                setTextColor(0xFF64748B.toInt())
                setPadding(12, 0, 12, 0)
            }
            gut.addView(t)
        }
        while (gut.childCount > lines) gut.removeViewAt(gut.childCount - 1)
        for (i in 0 until lines) {
            (gut.getChildAt(i) as TextView).text = (i + 1).toString()
        }
        syncGutterScroll()
    }

    private fun newFile() {
        currentFile = null
        binding.editorInput.setText("")
        binding.toolbar.title = "بدون عنوان"
        syncLineNumbers()
    }

    private fun openPicker() {
        val cwd = intent.getStringExtra("cwd") ?: filesDir.absolutePath
        val dir = File(cwd).let { if (it.exists()) it else filesDir }
        val files = dir.listFiles()?.sortedBy { it.name } ?: emptyArray()
        if (files.isEmpty()) {
            Toast.makeText(this, "لا توجد ملفات في $cwd", Toast.LENGTH_SHORT).show()
            return
        }
        val names = files.map { it.name }.toTypedArray()
        MaterialAlertDialogBuilder(this)
            .setTitle("فتح ملف")
            .setItems(names) { _, which ->
                val f = files[which]
                if (f.isDirectory) {
                    Toast.makeText(this, "مجلد — لا يمكن فتحه هنا", Toast.LENGTH_SHORT).show()
                } else {
                    loadFile(f)
                }
            }
            .setNegativeButton("إلغاء", null)
            .show()
    }

    private fun loadFile(f: File) {
        try {
            currentFile = f
            binding.editorInput.setText(f.readText())
            binding.toolbar.title = f.name
            syncLineNumbers()
        } catch (e: Exception) {
            Toast.makeText(this, "فشل الفتح: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    private fun persist() {
        val f = currentFile ?: return
        try { f.writeText(binding.editorInput.text.toString()) } catch (_: Exception) { }
    }

    private fun findDialog() {
        val input = EditText(this).apply { hint = "ابحث عن..." }
        val replace = EditText(this).apply { hint = "استبدل بـ (اختياري)" }
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 24, 48, 0)
            addView(input)
            addView(replace)
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("بحث واستبدال")
            .setView(container)
            .setPositiveButton("بحث") { _, _ ->
                val q = input.text.toString()
                if (q.isEmpty()) return@setPositiveButton
                val txt = binding.editorInput.text.toString()
                val idx = txt.indexOf(q)
                if (idx < 0) Toast.makeText(this, "غير موجود", Toast.LENGTH_SHORT).show()
                else binding.editorInput.setSelection(idx, idx + q.length)
            }
            .setNeutralButton("استبدال الكل") { _, _ ->
                val q = input.text.toString()
                val r = replace.text.toString()
                if (q.isEmpty()) return@setNeutralButton
                val newTxt = binding.editorInput.text.toString().replace(q, r)
                binding.editorInput.setText(newTxt)
                Toast.makeText(this, "تم الاستبدال", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("إغلاق", null)
            .show()
    }

    private fun runInTerminal() {
        persist()
        val f = currentFile
        if (f == null) {
            Toast.makeText(this, "احفظ الملف أولاً", Toast.LENGTH_SHORT).show()
            return
        }
        val cmd = when (f.extension.lowercase()) {
            "py" -> "python ${f.absolutePath}"
            "sh" -> "sh ${f.absolutePath}"
            "js" -> "node ${f.absolutePath}"
            else -> "cat ${f.absolutePath}"
        }
        Toast.makeText(this, "شغّل يدوياً:\n$cmd", Toast.LENGTH_LONG).show()
    }
}
KOT_ED

echo ""
echo "▶ [fix5b] التحقق من الاعتماديات:"
grep -E "viewpager2|fragment-ktx" app/build.gradle.kts

echo ""
echo "▶ [fix5b] أول سطر من كل ملف Kotlin:"
for f in $(find app/src/main/java -name "*.kt"); do
    printf "  %-70s  %s\n" "$f" "$(head -n 1 "$f")"
done

echo ""
echo "✔ [fix5b] انتهى. الآن:"
echo "   git add -A"
echo "   git commit -m 'fix: add viewpager2+fragment-ktx; rewrite SessionManager+Highlighter+MainActivity'"
echo "   git push"
