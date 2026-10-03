package com.awlqy.terminal.core

import java.text.Bidi

/**
 * محرك معالجة النص العربي عبر java.text.Bidi المدمج في Android.
 * - يكشف الأسطر التي تحتاج bidi.
 * - يعيد ترتيب الحروف بصرياً عند الحاجة.
 * - تشكيل الحروف (connecting) يقوم به خط النظام تلقائياً.
 */
object ArabicShaper {

    fun needsBidi(text: String): Boolean {
        if (text.isEmpty()) return false
        return Bidi.requiresBidi(text.toCharArray(), 0, text.length)
    }

    fun reorderLine(line: String): String {
        if (line.isEmpty()) return line
        if (!needsBidi(line)) return line
        val chars = line.toCharArray()
        val bidi = Bidi(chars, 0, chars.size, Bidi.DIRECTION_DEFAULT_LEFT_TO_RIGHT)
        if (bidi.isLeftToRight) return line
        val levels = ByteArray(chars.size)
        bidi.getLevels(levels, chars.size)
        Bidi.reorderVisually(levels, 0, chars, 0, chars.size)
        return String(chars)
    }

    fun shape(text: String): String {
        if (text.isEmpty()) return text
        val sb = StringBuilder(text.length + 8)
        var i = 0
        var lineStart = 0
        while (i <= text.length) {
            if (i == text.length || text[i] == '\n') {
                val line = text.substring(lineStart, i)
                sb.append(reorderLine(line))
                if (i < text.length) sb.append('\n')
                lineStart = i + 1
            }
            i++
        }
        return sb.toString()
    }
}
