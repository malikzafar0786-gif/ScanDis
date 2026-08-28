# Doc Scanner AI — Setup Guide

## 1. Project Setup
```bash
flutter create doc_scanner_ai
cd doc_scanner_ai
# replace pubspec.yaml and lib/ with the files provided
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs   # generates scanned_document.g.dart
```

## 2. Android Setup
`android/app/src/main/AndroidManifest.xml` — add inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```
`android/app/build.gradle`: set `minSdkVersion 21` or higher (ML Kit requirement).

## 3. iOS Setup
`ios/Runner/Info.plist` — add:
```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to scan your documents.</string>
```

## 4. Gemini API Key
Get a free key at https://aistudio.google.com/app/apikey, then run:
```bash
flutter run --dart-define=GEMINI_API_KEY=your_key_here
```
Or paste it directly in `lib/services/gemini_service.dart` for local testing only
(never commit a real key to a public repo).

## 5. Build APK via GitHub Actions (no local machine needed)
Since you work from mobile without a dev PC, use this CI workflow
(`.github/workflows/build.yml`):
```yaml
name: Build APK
on: [push, workflow_dispatch]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: flutter pub run build_runner build --delete-conflicting-outputs
      - run: flutter build apk --release --dart-define=GEMINI_API_KEY=${{ secrets.GEMINI_API_KEY }}
      - uses: actions/upload-artifact@v4
        with:
          name: app-release
          path: build/app/outputs/flutter-apk/app-release.apk
```
Add `GEMINI_API_KEY` as a GitHub Actions secret. This mirrors the same
CI/CD approach used for WormX.

## Project Structure
```
lib/
  main.dart
  models/scanned_document.dart
  providers/document_provider.dart
  providers/theme_provider.dart
  services/storage_service.dart
  services/ocr_service.dart
  services/image_filter_service.dart
  services/pdf_service.dart
  services/gemini_service.dart
  screens/home_screen.dart
  screens/scanner_screen.dart
  screens/document_detail_screen.dart
```

## Notes
- Edge detection & cropping is handled natively by `flutter_doc_scanner`
  (Google ML Kit Document Scanner on Android, VisionKit on iOS) — no manual
  corner-dragging UI needed for MVP.
- OCR runs fully on-device (free, offline, private) via `google_mlkit_text_recognition`.
- Gemini calls only happen when the user taps Summarize/Translate/Chat —
  keeps API cost low and gives the user control.
- For production: proxy Gemini calls through a small backend (Firebase
  Cloud Function) instead of calling the API directly from the app, so the
  key never ships inside the APK.
