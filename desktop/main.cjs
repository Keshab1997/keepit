const {
  app, BrowserWindow, dialog, shell, globalShortcut, Tray, Menu, clipboard,
  nativeImage, Notification, ipcMain,
} = require("electron");
const { spawn } = require("node:child_process");
const { randomBytes } = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

// Keep the origin stable: the existing web app stores bookmarks in IndexedDB,
// which is scoped to scheme + host + port. Only one KeepIt instance uses it.
const PORT = 43819;
const appOrigin = `http://127.0.0.1:${PORT}`;
const bootToken = randomBytes(32).toString("hex");
const captureShortcut = "CommandOrControl+Shift+K";
const captureShortcutLabel = process.platform === "darwin" ? "⌘+Shift+K" : "Ctrl+Shift+K";
const openAppShortcut = "CommandOrControl+Alt+K";
const openAppShortcutLabel = process.platform === "darwin" ? "⌘+Option+K" : "Ctrl+Alt+K";
let server;
let mainWindow;
let captureWindow;
let tray;
let bridgePollTimer;
let bridgePolling = false;
let reminderTimer;
let reminders = [];
let quitting = false;
let serverReady = false;

app.setName("KeepIt");
if (process.platform === "win32") app.setAppUserModelId("com.keshab.keepit");

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  const iconPath = path.join(__dirname, "build", "icon.png");
  const preloadPath = path.join(__dirname, "preload.cjs");
  const reminderPath = () => path.join(app.getPath("userData"), "reminders.json");

  function isFirebaseGoogleSignIn(rawUrl) {
    try {
      const url = new URL(rawUrl);
      const host = url.hostname;
      // Google OAuth hosts + Firebase auth handler + Google's new oauth hosts
      return host === "accounts.google.com" ||
        host === "accounts.youtube.com" ||
        host.endsWith(".googleusercontent.com") ||
        host.endsWith(".google.com") && url.pathname.includes("oauth") ||
        host.endsWith(".gstatic.com") ||
        (host.endsWith(".firebaseapp.com") && url.pathname.startsWith("/__/auth")) ||
        host === "keepit-deda6.firebaseapp.com" ||
        // Allow localhost callback for system-browser flow fallback
        (host === "127.0.0.1" && url.port === String(PORT) && url.pathname.startsWith("/__/auth")) ||
        (host === "localhost" && url.pathname.startsWith("/__/auth"));
    } catch {
      return false;
    }
  }

  function isAuthRelatedUrl(rawUrl) {
    try {
      const url = new URL(rawUrl);
      return isFirebaseGoogleSignIn(rawUrl) ||
        url.hostname.includes("google") && (url.pathname.includes("signin") || url.pathname.includes("oauth") || url.search.includes("oauth")) ||
        url.href.includes("firebase") && url.href.includes("auth");
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

  function isSafeUrl(rawUrl) {
    try { return ["http:", "https:"].includes(new URL(rawUrl).protocol); }
    catch { return false; }
  }

  function handleProtocolUrl(rawUrl) {
    try {
      if (new URL(rawUrl).protocol !== "keepit:") return;
      if (!serverReady) return;
      showMainWindow();
      // Handle keepit://auth?token=... deep link if implemented later
      if (rawUrl.includes("auth")) {
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send("keepit:auth-callback", rawUrl);
        }
      }
    } catch { /* Ignore malformed protocol URLs. */ }
  }

  app.on("open-url", (event, rawUrl) => {
    if (String(rawUrl).startsWith("keepit://")) {
      event.preventDefault();
      handleProtocolUrl(rawUrl);
    }
  });

  app.on("web-contents-created", (_event, contents) => {
    // Keep track of auth popups to allow their navigations
    const isAuthPopupWindow = () => {
      try {
        const parent = BrowserWindow.fromWebContents(contents)?.getParentWindow();
        // Also check if this contents is itself an auth popup by URL
        const url = contents.getURL();
        return Boolean(parent) || isFirebaseGoogleSignIn(url);
      } catch {
        return false;
      }
    };

    contents.setWindowOpenHandler(({ url }) => {
      console.log(`[KeepIt] window.open requested: ${url}`);
      if (isFirebaseGoogleSignIn(url) || isAuthRelatedUrl(url)) {
        console.log(`[KeepIt] Allowing auth popup for: ${url}`);
        return {
          action: "allow",
          overrideBrowserWindowOptions: {
            width: 520,
            height: 720,
            minWidth: 400,
            minHeight: 600,
            resizable: true,
            autoHideMenuBar: true,
            show: true,
            // CRITICAL FIX for Mac: sandbox must be false for Firebase popup postMessage to work
            // sandbox:true breaks window.opener communication on macOS
            webPreferences: { 
              nodeIntegration: false, 
              contextIsolation: true, 
              sandbox: false,
              partition: "default"
            },
          },
        };
      }
      console.log(`[KeepIt] Opening externally: ${url}`);
      openExternalSafely(url);
      return { action: "deny" };
    });

    contents.on("will-navigate", (event, rawUrl) => {
      try {
        const url = new URL(rawUrl);
        const isPopup = Boolean(BrowserWindow.fromWebContents(contents)?.getParentWindow());
        const isAuth = isFirebaseGoogleSignIn(rawUrl) || isAuthRelatedUrl(rawUrl);
        
        // Allow navigation within app origin
        if (url.origin === appOrigin) {
          console.log(`[KeepIt] Allowing navigation to app origin: ${rawUrl}`);
          return;
        }
        
        // Allow auth popup to navigate to Google/Firebase auth URLs
        if (isPopup && isAuth) {
          console.log(`[KeepIt] Allowing auth popup navigation: ${rawUrl}`);
          return;
        }
        
        // If main window tries to navigate to auth URL, allow it as popup instead
        if (!isPopup && isAuth) {
          console.log(`[KeepIt] Main window auth navigation, allowing: ${rawUrl}`);
          return;
        }
        
        // Block everything else and open externally
        console.log(`[KeepIt] Blocking navigation, opening externally: ${rawUrl}`);
        event.preventDefault();
        openExternalSafely(rawUrl);
      } catch {
        event.preventDefault();
      }
    });

    // Handle cases where Google shows "This browser or app may not be secure"
    // Detect and offer to open in system browser as fallback
    contents.on("did-fail-load", (_event, errorCode, errorDescription, validatedURL) => {
      if (isFirebaseGoogleSignIn(validatedURL) || isAuthRelatedUrl(validatedURL)) {
        console.warn(`[KeepIt] Auth page failed to load: ${errorCode} ${errorDescription} ${validatedURL}`);
      }
    });
  });

  function serverEntry() {
    return app.isPackaged
      ? path.join(process.resourcesPath, "next-server", "server.js")
      : path.join(__dirname, "..", "web-app", ".next", "standalone", "server.js");
  }

  function checkOurServer() {
    return new Promise((resolve) => {
      const request = http.get(`${appOrigin}/api/desktop-health`, {
        headers: { "x-keepit-desktop-boot-token": bootToken },
        timeout: 1000,
      }, (response) => {
        response.resume();
        resolve(response.statusCode === 200);
      });
      request.on("error", () => resolve(false));
      request.on("timeout", () => request.destroy());
    });
  }

  async function launchServer() {
    const entry = serverEntry();
    if (!fs.existsSync(entry)) throw new Error("Bundled web server is missing. Rebuild the desktop installer.");

    server = spawn(process.execPath, [entry], {
      cwd: path.dirname(entry),
      env: {
        ...process.env,
        ELECTRON_RUN_AS_NODE: "1",
        NODE_ENV: "production",
        HOSTNAME: "127.0.0.1",
        PORT: String(PORT),
        NODE_PATH: path.join(path.dirname(entry), "runtime-deps"),
        KEEPIT_DESKTOP_BOOT_TOKEN: bootToken,
        KEEPIT_DESKTOP_VERSION: app.getVersion(),
      },
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
    });

    let startupError = "";
    server.stderr.on("data", (chunk) => { startupError = (startupError + chunk.toString()).slice(-1500); });
    server.stdout.on("data", (chunk) => { console.log(chunk.toString().trim()); });
    server.on("error", (error) => { startupError = error.message; });
    server.on("exit", (code) => {
      if (!quitting && BrowserWindow.getAllWindows().length) {
        dialog.showErrorBox("KeepIt stopped", `The bundled server exited (code ${code}). Please restart KeepIt.`);
        app.quit();
      }
    });

    for (let attempt = 0; attempt < 100; attempt++) {
      if (server.exitCode !== null || !server.pid) {
        const details = startupError.trim() || "The server exited before it became ready.";
        if (/EADDRINUSE|address already in use/i.test(details)) {
          throw new Error(`Could not start the bundled web server because port ${PORT} is already in use. Close the other app using that port and try again.\n\n${details}`);
        }
        throw new Error(`The bundled web server stopped during startup (exit code ${server.exitCode ?? "unknown"}).\n\n${details}\n\nServer bundle: ${entry}`);
      }
      if (await checkOurServer()) return;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    throw new Error(`Timed out starting the bundled web server on port ${PORT}. ${startupError}`);
  }

  function showMainWindow() {
    if (!serverReady) return;
    if (!mainWindow || mainWindow.isDestroyed()) {
      createMainWindow();
      return;
    }
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
  }

  function createMainWindow() {
    if (mainWindow && !mainWindow.isDestroyed()) return mainWindow;
    const window = new BrowserWindow({
      width: 1360,
      height: 900,
      minWidth: 920,
      minHeight: 680,
      show: false,
      title: "KeepIt",
      icon: iconPath,
      autoHideMenuBar: process.platform === "win32",
      webPreferences: { preload: preloadPath, nodeIntegration: false, contextIsolation: true, sandbox: true },
    });
    mainWindow = window;
    window.once("ready-to-show", () => window.show());
    window.on("close", (event) => {
      if (!quitting) {
        event.preventDefault();
        window.hide();
      }
    });
    window.on("closed", () => { if (mainWindow === window) mainWindow = null; });
    void window.loadURL(appOrigin).catch((error) => {
      dialog.showErrorBox("KeepIt cannot load", error.message);
      app.quit();
    });
    return window;
  }

  async function createCaptureWindow(useClipboard = true) {
    if (captureWindow && !captureWindow.isDestroyed()) {
      captureWindow.show();
      captureWindow.focus();
      return;
    }
    let text = "";
    if (useClipboard) {
      try {
        const copiedText = await clipboard.readText();
        text = (typeof copiedText === "string" ? copiedText : "").trim().slice(0, 12_000);
      } catch (error) {
        console.warn("Could not read the clipboard for Quick Capture:", error.message);
      }
    }
    const mode = isSafeUrl(text) ? "link" : "note";
    const payload = encodeURIComponent(JSON.stringify({ mode, text }));
    const window = new BrowserWindow({
      width: 540,
      height: 610,
      minWidth: 480,
      minHeight: 500,
      maxWidth: 640,
      show: false,
      title: "Quick Capture · KeepIt",
      icon: iconPath,
      resizable: true,
      alwaysOnTop: true,
      autoHideMenuBar: true,
      webPreferences: {
        preload: preloadPath,
        additionalArguments: ["--keepit-capture-window=1"],
        nodeIntegration: false,
        contextIsolation: true,
        sandbox: true,
      },
    });
    captureWindow = window;
    window.once("ready-to-show", () => { window.show(); window.focus(); });
    window.on("closed", () => { if (captureWindow === window) captureWindow = null; });
    void window.loadURL(`${appOrigin}/#desktop-capture=${payload}`).catch((error) => {
      console.error("KeepIt capture window could not load:", error.message);
      window.close();
    });
  }

  function openCaptureWindow(useClipboard = true) {
    void createCaptureWindow(useClipboard).catch((error) => {
      console.error("KeepIt Quick Capture failed:", error.message);
      dialog.showErrorBox("Quick Capture failed", error.message || "Could not open the capture window.");
    });
  }

  function createTray() {
    if (tray) return;
    const image = nativeImage.createFromPath(iconPath).resize({ width: 32, height: 32 });
    tray = new Tray(image);
    tray.setToolTip("KeepIt · Save ideas for later");
    tray.setContextMenu(Menu.buildFromTemplate([
      { label: `Open KeepIt (${openAppShortcutLabel})`, click: showMainWindow },
      { label: `Quick Capture (${captureShortcutLabel})`, click: () => openCaptureWindow(true) },
      { label: "New blank note", click: () => openCaptureWindow(false) },
      { type: "separator" },
      { label: "Quit KeepIt", click: () => { quitting = true; app.quit(); } },
    ]));
    tray.on("click", showMainWindow);
    tray.on("double-click", showMainWindow);
  }

  function setupShortcuts() {
    const captureRegistered = globalShortcut.register(captureShortcut, () => openCaptureWindow(true));
    const openRegistered = globalShortcut.register(openAppShortcut, showMainWindow);
    if (!captureRegistered) console.warn(`Could not register ${captureShortcut}; it may be used by another app.`);
    if (!openRegistered) console.warn(`Could not register ${openAppShortcut}; it may be used by another app.`);
  }

  function startDesktopBridgePolling() {
    const poll = async () => {
      if (bridgePolling || !mainWindow || mainWindow.isDestroyed()) return;
      bridgePolling = true;
      try {
        const response = await fetch(`${appOrigin}/api/desktop-bridge`, {
          headers: { "x-keepit-desktop-boot-token": bootToken },
          cache: "no-store",
          signal: AbortSignal.timeout(1800),
        });
        if (response.ok) {
          const payload = await response.json();
          if (payload?.item && mainWindow && !mainWindow.isDestroyed()) {
            mainWindow.webContents.send("keepit:import-item", payload.item);
          }
        }
      } catch {
        // The local bridge is best-effort; offline saves continue to work.
      } finally {
        bridgePolling = false;
      }
    };
    void poll();
    bridgePollTimer = setInterval(() => void poll(), 900);
    bridgePollTimer.unref?.();
  }

  function loadReminders() {
    try {
      const data = JSON.parse(fs.readFileSync(reminderPath(), "utf8"));
      reminders = Array.isArray(data) ? data.filter((item) => item && typeof item.id === "string" && typeof item.title === "string" && Number.isFinite(Date.parse(item.remindAt))) : [];
    } catch {
      reminders = [];
    }
  }

  function persistReminders() {
    try {
      fs.mkdirSync(path.dirname(reminderPath()), { recursive: true });
      fs.writeFileSync(reminderPath(), JSON.stringify(reminders, null, 2), { mode: 0o600 });
    } catch (error) {
      console.warn("Could not save KeepIt reminders:", error.message);
    }
  }

  function syncReminders(next) {
    if (!Array.isArray(next)) return;
    const current = Date.now();
    reminders = next
      .filter((item) => item && typeof item.id === "string" && typeof item.title === "string" && typeof item.remindAt === "string")
      .map((item) => ({ id: item.id.slice(0, 120), title: item.title.slice(0, 300), remindAt: item.remindAt }))
      .filter((item) => Number.isFinite(Date.parse(item.remindAt)) && Date.parse(item.remindAt) > current)
      .slice(0, 500);
    persistReminders();
  }

  function showDueReminders() {
    const now = Date.now();
    const due = reminders.filter((item) => Date.parse(item.remindAt) <= now);
    if (!due.length) return;
    reminders = reminders.filter((item) => Date.parse(item.remindAt) > now);
    persistReminders();
    for (const item of due) {
      if (!Notification.isSupported()) continue;
      const notification = new Notification({ title: "A KeepIt idea is ready to revisit", body: item.title, silent: false });
      notification.on("click", () => {
        showMainWindow();
        setTimeout(() => {
          if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send("keepit:open-reminder", item.id);
        }, 350);
      });
      notification.show();
    }
  }

  ipcMain.on("keepit:close-capture", (event) => {
    if (captureWindow && event.sender === captureWindow.webContents) captureWindow.close();
  });

  ipcMain.on("keepit:capture-saved", (event) => {
    if (captureWindow && event.sender === captureWindow.webContents) {
      captureWindow.close();
      showMainWindow();
      setTimeout(() => {
        if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send("keepit:capture-saved");
      }, 250);
      return;
    }
    if (mainWindow && event.sender === mainWindow.webContents) showMainWindow();
  });

  ipcMain.on("keepit:sync-reminders", (event, next) => {
    if (mainWindow && event.sender === mainWindow.webContents) syncReminders(next);
  });

  // NEW: Handle auth callback from system browser flow
  ipcMain.on("keepit:auth-external", (_event, url) => {
    console.log(`[KeepIt] External auth requested: ${url}`);
    openExternalSafely(url);
  });

  app.on("second-instance", (_event, commandLine) => {
    const protocolUrl = Array.isArray(commandLine) ? commandLine.find((argument) => typeof argument === "string" && argument.startsWith("keepit://")) : null;
    if (protocolUrl) handleProtocolUrl(protocolUrl);
    showMainWindow();
  });
  app.on("activate", () => showMainWindow());

  app.whenReady().then(async () => {
    try {
      if (!app.isPackaged && process.platform === "win32") {
        app.setAsDefaultProtocolClient("keepit", process.execPath, [path.resolve(process.argv[1] || ".")]);
      } else {
        app.setAsDefaultProtocolClient("keepit");
      }
      await launchServer();
      serverReady = true;
      loadReminders();
      createTray();
      setupShortcuts();
      createMainWindow();
      startDesktopBridgePolling();
      reminderTimer = setInterval(showDueReminders, 15_000);
      reminderTimer.unref?.();
      showDueReminders();
    } catch (error) {
      dialog.showErrorBox("KeepIt cannot start", error.message);
      app.quit();
    }
  });

  app.on("before-quit", () => {
    quitting = true;
    globalShortcut.unregisterAll();
    if (bridgePollTimer) clearInterval(bridgePollTimer);
    if (reminderTimer) clearInterval(reminderTimer);
    if (tray) { tray.destroy(); tray = null; }
    if (server && !server.killed) server.kill();
  });

  app.on("window-all-closed", () => {
    if (quitting) app.quit();
  });
}
