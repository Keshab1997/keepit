# KeepIt — Google Play Store Release Guide

**App:** KeepIt — AI-Powered Second Brain & Smart Visual Bookmarks  
**Package name:** `com.keshabstudios.keepit`  
**Current version:** `1.0.1+4` (`versionName 1.0.1`, `versionCode 4`)  
**Privacy policy:** https://keshab1997.github.io/keepit/privacy-policy.html  
**Account/data deletion:** https://keshab1997.github.io/keepit/delete-account.html  
**Last reviewed:** 25 September 2026

> This guide is based on the current repository code, manifest, privacy policy and Firebase/AdMob configuration. Play Console answers must always describe the exact binary being uploaded. If Firebase, AdMob, permissions or features change, review the Data Safety answers again.

## 1. Important corrections before submitting

The supplied questionnaire values should **not** be copied blindly:

- **Encrypted in transit:** answer **Yes**. Firebase, Google Sign-In, AdMob and HTTP link-preview requests use HTTPS/TLS in the current release configuration. Do not answer No unless the release actually sends user data over unencrypted HTTP.
- **Account creation:** select **OAuth only** — Google Sign-In. Do not select username/password or generic “other”.
- **Location:** the current Android manifest has no location permission and the privacy policy says KeepIt does not access precise location. Do **not** declare approximate location unless the uploaded binary really collects it through an SDK or feature.
- **Personal data:** with Firebase Cloud Sync and AdMob enabled, answer **Yes**. If you deliberately publish an offline-only build with those services removed, complete a separate Data Safety declaration for that binary.
- **Name, email, user ID and profile photo:** Google Sign-In/Firebase handles these account fields. Declare the fields actually retained or processed by the release; the app’s privacy policy currently describes all four.
- **AdMob:** because the manifest contains a live AdMob application ID and the app uses `google_mobile_ads`, declare ads and the data shared with Google according to the AdMob SDK behavior and Google Play’s current form.

## 2. Pre-release engineering checklist

### Repository and secrets

- [ ] Never ship `flutter_app/.env` with production secrets in a public repository.
- [ ] Restrict or rotate any exposed ImgBB/API credentials.
- [ ] Keep `android/key.properties`, upload keystore, passwords and signing files outside Git.
- [ ] Confirm Firebase production project and Firestore rules are correct.
- [ ] Confirm `google-services.json` belongs to package `com.keshabstudios.keepit`.
- [ ] Confirm AdMob production app ID and ad unit IDs; remove all test ad IDs.
- [ ] Confirm the privacy policy and delete-account pages are publicly reachable without login.

### App quality

- [ ] Test first launch, onboarding, save link, save image, search, tags, Spaces, reminders, export and local deletion.
- [ ] Test Google Sign-In, sign-out, sync, conflict handling and account deletion on a clean device.
- [ ] Verify deleting an account removes Firebase Auth and associated Firestore data.
- [ ] Test Android 13+ notification permission and notification actions.
- [ ] Test offline mode and recovery after reconnecting.
- [ ] Test deep links/share target from Chrome, YouTube, Instagram and a browser.
- [ ] Test light/dark mode and Android 12+ native splash.
- [ ] Run `flutter analyze` and all tests.
- [ ] Test the minified release build, not only debug mode.

## 3. Create the signed Android App Bundle

From the repository:

```bash
cd flutter_app
flutter clean
flutter pub get
flutter analyze
flutter test
```

Create an upload keystore once, if you do not already have one:

```bash
keytool -genkeypair -v \
  -keystore ~/keepit-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias keepit-upload
```

Create `flutter_app/android/key.properties` locally (never commit it):

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=keepit-upload
storeFile=/absolute/path/to/keepit-upload-key.jks
```

Build the Play Store bundle:

```bash
flutter build appbundle --release
```

Expected output:

```text
flutter_app/build/app/outputs/bundle/release/app-release.aab
```

Before uploading, inspect the version and confirm the signed release is using the upload key. Each future upload needs a higher `versionCode`; update `version:` in `pubspec.yaml`, for example `1.0.2+5`.

> The Gradle file intentionally falls back to debug signing when `key.properties` is missing. A debug-signed bundle will be rejected by Play Console. Never use that fallback for a release upload.

## 4. Play Console setup

1. Open [Google Play Console](https://play.google.com/console/).
2. Create the app with:
   - Default language: English
   - App name: **KeepIt: Save Ideas & Links**
   - App: **App**
   - Free or paid: choose the intended business model
   - Contains ads: **Yes**
3. Complete **App content**:
   - Privacy policy URL
   - Ads declaration: Yes
   - App access: all functionality is available without special credentials; Google Sign-In is optional
   - Target audience and content
   - Content rating questionnaire
   - Data Safety using `PLAY_STORE_DATA_SAFETY.csv` as a worksheet
4. Complete the Store listing:
   - App name: `KeepIt — Smart Visual Bookmarks`
   - Short description: `Save ideas, links and inspiration. Find them again when they matter.`
   - Use the longer description below.
   - Upload a 512×512 app icon, feature graphic and phone screenshots.
5. Create a testing track, preferably **Internal testing**, and upload the `.aab`.
6. Add tester email addresses, install from the opt-in link and test the exact Play build.
7. Resolve pre-launch report warnings, policy declarations and crashes.
8. Promote to Closed testing, complete any required testing period, then apply for Production.

## 5. Suggested store listing

### Full description

KeepIt is your private second brain for ideas, articles, reels, videos, quotes and inspiration.

Save anything worth remembering from your phone’s share menu, then find it again in a beautiful visual feed. KeepIt works offline first, so saving is fast even when your connection is not.

**Highlights**

- Save links, notes, images and inspiration in one place
- Share directly from your favourite apps and browser
- Organise everything with tags and custom Spaces
- Search titles, notes, domains and saved content
- Rediscover forgotten ideas with smart Serendipity reminders
- Mark items as watched or read to keep your mind feed useful
- Optional Google sign-in for backup and multi-device Cloud Sync
- Export your data and delete your account whenever you choose
- Privacy-first local storage with optional cloud backup

KeepIt is built for curious people who collect ideas and want to make them useful later.

### Release notes — first release

Welcome to KeepIt. Save links, notes and visual inspiration, organise them with tags and Spaces, and rediscover them with smart reminders. This release includes optional Google Cloud Sync, data export and account deletion controls.

## 6. Data Safety worksheet

Import `docs/PLAY_STORE_DATA_SAFETY.csv` with Play Console → App content → Data safety → **Import from CSV**. It is built on Google's official sample (same header, question IDs and row order). Upload that file directly. Opening it in Excel and saving again can change the header or `TRUE`/`FALSE` and Play Console will reject line 1.

### Recommended high-level answers for the Firebase + AdMob build

- Collect or share required data: **Yes**
- All data encrypted in transit: **Yes**
- Account creation: **OAuth — Google Sign-In**
- Account deletion: **Yes**, in-app and by web URL
- Data deletion URL: `https://keshab1997.github.io/keepit/delete-account.html`
- Children: KeepIt is not directed to children under 13; do not opt into Designed for Families
- Independent MASA review: **No**, unless a valid review has actually been completed
- UPI badge: **No/not applicable**

### Data categories to verify

Based on the repository and privacy policy, the likely categories are:

- Personal info: name, email address, personal identifiers, Google profile photo after sign-in
- App activity: other user-generated content (saved links, notes, tags) when Cloud Sync is on; page views and taps from AdMob
- Device or other IDs: advertising ID and app set ID, collected and shared by AdMob
- App info and performance: diagnostics from the Mobile Ads SDK. Crash logs stay off unless Crashlytics is added.
- Location: approximate location only, because AdMob uses IP address to estimate general location. Precise location stays off; the app requests no location permission.
- Contacts, calendar, microphone, camera, health, financial and message data: **not collected**

## 7. App access and review notes

Paste this in the Play Console reviewer instructions if needed:

> All core functionality is available without an account. To test optional Cloud Sync, use the normal Google Sign-In flow. No special credentials or paid access are required. The app saves content locally first. Test account deletion from Profile → Delete account. Privacy policy: https://keshab1997.github.io/keepit/privacy-policy.html. Account deletion request page: https://keshab1997.github.io/keepit/delete-account.html.

## 8. Final sign-off

- [ ] Bundle package is `com.keshabstudios.keepit`.
- [ ] Version code is higher than the previous Play upload.
- [ ] Release is signed with the upload keystore.
- [ ] No debug/test AdMob IDs remain.
- [ ] Data Safety matches the binary, privacy policy and SDK behavior.
- [ ] Account deletion works and the public URL works.
- [ ] Store listing screenshots show the current UI.
- [ ] Internal/closed test completed successfully.
- [ ] No secrets, signing keys or private configuration are included in the AAB source repository.
