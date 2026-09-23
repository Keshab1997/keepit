# Serendipity & Spaced Repetition Notification Engine

> **Status: ✅ Implemented** (local notifications, no server required)

## 1. The Core Problem
Standard bookmarking apps are "black holes"—users save great ideas and never look at them again. KeepIt transforms passive bookmarks into active knowledge using **Smart Serendipity Notifications**.

---

## 2. Notification Cadence (Spaced Rediscovery)
Unwatched items are resurfaced on an adapted Ebbinghaus curve (`SerendipityPlanner.stageDays = [3, 14, 45, 90]`):

| Stage | Day | Example copy |
| :--- | :--- | :--- |
| First Spark | 3 | 🧠 *Remember this reel?* "Super Useful 3 Contacts" by Sidhartha Rai — you saved it 3 days ago. |
| Reinforcement | 14 | 💡 *Still relevant?* You saved "Build Tools 2026" 2 weeks ago. Worth a look now? |
| Deep Rediscovery | 45 / 90 | ✨ *Rediscover a hidden gem* — saved a month ago and still waiting in your mind. |
| Sunday Mind Digest | Sundays 10:00 | ☀️ Top 3 unwatched items (Top of Mind first, then most forgotten). |
| Snoozed | +7 days | ⏰ *Reminder, as promised* — after tapping "In 1 Week". |

Items overdue for several stages (e.g. saved 50 days ago, never reminded) jump straight to the **latest due stage** — no stale-stage spam.

---

## 3. Smart Delivery Rules
- **Max 1 notification per day** at the user's chosen time (default **8:30 PM**). On Sundays the Digest replaces the Spark.
- **Priority:** snoozed-and-now-due → Top of Mind → longest-waiting due item.
- **Watched items are never resurfaced.**
- **Action buttons on the notification** (work without opening the app):
  - `✅ Mark Watched`
  - `⏰ In 1 Week`
  - `Open` → opens the item's detail sheet
- **Tapping** a Spark opens that card's detail sheet; tapping the Digest opens the Serendipity tab.

---

## 4. How it works (code map)

```
lib/core/notifications/serendipity_planner.dart  Pure scheduling logic (unit-tested)
lib/core/notifications/serendipity_store.dart    JSON-file state + action queue
lib/core/utils/notification_service.dart         flutter_local_notifications wrapper
lib/presentation/widgets/notification_host.dart  Wires service ↔ Riverpod ↔ UI
lib/presentation/widgets/reminder_settings_sheet.dart  Settings UI (bell icon)
```

**Rolling pre-scheduling.** Local notifications can't run Dart code at fire time, so the planner simulates the next **14 days** and schedules concrete notifications (max 14, well under iOS's 64-pending limit). The plan is rebuilt:
- on app launch and every resume,
- whenever items are added / deleted / marked watched / pinned (debounced 800 ms),
- when settings change or an item is snoozed.

Before each rebuild, reminders whose time has passed are **committed** (the item's stage advances), so progress is kept even though Dart never ran at delivery time.

**Background actions.** "Mark Watched" / "In 1 Week" run in a background isolate (`keepItNotificationBackgroundHandler`). To avoid opening Hive from two isolates, that handler only appends a line to `serendipity_actions.jsonl`; the main isolate drains the queue on launch/resume, applies it to Hive and re-plans.

**Scheduling mode.** `AndroidScheduleMode.inexactAllowWhileIdle` — no exact-alarm permission needed and battery friendly (a few minutes of drift is fine for a gentle reminder). Times are converted to absolute UTC instants, so no timezone plugin is needed; DST shifts self-correct on the next re-plan.

---

## 5. Platform setup (already done)
- **Android** `AndroidManifest.xml`: `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver` (reschedules after reboot / app update), `ActionBroadcastReceiver` (buttons). `proguard-rules.pro` keeps the Gson classes the plugin uses in release builds.
- **iOS** `AppDelegate.swift`: `setPluginRegistrantCallback` (background actions) + `UNUserNotificationCenter` delegate (foreground display & tap routing). Actions are declared via the `keepit_spark` notification category.

## 6. Testing on a device
1. Open **Serendipity → 🔔 bell → Send a test notification** — shows a real Spark with action buttons.
2. Try **Mark Watched** with the app closed, then reopen: the item is marked watched and a toast confirms it.
3. Set the reminder time a couple of minutes ahead with an item saved ≥3 days ago (or the demo data) and lock the phone.
