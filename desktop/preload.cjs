const { contextBridge, ipcRenderer } = require("electron");

const captureWindow = process.argv.includes("--keepit-capture-window=1");
const importListeners = new Set();
const reminderListeners = new Set();
const pendingImports = [];
const pendingReminders = [];

function deliver(listeners, pending, value) {
  if (!listeners.size) {
    pending.push(value);
    if (pending.length > 50) pending.shift();
    return;
  }
  for (const listener of listeners) {
    try { listener(value); } catch (error) { console.error("KeepIt desktop event failed:", error); }
  }
}

ipcRenderer.on("keepit:import-item", (_event, item) => deliver(importListeners, pendingImports, item));
ipcRenderer.on("keepit:open-reminder", (_event, itemId) => deliver(reminderListeners, pendingReminders, itemId));

contextBridge.exposeInMainWorld("keepitDesktop", {
  isDesktop: true,
  isCaptureWindow: captureWindow,
  closeCapture: () => ipcRenderer.send("keepit:close-capture"),
  captureSaved: () => ipcRenderer.send("keepit:capture-saved"),
  syncReminders: (reminders) => ipcRenderer.send("keepit:sync-reminders", reminders),
  onImportItem: (callback) => {
    importListeners.add(callback);
    while (pendingImports.length) callback(pendingImports.shift());
    return () => importListeners.delete(callback);
  },
  onOpenReminder: (callback) => {
    reminderListeners.add(callback);
    while (pendingReminders.length) callback(pendingReminders.shift());
    return () => reminderListeners.delete(callback);
  },
});
