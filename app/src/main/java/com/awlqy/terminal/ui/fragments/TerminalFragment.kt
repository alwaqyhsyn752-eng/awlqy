package com.awlqy.terminal.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import androidx.fragment.app.Fragment
import com.awlqy.terminal.R
import com.awlqy.terminal.core.TerminalSession
import com.awlqy.terminal.databinding.FragmentTerminalBinding
import java.io.File

class TerminalFragment : Fragment() {

    private var _b: FragmentTerminalBinding? = null
    private val b get() = _b!!
    private var session: TerminalSession? = null

    override fun onCreateView(i: LayoutInflater, c: ViewGroup?, s: Bundle?): View {
        _b = FragmentTerminalBinding.inflate(i, c, false)
        return b.root
    }

    override fun onViewCreated(v: View, s: Bundle?) {
        val name = arguments?.getString(ARG_NAME) ?: "main"
        val home = File(requireContext().filesDir, "home").apply { mkdirs() }.absolutePath
        val shell = "/system/bin/sh"

        session = TerminalSession(name, shell, home, 24, 80) { chunk ->
            b.terminalView.append(chunk)
        }.also { it.start() }

        b.terminalView.onSizeChanged = { r, c -> session?.resize(r, c) }

        b.btnSend.setOnClickListener { sendCurrent() }
        b.inputEdit.setOnEditorActionListener { _, id, _ ->
            if (id == EditorInfo.IME_ACTION_SEND) { sendCurrent(); true } else false
        }

        b.btnCtrlC.setOnClickListener { session?.write("\u0003") }
        b.btnCtrlD.setOnClickListener { session?.write("\u0004") }
        b.btnCtrlZ.setOnClickListener { session?.write("\u001A") }
        b.btnTab.setOnClickListener   { session?.write("\t") }
        b.btnEsc.setOnClickListener   { session?.write("\u001B") }
        b.btnUp.setOnClickListener    { session?.write("\u001B[A") }
        b.btnDown.setOnClickListener  { session?.write("\u001B[B") }
        b.btnLeft.setOnClickListener  { session?.write("\u001B[D") }
        b.btnRight.setOnClickListener { session?.write("\u001B[C") }
        b.btnClear.setOnClickListener { b.terminalView.clear() }
    }

    private fun sendCurrent() {
        val txt = b.inputEdit.text.toString()
        if (txt.isEmpty()) { session?.write("\n"); return }
        session?.write(txt + "\n")
        b.inputEdit.setText("")
    }

    override fun onDestroyView() {
        session?.stop()
        _b = null
        super.onDestroyView()
    }

    companion object {
        private const val ARG_NAME = "name"
        fun newInstance(name: String) = TerminalFragment().apply {
            arguments = Bundle().apply { putString(ARG_NAME, name) }
        }
    }
}
