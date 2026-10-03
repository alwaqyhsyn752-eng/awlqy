#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · setup-phase1.sh
#  يكتب كل ملفات المرحلة 1 دفعة واحدة
#  Developer: حسين الخلاقي · GitHub: alwaqyhsyn752-eng
# ─────────────────────────────────────────────────────────────
set -euo pipefail

echo "▶ [awlqy] إنشاء هيكل المجلدات..."
mkdir -p .github/workflows
mkdir -p app/src/main/java/com/awlqy/terminal
mkdir -p app/src/main/res/values
mkdir -p app/src/main/res/drawable
mkdir -p app/src/main/res/mipmap-anydpi-v26

# ─── 1. .github/workflows/build.yml ─────────────────────────
cat > .github/workflows/build.yml <<'EOF_YML'
name: Build awlqy APK

on:
  push:
    branches: [ main, master ]
    tags:     [ 'v*' ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: awlqy-build-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    name: Build APK (release-signed)
    runs-on: ubuntu-22.04
    timeout-minutes: 40

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

      - name: Cache Gradle caches
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: awlqy-gradle-${{ runner.os }}-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: |
            awlqy-gradle-${{ runner.os }}-

      - name: Build Release APK
        run: gradle :app:assembleRelease --no-daemon --stacktrace

      - name: Collect artifact
        run: |
          set -e
          mkdir -p out
          APK="$(ls app/build/outputs/apk/release/*.apk | head -n 1)"
          cp "$APK" out/awlqy.apk
          sha256sum out/awlqy.apk > out/awlqy.apk.sha256
          ls -la out

      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: awlqy-apk
          path: |
            out/awlqy.apk
            out/awlqy.apk.sha256
          if-no-files-found: error
          retention-days: 30

      - name: Publish GitHub Release
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          name: awlqy ${{ github.ref_name }}
          files: |
            out/awlqy.apk
            out/awlqy.apk.sha256
          generate_release_notes: true
          draft: false
          prerelease: false
EOF_YML

# ─── 2. settings.gradle.kts ─────────────────────────────────
cat > settings.gradle.kts <<'EOF_SET'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "awlqy"
include(":app")
EOF_SET

# ─── 3. build.gradle.kts (root) ─────────────────────────────
cat > build.gradle.kts <<'EOF_ROOT'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
EOF_ROOT

# ─── 4. app/build.gradle.kts ────────────────────────────────
cat > app/build.gradle.kts <<'EOF_APP'
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
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.jakewharton.timber:timber:5.0.1")
}
EOF_APP

# ─── 5. app/proguard-rules.pro ──────────────────────────────
cat > app/proguard-rules.pro <<'EOF_PRO'
-keep class com.awlqy.terminal.** { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
EOF_PRO

# ─── 6. .gitignore ──────────────────────────────────────────
cat > .gitignore <<'EOF_GIT'
*.iml
.gradle/
/local.properties
/.idea/
.DS_Store
/build
/app/build
/captures
.externalNativeBuild
.cxx
local.properties
*.apk
*.ap_
*.dex
*.class
out/
EOF_GIT

# ─── 7. AndroidManifest.xml ─────────────────────────────────
cat > app/src/main/AndroidManifest.xml <<'EOF_MAN'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28" tools:ignore="ScopedStorage"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>

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

        <meta-data
            android:name="com.awlqy.DEVELOPER"
            android:value="حسين الخلاقي"/>
        <meta-data
            android:name="com.awlqy.GITHUB"
            android:value="alwaqyhsyn752-eng"/>
    </application>
</manifest>
EOF_MAN

# ─── 8. AwlqyApp.kt ─────────────────────────────────────────
cat > app/src/main/java/com/awlqy/terminal/AwlqyApp.kt <<'EOF_KOT'
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
        File(filesDir, "tmp").mkdirs()
        File(filesDir, "usr").mkdirs()
        File(filesDir, "usr/bin").mkdirs()

        createNotificationChannel()

        Timber.i("awlqy phase-1 booted — developer: %s", DEVELOPER)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_session),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = getString(R.string.app_tagline)
                setShowBadge(false)
            }
            val mgr = getSystemService(NotificationManager::class.java)
            mgr.createNotificationChannel(channel)
        }
    }

    companion object {
        const val CHANNEL_ID = "awlqy_session"
        const val DEVELOPER = "حسين الخلاقي"
    }
}
EOF_KOT

# ─── 9. MainActivity.kt ─────────────────────────────────────
cat > app/src/main/java/com/awlqy/terminal/MainActivity.kt <<'EOF_MA'
package com.awlqy.terminal

import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import timber.log.Timber

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(getColor(R.color.awlqy_bg))
            setPadding(48, 96, 48, 48)
        }

        val title = TextView(this).apply {
            text = getString(R.string.app_name)
            textSize = 42f
            setTextColor(getColor(R.color.awlqy_accent))
            gravity = Gravity.CENTER
        }

        val tagline = TextView(this).apply {
            text = getString(R.string.app_tagline)
            textSize = 14f
            setTextColor(getColor(R.color.awlqy_text_dim))
            gravity = Gravity.CENTER
            setPadding(0, 12, 0, 0)
        }

        val dev = TextView(this).apply {
            text = "${getString(R.string.developer_name)} — ${getString(R.string.developer_role)}"
            textSize = 16f
            setTextColor(getColor(R.color.awlqy_text))
            gravity = Gravity.CENTER
            setPadding(0, 48, 0, 0)
        }

        val phase = TextView(this).apply {
            text = "PHASE 1 · Skeleton Ready"
            textSize = 12f
            setTextColor(getColor(R.color.awlqy_text_dim))
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 0)
        }

        root.addView(title)
        root.addView(tagline)
        root.addView(dev)
        root.addView(phase)

        setContentView(root)

        Timber.i("MainActivity ready — waiting for Phase 2")
    }
}
EOF_MA

# ─── 10. strings.xml ────────────────────────────────────────
cat > app/src/main/res/values/strings.xml <<'EOF_STR'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">awlqy</string>
    <string name="app_tagline">طرفية · بيئة تطوير · مدير حزم ذكي</string>
    <string name="developer_name">حسين الخلاقي</string>
    <string name="developer_role">المطوّر / المنشئ</string>
    <string name="github_handle">alwaqyhsyn752-eng</string>
    <string name="notification_channel_session">جلسة awlqy</string>
    <string name="notification_session_active">جلسة الطرفية نشطة</string>
</resources>
EOF_STR

# ─── 11. colors.xml ─────────────────────────────────────────
cat > app/src/main/res/values/colors.xml <<'EOF_COL'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="awlqy_bg">#0A0E14</color>
    <color name="awlqy_surface">#121721</color>
    <color name="awlqy_glass">#1A2130</color>
    <color name="awlqy_accent">#3DDC97</color>
    <color name="awlqy_accent_dim">#1F7A5A</color>
    <color name="awlqy_text">#E6EDF3</color>
    <color name="awlqy_text_dim">#8B98A8</color>
    <color name="awlqy_error">#FF5C7A</color>
    <color name="ic_launcher_background">#0A0E14</color>
</resources>
EOF_COL

# ─── 12. themes.xml ─────────────────────────────────────────
cat > app/src/main/res/values/themes.xml <<'EOF_THM'
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.Awlqy" parent="Theme.Material3.Dark.NoActionBar">
        <item name="colorPrimary">@color/awlqy_accent</item>
        <item name="colorOnPrimary">@color/awlqy_bg</item>
        <item name="colorSurface">@color/awlqy_surface</item>
        <item name="colorOnSurface">@color/awlqy_text</item>
        <item name="android:colorBackground">@color/awlqy_bg</item>
        <item name="android:statusBarColor">@android:color/transparent</item>
        <item name="android:navigationBarColor">@color/awlqy_bg</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowLightNavigationBar" tools:targetApi="27">false</item>
        <item name="android:windowBackground">@color/awlqy_bg</item>
    </style>
</resources>
EOF_THM

# ─── 13. ic_launcher.xml ────────────────────────────────────
cat > app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml <<'EOF_ICO'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
EOF_ICO

# ─── 14. ic_launcher_foreground.xml ─────────────────────────
cat > app/src/main/res/drawable/ic_launcher_foreground.xml <<'EOF_FG'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#3DDC97"
        android:pathData="M34,42 L40,42 L40,66 L34,66 Z"/>
    <path android:fillColor="#3DDC97"
        android:pathData="M46,42 L52,42 L52,58 L58,58 L58,66 L46,66 Z"/>
    <path android:fillColor="#3DDC97"
        android:pathData="M62,42 L68,42 L68,66 L62,66 Z"/>
    <path android:fillColor="#3DDC97"
        android:pathData="M44,72 L64,72 L64,76 L44,76 Z"/>
</vector>
EOF_FG

# ─── التحقق ─────────────────────────────────────────────────
echo ""
echo "▶ [awlqy] التحقق من الملفات:"
find . -type f -not -path "./.git/*" -not -name "setup-phase1.sh" | sort

echo ""
echo "✔ [awlqy] المرحلة 1 جاهزة — 14 ملف."
