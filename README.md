# ScanDis — AI Document Scanner (Flutter)

## ⚠️ یہ ایک مکمل، self-contained پیکج ہے

اس repo میں صرف یہ چیزیں رکھی گئی ہیں:
```
lib/                         → پورا ایپ کوڈ
assets/icon/app_icon.png     → آپ کا لوگو
pubspec.yaml                 → dependencies
.github/workflows/build.yml  → build کرنے والا خودکار script
.gitignore
```

**`android/` اور `ios/` فولڈرز جان بوجھ کر شامل نہیں ہیں۔**
GitHub Actions ہر بار build کرتے وقت انہیں خود تازہ ترین Flutter کے
مطابق بناتا ہے (`flutter create` کے ذریعے) اور خود ہی camera
permissions اور app icon شامل کر دیتا ہے۔

نتیجہ: **آپ کو کبھی بھی مینوئل طور پر کوئی فائل ڈھونڈ کر بدلنی نہیں
پڑے گی۔** جب بھی کوڈ میں تبدیلی چاہیے ہو، بس `lib/` کی فائلیں بدلیں
اور push کر دیں۔

---

## پہلی دفعہ سیٹ اپ (صرف ایک بار)

1. اپنے GitHub repo (`ScanDis`) کی **تمام پرانی فائلیں ڈیلیٹ** کر دیں۔
2. اس zip کا پورا مواد اسی repo میں upload کر دیں (فولڈر structure ویسا
   ہی رہنے دیں جیسا zip میں ہے)۔
3. Repo کی **Settings → Secrets and variables → Actions** میں جا کر
   نیا secret بنائیں:
   - Name: `GEMINI_API_KEY`
   - Value: اپنی Gemini API key (https://aistudio.google.com/app/apikey)
4. Commit/push کریں۔

## Build کیسے چلے گی؟

- ہر بار جب آپ `main` branch پر push کریں گے، build خودکار چلے گی۔
- یا Repo کے **Actions** ٹیب میں جا کر "Build APK" ورک فلو کو
  **Run workflow** بٹن سے manually بھی چلا سکتے ہیں۔
- Build مکمل ہونے پر **Actions → (اس run) → Artifacts** سیکشن سے
  `ScanDis-release-apk` ڈاؤن لوڈ کر لیں۔

## آئندہ کوڈ میں تبدیلی کیسے کریں؟

- صرف `lib/` کے اندر متعلقہ `.dart` فائل edit کریں اور push کر دیں۔
- نیا logo لگانا ہو تو صرف `assets/icon/app_icon.png` کو نئی تصویر سے
  overwrite کریں۔
- `android/` یا `ios/` کے بارے میں کبھی سوچنے کی ضرورت نہیں — وہ ہر بار
  خود بن جاتے ہیں۔

## اگر Build پھر بھی fail ہو

Actions ٹیب میں فیل شدہ run کھولیں → "Build APK (Release)" step پر
کلک کریں → اوپر سکرول کر کے وہ لائن ڈھونڈیں جو
`FAILURE: Build failed with an exception` یا کسی مخصوص فائل کا نام/
لائن نمبر دکھائے — اسی حصے کا اسکرین شاٹ بھیجیں۔
