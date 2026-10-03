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
