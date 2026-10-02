# AdMob setup (monetization)

KeepIt monetizes with **Google AdMob** via [`google_mobile_ads`](https://pub.dev/packages/google_mobile_ads).

> 🔐 **The real AdMob IDs are not in this repository.** They live in GitHub
> Actions secrets and are injected at build time. See
> [`SECRETS_SETUP.md`](SECRETS_SETUP.md) for the one-time setup.
>
> A checkout without those secrets builds an **ad-free** app
> (`AdConfig.adsEnabled` defaults to `false`), so forks, CI runs and local
> builds can never serve — or burn — the production ad units.

## What's already implemented

| Format | Where | Frequency |
|---|---|---|
| **Banner** (anchored adaptive) | Bottom of the Everything / Spaces / Serendipity tabs (hidden on Profile) | Always visible on those tabs |
| **Interstitial** | Right after a successful save — a natural "reward moment" | Max 1 per **8 saves**, never more than once per **3 hours** |
| **Rewarded** | Profile → **Support KeepIt** | Only when the user taps it (opt-in) |

## Where things live

| Concern | File |
|---|---|
| IDs, switches, frequency caps | `flutter_app/lib/core/ads/ad_config.dart` |
| Load / show / cap logic | `flutter_app/lib/core/ads/ad_service.dart` |
| Banner widget | `flutter_app/lib/presentation/widgets/banner_ad_widget.dart` |
| Banner placement | `flutter_app/lib/presentation/screens/home_screen.dart` |
| Post-save interstitial trigger | `flutter_app/lib/presentation/controllers/mind_feed_controller.dart` |
| "Support KeepIt" rewarded tile | `flutter_app/lib/presentation/screens/profile_screen.dart` |
| App ID → `AndroidManifest.xml` | `flutter_app/android/app/build.gradle.kts` (`manifestPlaceholders["admobAppId"]`) |
| Secrets → build | `.github/workflows/publish-release.yml`, `release.yml`, `manual-build.yml` |

## How the IDs reach a release build

```
GitHub secret  ADMOB_APP_ID / ADMOB_BANNER_ID / ADMOB_INTERSTITIAL_ID / ADMOB_REWARDED_ID
        │
        ├─ dart-defines ──> --dart-define=ADMOB_...=...  ──> AdConfig (Dart)
        │                    --dart-define=ADMOB_ENABLED=true
        │
        └─ build-env ─────> $ADMOB_APP_ID (exported) ──> build.gradle.kts
                                                          System.getenv(...)
                                                            └─> AndroidManifest
                                                                ${admobAppId}
```

Two notes that matter:

- **The App ID must reach both places.** The Dart constant powers the SDK
  calls; the manifest meta-data is what AdMob reads at startup. The workflow
  passes `ADMOB_APP_ID` through `dart-defines` *and* `build-env` for exactly
  this reason — keep both lines.
- **`--dart-define` values are compiled into the binary**, so this hides the
  IDs from the *source repo*, not from anyone who downloads the APK. That is
  fine and normal for AdMob (every published app ships them), but do not put
  API keys or passwords through the same path.

## Go live in 5 steps

1. **Create an AdMob account** — https://apps.admob.com (sign in with the
   Google account that should receive payments).
2. **Register the app**: Apps → Add app → package name
   `com.keshabstudios.keepit`. You get an **App ID**
   (`ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY`).
3. **Create 3 ad units** for that app: Banner (anchored adaptive), Interstitial,
   Rewarded. Note each **Ad unit ID** (`ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ`).
4. **Put the four values in GitHub secrets** (never in a file):
   `ADMOB_APP_ID`, `ADMOB_BANNER_ID`, `ADMOB_INTERSTITIAL_ID`,
   `ADMOB_REWARDED_ID` — see [`SECRETS_SETUP.md`](SECRETS_SETUP.md).
5. **Run** Actions → *Publish Android Release*. The workflow supplies
   `ADMOB_ENABLED=true` itself, so the release app serves ads and every other
   build stays ad-free.

## Testing locally

Without secrets the app is ad-free, which makes it useless for ad testing. To
see real ad requests on a device, pass the defines yourself:

```bash
cd flutter_app
flutter run --release \
  --dart-define=ADMOB_ENABLED=true \
  --dart-define=ADMOB_APP_ID=ca-app-pub-...~... \
  --dart-define=ADMOB_BANNER_ID=ca-app-pub-.../... \
  --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-.../... \
  --dart-define=ADMOB_REWARDED_ID=ca-app-pub-.../...
ADMOB_APP_ID=ca-app-pub-...~... flutter build appbundle --release   # manifest value
```

> ⚠️ Never commit that command with real values. Use a shell alias or a
> git-ignored script.

## Play Console checklist

- **App content → Ads** → "Yes, my app contains ads".
- **Data safety** → import `PLAY_STORE_DATA_SAFETY.csv`. AdMob's automatic
  disclosure is already in that file: approximate location (from IP),
  diagnostics, app interactions, and device or other IDs, each collected and
  shared for advertising, analytics and fraud prevention. Copy/paste answers
  are in `PLAY_CONSOLE_ANSWERS.md`.
- The privacy policy already discloses AdMob (`privacy-policy.html`,
  section 5) — served at https://keshab1997.github.io/keepit/privacy-policy.html

## Tuning

| Knob | File / constant | Default |
|---|---|---|
| Show/hide a format | `ad_config.dart` → `_enableBanner` / `_enableInterstitial` / `_enableRewarded` | all on |
| Saves between interstitials | `savesBetweenInterstitials` | 8 |
| Minimum gap between interstitials | `minInterstitialInterval` | 3 hours |
| Delay after save before showing | `interstitialDelay` | 800 ms |
| Personalized vs non-personalized | `personalizedAds` | `false` (privacy-first, no consent SDK needed) |
| Kill switch for the whole feature | `ADMOB_ENABLED` dart-define | `false` without the release secrets |

To disable ads entirely, drop `ADMOB_ENABLED` from the workflow's
`dart-defines` (or delete the secret values) — no code change is needed.

## Important rules

- **Never click your own ads**, and never pay for or incent clicks — instant
  ban risk.
- New AdMob accounts/apps can take a few days (and an app review) before real
  ads serve.
- Payment threshold is **$100**; add tax info and a payment method in
  AdMob → Payments.
- Keep CI green: every push runs `flutter analyze` + `flutter test`.
