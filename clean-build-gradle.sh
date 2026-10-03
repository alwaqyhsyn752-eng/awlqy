#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · clean-build-gradle.sh
#  إعادة كتابة app/build.gradle.kts نظيف
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ [clean-gradle] نسخة احتياطية"
cp -f app/build.gradle.kts app/build.gradle.kts.bak 2>/dev/null || true

echo "▶ [clean-gradle] كتابة الملف النظيف"

cat > app/build.gradle.kts <<'GRADLE_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.awlqy.terminal"
    compileSdk = 34
    ndkVersion = "26.1.10909125"

    defaultConfig {
        applicationId = "com.awlqy.terminal"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c17 -O2"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
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

echo "▶ [clean-gradle] التحقق"

# عدد مرات ظهور kotlinOptions و buildFeatures يجب أن يكون 1
KO=$(grep -c "kotlinOptions" app/build.gradle.kts)
BF=$(grep -c "buildFeatures" app/build.gradle.kts)
PK=$(grep -c "packaging" app/build.gradle.kts)

echo "  kotlinOptions : $KO  (يجب 1)"
echo "  buildFeatures : $BF  (يجب 1)"
echo "  packaging     : $PK  (يجب 1)"

# التحقق من توازن الأقواس
OPEN=$(grep -o "{" app/build.gradle.kts | wc -l)
CLOSE=$(grep -o "}" app/build.gradle.kts | wc -l)
echo "  '{' = $OPEN  '}' = $CLOSE"

if [ "$KO" != "1" ] || [ "$BF" != "1" ] || [ "$OPEN" != "$CLOSE" ]; then
    echo "⚠ هناك خلل — راجع الملف يدوياً"
    exit 1
fi

echo ""
echo "▶ [clean-gradle] فحص أن الملف بدأ بـ plugins:"
head -n 3 app/build.gradle.kts

echo ""
echo "▶ [clean-gradle] قائمة التبعيات:"
grep "implementation(" app/build.gradle.kts

echo ""
echo "✔ [clean-gradle] انتهى."
echo ""
echo "   git add -A"
echo "   git commit -m 'fix: clean app/build.gradle.kts for PTY build'"
echo "   git push"
