# Fix: Google Sign-In redirect_uri_mismatch for KeepIt Extension

**Your Extension ID:** `oighcclifnifkacigeojkcpbddcagnga`

**Exact Redirect URI to whitelist:**
```
https://oighcclifnifkacigeojkcpbddcagnga.chromiumapp.org/keepit
```

## Steps (2 minutes)

1. Open: https://console.cloud.google.com/apis/credentials?project=keepit-deda6
2. Click OAuth Client: `332166521596-82nf4aljih1qkqmhhapkm2lnbtr3v49j.apps.googleusercontent.com`
3. Under **Authorized redirect URIs** -> ADD URI -> paste:
   ```
   https://oighcclifnifkacigeojkcpbddcagnga.chromiumapp.org/keepit
   ```
4. Also add (safe fallback):
   ```
   https://oighcclifnifkacigeojkcpbddcagnga.chromiumapp.org/
   ```
5. SAVE
6. If OAuth consent screen is in Testing mode:
   Go to https://console.cloud.google.com/apis/credentials/consent?project=keepit-deda6
   -> Test users -> Add `keshabsarkar2018@gmail.com` and your test accounts

7. Wait 5-10 minutes, then chrome://extensions -> KeepIt -> Reload -> Popup -> Connect

## Debug
In extension background service worker console (chrome://extensions -> KeepIt -> Service worker -> Inspect):
```js
chrome.identity.getRedirectURL('keepit')
```
Should return exactly the URI above.
