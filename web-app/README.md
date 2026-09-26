# KeepIt Web

A desktop-first Next.js companion to the KeepIt Flutter app. This is a real, empty-by-default personal library—not a seeded demo feed. Saved data lives in IndexedDB per browser profile (and per signed-in Firebase account when cloud sync is enabled).

## Run locally

```bash
cd web-app
npm install
npm run dev
```

The checked-in app does not include a service-account key or private credential. This workspace has a local `.env.local` using the Firebase **web client** settings already present in `chrome_extension/firebase-config.js`; the file is git-ignored. For another machine/deployment, copy `.env.example` to `.env.local` and supply the Firebase Web app settings.

## Features

- Save a URL or quick note; URL previews fetch Open Graph/title/description on the server with public-address checks, redirect validation, timeouts and response-size limits.
- Search, tag filters, responsive masonry library, edit title/notes/tags, open the source, pin, mark revisited and delete.
- Smart Spaces and a rediscovery queue. Space definitions are device/account-browser local; the current mobile sync schema synchronizes items, not Space definitions.
- IndexedDB local-first persistence, account-scoped browser storage, local export, and deletion tombstones retained while offline.
- Google sign-in and Firestore live sync use the same collection/schema as mobile: `users/{uid}/items/{itemId}`. On first account connection, local unsynced items merge with the cloud by `updatedAt`; newer cloud tombstones win over stale local copies.
- Save JPEG, PNG, WebP or GIF images (up to 4 MB for Vercel Function request limits) from the **Image** tab. The web server uploads them to ImgBB; KeepIt stores the returned public URL in the local library and optional Firestore sync.

## ImgBB image uploads

The app sends image files to the same-origin `/api/upload-image` route, which proxies the upload to ImgBB. The API key remains on the server and is never sent to browser JavaScript.

- Local development: add `IMGBB_API_KEY=...` to the git-ignored `web-app/.env.local`, then restart `npm run dev`.
- Vercel: import the GitHub repository, set **Root Directory** to `web-app`, then add `IMGBB_API_KEY` under **Project → Settings → Environment Variables** for Preview and Production, and redeploy. A GitHub Actions Secret does **not** automatically become a Vercel environment variable; set the same value in Vercel. No `NEXT_PUBLIC_` prefix is needed.
- For Firebase sync on Vercel, also add the `NEXT_PUBLIC_FIREBASE_*` Web app values from your local `.env.local`; after the first deploy, add the Vercel production hostname in Firebase Authentication → **Authorized domains**. Without these, local browser saves still work, but cloud sign-in/sync will not.
- Never call it `NEXT_PUBLIC_IMGBB_API_KEY` or hardcode the key in the client.
- ImgBB image URLs are public. KeepIt saves the URL, not the image bytes; deleting a saved item removes it from KeepIt, but does not necessarily delete ImgBB's hosted copy.

The upload route accepts at most 20 uploads per IP per 10 minutes per running server instance as a soft abuse guard. For a high-traffic public deployment, use a persistent rate limiter and/or require signed-in users.

## Firebase setup for another host

1. Register a Firebase **Web app** in the KeepIt project and set these values in `.env.local`:
   - `NEXT_PUBLIC_FIREBASE_API_KEY`
   - `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`
   - `NEXT_PUBLIC_FIREBASE_PROJECT_ID`
   - `NEXT_PUBLIC_FIREBASE_APP_ID` (optional for this client)
   - `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID` (optional for this client)
2. Enable Google sign-in in Firebase Authentication. Add the local/production site hostname under **Authorized domains**.
3. Deploy `flutter_app/firestore.rules` so each user can access only their own `users/{uid}/items` records.
4. Restart the Next.js process after changing environment variables.

The Firebase client config is public browser configuration. Never put a Firebase Admin/service-account private key in this app or in a `NEXT_PUBLIC_*` variable. For production, restrict the API key to the necessary Firebase APIs and your domains.

## Build / deployment

```bash
npm run build
npm run start
```

Deploy to a Node-capable Next.js host; link previews use the Node runtime API route at `/api/metadata` (the app is not configured as a static export). Google sign-in also requires the deployed origin in Firebase Authorized domains. Cloud sync must be enabled in Firebase for cross-device data; without it, local saves and offline usage still work in this browser.
