const { app, BrowserWindow, shell } = require("electron");
const path = require("node:path");

const { keepItWebUrl } = require("./app-config.json");

app.setName("KeepIt");
if (process.platform === "win32") app.setAppUserModelId("com.keshab.keepit");

const appOrigin = new URL(keepItWebUrl).origin;
const iconPath = path.join(__dirname, "build", "icon.png");

function isFirebaseGoogleSignIn(rawUrl) {
  try {
    const url = new URL(rawUrl);
    return url.hostname === "accounts.google.com" ||
      (url.hostname.endsWith(".firebaseapp.com") && url.pathname.startsWith("/__/auth/handler"));
  } catch {
    return false;
  }
}

function openExternalSafely(rawUrl) {
  try {
    const url = new URL(rawUrl);
    if (["https:", "http:", "mailto:"].includes(url.protocol)) void shell.openExternal(url.href);
  } catch {
    // Ignore malformed or unsupported link schemes.
  }
}

// Keep Firebase's Google sign-in popup in Electron; send ordinary links to the system browser.
app.on("web-contents-created", (_event, contents) => {
  contents.setWindowOpenHandler(({ url }) => {
    if (isFirebaseGoogleSignIn(url)) {
      return {
        action: "allow",
        overrideBrowserWindowOptions: {
          width: 520,
          height: 720,
          resizable: true,
          autoHideMenuBar: true,
          webPreferences: { nodeIntegration: false, contextIsolation: true, sandbox: true },
        },
      };
    }
    openExternalSafely(url);
    return { action: "deny" };
  });

  contents.on("will-navigate", (event, rawUrl) => {
    try {
      const url = new URL(rawUrl);
      const isAuthPopup = Boolean(BrowserWindow.fromWebContents(contents)?.getParentWindow());
      if (url.origin !== appOrigin && !(isAuthPopup && isFirebaseGoogleSignIn(rawUrl))) {
        event.preventDefault();
        openExternalSafely(rawUrl);
      }
    } catch {
      event.preventDefault();
    }
  });
});

function createWindow() {
  const window = new BrowserWindow({
    width: 1360,
    height: 900,
    minWidth: 920,
    minHeight: 680,
    show: false,
    title: "KeepIt",
    icon: iconPath,
    autoHideMenuBar: process.platform === "win32",
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
    },
  });

  window.once("ready-to-show", () => window.show());
  void window.loadURL(keepItWebUrl);
  return window;
}

app.whenReady().then(() => {
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
