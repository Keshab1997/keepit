# KeepIt Desktop packaging

This is a small Electron shell around the hosted KeepIt web app. It does not bundle the Next.js application: the desktop app needs an internet connection and opens the configured Vercel URL. Firebase Google sign-in popups are kept inside Electron; ordinary web links are opened in the system browser.

## Configure GitHub Actions

1. In the GitHub repository, open **Settings → Secrets and variables → Actions → Variables** and create a repository variable named `KEEPIT_WEB_URL` with the production HTTPS origin, for example `https://keepit-your-team.vercel.app` (no path, query, or trailing slash required).
2. Open **Actions → Build desktop installers → Run workflow**. You can leave the optional URL input blank to use the repository variable, or enter a URL to override it for that run.
3. The workflow produces a Windows x64 NSIS installer (`.exe`) and macOS Intel + Apple Silicon disk images (`.dmg`). Download the per-platform artifacts from the completed workflow run. To also publish a GitHub Release, push a tag such as `desktop-v1.0.0` after configuring the variable.

The URL is public and is embedded as a build-time app setting; do not put credentials or API keys in it. To switch production domains, update the variable and rebuild/release the desktop installers.

## Build locally

Requires Node.js 22 and npm. From this directory:

```sh
npm ci
KEEPIT_WEB_URL=https://keepit-your-team.vercel.app npm run dist:win
KEEPIT_WEB_URL=https://keepit-your-team.vercel.app npm run dist:mac
```

On Windows, use PowerShell syntax: `$env:KEEPIT_WEB_URL="https://keepit-your-team.vercel.app"; npm run dist:win`.

Installers are written to `desktop/release/`. The source artwork is `build/icon.svg`; the PNG, Windows ICO, and macOS ICNS icons are committed alongside it.

## Signing note

These CI installers are not code-signed or notarized. Windows may show SmartScreen warnings and macOS may require the user to approve an unidentified developer. Production signing requires an organization-owned Windows signing certificate and Apple Developer ID/notarization credentials stored as GitHub Actions secrets; no signing credentials are included here.
