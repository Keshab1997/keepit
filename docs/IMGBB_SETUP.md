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

## User flow

- Tap **+** in the Mind feed, then choose **Image** to select from the gallery.
- Or share an image from another app into KeepIt.
- KeepIt uploads the image, creates an `ItemType.image` item, and stores the
  returned URL in `thumbnailUrl` and `url`.
- The normal Hive → Firestore sync then uploads only the small URL and metadata.

The upload is limited to 32 MB per image. JPEG/PNG/WebP/GIF/HEIC/HEIF share
paths are recognised by the mobile share listener.
