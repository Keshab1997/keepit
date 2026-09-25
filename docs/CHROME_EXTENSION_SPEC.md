# Chrome Extension Manifest V3 Architecture

## 1. Overview
The KeepIt Chrome Extension enables instant 1-click saving of web pages, YouTube videos, Twitter threads, highlighted text snippets, and image assets directly into the user's KeepIt brain.

---

## 2. Technical Stack
- **Manifest:** V3 compliant
- **UI:** Minimal TailwindCSS floating badge / popup modal
- **Authentication:** Firebase Auth via Google OAuth in `chrome.identity`; the Firebase ID/refresh token pair is kept in extension storage and never logged.
- **Cloud transport:** Firestore REST API, using the same `users/{uid}/items/{itemId}` documents as the Flutter app.
- **Background Service Worker:** Intercepts context-menu clicks, keyboard shortcuts, normalizes item data, de-duplicates URLs, and runs the offline sync queue.

---

## 3. Key Capabilities
1. **Omnibox & Shortcut Save:** Press `Alt + S` (or `Cmd + Shift + K`) to instantly save current tab.
2. **Context Menu Actions:**
   - Right click an image -> *"Save image to KeepIt"*
   - Highlight text -> Right click -> *"Save quote to KeepIt"*
   - Right click any link -> *"Save link to KeepIt"*
3. **Instant Tagging Modal:**
   - Small non-blocking toast overlay showing auto-suggested tags and confirmation.
4. **Offline Queueing:**
   - Saves to `chrome.storage.local` if browser is offline, auto-flushing to Firebase when connection resumes.
5. **Shared data model:**
   - `keepit-schema.js` normalizes timestamps, tags, item types, and tracking parameters.
   - Duplicate URLs are merged instead of creating another card.
6. **Sync controls:**
   - The popup provides Connect, Sync, and local-only status.
   - A 15-minute alarm performs a non-interactive background sync.
