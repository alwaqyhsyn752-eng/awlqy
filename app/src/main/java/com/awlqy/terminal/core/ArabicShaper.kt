package com.awlqy.terminal.core

import java.text.Bidi

object ArabicShaper {

    fun needsBidi(text: String): Boolean {
        if (text.isEmpty()) return false
        val chars = text.toCharArray()
        return Bidi.requiresBidi(chars, 0, chars.size)
    }

    fun reorderLine(line: String): String {
        if (line.isEmpty()) return line
        if (!needsBidi(line)) return line
        val chars = line.toCharArray()
        val bidi = Bidi(chars, 0, null, 0, chars.size,
            Bidi.DIRECTION_DEFAULT_LEFT_TO_RIGHT)
        if (bidi.isLeftToRight) return line
        val levels = ByteArray(chars.size)
        bidi.getLevels(levels, 0)
        val boxes: Array<Any> = Array(chars.size) { i -> chars[i] }
        Bidi.reorderVisually(levels, 0, boxes, 0, chars.size)
        val out = CharArray(chars.size)
        var i = 0
        while (i < boxes.size) { out[i] = boxes[i] as Char; i++ }
        return String(out)
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
