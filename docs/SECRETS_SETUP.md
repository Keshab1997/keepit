# Secrets & build-time configuration

Everything the release build needs now lives in **GitHub Actions secrets**,
not in git. This page is the one-time setup, plus the Firebase/Play hardening
that goes with it.

> ⚠️ Do not paste real values into any file in this repository. It is public.

---

## TL;DR

```bash
cd keepit

# 1. AdMob (4 values, from the AdMob console → Apps → keepit → Ad units)
gh secret set ADMOB_APP_ID                 # ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY
gh secret set ADMOB_BANNER_ID              # ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ
gh secret set ADMOB_INTERSTITIAL_ID
gh secret set ADMOB_REWARDED_ID

# 2. Firebase client config (written into the build by flutter-builder v1.5.1+)
base64 -w0 flutter_app/android/app/google-services.json \
  | gh secret set GOOGLE_SERVICES_JSON_BASE64
```

Then run **Actions → Publish Android Release → Run workflow** and check the log
for `OK: android/app/google-services.json is valid JSON`.

---

## 1. The secrets

| Secret | Where to copy it from | Used by |
|---|---|---|
| `ADMOB_APP_ID` | AdMob → Apps → `com.keshabstudios.keepit` → App ID | Dart **and** `AndroidManifest.xml` |
| `ADMOB_BANNER_ID` | AdMob → ad units → Banner | Dart |
| `ADMOB_INTERSTITIAL_ID` | AdMob → ad units → Interstitial | Dart |
| `ADMOB_REWARDED_ID` | AdMob → ad units → Rewarded | Dart |
| `GOOGLE_SERVICES_JSON_BASE64` | `base64` of your local `google-services.json` | Gradle (Firebase plugin) |

Already-present secrets (unchanged): `ANDROID_KEYSTORE_BASE64`,
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.

### Add them from the terminal

```bash
gh secret set ADMOB_APP_ID                 # prompts for the value, hidden input
gh secret set ADMOB_BANNER_ID
gh secret set ADMOB_INTERSTITIAL_ID
gh secret set ADMOB_REWARDED_ID

# Linux:
base64 -w0 flutter_app/android/app/google-services.json | gh secret set GOOGLE_SERVICES_JSON_BASE64
# macOS:
base64 -i flutter_app/android/app/google-services.json  | gh secret set GOOGLE_SERVICES_JSON_BASE64
```

### Or from the UI

Repo → **Settings → Secrets and variables → Actions → New repository secret**.

> 💡 AdMob IDs are public identifiers, not credentials. If you would rather see
> them in the build log when debugging, put them in **Variables** instead and
> change `${{ secrets.ADMOB_... }}` to `${{ vars.ADMOB_... }}` in the
> workflows. Keep `GOOGLE_SERVICES_JSON_BASE64` a secret either way.

---

## 2. Verify it worked

Run **Actions → Publish Android Release → Run workflow** and look for:

| Log line | Meaning |
|---|---|
| `OK: android/app/google-services.json is valid JSON` | Firebase config injected ✅ |
| `Dart defines (values hidden): ADMOB_ENABLED, ADMOB_APP_ID, …` | AdMob defines compiled in ✅ |
| `No release placeholders found.` | No test IDs / `com.example` left in the source ✅ |

If a secret is missing you get `::notice::build-env: ADMOB_APP_ID is empty and
was skipped` — the build still succeeds, but ships **ad-free**. That is the
intended fail-safe, not a bug.

### Confirm ads actually ship

```bash
# In the release AAB, the manifest must carry the real app ID:
unzip -p app-release.aab base/manifest/AndroidManifest.xml \
  | strings | grep -o 'ca-app-pub-[0-9]*~[0-9]*'
```

---

## 3. Firebase hardening (do this — it is the real risk)

`google-services.json` is not a secret by itself, but the Firebase **API key**
inside it is currently unrestricted, and the project has **no App Check**. That
means anyone can point their own script at your Firestore and generate billable
load. Your users' data is safe — `firestore.rules` locks each user to
`users/{uid}` — but your quota is not.

### 3a. Restrict the API key (5 minutes)

1. https://console.cloud.google.com/apis/credentials (project `keepit-deda6`)
2. Open the key starting `AIzaSy…` (**Browser key** / the one in
   `google-services.json`).
3. Under **Application restrictions** choose **Android apps** → Add an item:
   - Package name: `com.keshabstudios.keepit`
   - SHA-1: paste **every** fingerprint you registered in Firebase (debug,
     upload, and Google Play's app signing fingerprints).
4. Save. Repeat for the Chrome extension's key with **HTTP referrers** →
   `https://<your-extension-id>.chromiumapp.org/*`.

### 3b. Turn on App Check (10 minutes)

1. Firebase Console → **App Check** → register the Android app.
2. Use **Play Integrity** as the attestation provider.
3. Once the release build is live, click **Enforce** for Firestore and
   Authentication.

With enforcement on, requests from anything that is not your genuine
Play-signed app are rejected — which closes the abuse window completely.

### 3c. Budget alert

Google Cloud Console → **Billing → Budgets & alerts** → create a budget
(for example ₹500 / $5) with alerts at 50% and 90%. Firebase abuse then shows up
as an email, not a surprise.

---

## 4. Play Console

You already have Play App Signing and automatic protection on, so the app
listing itself is safe. Two quick checks:

- **Users and permissions** — remove anyone you do not recognise.
- **2-Step Verification** on the Google account that owns the Play Console.

---

## 5. Cleanup: the old values are still in git history

Removing `google-services.json` and the AdMob IDs from `main` does **not**
erase them from the previous 104 commits. Anyone cloning the repo can still:

```bash
git log -p | grep -o 'ca-app-pub-[0-9]*~[0-9]*'
```

**Recommended:** do items 3a and 3b. Once the API key is restricted to your
package + SHA-1 and App Check is enforced, a leaked client config is useless to
anyone else — no history rewrite needed.

**Optional, if you want them gone from history** (⚠️ rewrites history — do it
on a quiet day, and tell anyone with a clone):

```bash
pip install git-filter-repo          # or: brew install git-filter-repo
git filter-repo --invert-paths --path flutter_app/android/app/google-services.json
git push --force --all
```

Afterwards every collaborator must re-clone, and any open PR must be rebased.

---

## 6. Day-to-day

| Situation | What happens |
|---|---|
| `flutter run` locally | Ad-free (no defines). Fine for feature work. |
| CI on a PR | Analyze + test only; no Firebase config needed. |
| PR from a **fork** | GitHub does not give forks your secrets → ad-free build. Expected. |
| Manual Android Build | Full defines — use this to test a release candidate. |
| Publish Android Release | Full defines + `ADMOB_ENABLED=true` → ads live. |

### Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `AdMob: ADMOB_ENABLED is set but the unit IDs were not supplied` | Secret missing or misspelled. App stays ad-free. |
| `Placeholder check failed … ca-app-pub-3940256099942544` | A Google test ID got into `lib/`. Remove it — release builds must not use test units. |
| Google Sign-In fails from a Play install | The **app signing** SHA-1 (not the upload key) is missing from Firebase. With quantum-ready signing there are three fingerprints to register. |
| `google-services.json` missing after a fresh clone | Correct. Copy your own file to `flutter_app/android/app/`, or let CI inject it. |

---

## 7. What changed

| File | Change |
|---|---|
| `lib/core/ads/ad_config.dart` | IDs read from `String.fromEnvironment`; `adsEnabled` defaults to `false` |
| `lib/core/ads/ad_service.dart` | Skips AdMob init when unit IDs are missing |
| `android/app/build.gradle.kts` | `manifestPlaceholders["admobAppId"]` from `ADMOB_APP_ID` |
| `android/app/src/main/AndroidManifest.xml` | `android:value="${admobAppId}"` |
| `android/app/google-services.json` | **Untracked** (was committed); now git-ignored |
| `.gitignore` (new, repo root) | Signing material, Firebase config, editor junk |
| `.github/workflows/*.yml` | Builder bumped to `v1.5.1`; `dart-defines` + `build-env` + `google-services-json-base64` |
| `Keshab1997/flutter-builder` | v1.5.1 adds the `google-services-json-base64` / `-plist-base64` inputs |
