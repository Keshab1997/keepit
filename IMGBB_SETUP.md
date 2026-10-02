# ImgBB image uploads

KeepIt can upload images selected from the gallery or shared from another app to
ImgBB. Firestore stores only the returned public URL, so image bytes are never
written to Firestore and do not increase Firestore document size or read/write
cost.

## Configure the key

1. Create an ImgBB API key at <https://api.imgbb.com/>.
2. Do **not** commit the key to the repository.
3. Pass it at run/build time:

```bash
cd flutter_app
flutter run --dart-define=IMGBB_API_KEY=YOUR_IMGBB_KEY

# Release build example
flutter build apk --release --dart-define=IMGBB_API_KEY=YOUR_IMGBB_KEY
```

The app shows a helpful error if the key is missing. The key is still
recoverable from a mobile binary, so use an ImgBB key dedicated to KeepIt and
monitor/rotate it if necessary. ImgBB URLs are public; do not use this mode for
private images.

## The committed `.env` placeholder

`flutter_app/.env` **is** in the repository, and it is intentionally empty of
secrets. `pubspec.yaml` lists `.env` under `flutter: assets:` because
`flutter_dotenv` needs the file bundled to read it at runtime. Flutter treats a
declared asset that does not exist as a build error, so a fresh clone — and
therefore CI — used to fail:

```text
warning • The asset file '.env' doesn't exist • pubspec.yaml:70:7 • asset_does_not_exist
```

`ci.yml` runs `flutter analyze --fatal-infos`, which turns even that single
warning into a failed build. The committed placeholder satisfies the asset
declaration and contains only comments.

The app never depended on the file being present: `lib/main.dart` calls
`await dotenv.load(isOptional: true)` and `ImgBbUploader` falls back to the
`--dart-define` value above. Uploading is simply disabled until a key exists,
which is what you want in CI and in tests.

**Prefer `--dart-define`.** `.gitignore` cannot protect `flutter_app/.env`
because git ignore rules have no effect on a path that is already tracked — so
if you type a real key into it, `git status` will offer that change in your next
commit. To keep a local key out of git, hide the file from the index *before*
editing it:

```bash
git update-index --skip-worktree flutter_app/.env
echo 'IMGBB_API_KEY=YOUR_IMGBB_KEY' >> flutter_app/.env

# undo later
git update-index --no-skip-worktree flutter_app/.env
```

`skip-worktree` is per clone — set it again after every fresh clone. As a habit,
check that `git status` does not list `flutter_app/.env` before committing.

Scratch files matching `.env.*.local` are still git-ignored, so
`flutter_app/.env.dev.local` and similar are safe to create freely.

## GitHub Secret

You may store the key as a repository secret named `IMGBB_API_KEY`:

**Repository → Settings and variables → Actions → New repository secret**

A secret does not automatically reach a local APK. For a local build, pass it
explicitly with `--dart-define` as shown above. If you later add a custom
GitHub Actions build step, inject the secret there as the same Dart define. Do
not hardcode it in Dart or commit it. The resulting mobile binary can still
contain/reveal the key because ImgBB requires a client key for direct upload.

## User flow

- Tap **+** in the Mind feed, then choose **Image** to select from the gallery.
- Or share an image from another app into KeepIt.
- KeepIt uploads the image, creates an `ItemType.image` item, and stores the
  returned URL in `thumbnailUrl` and `url`.
- The normal Hive → Firestore sync then uploads only the small URL and metadata.

The upload is limited to 32 MB per image. JPEG/PNG/WebP/GIF/HEIC/HEIF share
paths are recognised by the mobile share listener.
