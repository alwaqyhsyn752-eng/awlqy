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
