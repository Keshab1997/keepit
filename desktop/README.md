# KeepIt standalone desktop app

The desktop installers contain the **Next.js web build, its server/API routes, static assets, and Electron**. They do **not** open a deployed website or require Vercel. Electron starts the bundled server on `127.0.0.1:43819`, verifies that it is *its own* process, then shows the UI. You do not need a system Node.js installation on the user's machine.

The address/port is intentionally stable because the web app stores items in IndexedDB, which is tied to the page origin. Do not change the port after users have saved items without migrating their IndexedDB data. Only one app instance runs at a time; if another program already owns the port, KeepIt reports a startup error instead of showing a different program's page. Desktop builds check GitHub for newer stable `desktop-v*` releases at startup and show a dismissible in-app notice with a link to the release page; updates are not silently installed.

## Desktop capture, tray, and reminders

- **Quick Capture:** `Ctrl+Shift+K` on Windows or `⌘+Shift+K` on macOS opens a small capture window. It prefills a copied URL as a link or copied text as a note; copy the selection in another app before invoking the shortcut. Saving adds it to the same local library.
- **Open KeepIt directly:** `Ctrl+Alt+K` on Windows or `⌘+Option+K` on macOS brings the desktop window forward, including when it is hidden in the tray.
- **Tray/menu bar:** closing the main window hides KeepIt in the system tray (Windows) or menu bar (macOS). Use the tray menu to reopen the library, open Quick Capture with the clipboard, start a blank note, or quit. Native reminders continue while KeepIt is running in the tray; quitting the app stops reminder delivery until it is launched again.
- **Native reminders:** open a saved item and choose **Remind me in 1 week**. Electron persists the reminder and shows an OS notification when it is due; clicking the notification opens that item.
- **Chrome extension:** the popup detects Instagram Reel URLs and saves them as `instagramReel` items. **Open KeepIt Web** and the optional `Alt+Shift+K` extension command open `https://keepit-web-peach.vercel.app`; **Open Desktop App** launches the installed app via `keepit://` (Chrome may ask for confirmation). Chrome key bindings can be changed at `chrome://extensions/shortcuts`. Each desktop GitHub Release includes a versioned `KeepIt-Chrome-Extension-*.zip`; extract it and choose **Load unpacked** in `chrome://extensions` (Developer mode on). With KeepIt Desktop running, the popup can also send the page or selected text to its local library.

## Build installers using GitHub Actions

1. Go to **Actions → Build standalone desktop installers → Run workflow**. No hosted URL or `KEEPIT_WEB_URL` is required.
2. Download `windows-installer` (`.exe`, x64) and `macos-disk-images` (`.dmg`, Intel and Apple Silicon) from the completed run. The workflow builds the web app on each OS, bundles it, and packages the Electron app on that OS.
3. To automatically publish a GitHub Release with **release notes generated from commits** and all three installers attached, bump `desktop/package.json`'s version, then push a matching tag like `desktop-v1.0.1`. The workflow rebuilds the installers for that tag and publishes only after both builds succeed. Only tag a commit after reviewing and testing it. Downloads attached to the Release remain available after the workflow artifacts expire.

Unsigned builds are suitable for testing. Distributing without OS warnings needs Windows code signing and Apple Developer ID signing/notarization. Neither credential is included in the repository.

## Build/run locally

Install Node.js 22 and npm. From the `desktop/` directory:

```sh
npm ci
npm run build:web  # npm ci + Next build + copies/checks the standalone runtime
npm start          # optional: starts the built app on your machine
# On the appropriate OS (each dist command rebuilds the web bundle first):
npm run dist:win    # Windows x64 NSIS installer
npm run dist:mac    # macOS x64 + arm64 DMG files
```

Installers are written to `desktop/release/`. The packaging commands always rebuild and validate the standalone Next.js runtime before packaging so an old/incomplete web bundle cannot silently ship. The packaged Mac, Windows, and web UI icons are generated from `store_assets/play_store_icon_512.png`.

## What works without internet

The UI and local IndexedDB-backed library (existing saved links, notes, spaces, search, edits, JSON export) run without a web deployment. A first launch without internet shows an empty library; no demo data or external service is needed to save a text note or URL.

Fetching a *new* website's metadata, loading external thumbnails, ImgBB uploads and optional Firebase cloud sync all require network access. The metadata API is bundled locally, but it still contacts the website being saved. ImgBB uploads also require a personal/server-side `IMGBB_API_KEY` supplied in the app process environment at runtime; **never embed a shared API key or a Firebase Admin key in a public desktop installer**. Without that key the web image-upload action reports that it is unconfigured; text/URL saving still works. For self-contained local image uploads, the web app needs an additional local-media storage and sync design.

To enable optional Firebase client sync in desktop builds, configure these **public Web app** values as GitHub Actions repository *variables* before building: `NEXT_PUBLIC_FIREBASE_API_KEY`, `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`, `NEXT_PUBLIC_FIREBASE_PROJECT_ID` (plus `NEXT_PUBLIC_FIREBASE_APP_ID` and `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID` if needed). The web build bakes them into its JavaScript. Configure Firebase Auth authorized domains for the desktop origin as applicable. Google's OAuth policies may reject embedded Electron sign-in: test sign-in on each OS; a system-browser OAuth/deep-link flow may be needed. None of this is required for offline local use.

A desktop install has its **own** Chromium browser storage. It does not automatically copy bookmarks saved in Chrome or the hosted web app. The existing JSON export is a backup, but this web UI currently has no JSON import. To transfer existing items into desktop, cloud sync must work, or a JSON-import feature must be added. Do not clear Electron's application data if you need to preserve the local library.
