#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  awlqy · 03-github.sh (clean rebuild)
#  Developer: حسين الخلاقي · GitHub: alwaqyhsyn752-eng
# ─────────────────────────────────────────────────────────────
set -euo pipefail

GITHUB_USER="alwaqyhsyn752-eng"
REPO_NAME="awlqy"
DEV_NAME="حسين الخلاقي"

echo "▶ [awlqy] 03-github: writing workflow + README + git"

# ═══ إنشاء مجلد الـ workflow ═══
mkdir -p .github/workflows

# ═══ .github/workflows/build.yml ═══
cat > .github/workflows/build.yml <<'AWLQY_YML_EOF'
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
    name: Build APK
    runs-on: ubuntu-22.04
    timeout-minutes: 60
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive
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
            ndk;26.1.10909125
            cmake;3.22.1

      - name: Export NDK env
        run: |
          echo "ANDROID_NDK_HOME=$ANDROID_SDK_ROOT/ndk/26.1.10909125" >> "$GITHUB_ENV"
          echo "ANDROID_NDK=$ANDROID_SDK_ROOT/ndk/26.1.10909125"      >> "$GITHUB_ENV"
          echo "ANDROID_NDK_ROOT=$ANDROID_SDK_ROOT/ndk/26.1.10909125"  >> "$GITHUB_ENV"

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v3
        with:
          gradle-version: '8.7'

      - name: Cache
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
            app/.cxx
          key: awlqy-cmake-${{ runner.os }}-${{ hashFiles('app/src/main/cpp/CMakeLists.txt') }}
          restore-keys: |
            awlqy-cmake-${{ runner.os }}-

      - name: Build Release APK
        run: gradle :app:assembleRelease --no-daemon --stacktrace

      - name: Collect
        run: |
          set -e
          mkdir -p out
          APK="$(ls app/build/outputs/apk/release/*.apk | head -n 1)"
          cp "$APK" out/awlqy.apk
          sha256sum out/awlqy.apk > out/awlqy.apk.sha256

      - name: Upload
        uses: actions/upload-artifact@v4
        with:
          name: awlqy-apk
          path: |
            out/awlqy.apk
            out/awlqy.apk.sha256
          if-no-files-found: error
          retention-days: 30

      - name: Release
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
AWLQY_YML_EOF

# ═══ README.md (نص عادي، بدون backticks) ═══
cat > README.md <<'AWLQY_README_EOF'
<div dir="rtl">

# awlqy · طرفية وبيئة تطوير أندرويد متقدمة

المطوّر / المنشئ: حسين الخلاقي
GitHub: alwaqyhsyn752-eng
الترخيص: MIT — الحد الأدنى: أندرويد 7.0 (API 24)

## المميزات

- طرفية كاملة عبر PTY أصلي (forkpty + exec) — ليست محاكاة.
- محرك نص عربي حقيقي: FriBidi + HarfBuzz + Presentation Forms-B.
- واجهة عصرية: Drawer، تبويبات، FloatingActionButton، Glassmorphism.
- دليل أكواد مدمج: Python, Bash, JS, TS, C++, Go, Rust, Java, PHP.
- مدير حزم ذكي AwlqyPkg مع إصلاح ذاتي (dpkg --configure -a، apt fix-broken).
- مثبّت مكتبات تلقائي عند ModuleNotFoundError.
- بناء/تفكيك APK على الجهاز: apktool، apksigner، zipalign، jadx، aapt2.
- وحدة أتمتة سوشيال ميديا عبر API/Webhooks.
- مولّد ASCII: banners، frames، progress bars.

## البناء عبر GitHub Actions

1. أنشئ مستودعاً باسم awlqy.
2. شغّل السكربتات الثلاثة بالترتيب:
   bash 01-bootstrap.sh
   bash 02-native.sh
   bash 03-github.sh
3. ارفع:
   git add .
   git commit -m "awlqy v1.0"
   git branch -M main
   git remote add origin https://github.com/alwaqyhsyn752-eng/awlqy.git
   git push -u origin main
4. GitHub → Actions → Artifacts → نزّل awlqy.apk.
5. لعمل Release: git tag v1.0.0 && git push origin v1.0.0

## الترخيص

MIT © 2025 حسين الخلاقي

</div>
AWLQY_README_EOF

# ═══ .gitignore ═══
cat > .gitignore <<'AWLQY_IGN_EOF'
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
AWLQY_IGN_EOF

# ═══ git init + commit ═══
if [ ! -d .git ]; then
    git init -q
    git branch -M main 2>/dev/null || true
fi

git config user.name  "$DEV_NAME"
git config user.email "${GITHUB_USER}@users.noreply.github.com"

git add .
if ! git diff --cached --quiet; then
    git commit -q -m "awlqy: bootstrap + native + kotlin core (Developer: حسين الخلاقي)"
    echo "✔ تم إنشاء commit أولي"
else
    echo "ℹ لا توجد تغييرات جديدة"
fi

echo ""
echo "════════════════════════════════════════════════"
echo " awlqy — اكتمل التوليد"
echo " المطوّر: $DEV_NAME"
echo " GitHub : $GITHUB_USER"
echo "════════════════════════════════════════════════"
echo " الخطوة التالية:"
echo "   git remote add origin https://github.com/$GITHUB_USER/$REPO_NAME.git"
echo "   git push -u origin main"
echo ""
echo " ثم: GitHub → Actions → Artifacts → awlqy.apk"
echo "════════════════════════════════════════════════"
echo "✔ [awlqy] 03-github: انتهى."
