# Secrets & build-time configuration

Everything the release build needs now lives in **GitHub Actions secrets**,
not in git. This page is the one-time setup, plus the Firebase/Play hardening
that goes with it.

> ⚠️ Do not paste real values into any file in this repository. It is public.

---

## TL;DR

```bash
cd keepit

# 1. AdMob → repository VARIABLES (not secrets — see the note below)
gh variable set ADMOB_APP_ID                 # ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY
gh variable set ADMOB_BANNER_ID              # ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ
gh variable set ADMOB_INTERSTITIAL_ID
gh variable set ADMOB_REWARDED_ID

# 2. Firebase client config → repository SECRET
#    Linux:
base64 -w0 flutter_app/android/app/google-services.json | gh secret set GOOGLE_SERVICES_JSON_BASE64
#    macOS:
base64 -i flutter_app/android/app/google-services.json  | gh secret set GOOGLE_SERVICES_JSON_BASE64
```

Then run **Actions → Publish Android Release → Run workflow** and check the log
for `OK: android/app/google-services.json is valid JSON`.

---

## 1. Variables vs secrets — why the split

> ⚠️ **GitHub Actions does not expose the `secrets` context inside a reusable
> workflow's `with:` inputs.** Writing
> `dart-defines: ADMOB_APP_ID=${{ secrets.ADMOB_APP_ID }}` makes the workflow
> fail instantly with **zero jobs** — no error message beyond a red run. This
> bit us once; don't reintroduce it.

AdMob IDs travel through `dart-defines` and `build-env`, which are `with:`
inputs, so they must be **Variables**. `google-services.json` is read from
inside the shared builder (`inputs.x || secrets.X`, v1.6.0+), so it can be a
**Secret**.

| Name | Kind | Where to copy it from |
|---|---|---|
| `ADMOB_APP_ID` | Variable | AdMob → Apps → `com.keshabstudios.keepit` → App ID |
| `ADMOB_BANNER_ID` | Variable | AdMob → ad units → Banner |
| `ADMOB_INTERSTITIAL_ID` | Variable | AdMob → ad units → Interstitial |
| `ADMOB_REWARDED_ID` | Variable | AdMob → ad units → Rewarded |
| `GOOGLE_SERVICES_JSON_BASE64` | Secret | `base64` of your local `google-services.json` |

This is fine security-wise: AdMob IDs are public identifiers — they are
compiled into every APK you publish anyway. The abuse risk we were fixing was
them sitting in the **source repo**, not in the binary.

Already-present secrets (unchanged): `ANDROID_KEYSTORE_BASE64`,
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.

> 💡 Prefer everything under one roof? You can keep the AdMob IDs as secrets
> too — but then you have to inline them in the workflow or feed them through a
> `secrets:`-backed input in `Keshab1997/flutter-builder`, because `with:` can
> never read them.

### Add them from the UI

Repo → **Settings → Secrets and variables → Actions**
→ **Variables** tab (AdMob) / **Secrets** tab (Google services JSON).

---

## 2. Verify it worked

Run **Actions → Publish Android Release → Run workflow** and look for:

| Log line | Meaning |
|---|---|
| `OK: android/app/google-services.json is valid JSON` | Firebase config injected ✅ |
| `Dart defines (values hidden): ADMOB_ENABLED, ADMOB_APP_ID, …` | AdMob defines compiled in ✅ |
| `No release placeholders found.` | No test IDs / `com.example` left in the source ✅ |

If a value is missing you get `::notice::build-env: ADMOB_APP_ID is empty and
was skipped` — the build still succeeds, but ships **ad-free**. That is the
intended fail-safe, not a bug.

> 🚨 If a run finishes **red with zero jobs**, a `${{ secrets.… }}` slipped into
> a `with:` input. See the warning in section 1.

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
| `.github/workflows/*.yml` | Builder bumped to `v1.6.0`; AdMob IDs via `dart-defines` + `build-env`, `google-services.json` via the `GOOGLE_SERVICES_JSON_BASE64` secret |
| `Keshab1997/flutter-builder` | v1.6.0 reads `google-services.json` / `GoogleService-Info.plist` from a secret or a `with:` input |
