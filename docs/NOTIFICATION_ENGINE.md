# Serendipity & Spaced Repetition Notification Engine

## 1. The Core Problem
Standard bookmarking apps are "black holes"—users save great ideas and never look at them again. KeepIt transforms passive bookmarks into active knowledge using **Smart Serendipity Notifications**.

---

## 2. Notification Cadence (Spaced Rediscovery)
Items are queued for rediscovery using an adapted Ebbinghaus Spaced Repetition Curve:

1. **First Spark (Day 3):**
   - *"Remember this reel by Sidhartha Rai you saved 3 days ago?"*
   - Context: Fresh recall before memory decays.
2. **Second Reinforcement (Day 14):**
   - *"You saved an article on AI Build Tools 2 weeks ago. Still relevant to your projects?"*
3. **Deep Rediscovery (Day 45 / Day 90):**
   - *"Rediscover this hidden gem from your mind."*
4. **Weekend Mind Digest (Sunday 10:00 AM):**
   - Top 3 unread/unwatched items from your `Top of Mind` queue.

---

## 3. Smart Delivery Rules
- **Non-Intrusive Frequency:** Maximum of 1 rediscovery notification per day.
- **Smart Time Windows:** Delivered based on user activity patterns (e.g. 8:30 PM evening wind-down or 8:00 AM morning commute).
- **Interactive Action Buttons directly on notification:**
  - `Mark Watched`
  - `Remind in 1 Week`
  - `Open Item`
- **Relevance Ranking:** Items with higher engagement or pinned to "Top of Mind" are prioritized.
