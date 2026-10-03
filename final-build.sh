#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · final-build.sh
#  يحل مشكلة libawlqy_pty.so — يبني بـ ProcessBuilder فقط
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p .github/workflows
mkdir -p app/src/main/java/com/awlqy/terminal

# ═════════════════════════════════════════════════════════════
# 1. .github/workflows/build.yml
# ═════════════════════════════════════════════════════════════
cat > .github/workflows/build.yml <<'YML_EOF'
name: Build awlqy APK

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: awlqy-build-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    name: Build Debug APK
    runs-on: ubuntu-22.04
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 1

      - name: Setup JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Setup Android SDK
        uses: android-actions/setup-android@v3
        with:
          packages: >-
            platform-tools
            platforms;android-34
            build-tools;34.0.0

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v3
        with:
          gradle-version: '8.7'

      - name: Cache Gradle
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: awlqy-gradle-${{ runner.os }}-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: |
            awlqy-gradle-${{ runner.os }}-

      - name: Build Debug APK
        run: gradle :app:assembleDebug --no-daemon --stacktrace

      - name: Collect APK
        run: |
          set -e
          mkdir -p out
          APK="app/build/outputs/apk/debug/app-debug.apk"
          if [ ! -f "$APK" ]; then
            echo "APK not found at $APK"
            find app/build/outputs -type f -name "*.apk" || true
            exit 1
          fi
          cp "$APK" out/awlqy.apk
          sha256sum out/awlqy.apk > out/awlqy.apk.sha256
          ls -la out

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: awlqy-apk
          path: |
            out/awlqy.apk
            out/awlqy.apk.sha256
          if-no-files-found: error
          retention-days: 30
YML_EOF

# ═════════════════════════════════════════════════════════════
# 2. app/build.gradle.kts
# ═════════════════════════════════════════════════════════════
cat > app/build.gradle.kts <<'GRADLE_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.awlqy.terminal"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.awlqy.terminal"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isDebuggable = true
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/*.kotlin_module",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*"
            )
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.jakewharton.timber:timber:5.0.1")
}
GRADLE_EOF

# ═════════════════════════════════════════════════════════════
# 3. MainActivity.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/MainActivity.kt <<'KOTLIN_EOF'
package com.awlqy.terminal

import android.content.Context
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextWatcher
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.awlqy.terminal.databinding.ActivityMainBinding
import com.google.android.material.button.MaterialButton
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    private val C_CYAN   = 0xFF22D3EE.toInt()
    private val C_GREEN  = 0xFF4ADE80.toInt()
    private val C_AMBER  = 0xFFFBBF24.toInt()
    private val C_RED    = 0xFFEF4444.toInt()
    private val C_TEXT   = 0xFFE2E8F0.toInt()
    private val C_DIM    = 0xFF64748B.toInt()
    private val C_YELLOW = 0xFFFACC15.toInt()
    private val C_WHITE  = 0xFFFFFFFF.toInt()

    private class TermSession(val name: String, val cwd: File) {
        val buffer = SpannableStringBuilder()
        val history = ArrayList<String>()
        var historyIndex = -1
        @Volatile var running = false
        @Volatile var proc: Process? = null
    }

    private val sessions = ArrayList<TermSession>()
    private var activeIdx = 0
    private var ctrlLatched = false
    private var altLatched = false
    private var suppressInput = false

    override fun onCreate(savedInstanceState: Bundle?) {
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
        val tv = TextView(this).apply {
            text = "awlqy crashed:\n\n${sw}"
            typeface = Typeface.MONOSPACE
            textSize = 10f
            setTextColor(C_RED)
            setPadding(24, 24, 24, 24)
            setBackgroundColor(0xFF000000.toInt())
        }
        setContentView(android.widget.ScrollView(this).apply { addView(tv) })
    }

    override fun onDestroy() {
        for (s in sessions) {
            s.running = false
            try { s.proc?.destroy() } catch (_: Exception) { }
        }
        super.onDestroy()
    }

    private fun newSession() {
        val home = File(filesDir, "home").apply { mkdirs() }
        val s = TermSession("session-${sessions.size + 1}", home)
        sessions.add(s)
        activeIdx = sessions.size - 1
        showMotd(s)
        startProcess(s)
        renderTabs()
        renderConsole()
    }

    private fun startProcess(s: TermSession) {
        try {
            val pb = ProcessBuilder("/system/bin/sh")
            pb.directory(s.cwd)
            pb.redirectErrorStream(true)
            val env = pb.environment()
            env["HOME"] = s.cwd.absolutePath
            env["TERM"] = "xterm-256color"
            env["LANG"] = "en_US.UTF-8"
            env["PATH"] = "${filesDir.absolutePath}/usr/bin:/system/bin:/system/xbin"
            val p = pb.start()
            s.proc = p
            s.running = true
            Thread { readLoop(s, p) }.start()
        } catch (e: Exception) {
            appendColored(s, "[awlqy] تعذّر تشغيل الطرفية: ${e.message}\n", C_RED)
            appendPrompt(s)
        }
    }

    private fun readLoop(s: TermSession, p: Process) {
        try {
            BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                var line = r.readLine()
                while (s.running && line != null) {
                    val out = line + "\n"
                    runOnUiThread {
                        appendStreamed(s, out)
                        if (sessions.getOrNull(activeIdx) === s) renderConsole()
                    }
                    line = r.readLine()
                }
            }
        } catch (_: Exception) { }
        val code = try { p.waitFor() } catch (_: Exception) { -1 }
        s.running = false
        runOnUiThread {
            appendColored(s, "\n[session exited: $code]\n", C_DIM)
            if (sessions.getOrNull(activeIdx) === s) renderConsole()
        }
    }

    private fun closeCurrent() {
        if (sessions.size <= 1) { toast("لا يمكن إغلاق الجلسة الأخيرة"); return }
        val s = sessions[activeIdx]
        s.running = false
        try { s.proc?.destroy() } catch (_: Exception) { }
        sessions.removeAt(activeIdx)
        if (activeIdx >= sessions.size) activeIdx = sessions.size - 1
        renderTabs()
        renderConsole()
    }

    private fun activeSession(): TermSession? = sessions.getOrNull(activeIdx)

    private fun writeToSession(data: ByteArray) {
        val s = activeSession() ?: return
        val p = s.proc ?: return
        try {
            OutputStreamWriter(p.outputStream, Charsets.UTF_8).apply {
                write(String(data, Charsets.UTF_8))
                flush()
            }
        } catch (_: Exception) { }
    }

    private fun showMotd(s: TermSession) {
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "?"
        val motd = "\n" +
            "  +==========================================+\n" +
            "  |   a w l q y   \u00B7   S m a r t   T e r m   |\n" +
            "  |   v1.0.0  |  Q-W  |  shell              |\n" +
            "  +==========================================+\n" +
            "\n" +
            "  [system]  Android API : ${Build.VERSION.SDK_INT}\n" +
            "  [system]  ABI         : $abi\n" +
            "  [system]  HOME        : ${s.cwd.absolutePath}\n" +
            "  [system]  Engine      : ProcessBuilder\n" +
            "\n" +
            "  اكتب help للأوامر، أو 'حسين' للوضع الخاص.\n" +
            "\n"
        appendColored(s, motd, C_TEXT)
        appendPrompt(s)
    }

    private fun appendPrompt(s: TermSession) {
        val prompt = "awlqy@android:~$ "
        val start = s.buffer.length
        s.buffer.append(prompt)
        span(s.buffer, start, start + 5, C_CYAN)
        span(s.buffer, start + 5, start + 6, C_WHITE)
        span(s.buffer, start + 6, start + 13, C_GREEN)
        span(s.buffer, start + 13, start + 14, C_AMBER)
        span(s.buffer, start + 14, start + 15, C_WHITE)
    }

    private fun appendColored(s: TermSession, text: String, color: Int) {
        val start = s.buffer.length
        s.buffer.append(text)
        span(s.buffer, start, s.buffer.length, color)
    }

    private fun appendStreamed(s: TermSession, text: String) {
        val start = s.buffer.length
        s.buffer.append(text)
        val err = Regex("(?i)\\b(error|failed|denied|not found|fatal|exception|cannot|no such)\\b")
        val ok  = Regex("(?i)\\b(ok|success|done|installed|finished|ready|total)\\b")
        err.findAll(text).forEach {
            span(s.buffer, start + it.range.first, start + it.range.last + 1, C_RED)
        }
        ok.findAll(text).forEach {
            span(s.buffer, start + it.range.first, start + it.range.last + 1, C_GREEN)
        }
        trim(s.buffer, 200_000)
    }

    private fun span(b: SpannableStringBuilder, a: Int, c: Int, color: Int) {
        if (a < 0 || c > b.length || a >= c) return
        b.setSpan(ForegroundColorSpan(color), a, c, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    }

    private fun trim(b: SpannableStringBuilder, max: Int) {
        if (b.length <= max) return
        val cut = b.length - max
        val nl = b.indexOf("\n", cut)
        val drop = if (nl > 0) nl + 1 else cut
        b.delete(0, drop)
    }

    private fun renderConsole() {
        val s = activeSession() ?: return
        binding.consoleText.text = s.buffer
        binding.consoleScroll.post { binding.consoleScroll.fullScroll(View.FOCUS_DOWN) }
    }

    private fun renderTabs() {
        val bar = binding.sessionTabs
        bar.removeAllViews()
        for (i in sessions.indices) {
            val tv = TextView(this).apply {
                text = "[${i + 1}]"
                typeface = Typeface.MONOSPACE
                textSize = 12f
                gravity = Gravity.CENTER
                setPadding(28, 12, 28, 12)
                setTextColor(if (i == activeIdx) C_CYAN else C_DIM)
                setBackgroundColor(if (i == activeIdx) 0xFF1E293B.toInt() else 0xFF0A0E14.toInt())
                setOnClickListener {
                    activeIdx = i
                    renderTabs()
                    renderConsole()
                    focusTerminal()
                }
                setOnLongClickListener {
                    if (i == activeIdx) { closeCurrent(); true } else false
                }
            }
            bar.addView(tv)
        }
        val add = TextView(this).apply {
            text = "[+]"
            typeface = Typeface.MONOSPACE
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(28, 12, 28, 12)
            setTextColor(C_GREEN)
            setBackgroundColor(0xFF0A0E14.toInt())
            setOnClickListener { newSession() }
        }
        bar.addView(add)
    }

    private fun buildAccessoryBar() {
        val container = binding.accessoryContainer

        container.addView(rowOf(
            makeKey("KEYBOARD", 0xFF1E293B.toInt()) { toggleSoftKeyboard() },
            makeKey("NEW", 0xFF4ADE80.toInt()) { newSession() },
            makeKey("CLOSE", 0xFFEF4444.toInt()) { closeCurrent() }
        ))

        container.addView(rowOf(
            makeKey("ESC")  { writeToSession(byteArrayOf(0x1B)) },
            makeKey("TAB")  { writeToSession(byteArrayOf(0x09)) },
            makeKey("CTRL", 0xFF1E293B.toInt()) { toggleCtrl() },
            makeKey("ALT",  0xFF1E293B.toInt()) { toggleAlt() },
            makeKey("HOME") { writeSeq("\u001B[H") },
            makeKey("UP")   { writeSeq("\u001B[A") },
            makeKey("END")  { writeSeq("\u001B[F") },
            makeKey("PGUP") { writeSeq("\u001B[5~") }
        ))

        container.addView(rowOf(
            makeKey("|")    { writeSeq("|") },
            makeKey("/")    { writeSeq("/") },
            makeKey("-")    { writeSeq("-") },
            makeKey("LEFT") { writeSeq("\u001B[D") },
            makeKey("DOWN") { writeSeq("\u001B[B") },
            makeKey("RGHT") { writeSeq("\u001B[C") },
            makeKey("PGDN") { writeSeq("\u001B[6~") }
        ))
    }

    private fun rowOf(vararg views: View): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            for (v in views) addView(v)
        }

    private fun makeKey(label: String, bg: Int = 0xFF1E293B.toInt(), action: () -> Unit): MaterialButton {
        val density = resources.displayMetrics.density
        val lp = LinearLayout.LayoutParams(0, (38 * density).toInt(), 1f).apply {
            marginStart = (2 * density).toInt()
            marginEnd = (2 * density).toInt()
        }
        return MaterialButton(this).apply {
            text = label
            textSize = 11f
            typeface = Typeface.MONOSPACE
            minWidth = 0
            minHeight = 0
            insetTop = 0
            insetBottom = 0
            layoutParams = lp
            setTextColor(C_TEXT)
            setBackgroundColor(bg)
            setOnClickListener { action() }
        }
    }

    private fun toggleCtrl() {
        ctrlLatched = !ctrlLatched
        if (ctrlLatched) altLatched = false
        refreshModifierVisuals()
    }

    private fun toggleAlt() {
        altLatched = !altLatched
        if (altLatched) ctrlLatched = false
        refreshModifierVisuals()
    }

    private fun refreshModifierVisuals() {
        val container = binding.accessoryContainer
        val row2 = container.getChildAt(1) as? LinearLayout ?: return
        for (i in 0 until row2.childCount) {
            val v = row2.getChildAt(i) as? MaterialButton ?: continue
            when (v.text.toString()) {
                "CTRL" -> v.setBackgroundColor(
                    if (ctrlLatched) C_RED else 0xFF1E293B.toInt()
                )
                "ALT" -> v.setBackgroundColor(
                    if (altLatched) C_YELLOW else 0xFF1E293B.toInt()
                )
            }
        }
    }

    private fun wireSoftKeyboard() {
        binding.inputEdit.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) { }
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) { }
            override fun afterTextChanged(s: Editable?) {
                if (suppressInput) return
                val text = s?.toString() ?: return
                if (text.isEmpty()) return
                handleTypedText(text)
                suppressInput = true
                binding.inputEdit.setText("")
                suppressInput = false
            }
        })

        binding.inputEdit.setOnKeyListener { _, keyCode, event ->
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DEL, KeyEvent.KEYCODE_FORWARD_DEL -> {
                        writeToSession(byteArrayOf(0x7F)); true
                    }
                    KeyEvent.KEYCODE_ENTER -> { writeToSession(byteArrayOf(0x0D)); true }
                    KeyEvent.KEYCODE_TAB   -> { writeToSession(byteArrayOf(0x09)); true }
                    else -> false
                }
            } else false
        }

        binding.sendButton.setOnClickListener {
            writeToSession(byteArrayOf(0x0D))
        }
    }

    private fun handleTypedText(text: String) {
        for (ch in text) {
            val b = ch.code
            if (altLatched) {
                writeToSession(byteArrayOf(0x1B))
                altLatched = false
                refreshModifierVisuals()
            }
            if (ctrlLatched) {
                val code = when {
                    b in 'a'.code..'z'.code -> b - 0x60
                    b in 'A'.code..'Z'.code -> b - 0x40
                    b == ' '.code -> 0
                    else -> b
                }
                writeToSession(byteArrayOf(code.toByte()))
                ctrlLatched = false
                refreshModifierVisuals()
            } else {
                writeToSession(ch.toString().toByteArray(Charsets.UTF_8))
            }
        }
    }

    private fun writeSeq(s: String) = writeToSession(s.toByteArray(Charsets.UTF_8))

    private fun toggleSoftKeyboard() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (binding.inputEdit.hasFocus()) {
            imm.hideSoftInputFromWindow(binding.inputEdit.windowToken, 0)
        } else focusTerminal()
    }

    private fun focusTerminal() {
        binding.inputEdit.requestFocus()
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.showSoftInput(binding.inputEdit, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun showSettings() {
        val msg = "التطبيق: awlqy Terminal & IDE\n" +
            "الإصدار: 1.0.0\n" +
            "المطوّر: حسين الخلاقي\n" +
            "GitHub: alwaqyhsyn752-eng\n" +
            "المحرّك: ProcessBuilder fallback\n" +
            "API: ${Build.VERSION.SDK_INT}\n" +
            "الجلسات: ${sessions.size}"
        MaterialAlertDialogBuilder(this)
            .setTitle("الإعدادات")
            .setMessage(msg)
            .setPositiveButton("حسناً", null)
            .show()
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
}
KOTLIN_EOF

# ═════════════════════════════════════════════════════════════
# التحقق
# ═════════════════════════════════════════════════════════════
echo ""
echo "▶ [final-build] الملفات المُنشأة:"
for f in \
    .github/workflows/build.yml \
    app/build.gradle.kts \
    app/src/main/java/com/awlqy/terminal/MainActivity.kt
do
    if [ -f "$f" ]; then
        echo "  ✔ $f  ($(wc -l < "$f") سطر)"
    else
        echo "  ✗ $f مفقود!"
    fi
done

echo ""
echo "▶ [final-build] أول سطر من MainActivity:"
head -n 1 app/src/main/java/com/awlqy/terminal/MainActivity.kt

echo ""
echo "▶ [final-build] أول سطر من build.gradle.kts:"
head -n 1 app/build.gradle.kts

echo ""
echo "▶ [final-build] لا NDK ولا externalNativeBuild:"
grep -c "externalNativeBuild\|ndkVersion\|libawlqy_pty" app/build.gradle.kts app/src/main/java/com/awlqy/terminal/MainActivity.kt 2>/dev/null || echo "  ✔ نظيف"

echo ""
echo "✔ [final-build] انتهى. الآن:"
echo "   git add -A"
echo "   git commit -m 'fix: pure ProcessBuilder engine (no NDK, no crash)'"
echo "   git push"
