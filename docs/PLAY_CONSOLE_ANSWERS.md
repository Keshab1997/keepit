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

### Variant A: with Firebase Cloud Sync (default once google-services.json is added)

**Does your app collect or share any of the required user data types?** Yes
**Is all user data encrypted in transit?** Yes
**Do you provide a way for users to request that their data is deleted?** Yes (in-app + URL)

| Data type | Collected | Shared | Optional? | Purpose | Notes |
|---|---|---|---|---|---|
| Personal info → **Name** | Yes | No | Optional | Account management | from Google sign-in |
| Personal info → **Email address** | Yes | No | Optional | Account management | |
| Personal info → **User IDs** | Yes | No | Optional | Account management, App functionality | Firebase UID |
| App activity → **Other user-generated content** | Yes | No | Optional | App functionality | saved links/notes, synced to cloud |
| Photos (profile photo URL) | No* | | | | *Only the URL of the Google avatar; you may also declare it under Photos → Optional → Account management to be safe |
| Device or other IDs → **Advertising ID** | Yes | **Yes** (Google AdMob) | Required | Advertising or marketing |
| App activity → **App interactions** (ad views / taps) | Yes | **Yes** (Google AdMob) | Required | Advertising or marketing |

- "Processed ephemerally?" → No. "Required or optional?" → **Optional** (users can use the app without signing in).
- Shared: **Yes** — the advertising ID and ad-interaction data are shared with Google AdMob (a third party) in order to serve ads. Everything else (saved items, account data) stays with us; Firebase is a *service provider* processing on our behalf, which doesn't count as sharing.
- Security practices: ✅ encrypted in transit, ✅ deletion request mechanism.

### Variant B: published without Firebase
Data collected: **No**. Data shared: **No**. (Everything stays on the device.)

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
