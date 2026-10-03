#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · fix.sh — إصلاح أخطاء البناء
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [fix] إنشاء خدمة الجلسة + مستقبل الإقلاع"
mkdir -p app/src/main/java/com/awlqy/terminal/service

cat > app/src/main/java/com/awlqy/terminal/service/AwlqySessionService.kt <<'AWLQY_SVC_EOF'
package com.awlqy.terminal.service

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.awlqy.terminal.AwlqyApp
import com.awlqy.terminal.R

class AwlqySessionService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n: Notification = NotificationCompat.Builder(this, AwlqyApp.CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.notification_session_active))
            .setSmallIcon(R.drawable.ic_plus)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(1, n)
        }
        return START_STICKY
    }
}
AWLQY_SVC_EOF

cat > app/src/main/java/com/awlqy/terminal/service/BootReceiver.kt <<'AWLQY_BOOT_EOF'
package com.awlqy.terminal.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val i = Intent(context, AwlqySessionService::class.java)
            ContextCompat.startForegroundService(context, i)
        }
    }
}
AWLQY_BOOT_EOF

echo "▶ [fix] إصلاح TerminalView (rename onSizeChanged → sizeListener)"
TV="app/src/main/java/com/awlqy/terminal/ui/TerminalView.kt"
sed -i 's/var onSizeChanged: ((rows: Int, cols: Int) -> Unit)? = null/var sizeListener: ((rows: Int, cols: Int) -> Unit)? = null/' "$TV"
sed -i 's/onSizeChanged?.invoke(rows, cols)/sizeListener?.invoke(rows, cols)/' "$TV"

echo "▶ [fix] إصلاح TerminalFragment لاستخدام sizeListener"
FR="app/src/main/java/com/awlqy/terminal/ui/fragments/TerminalFragment.kt"
sed -i 's/b\.terminalView\.onSizeChanged = { r, c -> session?\.resize(r, c) }/b.terminalView.sizeListener = { r, c -> session?.resize(r, c) }/' "$FR"

echo "▶ [fix] تحقق من التعديلات"
grep -n "sizeListener" "$TV" "$FR" || true

echo ""
echo "✔ تم التصحيح. الآن:"
echo "   git add ."
echo "   git commit -m 'fix: add service classes + rename onSizeChanged'"
echo "   git push"
