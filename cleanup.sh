#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · cleanup.sh — حذف كل آثار C++/NDK وإعادة المرحلة 1
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [cleanup] حذف مجلد cpp و CMakeLists"
rm -rf app/src/main/cpp
rm -rf app/.cxx
rm -f app/src/main/cpp/CMakeLists.txt 2>/dev/null || true

echo "▶ [cleanup] حذف أي Kotlin files تعتمد JNI"
rm -f app/src/main/java/com/awlqy/terminal/core/PtyBridge.kt 2>/dev/null || true
rm -f app/src/main/java/com/awlqy/terminal/core/ArabicShaper.kt 2>/dev/null || true
rm -f app/src/main/java/com/awlqy/terminal/core/TerminalSession.kt 2>/dev/null || true
rm -f app/src/main/java/com/awlqy/terminal/ui/TerminalView.kt 2>/dev/null || true
rm -f app/src/main/java/com/awlqy/terminal/ui/fragments/TerminalFragment.kt 2>/dev/null || true
rmdir app/src/main/java/com/awlqy/terminal/core 2>/dev/null || true

echo "▶ [cleanup] إعادة كتابة app/build.gradle.kts بدون NDK"
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

echo "▶ [cleanup] إعادة كتابة AndroidManifest.xml (بدون extractNativeLibs)"
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

echo "▶ [cleanup] تحديث .gitignore ليشمل cpp"
grep -q "^app/src/main/cpp" .gitignore 2>/dev/null || echo "app/src/main/cpp/" >> .gitignore
grep -q "^app/.cxx" .gitignore 2>/dev/null || echo "app/.cxx/" >> .gitignore

echo "▶ [cleanup] التحقق من أن لا يوجد أي أثر NDK"
echo ""
echo "─── ملفات build.gradle.kts التي تحتوي externalNativeBuild:"
grep -rl "externalNativeBuild" . --include="*.gradle.kts" 2>/dev/null || echo "  (لا شيء) ✔"
echo ""
echo "─── ملفات CMakeLists.txt:"
find . -name "CMakeLists.txt" -not -path "./.git/*" 2>/dev/null || true
echo ""
echo "─── مجلد cpp:"
ls app/src/main/cpp 2>/dev/null && echo "⚠ لا يزال موجود!" || echo "  (محذوف) ✔"
echo ""
echo "─── ملفات .kt في core:"
ls app/src/main/java/com/awlqy/terminal/core 2>/dev/null || echo "  (لا يوجد) ✔"

echo ""
echo "✔ [cleanup] انتهى. الآن:"
echo "   git add ."
echo "   git commit -m 'cleanup: remove NDK/C++ for phase-1 green build'"
echo "   git push"
