#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · phase5.sh — Hacker Terminal Overhaul
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p app/src/main/java/com/awlqy/terminal/{core,ui,service}
mkdir -p app/src/main/res/{layout,values,drawable,menu,xml}

# ═════════════════════════════════════════════════════════════
# 1. core/SessionManager.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/core/SessionManager.kt <<'KOT_1'
package com.awlqy.terminal.core

import android.content.Context
import android.text.SpannableStringBuilder
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

object SessionManager {

    data class Session(
        val id: String,
        val name: String,
        var cwd: File,
        val buffer: SpannableStringBuilder = SpannableStringBuilder(),
        val history: MutableList<String> = ArrayList(),
        var historyIndex: Int = -1,
        @Volatile var busy: Boolean = false,
        var lastExit: Int = 0
    )

    interface Listener {
        fun onSessionChanged(id: String)
        fun onSessionsListChanged()
        fun onActiveChanged(id: String)
    }

    private val sessions = ArrayList<Session>()
    private val listeners = LinkedHashSet<Listener>()
    @Volatile private var activeId: String = ""
    @Volatile private var homeDir: File? = null

    fun attachHome(home: File) {
        homeDir = home
        if (!home.exists()) home.mkdirs()
    }

    fun addListener(l: Listener) { synchronized(listeners) { listeners.add(l) } }
    fun removeListener(l: Listener) { synchronized(listeners) { listeners.remove(l) } }

    fun home(): File = homeDir ?: File("/data/local/tmp")

    fun list(): List<Session> = synchronized(sessions) { sessions.toList() }

    fun active(): Session? = synchronized(sessions) {
        sessions.firstOrNull { it.id == activeId } ?: sessions.firstOrNull()
    }

    fun setActive(id: String) {
        if (activeId == id) return
        activeId = id
        notifyActive(id)
    }

    fun create(name: String? = null, cwd: File? = null): Session {
        val n = (name ?: "session-${System.currentTimeMillis() % 100000}").trim()
        val s = Session(
            id = UUID.randomUUID().toString().take(8),
            name = n,
            cwd = (cwd ?: home()).apply { mkdirs() }
        )
        synchronized(sessions) { sessions.add(s) }
        if (activeId.isEmpty()) activeId = s.id
        notifyList()
        notifyActive(activeId)
        return s
    }

    fun close(id: String) {
        synchronized(sessions) { sessions.removeAll { it.id == id } }
        if (activeId == id) activeId = sessions.firstOrNull()?.id ?: ""
        notifyList()
        notifyActive(activeId)
        persist()
    }

    fun append(sessionId: String, text: CharSequence) {
        val s = sessions.firstOrNull { it.id == sessionId } ?: return
        s.buffer.append(text)
        trimBuffer(s.buffer, 200_000)
        notifyChanged(sessionId)
    }

    private fun trimBuffer(b: SpannableStringBuilder, max: Int) {
        if (b.length <= max) return
        val cut = b.length - max
        val nl = b.indexOf("\n", cut)
        val drop = if (nl > 0) nl + 1 else cut
        b.delete(0, drop)
    }

    private fun notifyChanged(id: String) {
        val snapshot = ArrayList<Listener>(listeners)
        snapshot.forEach { it.onSessionChanged(id) }
    }
    private fun notifyList() {
        val snapshot = ArrayList<Listener>(listeners)
        snapshot.forEach { it.onSessionsListChanged() }
    }
    private fun notifyActive(id: String) {
        val snapshot = ArrayList<Listener>(listeners)
        snapshot.forEach { it.onActiveChanged(id) }
    }

    // ─── Persistence ──────────────────────────────────

    fun persist() {
        val ctx = appContext ?: return
        try {
            val root = JSONObject()
            val arr = JSONArray()
            for (s in sessions) {
                val o = JSONObject()
                o.put("id", s.id)
                o.put("name", s.name)
                o.put("cwd", s.cwd.absolutePath)
                o.put("buffer", s.buffer.toString())
                val h = JSONArray(); s.history.forEach { h.put(it) }; o.put("history", h)
                arr.put(o)
            }
            root.put("sessions", arr)
            root.put("active", activeId)
            ctx.openFileOutput("sessions.json", Context.MODE_PRIVATE)
                .use { it.write(root.toString().toByteArray()) }
        } catch (_: Exception) { }
    }

    fun restore(ctx: Context) {
        appContext = ctx.applicationContext
        try {
            val f = File(ctx.filesDir, "sessions.json")
            if (!f.exists()) return
            val root = JSONObject(f.readText())
            val arr = root.optJSONArray("sessions") ?: JSONArray()
            synchronized(sessions) {
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
            }
            activeId = root.optString("active", sessions.firstOrNull()?.id ?: "")
        } catch (_: Exception) { }
    }

    @Volatile private var appContext: Context? = null
}
KOT_1

# ═════════════════════════════════════════════════════════════
# 2. core/SyntaxHighlighter.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/core/SyntaxHighlighter.kt <<'KOT_2'
package com.awlqy.terminal.core

import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import java.util.regex.Pattern

object SyntaxHighlighter {

    // palette (ARGB)
    const val C_PROMPT_AWLQY = 0xFF22D3EE.toInt()   // cyan
    const val C_PROMPT_AT    = 0xFF94A3B8.toInt()   // dim
    const val C_PROMPT_HOST  = 0xFF4ADE80.toInt()   // green
    const val C_PROMPT_PATH  = 0xFFFBBF24.toInt()   // amber
    const val C_PROMPT_DOLLAR= 0xFFFFFFFF.toInt()   // white
    const val C_KEYWORD      = 0xFFA78BFA.toInt()   // purple
    const val C_STRING       = 0xFF4ADE80.toInt()   // green
    const val C_NUMBER       = 0xFFFACC15.toInt()   // yellow
    const val C_PATH         = 0xFF22D3EE.toInt()   // cyan
    const val C_ERROR        = 0xFFEF4444.toInt()   // red
    const val C_WARN         = 0xFFF59E0B.toInt()   // orange
    const val C_OK           = 0xFF10B981.toInt()   // emerald
    const val C_DEFAULT      = 0xFFE2E8F0.toInt()   // soft white

    private val KW = Pattern.compile(
        "\\b(if|else|elif|for|while|do|def|class|return|import|from|as|try|except|finally|raise|with|lambda|yield|pass|break|continue|global|nonlocal|assert|in|is|not|and|or|async|await|public|private|protected|static|final|void|int|long|float|double|bool|String|new|this|super|null|None|True|False|true|false|function|var|let|const|interface|extends|implements|package|namespace|using|struct|enum|fn|mut|impl|trait|match|pub|println|print|echo|export|source)\\b"
    )
    private val STR = Pattern.compile("'[^'\\n]*'|\"[^\"\\n]*\"|`[^`\\n]*`")
    private val NUM = Pattern.compile("\\b\\d+(\\.\\d+)?\\b")
    private val PATH = Pattern.compile("(/[\\w.\\-@/]+)+")
    private val PROMPT = Pattern.compile("awlqy@android:([^\\$]*)\\$ ")
    private val ERROR  = Pattern.compile("(?i)\\b(error|failed|fatal|denied|not found|exception|traceback)\\b")
    private val OK     = Pattern.compile("(?i)\\b(ok|success|done|ready|installed|finished)\\b")

    fun highlight(text: String, baseColor: Int = C_DEFAULT): SpannableStringBuilder {
        val sb = SpannableStringBuilder(text)
        applyAll(sb, baseColor)
        return sb
    }

    fun highlightInPlace(sb: Spannable, baseColor: Int = C_DEFAULT) {
        applyAll(sb, baseColor)
    }

    private fun applyAll(sb: Spannable, baseColor: Int) {
        val s = sb.toString()
        paint(sb, PROMPT.matcher(s)) { m ->
            val start = m.start()
            val end = m.end()
            // "awlqy"
            span(sb, start, start + 5, C_PROMPT_AWLQY)
            // "@"
            span(sb, start + 5, start + 6, C_PROMPT_AT)
            // "android"
            span(sb, start + 6, start + 13, C_PROMPT_HOST)
            // ":path"
            span(sb, start + 13, end - 2, C_PROMPT_PATH)
            // "$"
            span(sb, end - 2, end - 1, C_PROMPT_DOLLAR)
        }
        paint(sb, STR.matcher(s))  { m -> span(sb, m.start(), m.end(), C_STRING) }
        paint(sb, KW.matcher(s))   { m -> span(sb, m.start(), m.end(), C_KEYWORD) }
        paint(sb, NUM.matcher(s))  { m -> span(sb, m.start(), m.end(), C_NUMBER) }
        paint(sb, PATH.matcher(s)) { m ->
            val t = m.group()
            if (t.length > 1) span(sb, m.start(), m.end(), C_PATH)
        }
        paint(sb, ERROR.matcher(s)) { m -> span(sb, m.start(), m.end(), C_ERROR) }
        paint(sb, OK.matcher(s))    { m -> span(sb, m.start(), m.end(), C_OK) }
    }

    private inline fun paint(sb: Spannable, m: java.util.regex.Matcher, block: (java.util.regex.Matcher) -> Unit) {
        while (m.find()) block(m)
    }

    private fun span(sb: Spannable, start: Int, end: Int, color: Int) {
        if (start < 0 || end > sb.length || start >= end) return
        sb.setSpan(ForegroundColorSpan(color), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
    }
}
KOT_2

# ═════════════════════════════════════════════════════════════
# 3. service/TerminalService.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/service/TerminalService.kt <<'KOT_3'
package com.awlqy.terminal.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.awlqy.terminal.AwlqyApp
import com.awlqy.terminal.MainActivity
import com.awlqy.terminal.R

class TerminalService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        acquireWake()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getActivity(this, 0, tapIntent, piFlags)

        val notif: Notification = NotificationCompat.Builder(this, AwlqyApp.CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.notification_session_active))
            .setSmallIcon(R.drawable.ic_terminal)
            .setOngoing(true)
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1001, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(1001, notif)
        }
        return START_STICKY
    }

    private fun acquireWake() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "awlqy::terminal")
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire(12 * 60 * 60 * 1000L)
        } catch (_: Exception) { }
    }

    override fun onDestroy() {
        try { wakeLock?.release() } catch (_: Exception) { }
        wakeLock = null
        super.onDestroy()
    }
}
KOT_3

# ═════════════════════════════════════════════════════════════
# 4. ui/TerminalFragment.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/ui/TerminalFragment.kt <<'KOT_4'
package com.awlqy.terminal.ui

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
        b.consoleText.setHorizontallyScrolling(false)
        b.consoleText.typeface = android.graphics.Typeface.MONOSPACE
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

    private fun renderTail() {
        val s = currentSession() ?: return
        val sp = SyntaxHighlighter.highlight(s.buffer.toString())
        b.consoleText.text = sp
        b.consoleScroll.post { b.consoleScroll.fullScroll(View.FOCUS_DOWN) }
    }

    override fun onSessionChanged(id: String) { if (id == sessionId) renderTail() }
    override fun onSessionsListChanged() { /* handled by parent */ }
    override fun onActiveChanged(id: String) { /* handled by parent */ }

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
                SessionManager.append(s.id, "[auto-heal] ⚕ ${plan.summary}\n")
                plan.suggestion?.let { SessionManager.append(s.id, "[auto-heal]   $it\n") }
                plan.autoRetryCommand?.let { SessionManager.append(s.id, "[auto-fix]  » $it\n") }
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
KOT_4

# ═════════════════════════════════════════════════════════════
# 5. MainActivity.kt
# ═════════════════════════════════════════════════════════════
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

class MainActivity : AppCompatActivity(), SessionManager.Listener {

    private lateinit var binding: ActivityMainBinding
    private var mediator: TabLayoutMediator? = null

    private val appVersionName: String by lazy {
        try {
            val pi: PackageManager = packageManager
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                pi.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0L))
            else { @Suppress("DEPRECATION") pi.getPackageInfo(packageName, 0) }
            info.versionName ?: "1.0.0"
        } catch (_: Exception) { "1.0.0" }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)

        SessionManager.attachHome(java.io.File(filesDir, "home").apply { mkdirs() })
        SessionManager.restore(this)
        SessionManager.addListener(this)

        if (SessionManager.list().isEmpty()) SessionManager.create("main")

        startForegroundService(Intent(this, TerminalService::class.java))

        setupPager()
        wireAccessoryBar()
        wireInputRow()
        renderActive()
    }

    override fun onPause() { super.onPause(); SessionManager.persist() }
    override fun onDestroy() {
        SessionManager.removeListener(this)
        mediator?.detach()
        SessionManager.persist()
        super.onDestroy()
    }

    // ─── Pager ────────────────────────────────────────

    private fun setupPager() {
        binding.pager.adapter = object : FragmentStateAdapter(this) {
            override fun getItemCount(): Int = SessionManager.list().size
            override fun createFragment(position: Int): Fragment {
                val s = SessionManager.list()[position]
                return TerminalFragment.new(s.id)
            }
        }
        mediator?.detach()
        mediator = TabLayoutMediator(binding.tabBar, binding.pager) { tab, pos ->
            val s = SessionManager.list().getOrNull(pos)
            tab.text = s?.name ?: "session"
        }.also { it.attach() }

        binding.pager.registerOnPageChangeCallback(object :
            androidx.viewpager2.widget.ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                val s = SessionManager.list().getOrNull(position) ?: return
                SessionManager.setActive(s.id)
                renderActive()
            }
        })
    }

    private fun refreshSessionsUi() {
        binding.pager.adapter?.notifyDataSetChanged()
        mediator?.detach()
        mediator = TabLayoutMediator(binding.tabBar, binding.pager) { tab, pos ->
            tab.text = SessionManager.list().getOrNull(pos)?.name ?: "session"
        }.also { it.attach() }
        val idx = SessionManager.list().indexOfFirst { it.id == SessionManager.active()?.id }
        if (idx >= 0) binding.pager.setCurrentItem(idx, true)
    }

    private fun activeFragment(): TerminalFragment? {
        val idx = binding.pager.currentItem
        val tag = "f$idx"
        return supportFragmentManager.findFragmentByTag(tag) as? TerminalFragment
    }

    private fun renderActive() {
        val s = SessionManager.active() ?: return
        binding.promptLabel.text = "awlqy@android:${s.cwd.absolutePath}\$ "
    }

    // ─── Accessory bar ────────────────────────────────

    private fun wireAccessoryBar() {
        binding.keyNewSession.setOnClickListener { newSession() }
        binding.keyKeyboard.setOnClickListener { toggleKeyboard() }
        binding.keyCtrl.setOnClickListener { activeFragment()?.kill() }
        binding.keyAlt.setOnClickListener {
            Toast.makeText(this, "Alt modifier non-aktif (tanpa PTY)", Toast.LENGTH_SHORT).show()
        }
        binding.keyTab.setOnClickListener  { insertInput("\t") }
        binding.keyEsc.setOnClickListener  { insertInput("\u001B") }
        binding.keyDollar.setOnClickListener { insertInput("$") }
        binding.keySlash.setOnClickListener  { insertInput("/") }
        binding.keyPipe.setOnClickListener   { insertInput("|") }
        binding.keyTilde.setOnClickListener  { insertInput("~") }
        binding.keyUnderscore.setOnClickListener { insertInput("_") }
        binding.keyUp.setOnClickListener    { inputFromHistory(-1) }
        binding.keyDown.setOnClickListener  { inputFromHistory(+1) }
        binding.keyLeft.setOnClickListener  { moveCursor(-1) }
        binding.keyRight.setOnClickListener { moveCursor(+1) }
        binding.keyEditor.setOnClickListener { openEditor() }
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
        val p = (e.selectionStart + d).coerceIn(0, e.text?.length ?: 0)
        e.setSelection(p)
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

    // ─── Input row ────────────────────────────────────

    private fun wireInputRow() {
        binding.runButton.setOnClickListener { runCurrent() }
        binding.inputEdit.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND ||
                actionId == EditorInfo.IME_ACTION_DONE) { runCurrent(); true } else false
        }
    }

    private fun runCurrent() {
        val cmd = binding.inputEdit.text.toString()
        if (cmd.isBlank()) return
        binding.inputEdit.setText("")
        activeFragment()?.sendCommand(cmd)
    }

    // ─── Menu ─────────────────────────────────────────

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.main_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_new_session -> { newSession(); true }
            R.id.action_close_session -> { closeCurrent(); true }
            R.id.action_open_editor -> { openEditor(); true }
            R.id.action_install_hub -> { installHub(); true }
            R.id.action_settings -> { showSettings(); true }
            R.id.action_update -> { checkUpdates(); true }
            R.id.action_about -> { showAbout(); true }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun newSession() {
        val n = "session-${SessionManager.list().size + 1}"
        SessionManager.create(n)
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
                    0 -> "echo 'pkg install python' ثم أعد المحاولة (يحتاج Termux)"
                    1 -> "echo 'pkg install nodejs-lts' (يحتاج Termux)"
                    2 -> "echo 'pkg install clang make' (يحتاج Termux)"
                    3 -> "git init 2>/dev/null; git --version; echo 'git init'"
                    4 -> "mkdir -p usr/bin; echo 'ضع aapt2 d8 apksigner zipalign في usr/bin'"
                    else -> "echo hello"
                }
                activeFragment()?.sendCommand(cmd)
                Toast.makeText(this, "أُرسل الأمر إلى الجلسة الحالية", Toast.LENGTH_SHORT).show()
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
            .setMessage(
                "awlqy — طرفية هكر حديثة وبيئة تطوير متكاملة.\n" +
                "© 2025 حسين الخلاقي — MIT"
            )
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

    // ─── SessionManager.Listener ──────────────────────

    override fun onSessionChanged(id: String) { }
    override fun onSessionsListChanged() { }
    override fun onActiveChanged(id: String) { renderActive() }
}
KOT_MAIN

# ═════════════════════════════════════════════════════════════
# 6. CodeEditorActivity.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/CodeEditorActivity.kt <<'KOT_ED'
package com.awlqy.terminal

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.Spannable
import android.text.TextWatcher
import android.view.Menu
import android.view.MenuItem
import android.view.View
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
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) {
                if (highlightLock) return
                highlightLock = true
                SyntaxHighlighter.highlightInPlace(s ?: return)
                highlightLock = false
                syncLineNumbers()
                saver.removeCallbacks(saveRunnable)
                saver.postDelayed(saveRunnable, 800)
            }
        })

        binding.editorScroll.setOnScrollChangeListener { _, _, _, _, _ -> syncGutterScroll() }

        binding.btnOpen.setOnClickListener  { openPicker() }
        binding.btnNew.setOnClickListener   { newFile() }
        binding.btnSave.setOnClickListener  { persist(); Toast.makeText(this, "حُفظ", Toast.LENGTH_SHORT).show() }
        binding.btnFind.setOnClickListener  { findDialog() }
        binding.btnRun.setOnClickListener   { runInTerminal() }

        val cwd = intent.getStringExtra("cwd") ?: filesDir.absolutePath
        binding.toolbar.subtitle = cwd
        refreshLineNumbers()
    }

    override fun onPause() { super.onPause(); persist() }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            android.R.id.home -> { finish(); true }
            R.id.action_editor_save -> { persist(); true }
            R.id.action_editor_run -> { runInTerminal(); true }
            else -> super.onOptionsItemSelected(item)
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.editor_menu, menu)
        return true
    }

    private fun syncGutterScroll() {
        binding.lineNumbers.scrollTo(0, binding.editorScroll.scrollY)
    }

    private fun syncLineNumbers() {
        val e = binding.editorInput
        val lines = e.lineCount.coerceAtLeast(1)
        val gut = binding.lineNumbers
        while (gut.childCount < lines) {
            val t = TextView(this).apply {
                typeface = android.graphics.Typeface.MONOSPACE
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

    private fun refreshLineNumbers() { syncLineNumbers() }

    private fun newFile() {
        currentFile = null
        binding.editorInput.setText("")
        binding.toolbar.title = "بدون عنوان"
        refreshLineNumbers()
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
            refreshLineNumbers()
        } catch (e: Exception) {
            Toast.makeText(this, "فشل الفتح: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    private fun persist() {
        val f = currentFile ?: return
        try {
            f.writeText(binding.editorInput.text.toString())
        } catch (_: Exception) { }
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
        val f = currentFile ?: run {
            Toast.makeText(this, "احفظ الملف أولاً", Toast.LENGTH_SHORT).show()
            return
        }
        val cmd = when (f.extension.lowercase()) {
            "py" -> "python ${f.absolutePath}"
            "sh" -> "sh ${f.absolutePath}"
            "js" -> "node ${f.absolutePath}"
            else -> "cat ${f.absolutePath}"
        }
        Toast.makeText(this, "شغّل يدوياً في الطرفية:\n$cmd", Toast.LENGTH_LONG).show()
    }
}
KOT_ED

# ═════════════════════════════════════════════════════════════
# 7. Layouts
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/layout/activity_main.xml <<'XML_MAIN'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000"
    android:orientation="vertical"
    android:fitsSystemWindows="true">

    <com.google.android.material.appbar.MaterialToolbar
        android:id="@+id/toolbar"
        android:layout_width="match_parent"
        android:layout_height="?attr/actionBarSize"
        android:background="#000000"
        app:title="awlqy"
        app:titleTextColor="#22D3EE"/>

    <com.google.android.material.tabs.TabLayout
        android:id="@+id/tabBar"
        android:layout_width="match_parent"
        android:layout_height="40dp"
        android:background="#0A0E14"
        app:tabIndicatorColor="#22D3EE"
        app:tabSelectedTextColor="#22D3EE"
        app:tabTextColor="#64748B"
        app:tabMode="scrollable"/>

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:background="#000000">

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

        <androidx.viewpager2.widget.ViewPager2
            android:id="@+id/pager"
            android:layout_width="match_parent"
            android:layout_height="match_parent"/>
    </FrameLayout>

    <HorizontalScrollView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="#0A0E14"
        android:scrollbars="none">

        <LinearLayout
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:padding="4dp">

            <Button android:id="@+id/keyNewSession" style="@style/KeyGlass" android:text="+ NEW"/>
            <Button android:id="@+id/keyKeyboard"   style="@style/KeyGlass" android:text="⌨"/>
            <Button android:id="@+id/keyCtrl"       style="@style/KeyGlass" android:text="CTRL+C"/>
            <Button android:id="@+id/keyAlt"        style="@style/KeyGlass" android:text="ALT"/>
            <Button android:id="@+id/keyTab"        style="@style/KeyGlass" android:text="TAB"/>
            <Button android:id="@+id/keyEsc"        style="@style/KeyGlass" android:text="ESC"/>
            <Button android:id="@+id/keyDollar"     style="@style/KeyGlass" android:text="$"/>
            <Button android:id="@+id/keySlash"      style="@style/KeyGlass" android:text="/"/>
            <Button android:id="@+id/keyPipe"       style="@style/KeyGlass" android:text="|"/>
            <Button android:id="@+id/keyTilde"      style="@style/KeyGlass" android:text="~"/>
            <Button android:id="@+id/keyUnderscore" style="@style/KeyGlass" android:text="_"/>
            <Button android:id="@+id/keyUp"         style="@style/KeyGlass" android:text="↑"/>
            <Button android:id="@+id/keyDown"       style="@style/KeyGlass" android:text="↓"/>
            <Button android:id="@+id/keyLeft"       style="@style/KeyGlass" android:text="←"/>
            <Button android:id="@+id/keyRight"      style="@style/KeyGlass" android:text="→"/>
            <Button android:id="@+id/keyEditor"     style="@style/KeyGlass" android:text="IDE"/>
        </LinearLayout>
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
            android:layout_height="match_parent"
            android:fontFamily="monospace"
            android:gravity="center_vertical"
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
            android:text="RUN"
            android:textColor="#000000"/>
    </LinearLayout>
</LinearLayout>
XML_MAIN

cat > app/src/main/res/layout/fragment_terminal.xml <<'XML_FT'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/consoleScroll"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
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
XML_FT

cat > app/src/main/res/layout/activity_code_editor.xml <<'XML_ED'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000"
    android:orientation="vertical"
    android:fitsSystemWindows="true">

    <com.google.android.material.appbar.MaterialToolbar
        android:id="@+id/toolbar"
        android:layout_width="match_parent"
        android:layout_height="?attr/actionBarSize"
        android:background="#0A0E14"
        app:navigationIcon="@android:drawable/ic_menu_close_clear_cancel"
        app:title="IDE"
        app:titleTextColor="#22D3EE"
        app:subtitleTextColor="#64748B"/>

    <HorizontalScrollView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="#0A0E14"
        android:scrollbars="none">

        <LinearLayout
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:padding="4dp">

            <Button android:id="@+id/btnNew"  style="@style/KeyGlass" android:text="جديد"/>
            <Button android:id="@+id/btnOpen" style="@style/KeyGlass" android:text="فتح"/>
            <Button android:id="@+id/btnSave" style="@style/KeyGlass" android:text="حفظ"/>
            <Button android:id="@+id/btnFind" style="@style/KeyGlass" android:text="بحث"/>
            <Button android:id="@+id/btnRun"  style="@style/KeyGlass" android:text="تشغيل"/>
        </LinearLayout>
    </HorizontalScrollView>

    <HorizontalScrollView
        android:id="@+id/editorScroll"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:background="#000000"
        android:scrollbars="vertical">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal">

            <LinearLayout
                android:id="@+id/lineNumbers"
                android:layout_width="48dp"
                android:layout_height="wrap_content"
                android:background="#050505"
                android:orientation="vertical"
                android:paddingTop="8dp"
                android:paddingBottom="8dp"/>

            <EditText
                android:id="@+id/editorInput"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:background="#000000"
                android:fontFamily="monospace"
                android:gravity="top|start"
                android:inputType="textMultiLine|textNoSuggestions"
                android:minLines="20"
                android:padding="8dp"
                android:textColor="#E2E8F0"
                android:textColorHint="#334155"
                android:textSize="13sp"/>
        </LinearLayout>
    </HorizontalScrollView>
</LinearLayout>
XML_ED

# ═════════════════════════════════════════════════════════════
# 8. Values
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/values/styles.xml <<'XML_STY'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="KeyGlass" parent="Widget.Material3.Button.TonalButton">
        <item name="android:layout_width">wrap_content</item>
        <item name="android:layout_height">38dp</item>
        <item name="android:layout_marginEnd">4dp</item>
        <item name="android:minWidth">48dp</item>
        <item name="android:textSize">11sp</item>
        <item name="android:fontFamily">monospace</item>
        <item name="android:paddingStart">10dp</item>
        <item name="android:paddingEnd">10dp</item>
        <item name="backgroundTint">#1E293B</item>
        <item name="android:textColor">#22D3EE</item>
    </style>
</resources>
XML_STY

cat > app/src/main/res/values/strings.xml <<'XML_STR'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">awlqy</string>
    <string name="app_tagline">Hacker Terminal · IDE</string>
    <string name="notification_channel_session">جلسة awlqy</string>
    <string name="notification_session_active">awlqy process running in background</string>
</resources>
XML_STR

# ═════════════════════════════════════════════════════════════
# 9. Menus
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/menu/main_menu.xml <<'XML_M1'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto">
    <item android:id="@+id/action_new_session"   android:title="جلسة جديدة"        app:showAsAction="never"/>
    <item android:id="@+id/action_close_session" android:title="إغلاق الجلسة"      app:showAsAction="never"/>
    <item android:id="@+id/action_open_editor"   android:title="محرر الكود"        app:showAsAction="never"/>
    <item android:id="@+id/action_install_hub"   android:title="مركز الأدوات"      app:showAsAction="never"/>
    <item android:id="@+id/action_update"        android:title="التحقق من التحديثات" app:showAsAction="never"/>
    <item android:id="@+id/action_settings"      android:title="الإعدادات"         app:showAsAction="never"/>
    <item android:id="@+id/action_about"         android:title="حول التطبيق"       app:showAsAction="never"/>
</menu>
XML_M1

cat > app/src/main/res/menu/editor_menu.xml <<'XML_M2'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto">
    <item android:id="@+id/action_editor_save" android:title="حفظ" app:showAsAction="never"/>
    <item android:id="@+id/action_editor_run"  android:title="تشغيل" app:showAsAction="never"/>
</menu>
XML_M2

# ═════════════════════════════════════════════════════════════
# 10. ic_terminal drawable
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/drawable/ic_terminal.xml <<'XML_IC'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#22D3EE" android:pathData="M4,4h16v16H4zM6,7l3,3l-3,3v-2h4v-2H6zM11,13h6v2h-6z"/>
</vector>
XML_IC

# ═════════════════════════════════════════════════════════════
# 11. AndroidManifest.xml
# ═════════════════════════════════════════════════════════════
cat > app/src/main/AndroidManifest.xml <<'XML_MAN'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28" tools:ignore="ScopedStorage"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
    <uses-permission android:name="android.permission.VIBRATE"/>

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

        <activity
            android:name=".CodeEditorActivity"
            android:exported="false"
            android:configChanges="orientation|screenSize|keyboardHidden|uiMode"
            android:windowSoftInputMode="adjustResize"
            android:label="awlqy IDE"/>

        <service
            android:name=".service.TerminalService"
            android:exported="false"
            android:foregroundServiceType="dataSync"/>

        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths"/>
        </provider>

        <meta-data android:name="com.awlqy.DEVELOPER" android:value="حسين الخلاقي"/>
    </application>
</manifest>
XML_MAN

# ═════════════════════════════════════════════════════════════
# 12. AwlqyApp.kt (تحديث القناة)
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/AwlqyApp.kt <<'KOT_APP'
package com.awlqy.terminal

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import timber.log.Timber
import java.io.File

class AwlqyApp : Application() {

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) Timber.plant(Timber.DebugTree())

        File(filesDir, "home").mkdirs()
        File(filesDir, "usr/bin").mkdirs()
        File(filesDir, "apk-work").mkdirs()

        createChannel()
        Timber.i("awlqy phase-5 booted — developer: حسين الخلاقي")
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_session),
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            (getSystemService(NotificationManager::class.java))
                .createNotificationChannel(ch)
        }
    }

    companion object {
        const val CHANNEL_ID = "awlqy_session"
        const val DEVELOPER = "حسين الخلاقي"
    }
}
KOT_APP

# ═════════════════════════════════════════════════════════════
# 13. themes.xml + file_paths.xml
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/values/themes.xml <<'XML_THM'
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.Awlqy" parent="Theme.Material3.Dark.NoActionBar">
        <item name="colorPrimary">#22D3EE</item>
        <item name="colorOnPrimary">#000000</item>
        <item name="colorSurface">#0A0E14</item>
        <item name="colorOnSurface">#E2E8F0</item>
        <item name="android:colorBackground">#000000</item>
        <item name="android:statusBarColor">#000000</item>
        <item name="android:navigationBarColor">#000000</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowLightNavigationBar" tools:targetApi="27">false</item>
        <item name="android:windowBackground">#000000</item>
    </style>
</resources>
XML_THM

cat > app/src/main/res/xml/file_paths.xml <<'XML_FP'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="apk_cache" path="."/>
    <files-path name="internal_files" path="."/>
    <external-path name="apk_external" path="."/>
    <external-files-path name="external_files" path="."/>
</paths>
XML_FP

# ═════════════════════════════════════════════════════════════
# التحقق
# ═════════════════════════════════════════════════════════════
echo ""
echo "▶ [phase5] الملفات الأساسية:"
ls -1 app/src/main/java/com/awlqy/terminal/*.kt
ls -1 app/src/main/java/com/awlqy/terminal/core/*.kt
ls -1 app/src/main/java/com/awlqy/terminal/ui/*.kt
ls -1 app/src/main/java/com/awlqy/terminal/service/*.kt
echo ""
echo "▶ [phase5] Layouts:"
ls -1 app/src/main/res/layout/*.xml
echo ""
echo "▶ [phase5] أول سطر من كل ملف Kotlin (يجب أن يبدأ بـ package):"
for f in app/src/main/java/com/awlqy/terminal/**/*.kt app/src/main/java/com/awlqy/terminal/*.kt; do
    [ -f "$f" ] && echo "  $(head -n 1 "$f")  ← $f"
done
echo ""
echo "✔ [phase5] انتهى."
echo "   git add -A"
echo "   git commit -m 'phase-5: hacker terminal overhaul (multi-session + service + editor)'"
echo "   git push"
