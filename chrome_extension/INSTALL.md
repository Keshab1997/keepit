# Install KeepIt for Chrome

1. Download `KeepIt-Chrome-Extension-1.2.0.zip` from the [latest KeepIt GitHub Release](https://github.com/Keshab1997/keepit/releases/latest) and unzip it.
2. In Chrome, open `chrome://extensions` and turn on **Developer mode**.
3. Click **Load unpacked** and select the extracted folder that contains `manifest.json`.
4. Pin KeepIt from Chrome's Extensions menu for one-click access.

The ZIP is a ready-to-load unpacked extension bundle; Chrome requires the ZIP to be extracted first. For updates, download and extract the newer ZIP, then use **Reload** on the KeepIt card in `chrome://extensions` (or load the new extracted folder).

## Shortcuts

- **Alt+S** — save the current page to KeepIt.
- **Alt+Shift+K** — open the KeepIt web library at <https://keepit-web-peach.vercel.app>.
- Change either key binding at <chrome://extensions/shortcuts>.
- **Open Desktop App** in the popup uses the `keepit://` app link; Chrome may ask you to confirm opening KeepIt.
- KeepIt Desktop also has a system-wide show-app shortcut: **Ctrl+Alt+K** on Windows or **⌘+Option+K** on macOS. Quick Capture is **Ctrl+Shift+K** / **⌘+Shift+K**.

## Notes

- Instagram Reel links are normalized and saved with the Reel item type. Private or login-only Reels may not expose a preview, but the link and Reel type are still saved.
- **Send page** and **Send selected text** need KeepIt Desktop to be running. They send to the local desktop library and do not require Firebase sync.
- Cloud sync is optional. Firebase client settings in the extension are public web configuration; never place a private key or service-account credential in this bundle.
