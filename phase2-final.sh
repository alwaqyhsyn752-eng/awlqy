#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · phase2-final.sh — توحيد كل ملفات المرحلة 2
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [phase2-final] حذف المجلدات القديمة"

# احذف update/ القديم (AutoUpdateManager صار في core/)
rm -rf app/src/main/java/com/awlqy/terminal/update

# تأكد من وجود المجلدات
mkdir -p app/src/main/java/com/awlqy/terminal/core
mkdir -p app/src/main/res/{layout,menu,xml,values,drawable,mipmap-anydpi-v26}

# ─── ArabicShaper.kt (نسخة نظيفة) ───────────────────────────
cat > app/src/main/java/com/awlqy/terminal/core/ArabicShaper.kt <<'EOF_1'
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
EOF_1

# ─── ShellExecutor.kt ───────────────────────────────────────
cat > app/src/main/java/com/awlqy/terminal/core/ShellExecutor.kt <<'EOF_2'
package com.awlqy.terminal.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

data class ShellResult(
    val exitCode: Int,
    val stdout: String,
    val stderr: String,
    val durationMs: Long
) {
    val ok: Boolean get() = exitCode == 0
}

object ShellExecutor {

    private const val SHELL = "/system/bin/sh"

    suspend fun run(
        command: String,
        workDir: File,
        extraEnv: Map<String, String> = emptyMap()
    ): ShellResult = withContext(Dispatchers.IO) {
        val start = System.currentTimeMillis()
        var exit = -1
        val out = StringBuilder()
        val err = StringBuilder()
        try {
            if (!workDir.exists()) workDir.mkdirs()
            val pb = ProcessBuilder(SHELL, "-c", command)
            pb.directory(workDir)
            val env = pb.environment()
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "truecolor"
            env["HOME"] = workDir.absolutePath
            env["LANG"] = "en_US.UTF-8"
            env["LC_ALL"] = "en_US.UTF-8"
            env["PATH"] = "/data/data/com.awlqy.terminal/files/usr/bin:/system/bin:/system/xbin"
            env.putAll(extraEnv)

            val p = pb.start()

            val tOut = Thread {
                try {
                    BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                        var line = r.readLine()
                        while (line != null) {
                            out.append(line).append('\n')
                            line = r.readLine()
                        }
                    }
                } catch (_: Exception) { }
            }
            val tErr = Thread {
                try {
                    BufferedReader(InputStreamReader(p.errorStream)).use { r ->
                        var line = r.readLine()
                        while (line != null) {
                            err.append(line).append('\n')
                            line = r.readLine()
                        }
                    }
                } catch (_: Exception) { }
            }
            tOut.start(); tErr.start()
            exit = p.waitFor()
            tOut.join(3000)
            tErr.join(3000)
        } catch (e: Exception) {
            err.append(e.message ?: e.javaClass.simpleName).append('\n')
        }
        ShellResult(exit, out.toString(), err.toString(), System.currentTimeMillis() - start)
    }

    fun diagnose(stderr: String, stdout: String): String? {
        val s = "$stderr\n$stdout"
        if (s.isBlank()) return null

        Regex("ModuleNotFoundError: No module named '([^']+)'").find(s)?.let {
            return "مكتبة Python مفقودة '${it.groupValues[1]}'. جرّب: pip install ${it.groupValues[1]}"
        }
        Regex("ImportError: cannot import name '([^']+)'").find(s)?.let {
            return "استيراد فاشل لـ '${it.groupValues[1]}'. تحقق من التثبيت."
        }
        Regex("Cannot find module '([^']+)'").find(s)?.let {
            return "حزمة Node.js مفقودة '${it.groupValues[1]}'. جرّب: npm install ${it.groupValues[1]}"
        }
        if (s.contains("command not found") || s.contains(": not found")) {
            return "الأمر غير مثبت أو غير موجود في PATH. تحقق من الاسم."
        }
        if (s.contains("No such file or directory")) {
            return "الملف/المجلد غير موجود. تحقق من المسار."
        }
        if (s.contains("Permission denied")) {
            return "صلاحية مرفوضة. جرّب: chmod +x على الملف."
        }
        if (s.contains("SyntaxError")) {
            return "خطأ بنيوي. تحقق من علامات الاقتباس، الأقواس، والمسافات البادئة."
        }
        if (s.contains("is a directory")) {
            return "هذا مسار مجلد، ليس ملفاً. استخدم ls."
        }
        if (s.contains("No space left on device")) {
            return "المساحة ممتلئة. احذف ملفات غير ضرورية."
        }
        if (s.contains("Cannot resolve host") || s.contains("Could not resolve host")) {
            return "تعذر الاتصال بالشبكة. تحقق من الإنترنت."
        }
        return null
    }
}
EOF_2

# ─── AutoUpdateManager.kt (في core/) ────────────────────────
cat > app/src/main/java/com/awlqy/terminal/core/AutoUpdateManager.kt <<'EOF_3'
package com.awlqy.terminal.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

object AutoUpdateManager {

    private const val OWNER = "alwaqyhsyn752-eng"
    private const val REPO = "awlqy"
    private const val API_URL = "https://api.github.com/repos/$OWNER/$REPO/releases/latest"
    private const val UA = "awlqy-updater-android"

    data class UpdateInfo(
        val tag: String,
        val notes: String,
        val apkUrl: String,
        val apkName: String,
        val hasUpdate: Boolean
    )

    fun checkLatest(ctx: Context, currentVersion: String): UpdateInfo? {
        var conn: HttpURLConnection? = null
        return try {
            val u = URL(API_URL)
            conn = u.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.setRequestProperty("User-Agent", UA)
            conn.setRequestProperty("Accept", "application/vnd.github+json")
            if (conn.responseCode != 200) return null

            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            val tag = json.optString("tag_name", "").trim()
            val notes = json.optString("body", "")
            val assets = json.optJSONArray("assets")

            var apkUrl = ""
            var apkName = "awlqy.apk"
            if (assets != null) {
                var i = 0
                while (i < assets.length()) {
                    val a = assets.getJSONObject(i)
                    val name = a.optString("name", "")
                    if (name.endsWith(".apk", ignoreCase = true)) {
                        apkUrl = a.optString("browser_download_url", "")
                        apkName = name
                        break
                    }
                    i++
                }
            }

            val latest = tag.trimStart('v', 'V')
            val current = currentVersion.trimStart('v', 'V')
            val hasUpdate = apkUrl.isNotBlank() && compareVersions(latest, current) > 0

            UpdateInfo(tag.ifBlank { "v?" }, notes, apkUrl, apkName, hasUpdate)
        } catch (_: Exception) {
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) { }
        }
    }

    fun compareVersions(a: String, b: String): Int {
        val pa = a.split('.').map { s -> s.filter { it.isDigit() }.toIntOrNull() ?: 0 }
        val pb = b.split('.').map { s -> s.filter { it.isDigit() }.toIntOrNull() ?: 0 }
        val n = maxOf(pa.size, pb.size)
        for (i in 0 until n) {
            val x = pa.getOrElse(i) { 0 }
            val y = pb.getOrElse(i) { 0 }
            if (x != y) return if (x > y) 1 else -1
        }
        return 0
    }

    fun downloadApk(ctx: Context, info: UpdateInfo, onProgress: (Int) -> Unit): File? {
        val dest = File(ctx.cacheDir, info.apkName)
        if (dest.exists()) dest.delete()
        var conn: HttpURLConnection? = null
        return try {
            val u = URL(info.apkUrl)
            conn = u.openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = true
            conn.connectTimeout = 20000
            conn.readTimeout = 60000
            conn.setRequestProperty("User-Agent", UA)
            val code = conn.responseCode
            if (code !in 200..299) return null

            val total = conn.contentLengthLong
            conn.inputStream.use { input ->
                dest.outputStream().use { output ->
                    val buf = ByteArray(64 * 1024)
                    var sum = 0L
                    var read = input.read(buf)
                    while (read > 0) {
                        output.write(buf, 0, read)
                        sum += read
                        if (total > 0) onProgress(((sum * 100L) / total).toInt())
                        read = input.read(buf)
                    }
                }
            }
            if (dest.length() < 1024L) return null
            dest
        } catch (_: Exception) {
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) { }
        }
    }

    fun installApk(ctx: Context, apk: File): Boolean {
        return try {
            val uri: Uri = FileProvider.getUriForFile(
                ctx,
                "${ctx.packageName}.fileprovider",
                apk
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
EOF_3

# ─── activity_main.xml (مضمون مطابق للمعرفات في MainActivity) ─
cat > app/src/main/res/layout/activity_main.xml <<'EOF_4'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/awlqy_bg"
    android:orientation="vertical"
    android:fitsSystemWindows="true">

    <com.google.android.material.appbar.MaterialToolbar
        android:id="@+id/toolbar"
        android:layout_width="match_parent"
        android:layout_height="?attr/actionBarSize"
        android:background="@color/awlqy_surface"
        app:title="@string/app_name"
        app:titleTextColor="@color/awlqy_accent"/>

    <ScrollView
        android:id="@+id/consoleScroll"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:background="@color/awlqy_terminal_bg"
        android:fillViewport="true"
        android:padding="8dp"
        android:scrollbars="vertical">

        <TextView
            android:id="@+id/consoleText"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:fontFamily="monospace"
            android:text=""
            android:textColor="@color/awlqy_terminal_text"
            android:textIsSelectable="true"
            android:textSize="12sp"/>
    </ScrollView>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="@color/awlqy_surface"
        android:orientation="horizontal"
        android:padding="6dp">

        <EditText
            android:id="@+id/inputEdit"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:background="@color/awlqy_glass"
            android:hint="@string/hint_command"
            android:imeOptions="actionSend|flagNoFullscreen"
            android:inputType="text|textNoSuggestions|textVisiblePassword|textMultiLine"
            android:maxLines="3"
            android:padding="10dp"
            android:textColor="@color/awlqy_terminal_text"
            android:textColorHint="@color/awlqy_text_dim"
            android:textDirection="locale"/>

        <Button
            android:id="@+id/clearButton"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="4dp"
            android:backgroundTint="@color/awlqy_glass"
            android:text="@string/action_clear"
            android:textColor="@color/awlqy_text"/>

        <Button
            android:id="@+id/runButton"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="4dp"
            android:backgroundTint="@color/awlqy_accent"
            android:text="@string/action_run"
            android:textColor="@color/awlqy_bg"/>
    </LinearLayout>
</LinearLayout>
EOF_4

# ─── main_menu.xml ──────────────────────────────────────────
cat > app/src/main/res/menu/main_menu.xml <<'EOF_5'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto">
    <item
        android:id="@+id/action_update"
        android:title="@string/menu_update"
        app:showAsAction="never"/>
    <item
        android:id="@+id/action_settings"
        android:title="@string/menu_settings"
        app:showAsAction="never"/>
    <item
        android:id="@+id/action_about"
        android:title="@string/menu_about"
        app:showAsAction="never"/>
</menu>
EOF_5

# ─── strings.xml (كامل) ─────────────────────────────────────
cat > app/src/main/res/values/strings.xml <<'EOF_6'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">awlqy</string>
    <string name="app_tagline">طرفية ذكية · بيئة تطوير · إصلاح ذاتي</string>
    <string name="developer_name">حسين الخلاقي</string>
    <string name="developer_role">المطوّر / المنشئ</string>
    <string name="github_handle">alwaqyhsyn752-eng</string>
    <string name="notification_channel_session">جلسة awlqy</string>
    <string name="notification_session_active">جلسة الطرفية نشطة</string>
    <string name="hint_command">اكتب أمراً…</string>
    <string name="action_run">تشغيل</string>
    <string name="action_clear">مسح</string>
    <string name="action_send">إرسال</string>
    <string name="menu_update">التحقق من التحديثات</string>
    <string name="menu_settings">الإعدادات</string>
    <string name="menu_about">حول التطبيق</string>
</resources>
EOF_6

# ─── colors.xml (كامل — يضمن awlqy_terminal_bg + awlqy_terminal_text) ─
cat > app/src/main/res/values/colors.xml <<'EOF_7'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="awlqy_bg">#020617</color>
    <color name="awlqy_surface">#0F172A</color>
    <color name="awlqy_glass">#1E293B</color>
    <color name="awlqy_accent">#22D3EE</color>
    <color name="awlqy_accent_dim">#0E7490</color>
    <color name="awlqy_text">#E2E8F0</color>
    <color name="awlqy_text_dim">#94A3B8</color>
    <color name="awlqy_error">#F87171</color>
    <color name="awlqy_terminal_bg">#000000</color>
    <color name="awlqy_terminal_text">#4ADE80</color>
    <color name="ic_launcher_background">#020617</color>
</resources>
EOF_7

# ─── file_paths.xml ─────────────────────────────────────────
cat > app/src/main/res/xml/file_paths.xml <<'EOF_8'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="apk_cache" path="."/>
    <external-cache-path name="apk_external_cache" path="."/>
    <external-path name="apk_external" path="."/>
    <files-path name="internal_files" path="."/>
    <external-files-path name="external_files" path="."/>
</paths>
EOF_8

echo "▶ [phase2-final] التحقق من التوافق"
echo ""
echo "─── ملفات Kotlin:"
find app/src/main/java -name "*.kt" | sort
echo ""
echo "─── R.id في MainActivity:"
grep -o "R\.id\.[a-z_A-Z]*" app/src/main/java/com/awlqy/terminal/MainActivity.kt | sort -u
echo ""
echo "─── id= في activity_main.xml:"
grep -o 'android:id="@+id/[a-z_A-Z]*"' app/src/main/res/layout/activity_main.xml | sort -u
echo ""
echo "─── id= في main_menu.xml:"
grep -o 'android:id="@+id/[a-z_A-Z]*"' app/src/main/res/menu/main_menu.xml | sort -u
echo ""
echo "✔ [phase2-final] انتهى. الآن:"
echo "   git add -A"
echo "   git commit -m 'consistency: unify phase-2 files'"
echo "   git push"
