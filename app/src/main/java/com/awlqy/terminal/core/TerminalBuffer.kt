package com.awlqy.terminal.core

import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import java.util.ArrayDeque

/**
 * معالج ANSI بسيط:
 * - SGR (ألوان) → Spannable
 * - \r → عودة إلى بداية السطر
 * - \n → سطر جديد
 * - \b → حذف حرف
 * - ESC[2J → مسح الشاشة
 * - ESC[H → home
 * - ESC[K → مسح السطر
 * - باقي ESC → تُحذف
 */
class TerminalBuffer(private val maxChars: Int = 200_000) {

    class Style(var fg: Int = DEFAULT_FG) {
        fun copy(): Style = Style(fg)
        companion object { const val DEFAULT_FG = 0xFFE2E8F0.toInt() }
    }

    private val sb = SpannableStringBuilder()
    private var curStyle = Style()
    private var escapeBuf = StringBuilder()
    private var inEscape = false
    private var inCsi = false
    private var csiBuf = StringBuilder()

    private val ansiColors = intArrayOf(
        0xFF000000.toInt(), 0xFFEF4444.toInt(), 0xFF4ADE80.toInt(), 0xFFFACC15.toInt(),
        0xFF3B82F6.toInt(), 0xFFA855F7.toInt(), 0xFF22D3EE.toInt(), 0xFFE2E8F0.toInt(),
        0xFF64748B.toInt(), 0xFFF87171.toInt(), 0xFF86EFAC.toInt(), 0xFFFDE047.toInt(),
        0xFF60A5FA.toInt(), 0xFFC084FC.toInt(), 0xFF67E8F9.toInt(), 0xFFFFFFFF.toInt()
    )

    fun append(text: String) {
        var i = 0
        val n = text.length
        while (i < n) {
            val c = text[i]
            if (inEscape) {
                handleEscape(c)
                i++
                continue
            }
            when (c) {
                '\u001B' -> { inEscape = true; escapeBuf.setLength(0); i++ }
                '\n'      -> { sb.append('\n'); i++ }
                '\r'      -> { returnToLineStart(); i++ }
                '\b'      -> { backspace(); i++ }
                '\t'      -> { sb.append("        ".take(8 - (currentCol() % 8))); i++ }
                '\u0007'  -> { i++ } // bell - ignore
                else      -> { appendChar(c); i++ }
            }
        }
        trim()
    }

    private fun handleEscape(c: Char) {
        if (!inCsi && c == '[') { inCsi = true; csiBuf.setLength(0); return }
        if (inCsi) {
            if (c in '0'..'9' || c == ';' || c == '?') { csiBuf.append(c); return }
            // final char
            applyCsi(csiBuf.toString(), c)
            inCsi = false
            inEscape = false
            csiBuf.setLength(0)
            return
        }
        // Two-char escape (e.g., ESC c, ESC 7, ESC 8)
        // We simply ignore.
        inEscape = false
    }

    private fun applyCsi(params: String, final: Char) {
        when (final) {
            'm' -> applySgr(params)
            'J' -> {
                val p = params.toIntOrNull() ?: 0
                if (p == 2 || p == 3) sb.clear()
            }
            'H', 'f' -> { /* home - ignore for now */ }
            'K' -> {
                val p = params.toIntOrNull() ?: 0
                if (p == 0) clearToEndOfLine() else if (p == 2) clearLine()
            }
            'A' -> { /* cursor up */ }
            'B' -> { /* cursor down */ }
            'C' -> { /* cursor right */ }
            'D' -> { /* cursor left */ }
            else -> { /* ignore */ }
        }
    }

    private fun applySgr(params: String) {
        val parts = params.split(';').mapNotNull { it.toIntOrNull() }
        if (parts.isEmpty()) { curStyle = Style(); return }
        var i = 0
        while (i < parts.size) {
            val p = parts[i]
            when {
                p == 0  -> curStyle = Style()
                p in 30..37 -> curStyle.fg = ansiColors[p - 30]
                p in 90..97 -> curStyle.fg = ansiColors[p - 90 + 8]
                p == 39 -> curStyle.fg = Style.DEFAULT_FG
                p == 1  -> { /* bold - keep color */ }
                p == 22 -> { /* normal - keep color */ }
                p == 38 && i + 4 < parts.size && parts[i + 1] == 5 -> {
                    val idx = parts[i + 2]
                    if (idx in 0..15) curStyle.fg = ansiColors[idx]
                    i += 2
                }
            }
            i++
        }
    }

    private fun appendChar(c: Char) {
        val start = sb.length
        sb.append(c)
        sb.setSpan(
            ForegroundColorSpan(curStyle.fg),
            start, sb.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }

    private fun currentCol(): Int {
        val nl = sb.indexOf("\n", sb.length - 1)
        val lineStart = if (nl < 0) 0 else nl + 1
        return sb.length - lineStart
    }

    private fun returnToLineStart() {
        val nl = sb.lastIndexOf("\n")
        val lineStart = nl + 1
        if (lineStart < sb.length) sb.delete(lineStart, sb.length)
    }

    private fun backspace() {
        if (sb.isEmpty()) return
        sb.delete(sb.length - 1, sb.length)
    }

    private fun clearToEndOfLine() {
        val nl = sb.indexOf("\n", sb.length - 1)
        if (nl < 0) sb.delete(sb.length, sb.length)
    }

    private fun clearLine() {
        val nl = sb.lastIndexOf("\n")
        val start = nl + 1
        if (start < sb.length) sb.delete(start, sb.length)
    }

    private fun trim() {
        if (sb.length <= maxChars) return
        val cut = sb.length - maxChars
        val nl = sb.indexOf("\n", cut)
        val drop = if (nl > 0) nl + 1 else cut
        sb.delete(0, drop)
    }

    fun snapshot(): CharSequence = sb
    fun clear() { sb.clear(); curStyle = Style() }
}
