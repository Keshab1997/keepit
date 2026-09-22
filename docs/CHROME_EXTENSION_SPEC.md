# Chrome Extension Manifest V3 Architecture

## 1. Overview
The KeepIt Chrome Extension enables instant 1-click saving of web pages, YouTube videos, Twitter threads, highlighted text snippets, and image assets directly into the user's KeepIt brain.

---

## 2. Technical Stack
- **Manifest:** V3 compliant
- **UI:** Minimal TailwindCSS floating badge / popup modal
- **Authentication:** Firebase Auth (JWT token shared via secure storage)
- **Background Service Worker:** Intercepts context-menu clicks, keyboard shortcuts, and parses Open Graph / JSON-LD metadata.

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
