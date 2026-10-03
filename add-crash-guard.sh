#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

F="app/src/main/java/com/awlqy/terminal/MainActivity.kt"

echo "▶ [guard] نسخة احتياطية"
cp -f "$F" "$F.bak"

echo "▶ [guard] إضافة try/catch في onCreate + طباعة الخطأ للشاشة"

python3 - <<'PYEOF'
import pathlib, re
p = pathlib.Path("app/src/main/java/com/awlqy/terminal/MainActivity.kt")
s = p.read_text(encoding="utf-8")

# غلّف جسم onCreate في try/catch
old = '''    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.consoleText.typeface = Typeface.MONOSPACE
        binding.consoleText.textSize = 12f

        binding.gearBtn.setOnClickListener { showSettings() }

        buildAccessoryBar()
        wireSoftKeyboard()
        newSession()
    }'''

new = '''    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            binding = ActivityMainBinding.inflate(layoutInflater)
            setContentView(binding.root)

            binding.consoleText.typeface = Typeface.MONOSPACE
            binding.consoleText.textSize = 12f

            binding.gearBtn.setOnClickListener { showSettings() }

            buildAccessoryBar()
            wireSoftKeyboard()
            newSession()
        } catch (t: Throwable) {
            showFatal(t)
        }
    }

    private fun showFatal(t: Throwable) {
        val sw = java.io.StringWriter()
        t.printStackTrace(java.io.PrintWriter(sw))
        val msg = sw.toString()
        android.util.Log.e("awlqy", msg)
        val tv = android.widget.TextView(this).apply {
            text = "awlqy crashed:\\n\\n$msg"
            typeface = android.graphics.Typeface.MONOSPACE
            textSize = 10f
            setTextColor(0xFFFF5C7A.toInt())
            setPadding(24, 24, 24, 24)
            setBackgroundColor(0xFF000000.toInt())
        }
        val scroll = android.widget.ScrollView(this).apply { addView(tv) }
        setContentView(scroll)
    }'''

if old in s:
    s = s.replace(old, new)
    p.write_text(s, encoding="utf-8")
    print("✔ patched onCreate with crash guard")
else:
    print("⚠ لم أجد النص الأصلي — الملف قد يكون معدلاً")
PYEOF

echo ""
echo "▶ [guard] تحقق:"
grep -n "showFatal\|try {" "$F" | head -5

echo ""
echo "✔ انتهى. الآن:"
echo "   git add -A"
echo "   git commit -m 'debug: crash guard in onCreate'"
echo "   git push"
