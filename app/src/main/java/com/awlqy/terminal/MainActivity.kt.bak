package com.awlqy.terminal

import android.content.Context
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.awlqy.terminal.core.TerminalBuffer
import com.awlqy.terminal.core.TerminalSession
import com.awlqy.terminal.databinding.ActivityMainBinding
import com.google.android.material.button.MaterialButton
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import java.io.File

class MainActivity : AppCompatActivity(), TerminalSession.Listener {

    private lateinit var binding: ActivityMainBinding

    private val sessions = ArrayList<TerminalSession>()
    private val buffers = HashMap<String, TerminalBuffer>()
    private var activeIdx = 0

    private var ctrlLatched = false
    private var altLatched = false
    private var suppressInput = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.consoleText.typeface = Typeface.MONOSPACE
        binding.consoleText.textSize = 12f

        binding.gearBtn.setOnClickListener { showSettings() }

        buildAccessoryBar()
        wireSoftKeyboard()
        newSession()
    }

    override fun onDestroy() {
        for (s in sessions) s.stop()
        super.onDestroy()
    }

    // ─── Session management ──────────────────────────────

    private fun newSession() {
        val home = File(filesDir, "home").apply { mkdirs() }
        val s = TerminalSession(
            name = "session-${sessions.size + 1}",
            shellPath = "/system/bin/sh",
            cwd = home,
            rows = 24,
            cols = 80
        )
        s.listener = this
        sessions.add(s)
        buffers[s.name] = TerminalBuffer()
        activeIdx = sessions.size - 1
        s.start()
        renderTabs()
        renderConsole()
    }

    private fun closeCurrent() {
        if (sessions.size <= 1) { toast("لا يمكن إغلاق الجلسة الأخيرة"); return }
        val s = sessions[activeIdx]
        s.stop()
        sessions.removeAt(activeIdx)
        buffers.remove(s.name)
        if (activeIdx >= sessions.size) activeIdx = sessions.size - 1
        renderTabs()
        renderConsole()
    }

    private fun activeSession(): TerminalSession? = sessions.getOrNull(activeIdx)
    private fun activeBuffer(): TerminalBuffer? = activeSession()?.let { buffers[it.name] }

    private fun renderTabs() {
        val bar = binding.sessionTabs
        bar.removeAllViews()
        for (i in sessions.indices) {
            val s = sessions[i]
            val tv = TextView(this).apply {
                text = "[${i + 1}]"
                typeface = Typeface.MONOSPACE
                textSize = 12f
                gravity = Gravity.CENTER
                setPadding(28, 12, 28, 12)
                setTextColor(if (i == activeIdx) 0xFF22D3EE.toInt() else 0xFF64748B.toInt())
                setBackgroundColor(if (i == activeIdx) 0xFF1E293B.toInt() else 0xFF0A0E14.toInt())
                setOnClickListener {
                    activeIdx = i
                    renderTabs()
                    renderConsole()
                    focusTerminal()
                }
                setOnLongClickListener {
                    if (i == activeIdx) closeCurrent()
                    else {
                        MaterialAlertDialogBuilder(this@MainActivity)
                            .setTitle("إغلاق الجلسة")
                            .setMessage("إغلاق ${s.name}؟")
                            .setPositiveButton("إغلاق") { _, _ ->
                                s.stop()
                                sessions.removeAt(i)
                                buffers.remove(s.name)
                                if (activeIdx >= sessions.size) activeIdx = sessions.size - 1
                                renderTabs()
                                renderConsole()
                            }
                            .setNegativeButton("إلغاء", null)
                            .show()
                    }
                    true
                }
            }
            bar.addView(tv)
        }
        val add = TextView(this).apply {
            text = "[+]"
            typeface = Typeface.MONOSPACE
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(28, 12, 28, 12)
            setTextColor(0xFF4ADE80.toInt())
            setOnClickListener { newSession() }
        }
        bar.addView(add)
    }

    private fun renderConsole() {
        val b = activeBuffer() ?: return
        binding.consoleText.text = b.snapshot()
        binding.consoleScroll.post { binding.consoleScroll.fullScroll(View.FOCUS_DOWN) }
    }

    // ─── TerminalSession.Listener ───────────────────────

    override fun onOutput(session: TerminalSession, data: String) {
        if (buffers[session.name] == null) buffers[session.name] = TerminalBuffer()
        buffers[session.name]!!.append(data)
        if (sessions.getOrNull(activeIdx) === session) {
            binding.consoleText.text = buffers[session.name]!!.snapshot()
            binding.consoleScroll.post { binding.consoleScroll.fullScroll(View.FOCUS_DOWN) }
        }
    }

    override fun onExited(session: TerminalSession, exitCode: Int) {
        onOutput(session, "\n[session exited: $exitCode]\n")
    }

    // ─── Accessory bar ──────────────────────────────────

    private fun buildAccessoryBar() {
        val container = binding.accessoryContainer

        val row1 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        row1.addView(makeKey("KEYBOARD", 0xFF1E293B.toInt()) { toggleSoftKeyboard() })
        row1.addView(makeKey("NEW", 0xFF4ADE80.toInt()) { newSession() })
        row1.addView(makeKey("CLOSE", 0xFFEF4444.toInt()) { closeCurrent() })
        container.addView(row1)

        val row2 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        row2.addView(makeKey("ESC")  { sendBytes(byteArrayOf(0x1B)) })
        row2.addView(makeKey("TAB")  { sendBytes(byteArrayOf(0x09)) })
        row2.addView(makeKey("CTRL", 0xFF1E293B.toInt()) { toggleCtrl() })
        row2.addView(makeKey("ALT",  0xFF1E293B.toInt()) { toggleAlt() })
        row2.addView(makeKey("HOME") { sendSeq("\u001B[H") })
        row2.addView(makeKey("UP")   { sendSeq("\u001B[A") })
        row2.addView(makeKey("END")  { sendSeq("\u001B[F") })
        row2.addView(makeKey("PGUP") { sendSeq("\u001B[5~") })
        container.addView(row2)

        val row3 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        row3.addView(makeKey("|")    { sendSeq("|") })
        row3.addView(makeKey("/")    { sendSeq("/") })
        row3.addView(makeKey("-")    { sendSeq("-") })
        row3.addView(makeKey("LEFT") { sendSeq("\u001B[D") })
        row3.addView(makeKey("DOWN") { sendSeq("\u001B[B") })
        row3.addView(makeKey("RGHT") { sendSeq("\u001B[C") })
        row3.addView(makeKey("PGDN") { sendSeq("\u001B[6~") })
        container.addView(row3)
    }

    private fun makeKey(
        label: String,
        bg: Int = 0xFF1E293B.toInt(),
        action: () -> Unit
    ): MaterialButton {
        val density = resources.displayMetrics.density
        val lp = LinearLayout.LayoutParams(
            0, (38 * density).toInt(), 1f
        ).apply {
            marginStart = (2 * density).toInt()
            marginEnd = (2 * density).toInt()
        }
        return MaterialButton(this).apply {
            text = label
            textSize = 11f
            typeface = Typeface.MONOSPACE
            minWidth = 0
            minHeight = 0
            insetTop = 0
            insetBottom = 0
            layoutParams = lp
            setTextColor(0xFFE2E8F0.toInt())
            setBackgroundColor(bg)
            setOnClickListener { action() }
        }
    }

    private fun toggleCtrl() {
        ctrlLatched = !ctrlLatched
        if (ctrlLatched) altLatched = false
        refreshModifierVisuals()
    }

    private fun toggleAlt() {
        altLatched = !altLatched
        if (altLatched) ctrlLatched = false
        refreshModifierVisuals()
    }

    private fun refreshModifierVisuals() {
        val container = binding.accessoryContainer
        val row2 = container.getChildAt(1) as? LinearLayout ?: return
        for (i in 0 until row2.childCount) {
            val v = row2.getChildAt(i) as? MaterialButton ?: continue
            when (v.text.toString()) {
                "CTRL" -> v.setBackgroundColor(
                    if (ctrlLatched) 0xFFEF4444.toInt() else 0xFF1E293B.toInt()
                )
                "ALT" -> v.setBackgroundColor(
                    if (altLatched) 0xFFFACC15.toInt() else 0xFF1E293B.toInt()
                )
            }
        }
    }

    // ─── Input routing ───────────────────────────────────

    private fun wireSoftKeyboard() {
        binding.inputEdit.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) {
                if (suppressInput) return
                val text = s?.toString() ?: return
                if (text.isEmpty()) return
                handleTypedText(text)
                suppressInput = true
                binding.inputEdit.setText("")
                suppressInput = false
            }
        })

        binding.inputEdit.setOnKeyListener { _, keyCode, event ->
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DEL, KeyEvent.KEYCODE_FORWARD_DEL -> {
                        sendBytes(byteArrayOf(0x7F)); true
                    }
                    KeyEvent.KEYCODE_ENTER -> { sendBytes(byteArrayOf(0x0D)); true }
                    KeyEvent.KEYCODE_TAB   -> { sendBytes(byteArrayOf(0x09)); true }
                    KeyEvent.KEYCODE_ESCAPE-> { sendBytes(byteArrayOf(0x1B)); true }
                    else -> false
                }
            } else false
        }

        binding.sendButton.setOnClickListener { sendBytes(byteArrayOf(0x0D)) }
    }

    private fun handleTypedText(text: String) {
        val session = activeSession() ?: return
        for (ch in text) {
            val byte = ch.code
            if (altLatched) {
                session.writeBytes(byteArrayOf(0x1B))
                altLatched = false
                refreshModifierVisuals()
            }
            if (ctrlLatched) {
                val code = when {
                    byte in 'a'.code..'z'.code -> byte - 0x60
                    byte in 'A'.code..'Z'.code -> byte - 0x40
                    byte == ' '.code -> 0
                    else -> byte
                }
                session.writeBytes(byteArrayOf(code.toByte()))
                ctrlLatched = false
                refreshModifierVisuals()
            } else {
                session.writeBytes(ch.toString().toByteArray(Charsets.UTF_8))
            }
        }
    }

    private fun sendBytes(bytes: ByteArray) {
        val session = activeSession() ?: return
        var payload = bytes
        if (altLatched && bytes.isNotEmpty() && bytes[0] != 0x1B.toByte()) {
            payload = byteArrayOf(0x1B.toByte()) + bytes
            altLatched = false
            refreshModifierVisuals()
        }
        if (ctrlLatched && bytes.size == 1) {
            val b = bytes[0].toInt() and 0xFF
            val code = when {
                b in 0x61..0x7A -> b - 0x60
                b in 0x41..0x5A -> b - 0x40
                b == 0x20 -> 0
                b == 0x3F -> 0x7F
                else -> b
            }
            payload = byteArrayOf(code.toByte())
            ctrlLatched = false
            refreshModifierVisuals()
        }
        session.writeBytes(payload)
        focusTerminal()
    }

    private fun sendSeq(seq: String) {
        val session = activeSession() ?: return
        session.writeText(seq)
        focusTerminal()
    }

    private fun toggleSoftKeyboard() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (binding.inputEdit.hasFocus()) {
            imm.hideSoftInputFromWindow(binding.inputEdit.windowToken, 0)
        } else {
            focusTerminal()
        }
    }

    private fun focusTerminal() {
        binding.inputEdit.requestFocus()
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.showSoftInput(binding.inputEdit, InputMethodManager.SHOW_IMPLICIT)
    }

    // ─── Settings ────────────────────────────────────────

    private fun showSettings() {
        val msg = buildString {
            append("التطبيق: awlqy Terminal & IDE\n")
            append("الإصدار: 1.0.0\n")
            append("المطوّر: حسين الخلاقي\n")
            append("GitHub: alwaqyhsyn752-eng\n")
            append("المحرّك: Native PTY\n")
            append("API: ").append(Build.VERSION.SDK_INT).append("\n")
            append("الجلسات: ").append(sessions.size)
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("الإعدادات")
            .setMessage(msg)
            .setPositiveButton("حسناً", null)
            .show()
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
}
