#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [fix5] تصحيح AwlqyApp.kt — nullable receiver"

cat > app/src/main/java/com/awlqy/terminal/AwlqyApp.kt <<'KOT_APP'
package com.awlqy.terminal

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import timber.log.Timber
import java.io.File

class AwlqyApp : Application() {

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) Timber.plant(Timber.DebugTree())

        File(filesDir, "home").mkdirs()
        File(filesDir, "usr/bin").mkdirs()
        File(filesDir, "apk-work").mkdirs()

        createChannel()
        Timber.i("awlqy phase-5 booted — developer: حسين الخلاقي")
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_session),
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            val mgr = getSystemService(NotificationManager::class.java)
            mgr?.createNotificationChannel(ch)
        }
    }

    companion object {
        const val CHANNEL_ID = "awlqy_session"
        const val DEVELOPER = "حسين الخلاقي"
    }
}
KOT_APP

echo "▶ [fix5] تصحيح بدء الخدمة في MainActivity.kt"
# استبدل startForegroundService المباشر بمغلّف آمن
python3 - <<'PYEOF' 2>/dev/null || sed -i \
  's|startForegroundService(Intent(this, TerminalService::class.java))|startTerminalService()|' \
  app/src/main/java/com/awlqy/terminal/MainActivity.kt

import re, pathlib
p = pathlib.Path("app/src/main/java/com/awlqy/terminal/MainActivity.kt")
s = p.read_text(encoding="utf-8")
s = s.replace(
    "startForegroundService(Intent(this, TerminalService::class.java))",
    "startTerminalService()"
)
if "private fun startTerminalService()" not in s:
    marker = "    // ─── Pager ────────────────────────────────────────"
    helper = """    private fun startTerminalService() {
        val i = Intent(this, TerminalService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(i)
        } else {
            startService(i)
        }
    }

"""
    s = s.replace(marker, helper + marker)
p.write_text(s, encoding="utf-8")
print("patched MainActivity")
PYEOF

echo "▶ [fix5] تحقق"
head -n 3 app/src/main/java/com/awlqy/terminal/MainActivity.kt
grep -n "startTerminalService\|startForegroundService" \
    app/src/main/java/com/awlqy/terminal/MainActivity.kt || true
echo ""
echo "✔ تم. الآن:"
echo "   git add -A"
echo "   git commit -m 'fix: AwlqyApp nullable NotificationManager + API-safe service start'"
echo "   git push"
