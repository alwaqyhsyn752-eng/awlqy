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
