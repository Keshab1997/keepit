# CI & release workflows

KeepIt uses the shared reusable workflows from
[`Keshab1997/flutter-builder`](https://github.com/Keshab1997/flutter-builder),
pinned to the tested tag **`v1.4.0`**. The Flutter app lives in
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

## Two gates that have bitten this repo

Both were fixed on 2026-09-25 after 15 consecutive red runs. Knowing why they
fail saves a lot of guessing.

### 1. `Check Dart formatting` — format against the *resolved* language version

`ci.yml` runs `dart format --output=none --set-exit-if-changed .` **after**
`flutter pub get`. pub derives the package language version from the lower bound
in `pubspec.yaml`:

```yaml
environment:
  sdk: ">=3.0.0 <4.0.0"   # -> language version 3.0
```

Dart 3.7 switched `dart format` to the new *tall* style, but only applies it to
packages whose language version is **3.7 or higher**. At 3.0 the formatter still
wants the old *short* style.

The trap: running `dart format` **without** a `.dart_tool/package_config.json`
makes the formatter fall back to the SDK default, i.e. tall style, so it reports
`0 changed` on a machine that never ran `pub get` — while CI disagrees and fails.
Always reproduce the gate exactly:

```bash
cd flutter_app
flutter pub get                                   # writes .dart_tool/package_config.json
dart format --output=none --set-exit-if-changed . # must print "0 changed"
dart format .                                     # apply if it did not
```

The other way out is raising the SDK bound to `>=3.7.0` and reformatting to tall
style. That touches ~26 files and every dependency constraint, so this repo
keeps 3.0 and formats to short style instead.

### 2. `Analyze source code` — `--fatal-infos` makes warnings fatal

The step runs `flutter analyze --fatal-infos`, so a single *info* fails the
build. The `.env` asset warning described in
[docs/IMGBB_SETUP.md](IMGBB_SETUP.md) was enough to keep every run red, and
because the format gate failed first, the analyze step was skipped — the real
cause stayed hidden for 14 runs.

Note that `flutter_app/vendor/lucide_icons` is excluded from the analyzer in
`analysis_options.yaml`, so it never contributes issues.

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
