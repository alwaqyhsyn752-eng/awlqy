#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · rebuild-p1.sh — إعادة كتابة كل ملفات Phase 1 نظيفة
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [rebuild-p1] حذف كل الملفات القديمة"

# ملفات Kotlin
rm -rf app/src/main/java

# ملفات XML resources
rm -rf app/src/main/res/layout
rm -rf app/src/main/res/values
rm -rf app/src/main/res/drawable
rm -rf app/src/main/res/mipmap-anydpi-v26
rm -rf app/src/main/res/menu
rm -rf app/src/main/res/xml

# المانيفست
rm -f app/src/main/AndroidManifest.xml

# إعادة البناء
mkdir -p app/src/main/java/com/awlqy/terminal
mkdir -p app/src/main/res/{layout,values,drawable,mipmap-anydpi-v26,xml}
mkdir -p .github/workflows

# ═════════════════════════════════════════════════════════════
# 1. MainActivity.kt
# ═════════════════════════════════════════════════════════════
cat > app/src/main/java/com/awlqy/terminal/MainActivity.kt <<'KOT_MAIN'
package com.awlqy.terminal

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import timber.log.Timber

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        Timber.i("MainActivity — phase-1 skeleton ready")
    }
}
KOT_MAIN

# ═════════════════════════════════════════════════════════════
# 2. AwlqyApp.kt
# ═════════════════════════════════════════════════════════════
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

        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }

        File(filesDir, "home").mkdirs()
        File(filesDir, "usr").mkdirs()
        File(filesDir, "usr/bin").mkdirs()
        File(filesDir, "apk-work").mkdirs()
        File(filesDir, "logs").mkdirs()

        createNotificationChannel()
        Timber.i("awlqy booted — phase-1 — developer: حسين الخلاقي")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel),
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

# ═════════════════════════════════════════════════════════════
# 3. activity_main.xml — نظيف
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/layout/activity_main.xml <<'XML_MAIN'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">

    <TextView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:alpha="0.05"
        android:fontFamily="monospace"
        android:gravity="center"
        android:letterSpacing="0.25"
        android:shadowColor="#22D3EE"
        android:shadowDx="0"
        android:shadowDy="0"
        android:shadowRadius="30"
        android:text="Q · W"
        android:textColor="#22D3EE"
        android:textSize="120sp"
        android:textStyle="bold"/>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:gravity="center"
        android:orientation="vertical"
        android:padding="32dp">

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:fontFamily="monospace"
            android:text="awlqy"
            android:textColor="#22D3EE"
            android:textSize="48sp"
            android:textStyle="bold"/>

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:fontFamily="monospace"
            android:text="@string/app_tagline"
            android:textColor="#64748B"
            android:textSize="13sp"/>

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="40dp"
            android:fontFamily="monospace"
            android:text="PHASE 1 · Skeleton Ready"
            android:textColor="#4ADE80"
            android:textSize="12sp"/>

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="8dp"
            android:fontFamily="monospace"
            android:text="المطوّر: حسين الخلاقي"
            android:textColor="#94A3B8"
            android:textSize="12sp"/>
    </LinearLayout>
</FrameLayout>
XML_MAIN

# ═════════════════════════════════════════════════════════════
# 4. AndroidManifest.xml — بدون أي تكرار
# ═════════════════════════════════════════════════════════════
cat > app/src/main/AndroidManifest.xml <<'XML_MAN'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28"
        tools:ignore="ScopedStorage"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"
        tools:ignore="QueryAllPackagesPermission"/>

    <application
        android:name=".AwlqyApp"
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:requestLegacyExternalStorage="true"
        android:roundIcon="@mipmap/ic_launcher"
        android:supportsRtl="true"
        android:usesCleartextTraffic="true"
        android:largeHeap="true"
        android:theme="@style/Theme.Awlqy"
        tools:targetApi="34">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|keyboardHidden|uiMode"
            android:windowSoftInputMode="adjustResize"
            android:launchMode="singleTask">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths"/>
        </provider>

        <meta-data
            android:name="com.awlqy.DEVELOPER"
            android:value="حسين الخلاقي"/>
        <meta-data
            android:name="com.awlqy.GITHUB"
            android:value="alwaqyhsyn752-eng"/>
    </application>
</manifest>
XML_MAN

# ═════════════════════════════════════════════════════════════
# 5. strings.xml — بدون تكرار
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/values/strings.xml <<'XML_STR'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">awlqy</string>
    <string name="app_tagline">Smart Terminal · Multi-IDE · APK Suite</string>
    <string name="notification_channel">awlqy session</string>
    <string name="notification_session_active">awlqy session active</string>
</resources>
XML_STR

# ═════════════════════════════════════════════════════════════
# 6. colors.xml — بدون تكرار
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/values/colors.xml <<'XML_COL'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="awlqy_bg">#000000</color>
    <color name="awlqy_surface">#0A0E14</color>
    <color name="awlqy_glass">#1E293B</color>
    <color name="awlqy_accent">#22D3EE</color>
    <color name="awlqy_text">#E2E8F0</color>
    <color name="awlqy_text_dim">#64748B</color>
    <color name="awlqy_error">#EF4444</color>
    <color name="awlqy_ok">#4ADE80</color>
    <color name="ic_launcher_background">#000000</color>
</resources>
XML_COL

# ═════════════════════════════════════════════════════════════
# 7. themes.xml — بدون تكرار
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/values/themes.xml <<'XML_THM'
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.Awlqy" parent="Theme.Material3.Dark.NoActionBar">
        <item name="colorPrimary">@color/awlqy_accent</item>
        <item name="colorOnPrimary">@color/awlqy_bg</item>
        <item name="colorSurface">@color/awlqy_surface</item>
        <item name="colorOnSurface">@color/awlqy_text</item>
        <item name="android:colorBackground">@color/awlqy_bg</item>
        <item name="android:statusBarColor">@color/awlqy_bg</item>
        <item name="android:navigationBarColor">@color/awlqy_bg</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowLightNavigationBar" tools:targetApi="27">false</item>
        <item name="android:windowBackground">@color/awlqy_bg</item>
    </style>
</resources>
XML_THM

# ═════════════════════════════════════════════════════════════
# 8. file_paths.xml
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/xml/file_paths.xml <<'XML_FP'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path          name="apk_cache"           path="."/>
    <external-cache-path name="apk_external_cache"  path="."/>
    <files-path          name="internal_files"      path="."/>
    <external-files-path name="external_files"      path="."/>
    <external-path       name="apk_external"        path="."/>
</paths>
XML_FP

# ═════════════════════════════════════════════════════════════
# 9. أيقونة launcher
# ═════════════════════════════════════════════════════════════
cat > app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml <<'XML_ICO'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
XML_ICO

cat > app/src/main/res/drawable/ic_launcher_foreground.xml <<'XML_FG'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#22D3EE"
        android:pathData="M34,42 L40,42 L40,66 L34,66 Z"/>
    <path android:fillColor="#22D3EE"
        android:pathData="M46,42 L52,42 L52,58 L58,58 L58,66 L46,66 Z"/>
    <path android:fillColor="#22D3EE"
        android:pathData="M62,42 L68,42 L68,66 L62,66 Z"/>
    <path android:fillColor="#22D3EE"
        android:pathData="M44,72 L64,72 L64,76 L44,76 Z"/>
</vector>
XML_FG

# ═════════════════════════════════════════════════════════════
# التحقق النهائي
# ═════════════════════════════════════════════════════════════
echo ""
echo "▶ [rebuild-p1] ملفات Kotlin:"
find app/src/main/java -name "*.kt" -exec sh -c 'echo "  $1"; head -n 1 "$1" | sed "s/^/    /"' _ {} \;
echo ""
echo "▶ [rebuild-p1] ملفات resources:"
find app/src/main/res -type f | sort
echo ""
echo "▶ [rebuild-p1] فحص أول سطر من AndroidManifest:"
head -n 1 app/src/main/AndroidManifest.xml
echo ""
echo "▶ [rebuild-p1] فحص أن XML نظيف (لا وجود لـ 'nano' أو 'k6k'):"
if grep -rl "nano app/\|k6k" app/src/main/res/ app/src/main/AndroidManifest.xml 2>/dev/null; then
    echo "⚠ توجد ملفات ملوّثة"
else
    echo "  ✔ نظيف"
fi
echo ""
echo "✔ [rebuild-p1] انتهى."
echo ""
echo "   git add -A"
echo "   git commit -m 'rebuild phase-1 cleanly from scratch'"
echo "   git push"
