# KeepIt — In-App Updates (Google Play)

**App:** KeepIt — AI-Powered Second Brain & Smart Visual Bookmarks
**Package name:** `com.keshabstudios.keepit`
**Mechanism:** Google Play in-app update (flexible by default, immediate when mandatory)
**Code lives in:** `flutter_app/lib/core/updates/` + `flutter_app/lib/presentation/controllers/app_update_controller.dart`
**Last reviewed:** 25 September 2026

> Publish a new build on Google Play → users see an update screen inside KeepIt
> the next time they open it. No extra step, no version file to edit, no
> Firebase Remote Config to babysit: Play itself is the source of truth.

---

## 1. What the user sees

| Situation | What happens |
| :--- | :--- |
| **A newer build is on Play** | KeepIt's own bottom sheet: *"A new version is ready"* → **Update now** / **Later**. |
| User taps **Update now** | Play asks to confirm, then downloads in the background while the user keeps using the app. A quiet *"Downloading update…"* pill sits at the top. |
| Download finished | Second sheet: *"Update downloaded"* → **Restart & install**. One tap, KeepIt restarts on the new build. |
| User taps **Later** | Prompt stays hidden for **24 hours** for that build. A newer build on Play breaks the silence immediately. |
| **Mandatory release** | Full-screen *"Update required"* screen replaces the app. Back button is disabled; **Update now** (Play's own full-screen installer) or **Open in Play Store**. |
| No update / offline / sideloaded APK | Nothing. The check is silent and never blocks the app. |
| Profile → **Check for update** | Manual check, ignores the 24-hour snooze, toasts *"KeepIt is up to date"* when there is nothing new. |

The check at startup is **silent**: Play is never asked to show anything until
the user taps *Update now*, so a cold start never throws a system dialog in
anyone's face before the app has painted.

---

## 2. Shipping a normal (optional) update

This is the everyday path — nothing to configure:

1. Bump `version` in `flutter_app/pubspec.yaml`, e.g. `1.0.3+6` → `1.0.4+7`.
   The number after `+` is the `versionCode` and **must** increase.
2. Build and upload the AAB to Play (the existing
   *Publish Android Release* workflow, or `docs/PUBLISHING.md` by hand).
3. Roll it out.

Every install with a lower `versionCode` now shows the update sheet on its next
cold start. Staged rollouts work as expected: a user is only prompted once Play
has actually served them the new build.

---

## 3. Forcing an update (mandatory)

Use this only when an old build genuinely cannot continue — a breaking sync
format, a security fix, or a crash loop. Two independent switches:

### A. From code — `UpdateConfig.mandatoryBelowBuildNumber`

```dart
// flutter_app/lib/core/updates/update_config.dart
static const int mandatoryBelowBuildNumber = 7;   // was 0
```

Everybody on build **6 or older** is blocked until they install build 7+.
Ship that constant in the release that needs it, then set it back to `0`
whenever you are ready to stop forcing.

### B. Without shipping code — Play's in-app update priority

Play Console (or the Play Developer API) lets you set an **in-app update
priority** of 0–5 per release. KeepIt treats priority **5** (`UpdateConfig.mandatoryPriority`) as mandatory, so you can force a rollout for an
already-published build — handy in an emergency.

---

## 4. Why "flexible by default, mandatory on demand"

| Choice | Upside | Downside |
| :--- | :--- | :--- |
| **Force every update** | Everyone is always current. | Blocks users on metered data, mid-task, or offline. Play's full-screen flow is jarring — a reliable source of 1★ reviews. |
| **Only ever soft** | Nobody is interrupted. | You can never retire a broken old build. |
| **Soft + mandatory switch** *(implemented)* | Routine releases stay polite; you keep an escape hatch for breaking changes. | One extra constant to think about. |

Rule of thumb: **force only when an old build is actively harmful**, and stop
forcing as soon as the forced build is widely adopted.

---

## 5. Testing — read this before you try it

**In-app updates cannot be tested from `flutter run`.** The Play Core API only
answers for a build that was *installed by the Play Store app*; a local build
gets `updateNotAvailable` or `ERROR_API_NOT_AVAILABLE`. That is expected, not a
bug in KeepIt.

To see the real thing:

1. Add yourself as a tester → Play Console → **Testing → Internal testing**,
   create/choose a testers list that includes your own account.
2. Publish build **N** (e.g. `1.0.4+7`) to that track.
3. Install KeepIt **from the Play Store** on a device signed in with that
   account (the opt-in link from the Testers tab).
4. Bump to build **N+1** (`1.0.5+8`) and publish it to the same track.
5. Wait for Play to pick it up (minutes to a few hours), then open the app from
   the device. The *"A new version is ready"* sheet appears.

Checklist while testing:

- [ ] Sheet appears on cold start, **not** before the app has painted.
- [ ] **Update now** → Play dialog → background download → *"Update downloaded"*.
- [ ] **Restart & install** → app restarts on the new build, library intact.
- [ ] **Later** → no prompt for 24 h; Profile → Check for update still finds it.
- [ ] Publish build N+2 → prompt returns immediately (snooze is per build).
- [ ] Mandatory path: set `mandatoryBelowBuildNumber` above the installed build
      → *"Update required"* screen, back button disabled.
- [ ] Airplane mode → app opens normally, no prompt, no crash.

---

## 6. Behaviour details

| Topic | Behaviour |
| :--- | :--- |
| Platforms | Android only. iOS / web / desktop use `NoopAppUpdateService` and the Profile tile is hidden. |
| When it checks | Once per cold start (~1.2 s after the first frame) and on Profile → Check for update. |
| Failure mode | Every Play call fails soft and is logged with `debugPrint`. A broken update check must never stop KeepIt from opening. |
| Snooze storage | Hive meta box: `update_snooze_until_ms`, `update_snooze_version_code`. |
| Your data | Updates never touch the local Hive library — KeepIt is local-first. |
| Cancelled mandatory update | Keeps the app blocked (Google's own guidance) with an *Open in Play Store* escape hatch. |
| ProGuard / R8 | No extra keep rules needed; the release build already has `isMinifyEnabled = true`. |
| Permissions | None added. No extra Play Data Safety disclosure — no data leaves the device. |

---

## 7. Files

| File | Role |
| :--- | :--- |
| `flutter_app/lib/core/updates/update_config.dart` | The knobs: `mandatoryBelowBuildNumber`, `mandatoryPriority`, `snoozeDuration`, `enabled`. |
| `flutter_app/lib/core/updates/app_update_service.dart` | Thin seam over the `in_app_update` plugin; no-op implementation for non-Android. |
| `flutter_app/lib/presentation/controllers/app_update_controller.dart` | The state machine, snooze rules and Riverpod providers. |
| `flutter_app/lib/presentation/widgets/update_host.dart` | Wraps the app, runs the startup check, shows the download pill. |
| `flutter_app/lib/presentation/widgets/update_prompt_sheet.dart` | The *"A new version is ready"* / *"Update downloaded"* sheets. |
| `flutter_app/lib/presentation/widgets/update_required_screen.dart` | The blocking *"Update required"* screen. |
| `flutter_app/test/app_update_controller_test.dart` | 12 unit tests for the rules that cannot be tested on a device. |

Kill switch: set `UpdateConfig.enabled = false` and ship — KeepIt then never
mentions updates again.
