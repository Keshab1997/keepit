# Firebase setup (Cloud Sync + Google Sign-In)

Until you finish this guide, KeepIt runs **fully offline**: Profile → Cloud Sync shows
"Cloud sync not set up yet", and everything else works. No code changes are needed; just
add the config files below and rebuild.

> Time needed: about 15 minutes. Cost: free (Firebase Spark plan is more than enough).

---

## 1. Create the Firebase project

1. Go to <https://console.firebase.google.com> → **Add project** → name it `keepit`.
2. Google Analytics: **not needed** (you can turn it off; the privacy policy says "no analytics").

## 2. Add the Android app

1. Project overview → **Add app → Android**.
2. **Android package name:** `com.keshabstudios.keepit` (must match `applicationId` in
   `flutter_app/android/app/build.gradle.kts`).
3. **App nickname:** KeepIt Android.
4. **Debug signing certificate SHA-1:** required for Google Sign-In. Get it with:

   ```bash
   cd flutter_app/android
   ./gradlew signingReport          # look for Variant: debug → SHA1
   # or
   keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android
   ```

5. Download **`google-services.json`** and put it at:

   ```
   flutter_app/android/app/google-services.json
   ```

   It's git-ignored because this repo is public. The Gradle build applies the Google
   Services plugin automatically when this file exists.

### Add ALL SHA fingerprints (important!)
Google Sign-In fails with *"Developer error / clientConfigurationError"* if the SHA of the
build you're running isn't registered. In **Project settings → Your apps → Android → Add fingerprint**, add:

| Build | Where to get SHA-1 **and** SHA-256 |
|---|---|
| Debug (your PC) | `./gradlew signingReport` |
| Release / upload key | `keytool -list -v -keystore ~/keepit-upload.jks -alias upload` |
| **Play App Signing** (the build users install from Play) | Play Console → your app → **Test and release → App integrity → App signing key certificate** |

After adding a fingerprint, **download google-services.json again** and replace the old one.

## 3. Enable Google Sign-In

1. Firebase Console → **Authentication → Get started → Sign-in method → Google → Enable**.
2. Choose a **support email** → Save.
3. This creates a **Web OAuth client** automatically. When `google-services.json` contains it
   (`"client_type": 3`), the app needs nothing else.
   - If sign-in still fails, copy the *Web client ID* (Authentication → Google → Web SDK
     configuration) and build with:
     ```bash
     flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=1234-abc.apps.googleusercontent.com
     ```

## 4. Create Firestore

1. **Firestore Database → Create database** → **Production mode**.
2. Location: `asia-south1 (Mumbai)`. This is closest to India and **can't be changed later**.
3. **Rules:** replace everything with the contents of [`flutter_app/firestore.rules`](../flutter_app/firestore.rules) → **Publish**.
   (Or with the CLI: `npm i -g firebase-tools && cd flutter_app && firebase login && firebase use --add && firebase deploy --only firestore:rules`)
4. Indexes: none needed (single-field queries only).

## 5. (Optional) iOS

1. Add an **iOS app** with bundle ID `com.keshabstudios.keepit` → download `GoogleService-Info.plist`
   → drag it into `ios/Runner` in Xcode (git-ignored).
2. In `ios/Runner/Info.plist`, replace `com.googleusercontent.apps.REPLACE_WITH_REVERSED_CLIENT_ID`
   with the `REVERSED_CLIENT_ID` value from the plist.
3. `cd ios && pod install`.

## 6. Test

```bash
cd flutter_app
flutter run
```

Profile → **Continue with Google** → pick an account → "Signed in · syncing…" → "Up to date".
Check Firestore: `users/<uid>/items/*` should contain your items.

### Troubleshooting

| Symptom | Fix |
|---|---|
| "Cloud sync not set up yet" | `google-services.json` missing / wrong folder → rebuild (`flutter clean` if needed). |
| Sign-in closes immediately, "cancelled" or "Developer error" | SHA-1/SHA-256 of this build not added → add it, re-download json. |
| Works in debug, fails from Play Store | Add the **Play App Signing** SHA fingerprints (section 2). |
| `PERMISSION_DENIED` in sync | Firestore rules not published, or you're testing with another user's uid. |
| Delete account says "sign in again" | Normal security check; the app re-authenticates and retries automatically. |

## How sync works (for developers)

- Local-first: Hive is the source of truth; the UI never waits for the network.
- Layout: `users/{uid}/items/{itemId}` = item fields + `updatedAtMs`, `deleted`, `serverUpdatedAt`.
- Pull: `serverUpdatedAt > lastCursor` (incremental). Push: dirty items (`isSynced == false`) + local tombstones.
- Conflicts: **last write wins** by `updatedAt`. Deletes are tombstones so other devices learn about them.
- Auto sync: 4 s after any local change and on sign-in. Foreground remote polling is capped at once per 5 minutes to avoid billed empty reads; Profile → Sync now always checks immediately. Can be turned off in Profile.
- Cost control: normal sync writes only changed item documents; it does not write a separate per-sync user metadata document.
- Demo cards (ids 1-4) are never uploaded.
- Code: `lib/core/cloud/*`, `lib/presentation/controllers/cloud_sync_controller.dart`, tests in `test/sync_engine_test.dart`.
