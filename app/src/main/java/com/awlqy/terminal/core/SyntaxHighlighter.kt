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
