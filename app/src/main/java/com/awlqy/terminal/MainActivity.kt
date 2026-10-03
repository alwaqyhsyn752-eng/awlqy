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

        startTerminalService()

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

    private fun startTerminalService() {
        val i = Intent(this, TerminalService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(i)
        } else {
            startService(i)
        }
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
