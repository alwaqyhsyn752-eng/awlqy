#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · fix-arabic.sh — إصلاح ArabicShaper API
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [fix-arabic] إعادة كتابة ArabicShaper.kt"

cat > app/src/main/java/com/awlqy/terminal/core/ArabicShaper.kt <<'EOF_AR'
package com.awlqy.terminal.core

import java.text.Bidi

/**
 * محرك معالجة النص العربي عبر java.text.Bidi المدمج في Android.
 * - يكشف الأسطر التي تحتاج bidi.
 * - يعيد ترتيب الحروف بصرياً عند الحاجة.
 */
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
        val bidi = Bidi(
            chars,
            0,
            null,
            0,
            chars.size,
            Bidi.DIRECTION_DEFAULT_LEFT_TO_RIGHT
        )
        if (bidi.isLeftToRight) return line

        val levels = ByteArray(chars.size)
        bidi.getLevels(levels, 0)

        val boxes: Array<Any> = Array(chars.size) { i -> chars[i] }
        Bidi.reorderVisually(levels, 0, boxes, 0, chars.size)

        val out = CharArray(chars.size)
        var i = 0
        while (i < boxes.size) {
            out[i] = boxes[i] as Char
            i++
        }
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
EOF_AR

echo "▶ [fix-arabic] التحقق"
grep -n "Bidi(" app/src/main/java/com/awlqy/terminal/core/ArabicShaper.kt

echo ""
echo "✔ تم الإصلاح. الآن:"
echo "   git add -A"
echo "   git commit -m 'fix: Bidi constructor + reorderVisually Object[]'"
echo "   git push"
