# AdMob setup (monetization)

KeepIt monetizes with **Google AdMob** via [`google_mobile_ads`](https://pub.dev/packages/google_mobile_ads).
The real AdMob app + ad unit IDs (App `ca-app-pub-4216917764852377~9499831430`,
banner/interstitial/rewarded units) are wired in — see `ad_config.dart`.

## What's already implemented

| Format | Where | Frequency |
|---|---|---|
| **Banner** (anchored adaptive) | Bottom of the Everything / Spaces / Serendipity tabs (hidden on Profile) | Always visible on those tabs |
| **Interstitial** | Right after a successful save — a natural "reward moment" | Max 1 per **8 saves**, never more than once per **3 hours** |
| **Rewarded** | Profile → **Support KeepIt** | Only when the user taps it (opt-in) |

All IDs and caps live in one place:

- `flutter_app/lib/core/ads/ad_config.dart` — IDs, switches, frequency caps
- `flutter_app/lib/core/ads/ad_service.dart` — load / show / cap logic
- `flutter_app/lib/presentation/widgets/banner_ad_widget.dart` — banner widget
- `flutter_app/lib/presentation/screens/home_screen.dart` — banner placement
- `flutter_app/lib/presentation/controllers/mind_feed_controller.dart` — post-save interstitial trigger
- `flutter_app/lib/presentation/screens/profile_screen.dart` — "Support KeepIt" rewarded tile

## Go live in 5 steps

1. **Create an AdMob account** — https://apps.admob.com (sign in with the Google account that
   should receive payments).
2. **Register the app**: Apps → Add app → "Yes, it's listed on a store" (or "No" while
   testing) → package name `com.keshabstudios.keepit`. You get an **App ID**
   (`ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY`).
3. **Create 3 ad units** for that app: Banner (anchored adaptive), Interstitial, Rewarded.
   Note each **Ad unit ID** (`ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ`).
4. **Replace the IDs** (two files):
   - `flutter_app/lib/core/ads/ad_config.dart` → `bannerUnitId`, `interstitialUnitId`,
     `rewardedUnitId`
   - `flutter_app/android/app/src/main/AndroidManifest.xml` → the
     `com.google.android.gms.ads.APPLICATION_ID` meta-data value (the App ID from step 2)
5. **Build & publish**: `flutter build appbundle --release` → upload to Play Console.

> ⚠️ The App ID must be changed in **both** places — the manifest value is what the AdMob SDK
> reads at startup. Mismatched IDs can crash the app or stop ads from serving.

## Play Console checklist

- **App content → Ads** → "Yes, my app contains ads".
- **Data safety** → import `PLAY_STORE_DATA_SAFETY.csv`. AdMob's automatic disclosure is already in that file: approximate location (from IP), diagnostics, app interactions, and device or other IDs, each collected and shared for advertising, analytics and fraud prevention. Copy/paste answers are in `PLAY_CONSOLE_ANSWERS.md`.
- The privacy policy already discloses AdMob (`privacy-policy.html`, section 5) — it is served
  at https://keshab1997.github.io/keepit/privacy-policy.html

## Tuning

| Knob | File / constant | Default |
|---|---|---|
| Show/hide a format | `ad_config.dart` → `enableBanner` / `enableInterstitial` / `enableRewarded` | all on |
| Saves between interstitials | `savesBetweenInterstitials` | 8 |
| Minimum gap between interstitials | `minInterstitialInterval` | 3 hours |
| Delay after save before showing | `interstitialDelay` | 800 ms |
| Personalized vs non-personalized | `personalizedAds` | `false` (privacy-first, no consent SDK needed) |
| Kill switch for the whole feature | `adsEnabled` | `true` |

To disable ads entirely, set `adsEnabled = false` (or delete the three ad units from AdMob) —
no other code change is needed.

## Important rules

- **Never click your own ads**, and never pay for or incent clicks — instant ban risk.
- New AdMob accounts/apps can take a few days (and an app review) before real ads serve.
  Test ads always serve, so use them while waiting.
- Payment threshold is **$100**; add tax info and a payment method in AdMob → Payments.
- Keep CI green: every push runs `flutter analyze` + `flutter test` + a debug APK build.
