# Publishing KeepIt to Google Play: step by step

Everything in the codebase is ready; the steps below are the things only **you** can do
(accounts, keys, uploads). Items marked ✅ are already done in the repo.

## 0. Already done in code ✅

- ✅ Unique package name `com.keshabstudios.keepit`, version from `pubspec.yaml` (`1.0.0+1`)
- ✅ Brand app icon: Android legacy + adaptive + themed (monochrome), iOS, web; notification icon
- ✅ Release signing wired to `android/key.properties` (falls back to debug for local runs)
- ✅ R8 minify + resource shrinking, with ProGuard rules for notifications
- ✅ Target SDK = latest (Flutter default), Android 13+ notification permission, no exact-alarm permission needed
- ✅ Profile screen: Google account, Cloud Sync, export data, delete local data, **in-app account deletion** (Play requirement)
- ✅ Privacy Policy, Terms, Account-deletion page (`docs/*.html` → GitHub Pages)
- ✅ Play Store assets: `store_assets/play_store_icon_512.png`, `store_assets/feature_graphic_1024x500.png`
- ✅ CI (`.github/workflows/flutter_ci.yml`): analyze + tests + debug APK on every PR

## 1. Publish the legal pages (2 min)

GitHub → repo **Settings → Pages → Build and deployment → Source: Deploy from a branch →
Branch `main` / folder `/docs` → Save**. After about a minute:

- https://keshab1997.github.io/keepit/privacy-policy.html
- https://keshab1997.github.io/keepit/terms.html
- https://keshab1997.github.io/keepit/delete-account.html

(These URLs are already used in the app: `lib/core/config/app_config.dart`.)

## 2. Firebase (for Cloud Sync)

Follow [FIREBASE_SETUP.md](FIREBASE_SETUP.md). You can also publish **without** Firebase: the
app works offline and the Cloud Sync card says "not set up yet". In that case, answer Data
Safety with the "no account" variant (see [PLAY_CONSOLE_ANSWERS.md](PLAY_CONSOLE_ANSWERS.md)).

## 3. Create an upload keystore (once, keep it forever!)

```bash
keytool -genkey -v -keystore ~/keepit-upload.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias upload
```

Create `flutter_app/android/key.properties` (git-ignored, **never commit**):

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=/home/you/keepit-upload.jks
```

> ⚠️ Back up `keepit-upload.jks` + passwords (Google Drive / password manager). With Play App
> Signing a lost upload key can be reset, but it takes days.

Add the upload key's SHA-1/SHA-256 to Firebase (FIREBASE_SETUP.md §2).

## 4. Build the release bundle

```bash
cd flutter_app
flutter clean && flutter pub get
flutter test
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
# → build/app/outputs/bundle/release/app-release.aab
```

Optional: `--dart-define=GOOGLE_SERVER_CLIENT_ID=...` if you needed it in Firebase setup.
Keep `build/symbols` for readable crash stack traces.

For every new release bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`). **The number after + must always increase.**

## 5. Play Console

1. Create a developer account at <https://play.google.com/console> (one-time US$25). An
   **individual** account needs identity verification.
2. **Create app** → name `KeepIt: Smart Bookmark & Mind` · App · Free · accept declarations.
3. **Set up your app** (Dashboard checklist). Copy answers from [PLAY_CONSOLE_ANSWERS.md](PLAY_CONSOLE_ANSWERS.md):
   - Privacy policy URL
   - App access (no login required; all features usable)
   - Ads: **No**
   - Content rating questionnaire
   - Target audience: **18+** (or 13+). Not for children
   - News app: No · Government app: No · Financial features: None · Health: No
   - **Data safety** form
   - **Account deletion** URL: `https://keshab1997.github.io/keepit/delete-account.html`
4. **Store listing:** text from [PLAY_STORE_LISTING.md](PLAY_STORE_LISTING.md), icon 512,
   feature graphic, and **2–8 phone screenshots** (1080×1920 or 1080×2400; take them from a
   real phone/emulator: Everything feed, item detail, Spaces, Serendipity, Profile).
5. **Play App Signing:** accept the default (Google manages the app signing key). Then copy
   the **App signing key SHA-1/SHA-256** into Firebase and re-download `google-services.json`, then
   rebuild. *Otherwise Google Sign-In fails for users who install from Play.*

## 6. Testing track (required for new personal accounts)

New **personal** developer accounts must run a **closed test with at least 12 testers for 14
continuous days** before production access.

1. Test and release → **Closed testing** → create track → upload `app-release.aab`.
2. Testers: add a Google Group or email list (at least 12 people). Share the opt-in link.
3. Keep testers active for 14 days, then **Apply for production access**.

(Tip: first upload to **Internal testing** to check the build installs and sign-in works.)

## 7. Production release

Production → Create release → upload the .aab → release notes → staged rollout (e.g. 20% →
100%) → Send for review (usually 1–7 days for new apps).

## Release checklist (every version)

- [ ] `pubspec.yaml` version bumped
- [ ] `flutter analyze` clean, `flutter test` green
- [ ] Tested a **release** build on a real phone: share-to-save, notifications, sign-in, sync, delete account
- [ ] `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols`
- [ ] Release notes written
- [ ] Data safety still accurate (new SDKs? new data?)
