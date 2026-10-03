#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · 01-bootstrap.sh
#  هيكل المشروع + Gradle + Manifest + الموارد + الواجهات + Kotlin الأساسي
#  Developer: حسين الخلاقي  ·  GitHub: alwaqyhsyn752-eng
# ─────────────────────────────────────────────────────────────
set -euo pipefail

echo "▶ [awlqy] 01-bootstrap: بناء هيكل المشروع"

# ═══ DIRS ═══
mkdir -p app/src/main/java/com/awlqy/terminal/{core,ui,ui/fragments,ui/adapters,service,data,util}
mkdir -p app/src/main/res/{layout,values,drawable,mipmap-anydpi-v26,xml,menu,anim,navigation}
mkdir -p app/src/main/cpp
mkdir -p app/src/main/assets
mkdir -p .github/workflows

# ═══ settings.gradle ═══
cat > settings.gradle <<'AWLQY_EOF'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "awlqy"
include ':app'
AWLQY_EOF

# ═══ build.gradle (root) ═══
cat > build.gradle <<'AWLQY_EOF'
plugins {
    id 'com.android.application' version '8.5.2' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.24' apply false
}
tasks.register('clean', Delete) { delete rootProject.layout.buildDirectory }
AWLQY_EOF

# ═══ gradle.properties ═══
cat > gradle.properties <<'AWLQY_EOF'
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=1024m -Dfile.encoding=UTF-8
org.gradle.parallel=true
org.gradle.caching=true
android.useAndroidX=true
android.nonTransitiveRClass=true
android.nonFinalResIds=false
android.defaults.buildfeatures.buildconfig=true
kotlin.code.style=official
AWLQY_EOF

# ═══ app/build.gradle ═══
cat > app/build.gradle <<'AWLQY_EOF'
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}
android {
    namespace 'com.awlqy.terminal'
    compileSdk 34
    ndkVersion '26.1.10909125'
    defaultConfig {
        applicationId "com.awlqy.terminal"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0.0"
        ndk { abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64' }
        externalNativeBuild {
            cmake {
                cppFlags '-std=c++17 -frtti -fexceptions -O2'
                arguments '-DANDROID_STL=c++_shared'
            }
        }
    }
    buildTypes {
        debug { minifyEnabled false; debuggable true }
        release {
            minifyEnabled false
            shrinkResources false
            signingConfig signingConfigs.debug
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    externalNativeBuild { cmake { path file('src/main/cpp/CMakeLists.txt'); version '3.22.1' } }
    compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = '17' }
    buildFeatures { viewBinding true; buildConfig true }
    packaging { jniLibs { useLegacyPackaging true } }
}
dependencies {
    implementation 'androidx.core:core-ktx:1.13.1'
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'com.google.android.material:material:1.12.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    implementation 'androidx.recyclerview:recyclerview:1.3.2'
    implementation 'androidx.viewpager2:viewpager2:1.1.0'
    implementation 'androidx.drawerlayout:drawerlayout:1.2.0'
    implementation 'androidx.preference:preference-ktx:1.2.1'
    implementation 'androidx.lifecycle:lifecycle-runtime-ktx:2.8.4'
    implementation 'androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.4'
    implementation 'androidx.fragment:fragment-ktx:1.8.2'
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1'
    implementation 'com.jakewharton.timber:timber:5.0.1'
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
}
AWLQY_EOF

# ═══ proguard ═══
cat > app/proguard-rules.pro <<'AWLQY_EOF'
-keep class com.awlqy.terminal.core.** { *; }
-keepclasseswithmembernames class * { native <methods>; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
AWLQY_EOF

# ═══ AndroidManifest.xml ═══
cat > app/src/main/AndroidManifest.xml <<'AWLQY_EOF'
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
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"
        tools:ignore="QueryAllPackagesPermission"/>

    <application
        android:name=".AwlqyApp"
        android:allowBackup="true"
        android:extractNativeLibs="true"
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

        <service
            android:name=".service.AwlqySessionService"
            android:exported="false"
            android:foregroundServiceType="dataSync"/>

        <receiver
            android:name=".service.BootReceiver"
            android:exported="true"
            android:enabled="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
            </intent-filter>
        </receiver>

        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths"/>
        </provider>

        <meta-data android:name="com.awlqy.DEVELOPER" android:value="حسين الخلاقي"/>
    </application>
</manifest>
AWLQY_EOF

# ═══ file_paths.xml ═══
cat > app/src/main/res/xml/file_paths.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <files-path name="files" path="."/>
    <cache-path name="cache" path="."/>
    <external-files-path name="ext_files" path="."/>
    <external-cache-path name="ext_cache" path="."/>
    <external-path name="external" path="."/>
</paths>
AWLQY_EOF

# ═══ strings.xml ═══
cat > app/src/main/res/values/strings.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">awlqy</string>
    <string name="app_tagline">طرفية · بيئة تطوير · مدير حزم ذكي</string>
    <string name="developer_name">حسين الخلاقي</string>
    <string name="developer_role">المطوّر / المنشئ</string>
    <string name="github_handle">alwaqyhsyn752-eng</string>
    <string name="notification_channel_session">جلسة awlqy</string>
    <string name="notification_session_active">جلسة الطرفية نشطة</string>
    <string name="menu_terminal">الطرفية</string>
    <string name="menu_settings">الإعدادات</string>
    <string name="menu_help">المساعدة</string>
    <string name="menu_code_guide">دليل الأكواد</string>
    <string name="menu_ascii">مولّد ASCII</string>
    <string name="menu_pkg">مدير الحزم</string>
    <string name="menu_apk">بناء APK</string>
    <string name="menu_about">حول التطبيق</string>
    <string name="tab_new">جلسة جديدة</string>
    <string name="action_send">إرسال</string>
    <string name="action_clear">مسح</string>
    <string name="action_ctrl_c">Ctrl+C</string>
    <string name="action_ctrl_d">Ctrl+D</string>
    <string name="action_tab">Tab</string>
    <string name="action_esc">Esc</string>
</resources>
AWLQY_EOF

# ═══ colors.xml ═══
cat > app/src/main/res/values/colors.xml <<'AWLQY_EOF'
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
AWLQY_EOF

# ═══ themes.xml ═══
cat > app/src/main/res/values/themes.xml <<'AWLQY_EOF'
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
AWLQY_EOF

# ═══ launcher icon ═══
cat > app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
AWLQY_EOF

cat > app/src/main/res/drawable/ic_launcher_foreground.xml <<'AWLQY_EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#3DDC97" android:pathData="M34,42 L40,42 L40,66 L34,66 Z"/>
    <path android:fillColor="#3DDC97" android:pathData="M46,42 L52,42 L52,58 L58,58 L58,66 L46,66 Z"/>
    <path android:fillColor="#3DDC97" android:pathData="M62,42 L68,42 L68,66 L62,66 Z"/>
    <path android:fillColor="#3DDC97" android:pathData="M44,72 L64,72 L64,76 L44,76 Z"/>
</vector>
AWLQY_EOF

# ═══ bg_terminal.xml ═══
cat > app/src/main/res/drawable/bg_terminal.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="@color/awlqy_bg"/>
    <corners android:radius="8dp"/>
    <stroke android:width="1dp" android:color="@color/awlqy_accent_dim"/>
</shape>
AWLQY_EOF

# ═══ activity_main.xml ═══
cat > app/src/main/res/layout/activity_main.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.drawerlayout.widget.DrawerLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:id="@+id/drawerLayout"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/awlqy_bg"
    android:fitsSystemWindows="true">

    <androidx.coordinatorlayout.widget.CoordinatorLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent">

        <com.google.android.material.appbar.AppBarLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="@color/awlqy_surface"
            app:elevation="0dp">

            <com.google.android.material.appbar.MaterialToolbar
                android:id="@+id/toolbar"
                android:layout_width="match_parent"
                android:layout_height="?attr/actionBarSize"
                android:background="@color/awlqy_surface"
                app:navigationIcon="@drawable/ic_menu"
                app:title="@string/app_name"
                app:titleTextColor="@color/awlqy_text"/>

            <com.google.android.material.tabs.TabLayout
                android:id="@+id/tabLayout"
                android:layout_width="match_parent"
                android:layout_height="40dp"
                android:background="@color/awlqy_surface"
                app:tabIndicatorColor="@color/awlqy_accent"
                app:tabSelectedTextColor="@color/awlqy_accent"
                app:tabTextColor="@color/awlqy_text_dim"
                app:tabMode="scrollable"/>
        </com.google.android.material.appbar.AppBarLayout>

        <androidx.viewpager2.widget.ViewPager2
            android:id="@+id/viewPager"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            app:layout_behavior="@string/appbar_scrolling_view_behavior"/>

        <com.google.android.material.floatingactionbutton.FloatingActionButton
            android:id="@+id/fabNewSession"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_gravity="bottom|end"
            android:layout_margin="16dp"
            android:contentDescription="@string/tab_new"
            android:src="@drawable/ic_plus"
            app:backgroundTint="@color/awlqy_accent"
            app:tint="@color/awlqy_bg"/>
    </androidx.coordinatorlayout.widget.CoordinatorLayout>

    <com.google.android.material.navigation.NavigationView
        android:id="@+id/navView"
        android:layout_width="280dp"
        android:layout_height="match_parent"
        android:layout_gravity="start"
        android:background="@color/awlqy_surface"
        android:fitsSystemWindows="true"
        app:headerLayout="@layout/nav_header"
        app:itemIconTint="@color/awlqy_accent"
        app:itemTextColor="@color/awlqy_text"
        app:menu="@menu/drawer_menu"/>
</androidx.drawerlayout.widget.DrawerLayout>
AWLQY_EOF

# ═══ nav_header.xml ═══
cat > app/src/main/res/layout/nav_header.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="180dp"
    android:background="@color/awlqy_glass"
    android:gravity="bottom"
    android:orientation="vertical"
    android:padding="16dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="awlqy"
        android:textColor="@color/awlqy_accent"
        android:textSize="26sp"
        android:textStyle="bold"/>

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="4dp"
        android:text="@string/app_tagline"
        android:textColor="@color/awlqy_text_dim"
        android:textSize="12sp"/>

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="12dp"
        android:text="@string/developer_name"
        android:textColor="@color/awlqy_text"
        android:textSize="14sp"
        android:textStyle="bold"/>

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/developer_role"
        android:textColor="@color/awlqy_text_dim"
        android:textSize="11sp"/>
</LinearLayout>
AWLQY_EOF

# ═══ drawer_menu.xml ═══
cat > app/src/main/res/menu/drawer_menu.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android">
    <group android:checkableBehavior="single">
        <item android:id="@+id/nav_terminal"   android:title="@string/menu_terminal"/>
        <item android:id="@+id/nav_pkg"        android:title="@string/menu_pkg"/>
        <item android:id="@+id/nav_apk"        android:title="@string/menu_apk"/>
        <item android:id="@+id/nav_code"       android:title="@string/menu_code_guide"/>
        <item android:id="@+id/nav_ascii"      android:title="@string/menu_ascii"/>
        <item android:id="@+id/nav_help"       android:title="@string/menu_help"/>
        <item android:id="@+id/nav_settings"   android:title="@string/menu_settings"/>
        <item android:id="@+id/nav_about"      android:title="@string/menu_about"/>
    </group>
</menu>
AWLQY_EOF

# ═══ fragment_terminal.xml ═══
cat > app/src/main/res/layout/fragment_terminal.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/awlqy_bg"
    android:orientation="vertical">

    <com.awlqy.terminal.ui.TerminalView
        android:id="@+id/terminalView"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:background="@drawable/bg_terminal"
        android:padding="6dp"/>

    <HorizontalScrollView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="@color/awlqy_surface"
        android:scrollbars="none">

        <LinearLayout
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:padding="6dp">

            <Button android:id="@+id/btnCtrlC" style="@style/KeyButton" android:text="Ctrl+C"/>
            <Button android:id="@+id/btnCtrlD" style="@style/KeyButton" android:text="Ctrl+D"/>
            <Button android:id="@+id/btnCtrlZ" style="@style/KeyButton" android:text="Ctrl+Z"/>
            <Button android:id="@+id/btnTab"   style="@style/KeyButton" android:text="Tab"/>
            <Button android:id="@+id/btnEsc"   style="@style/KeyButton" android:text="Esc"/>
            <Button android:id="@+id/btnUp"    style="@style/KeyButton" android:text="↑"/>
            <Button android:id="@+id/btnDown"  style="@style/KeyButton" android:text="↓"/>
            <Button android:id="@+id/btnLeft"  style="@style/KeyButton" android:text="←"/>
            <Button android:id="@+id/btnRight" style="@style/KeyButton" android:text="→"/>
            <Button android:id="@+id/btnClear" style="@style/KeyButton" android:text="Clear"/>
        </LinearLayout>
    </HorizontalScrollView>

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
            android:hint="اكتب أمراً..."
            android:imeOptions="actionSend|flagNoFullscreen"
            android:inputType="text|textNoSuggestions|textVisiblePassword"
            android:padding="10dp"
            android:textColor="@color/awlqy_text"
            android:textColorHint="@color/awlqy_text_dim"
            android:textDirection="locale"/>

        <Button
            android:id="@+id/btnSend"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="6dp"
            android:backgroundTint="@color/awlqy_accent"
            android:text="@string/action_send"
            android:textColor="@color/awlqy_bg"/>
    </LinearLayout>
</LinearLayout>
AWLQY_EOF

# ═══ KeyButton style ═══
cat >> app/src/main/res/values/themes.xml <<'AWLQY_EOF'
AWLQY_EOF

cat > app/src/main/res/values/styles.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="KeyButton" parent="Widget.Material3.Button.TonalButton">
        <item name="android:layout_width">wrap_content</item>
        <item name="android:layout_height">40dp</item>
        <item name="android:layout_marginEnd">4dp</item>
        <item name="android:minWidth">52dp</item>
        <item name="android:textSize">12sp</item>
        <item name="android:paddingStart">10dp</item>
        <item name="android:paddingEnd">10dp</item>
        <item name="backgroundTint">@color/awlqy_glass</item>
        <item name="android:textColor">@color/awlqy_accent</item>
    </style>
</resources>
AWLQY_EOF

# ═══ fragment_settings.xml ═══
cat > app/src/main/res/layout/fragment_settings.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/awlqy_bg"
    android:padding="16dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical">

        <TextView style="@style/SectionTitle" android:text="المطوّر"/>
        <TextView style="@style/BodyText" android:text="@string/developer_name"/>
        <TextView style="@style/BodyDim" android:text="@string/developer_role"/>

        <TextView style="@style/SectionTitle" android:layout_marginTop="24dp" android:text="GitHub"/>
        <TextView style="@style/BodyText" android:text="@string/github_handle"/>

        <TextView style="@style/SectionTitle" android:layout_marginTop="24dp" android:text="الطرفية"/>
        <EditText android:id="@+id/editShell" style="@style/InputRow"
            android:hint="/system/bin/sh" android:text="/system/bin/sh"/>
        <EditText android:id="@+id/editHome" style="@style/InputRow"
            android:hint="/data/data/com.awlqy.terminal/files/home"
            android:text="/data/data/com.awlqy.terminal/files/home"/>

        <TextView style="@style/SectionTitle" android:layout_marginTop="24dp" android:text="المظهر"/>
        <Switch android:id="@+id/switchRtl" style="@style/BodyText"
            android:text="تفعيل محرك النص العربي (RTL)"/>
        <Switch android:id="@+id/switchGlass" style="@style/BodyText"
            android:text="تأثير Glassmorphism"/>

        <Button
            android:id="@+id/btnSave"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="24dp"
            android:backgroundTint="@color/awlqy_accent"
            android:text="حفظ الإعدادات"
            android:textColor="@color/awlqy_bg"/>
    </LinearLayout>
</ScrollView>
AWLQY_EOF

cat > app/src/main/res/values/styles.xml <<'AWLQY_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="SectionTitle">
        <item name="android:layout_width">match_parent</item>
        <item name="android:layout_height">wrap_content</item>
        <item name="android:textColor">@color/awlqy_accent</item>
        <item name="android:textSize">14sp</item>
        <item name="android:textStyle">bold</item>
        <item name="android:layout_marginBottom">6dp</item>
    </style>
    <style name="BodyText">
        <item name="android:layout_width">match_parent</item>
        <item name="android:layout_height">wrap_content</item>
        <item name="android:textColor">@color/awlqy_text</item>
        <item name="android:textSize">15sp</item>
    </style>
    <style name="BodyDim">
        <item name="android:layout_width">match_parent</item>
        <item name="android:layout_height">wrap_content</item>
        <item name="android:textColor">@color/awlqy_text_dim</item>
        <item name="android:textSize">12sp</item>
    </style>
    <style name="InputRow">
        <item name="android:layout_width">match_parent</item>
        <item name="android:layout_height">wrap_content</item>
        <item name="android:background">@color/awlqy_glass</item>
        <item name="android:padding">10dp</item>
        <item name="android:layout_marginBottom">8dp</item>
        <item name="android:textColor">@color/awlqy_text</item>
        <item name="android:textColorHint">@color/awlqy_text_dim</item>
    </style>
</resources>
AWLQY_EOF

# ═══ ic_menu / ic_plus (vector) ═══
cat > app/src/main/res/drawable/ic_menu.xml <<'AWLQY_EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#E6EDF3" android:pathData="M3,6h18v2H3zM3,11h18v2H3zM3,16h18v2H3z"/>
</vector>
AWLQY_EOF

cat > app/src/main/res/drawable/ic_plus.xml <<'AWLQY_EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#0A0E14" android:pathData="M11,5h2v6h6v2h-6v6h-2v-6H5v-2h6z"/>
</vector>
AWLQY_EOF

# ═══ AwlqyApp.kt ═══
cat > app/src/main/java/com/awlqy/terminal/AwlqyApp.kt <<'AWLQY_EOF'
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

        // تهيئة بيئة التطبيق: مجلد home، tmp، usr
        val home = File(filesDir, "home").apply { mkdirs() }
        File(filesDir, "tmp").mkdirs()
        File(filesDir, "usr").mkdirs()
        File(filesDir, "usr/bin").mkdirs()
        System.setProperty("awlqy.home", home.absolutePath)

        createNotificationChannel()
        Timber.i("awlqy by حسين الخلاقي — ready. home=%s", home.absolutePath)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_session),
                NotificationManager.IMPORTANCE_LOW
            )
            val mgr = getSystemService(NotificationManager::class.java)
            mgr.createNotificationChannel(ch)
        }
    }

    companion object { const val CHANNEL_ID = "awlqy_session" }
}
AWLQY_EOF

# ═══ MainActivity.kt ═══
cat > app/src/main/java/com/awlqy/terminal/MainActivity.kt <<'AWLQY_EOF'
package com.awlqy.terminal

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.GravityCompat
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import androidx.viewpager2.adapter.FragmentStateAdapter
import com.awlqy.terminal.databinding.ActivityMainBinding
import com.awlqy.terminal.service.AwlqySessionService
import com.awlqy.terminal.ui.fragments.*
import com.google.android.material.tabs.TabLayoutMediator
import timber.log.Timber

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val terminalTabs = mutableListOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setSupportActionBar(binding.toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        binding.toolbar.setNavigationOnClickListener {
            binding.drawerLayout.openDrawer(GravityCompat.START)
        }

        setupViewPager()
        setupDrawer()

        binding.fabNewSession.setOnClickListener {
            addTerminalTab("session-${terminalTabs.size + 1}")
        }

        addTerminalTab("main")

        // شغّل الخدمة الأمامية
        startForegroundService(Intent(this, AwlqySessionService::class.java))
    }

    private fun setupViewPager() {
        binding.viewPager.adapter = TerminalPagerAdapter(this)
        TabLayoutMediator(binding.tabLayout, binding.viewPager) { tab, pos ->
            tab.text = terminalTabs.getOrElse(pos) { "؟" }
        }.attach()
    }

    private fun addTerminalTab(name: String) {
        terminalTabs.add(name)
        binding.viewPager.adapter?.notifyDataSetChanged()
        binding.viewPager.setCurrentItem(terminalTabs.size - 1, true)
    }

    private fun setupDrawer() {
        binding.navView.setNavigationItemSelectedListener { item ->
            when (item.itemId) {
                R.id.nav_terminal -> { /* الطرفية مرئية أساساً */ }
                R.id.nav_settings -> replaceContent(SettingsFragment())
                R.id.nav_help     -> replaceContent(HelpFragment())
                R.id.nav_code     -> replaceContent(CodeGuideFragment())
                R.id.nav_ascii    -> replaceContent(AsciiFragment())
                R.id.nav_pkg      -> replaceContent(PkgFragment())
                R.id.nav_apk      -> replaceContent(ApkFragment())
                R.id.nav_about    -> showAbout()
            }
            binding.drawerLayout.closeDrawer(GravityCompat.START)
            true
        }
    }

    private fun replaceContent(f: Fragment) {
        supportFragmentManager.beginTransaction()
            .replace(android.R.id.content, f)
            .addToBackStack(null)
            .commit()
    }

    private fun showAbout() {
        Toast.makeText(
            this,
            "awlqy v${BuildConfig.VERSION_NAME}\nالمطوّر: ${getString(R.string.developer_name)}",
            Toast.LENGTH_LONG
        ).show()
    }

    inner class TerminalPagerAdapter(activity: FragmentActivity) : FragmentStateAdapter(activity) {
        override fun getItemCount(): Int = terminalTabs.size
        override fun createFragment(position: Int): Fragment =
            TerminalFragment.newInstance(terminalTabs[position])
    }
}
AWLQY_EOF

# ═══ Fragments placeholders (سنكملها في الملف 2) ═══
for f in TerminalFragment HelpFragment CodeGuideFragment AsciiFragment PkgFragment ApkFragment SettingsFragment; do
cat > app/src/main/java/com/awlqy/terminal/ui/fragments/$f.kt <<AWLQY_EOF
package com.awlqy.terminal.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment

class $f : Fragment() {
    override fun onCreateView(i: LayoutInflater, c: ViewGroup?, s: Bundle?): View =
        View(i.context)
}
AWLQY_EOF
done

echo "✔ [awlqy] 01-bootstrap: انتهى."
