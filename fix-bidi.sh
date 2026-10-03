#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

cat > app/src/main/java/com/awlqy/terminal/core/ArabicShaper.kt <<'EOF_AR'
package com.awlqy.terminal.core

import java.text.Bidi

/**
 * معالج النص العربي.
 *
 * ملاحظة معمارية:
 * Android TextView يعالج Bidi وتشكيل (shaping) العربية تلقائياً عبر
 * خط النظام (Noto Naskh / Noto Sans Arabic). لا حاجة لإعادة ترتيب يدوي
 * — بل إن إعادة الترتيب قد تسبب انعكاساً مزدوجاً.
 *
 * لذلك: نوفر واجهة API بسيطة للاستخدام المستقبلي، مع كشف يحتاج bidi فقط.
 */
object ArabicShaper {

    fun needsBidi(text: String): Boolean {
        if (text.isEmpty()) return false
        val chars = text.toCharArray()
        return Bidi.requiresBidi(chars, 0, chars.size)
    }

    fun reorderLine(line: String): String = line

    fun shape(text: String): String = text
}
EOF_AR

echo "✔ تم التحديث."
echo "   git add -A"
echo "   git commit -m 'fix: Android Bidi has no getLevels(); rely on TextView native shaping'"
echo "   git push"
