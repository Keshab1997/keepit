# Architecture & Local-First Sync Engine

## 1. Overview
KeepIt is designed with a **Local-First, Cloud-Synced** paradigm. The user never waits on a network spinner to save a bookmark, load their feed, or edit notes. Everything is written instantly to the local embedded database and seamlessly mirrored to Firebase.

---

## 2. Core Principles
1. **Zero Latency Writes:** All actions (saving link, archiving, tagging, marking as watched) execute instantly in the local database.
2. **Offline-First:** The app runs 100% offline without degradation.
3. **Optimistic UI Updates:** UI reacts immediately to user modifications.
4. **Idempotent Sync Engine:** Background worker queues synchronization tasks with timestamp-based conflict resolution (Last-Write-Wins with granular field merging).

---

## 3. Data Flow Diagram

```
User Action (Share / Add)
       │
       ▼
 ┌──────────────┐
 │ Local Store  │ ◄────── Instant Write (<10ms)
 │ (Hive / Isar)│
 └──────┬───────┘
        │
   Sync Queue
        │
        ▼
 ┌──────────────┐
 │ Sync Manager │ ◄────── Connectivity Aware
 └──────┬───────┘
        │
        ▼ (when online)
 ┌──────────────┐
 │ Firebase     │ ◄────── Firestore & Cloud Storage
 │ Backend      │
 └──────────────┘
```

---

## 4. Database Schema (Item Entity)

```json
{
  "id": "uuid-v4",
  "userId": "firebase-uid",
  "title": "Super Useful 3 Contacts",
  "url": "https://www.instagram.com/reel/xyz123",
  "sourceType": "instagram_reel", // 'webpage' | 'instagram_reel' | 'youtube_video' | 'image' | 'note' | 'tweet'
  "content": "Description or transcription snippet",
  "thumbnailUrl": "https://cdn.keepit.app/thumbs/xyz.jpg",
  "authorName": "Sidhartha Rai",
  "authorAvatar": "https://...",
  "tags": ["ai", "contacts", "useful", "productivity"],
  "spaceId": "tech-tools-space-id",
  "isWatched": false,
  "isTopMind": true,
  "colorHex": "#E85D04",
  "createdAt": 1727072000000,
  "updatedAt": 1727072000000,
  "syncStatus": "synced" // 'pending' | 'syncing' | 'synced' | 'conflict'
}
```

---

## 5. Conflict Resolution Strategy
- **Client Timestamping:** Each record carries an ISO 8601 UTC timestamp and monotonic sequence.
- **Field-Level Patching:** Changes update only modified fields rather than replacing whole documents.
- **Tombstoning:** Soft deletes (`isDeleted = true`) allow propagating deletions across multiple devices (e.g., deleted on mobile -> removes from Chrome extension).
