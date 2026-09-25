# Play Console answers (copy/paste)

## App access
> All functionality is available without special access. Signing in with Google is optional
> (only used for Cloud Sync). No credentials needed for review.

## Ads
**Yes** — the app contains ads (Google AdMob): a bottom banner, occasional interstitials
(strictly capped: max 1 per 8 saves, never more than once per 3 hours) and opt-in rewarded
ads. Ads are non-personalized by default. Play Console → App content → Ads → "Yes, my app
contains ads".

## Content rating (IARC questionnaire)
Category: **Utility, Productivity, Communication or Other**. Answer **No** to violence, sexual
content, profanity, drugs, gambling, and user-to-user interaction/sharing (users can't
communicate with each other; items are private). Expected rating: **Everyone / 3+**.

## Target audience
18 and over (you can also tick 13–17). Not designed for children → no Families policy.

## Data safety

Import `docs/PLAY_STORE_DATA_SAFETY.csv` from Play Console → App content → Data safety → **Import from CSV**. Do not open and re-save it in Excel first. The file uses Google's official 5-column header; a notes column or shortened header is rejected as `Line 1: Invalid header row`.

Account creation method, the deletion URL, Families, MASA and the UPI badge are **not** part of this CSV. Fill those on their own Play Console screens. Deletion URL: `https://keshab1997.github.io/keepit/delete-account.html`.

### Variant A: Firebase Cloud Sync + AdMob (current `flutter_app`)

**Does your app collect or share any of the required user data types?** Yes
**Is all user data encrypted in transit?** Yes
**Do you provide a way for users to request that their data is deleted?** Yes (in-app + URL)
**Processed ephemerally?** No, for every type below.

| Data type | Collected | Shared | Optional? | Purpose | Notes |
|---|---|---|---|---|---|
| Personal info → **Name** | Yes | No | Optional | Account management | Google Sign-In |
| Personal info → **Email address** | Yes | No | Optional | Account management | Google Sign-In |
| Personal info → **Personal identifiers** | Yes | No | Optional | Account management, App functionality | Firebase UID |
| Photos and videos → **Photos** | Yes | No | Optional | Account management | Google profile photo, only after sign-in |
| App activity → **Other user-generated content** | Yes | No | Optional | App functionality | saved links/notes/tags, only if Cloud Sync is on |
| Location → **Approximate location** | Yes | **Yes** (AdMob) | Required | Advertising, Analytics, Fraud prevention | IP address used by the Mobile Ads SDK to estimate general location. The app has no location permission. |
| App info and performance → **Diagnostics** | Yes | **Yes** (AdMob) | Required | Advertising, Analytics, Fraud prevention | SDK performance data (launch time, hang rate, energy). No Crashlytics, so crash logs stay off. |
| App activity → **Page views and taps in app** | Yes | **Yes** (AdMob) | Required | Advertising, Analytics, Fraud prevention | ad views, taps, app launch |
| Device or other IDs | Yes | **Yes** (AdMob) | Required | Advertising, Analytics, Fraud prevention | advertising ID and app set ID |

Firebase processes account and saved-item data on our behalf. That is collection, not sharing. AdMob is an independent third party, so its data is both collected and shared. Source: [Google Mobile Ads SDK data disclosure](https://developers.google.com/admob/android/privacy/play-data-disclosure).

### Variant B: published without Firebase and without AdMob
Only then answer **No** to collection and sharing. Removing Firebase alone is not enough while `google_mobile_ads` is still in the binary.

## Account deletion
- Can users create an account? **Yes** (Google sign-in)
- In-app: Profile → Delete account
- Web URL: `https://keshab1997.github.io/keepit/delete-account.html`

## Permissions declarations
- `POST_NOTIFICATIONS`: Serendipity reminders.
- No exact-alarm permission is used (reminders use inexact scheduling), so there's **no** `SCHEDULE_EXACT_ALARM` declaration to fill in.
- `RECEIVE_BOOT_COMPLETED`: re-schedule reminders after reboot.
- `INTERNET`: link previews and Cloud Sync.

## Privacy policy URL
`https://keshab1997.github.io/keepit/privacy-policy.html`
