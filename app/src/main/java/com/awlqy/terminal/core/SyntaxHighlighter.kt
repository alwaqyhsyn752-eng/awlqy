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
