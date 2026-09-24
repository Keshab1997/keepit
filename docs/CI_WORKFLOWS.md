# CI & release workflows

KeepIt uses the shared reusable workflows from
[`Keshab1997/flutter-builder`](https://github.com/Keshab1997/flutter-builder),
pinned to the tested tag **`v1.3.0`**. The Flutter app lives in
`flutter_app/`, so every caller sets `working-directory: flutter_app`.

Nothing is built or configured locally — GitHub Actions sets up the Flutter
and Android SDKs on demand.

## The four workflows

| File | Runs when | What it does |
|---|---|---|
| `ci.yml` | push / PR to `main`, or manual | `dart format` check → `flutter analyze --fatal-infos` → `flutter test` + coverage %, plus the same validation on the `beta` Flutter channel |
| `manual-build.yml` | Actions → **Manual Android Build** → Run workflow | release **APK** or **AAB**, uploaded as an artifact |
| `publish-release.yml` | Actions → **Publish Android Release** → Run workflow | signed APK + AAB, `v<version>` tag, English release notes, GitHub Release, `SHA256SUMS.txt` |
| `release.yml` | `git push` of a `v*` tag | signed **AAB** artifact only (no GitHub Release) |

### What changed from the old `flutter_ci.yml`

The previous inline CI ran format/analyze/test and then built a **debug APK on
every push**. That APK build is gone from `ci.yml` — the shared workflow
deliberately skips builds for ordinary code changes, and `flutter test`
already compiles the app. To get an installable APK use **Manual Android
Build** (it produces a *release* APK, which is what you actually want on a
phone). If you prefer an APK on every push, set `build-apk: true` in `ci.yml`.

## Required secrets

Only the AAB / release workflows need signing. Add them in
**Settings → Secrets and variables → Actions → Secrets**:

```text
ANDROID_KEYSTORE_BASE64   base64 -w0 upload-keystore.jks
KEYSTORE_PASSWORD
KEY_ALIAS
KEY_PASSWORD
```

`android/app/build.gradle.kts` writes these into `android/key.properties`
whenever the secret is present, and falls back to the debug key otherwise —
so `manual-build.yml` with `format: apk` works even before the secrets exist.
AAB and GitHub Release publishing **fail fast** if a secret is missing.
Signing details: <https://github.com/Keshab1997/flutter-builder/blob/main/docs/ANDROID_SIGNING.md>

## Versioning

`publish-release.yml` reads `flutter_app/pubspec.yaml`:

```yaml
version: 1.0.1+2   # tag v1.0.1 · versionName 1.0.1 · versionCode 2
```

Bump the version in a PR *before* running the release workflow — it never
bumps for you, because the run builds the exact commit that triggered it.
Play Store uploads always need a higher `versionCode`. A tag that already
exists makes the workflow fail on purpose.
