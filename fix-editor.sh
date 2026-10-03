#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

F="app/src/main/java/com/awlqy/terminal/CodeEditorActivity.kt"

if [ ! -f "$F" ]; then
    echo "ℹ $F غير موجود — لا شيء للإصلاح."
    echo "   (يبدو أنك شغّلت safe-reset.sh — الملف أُزيل بشكل مقصود.)"
    exit 0
fi

echo "▶ [fix-editor] قبل:"
grep -n "emptyArray" "$F" || true

# استبدال دقيق: فقط السطر الذي يحتوي listFiles()?.sortedBy
sed -i 's|dir\.listFiles()?\.sortedBy { it\.name } ?: emptyArray()|dir.listFiles()?.sortedBy { it.name } ?: emptyList<File>()|' "$F"

echo "▶ [fix-editor] بعد:"
grep -n "listFiles()?.sortedBy" "$F" || true

# تحقق
if grep -q "?: emptyArray()" "$F"; then
    echo "⚠ لا يزال هناك emptyArray — طبّق تعديلاً يدوياً"
    exit 1
fi

echo ""
echo "✔ تم الإصلاح. الآن:"
echo "   git add -A"
echo "   git commit -m 'fix: emptyList() instead of emptyArray() in CodeEditorActivity'"
echo "   git push"
