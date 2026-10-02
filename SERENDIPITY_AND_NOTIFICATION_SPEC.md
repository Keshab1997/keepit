# KeepIt Serendipity & Spaced Repetition Notification Engine

## 1. Overview & Problem Statement
The average user saves 10-20 Instagram reels, YouTube shorts, and articles every week, but forgets 90% of them within 72 hours. Standard bookmarking tools act like black holes where valuable knowledge is lost. 

**KeepIt Serendipity Engine** solves this by actively resurfacing forgotten ideas at optimal cognitive intervals (Spaced Repetition & Memory Retention).

---

## 2. Core Modules

### A. Serendipity Tab ("Rediscovery Feed")
1. **"On This Day" / Time Capsule:**
   - Highlights items saved 7 days, 14 days, 30 days, or months ago.
2. **"Unwatched Gems":**
   - Curated queue of high-value saved reels/articles that user has not yet marked as *"I've watched this reel"*.
3. **Quick Serendipity Actions:**
   - ⚡ **Rediscover (Open App)**: Direct one-tap jump to Instagram/YouTube.
   - ✅ **Mark as Processed / Watched**: Clean up the active mind memory.
   - 🌟 **Shuffle Spark**: Shake or tap to bring a completely random forgotten item.

### B. Smart Scheduled Notification Engine
Local background notifications delivered without annoying the user:
- **Optimal Time Slot:** Evenings (e.g., 8:30 PM) or Weekend Mornings (10:00 AM) when user has leisure time.
- **Smart Copy:** 
  - *"Remember this reel by Sidhartha Rai you saved 2 weeks ago?"*
  - *"Rediscover: 'Super Useful 3 Contacts' is waiting in your mind."*
- **One-Tap Deep Link:** Tapping notification opens the app directly to that specific card detail sheet.

---

## 3. Algorithm & Logic Flow

```
Daily Trigger (Scheduled at 20:30)
      │
      ▼
Fetch all items from Hive DB
      │
      ▼
Filter: isWatched == false AND createdAt <= (Now - 3 days)
      │
      ▼
Sort by: [isTopMind (Weight 2.0), Age, Tags]
      │
      ▼
Pick Top 1 Candidate
      │
      ▼
Deliver Flutter Local Notification
```

---

## 4. Implementation Steps
1. **Notification Service (`notification_service.dart`)**:
   - Initialize `flutter_local_notifications` with high-importance notification channel.
   - Request notification permissions cleanly on Android 13+.
   - Helper methods: `scheduleDailySerendipity()`, `showInstantMemoryReminder()`.

2. **Serendipity Screen (`serendipity_screen.dart`)**:
   - Replace static placeholder with interactive **Daily Capsule & Memory Carousel**.
   - Add shuffle button ("✨ Spark a random memory").
   - Include direct processing toggles.

3. **Wire into `HomeScreen` & State Management**:
   - Live synchronization with `MindFeedController`.
