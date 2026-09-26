const { app, BrowserWindow, dialog, shell } = require("electron");
const { spawn } = require("node:child_process");
const { randomBytes } = require("node:crypto");
const http = require("node:http");
const path = require("node:path");

// Keep the origin stable: the existing web app stores bookmarks in IndexedDB,
// which is scoped to scheme + host + port. A random port would hide the user's
// library on every restart. Only one KeepIt desktop instance may use this port.
const PORT = 43819;
const appOrigin = `http://127.0.0.1:${PORT}`;
const bootToken = randomBytes(32).toString("hex");
let server;
let quitting = false;

app.setName("KeepIt");
if (process.platform === "win32") app.setAppUserModelId("com.keshab.keepit");

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on("second-instance", () => {
    const window = BrowserWindow.getAllWindows()[0];
    if (window) {
      if (window.isMinimized()) window.restore();
      window.focus();
    }
  });

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

  // Google/Firebase authentication popups stay in Electron; ordinary links
  // open in the user's browser. Google can refuse OAuth in embedded browsers;
  // cloud sign-in must still be tested on the actual macOS/Windows installers.
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
    const fs = require("node:fs");
    if (!fs.existsSync(entry)) throw new Error("Bundled web server is missing. Rebuild the desktop installer.");

    // Electron contains a Node runtime. Run the traced Next.js standalone
    // server in a separate Node-mode process, with no system Node installation.
    server = spawn(process.execPath, [entry], {
      cwd: path.dirname(entry),
      env: {
        ...process.env,
        ELECTRON_RUN_AS_NODE: "1",
        NODE_ENV: "production",
        HOSTNAME: "127.0.0.1",
        PORT: String(PORT),
        KEEPIT_DESKTOP_BOOT_TOKEN: bootToken,
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
        throw new Error(`Could not start the bundled web server. Port ${PORT} may be in use. ${startupError}`);
      }
      if (await checkOurServer()) return;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    throw new Error(`Timed out starting the bundled web server on port ${PORT}. ${startupError}`);
  }

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
      webPreferences: { nodeIntegration: false, contextIsolation: true, sandbox: true },
    });
    window.once("ready-to-show", () => window.show());
    void window.loadURL(appOrigin).catch((error) => {
      dialog.showErrorBox("KeepIt cannot load", error.message);
      app.quit();
    });
    return window;
  }

  app.whenReady().then(async () => {
    try {
      await launchServer();
      createWindow();
      app.on("activate", () => {
        if (BrowserWindow.getAllWindows().length === 0) createWindow();
      });
    } catch (error) {
      dialog.showErrorBox("KeepIt cannot start", error.message);
      app.quit();
    }
  });

  app.on("before-quit", () => {
    quitting = true;
    if (server && !server.killed) server.kill();
  });
  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });
}
