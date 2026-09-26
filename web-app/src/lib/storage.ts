import type { MindItem } from "@/lib/items";

export type KeepItSpace = { id: string; name: string; subtitle: string; color: string; icon: string; tags: string[] };
export type LocalTombstone = { id: string; deletedAtMs: number };

const dbCache = new Map<string, Promise<IDBDatabase>>();
const memoryItems = new Map<string, MindItem[]>();
const memorySpaces = new Map<string, KeepItSpace[]>();
const memoryTombstones = new Map<string, Map<string, number>>();
function database(scope: string): Promise<IDBDatabase> {
  const safeScope = scope.replace(/[^a-zA-Z0-9_-]/g, "_");
  const name = `keepit-local-v1-${safeScope}`;
  const existing = dbCache.get(name);
  if (existing) return existing;
  const opening = new Promise<IDBDatabase>((resolve, reject) => {
    if (typeof indexedDB === "undefined") { reject(new Error("This browser does not support local offline storage.")); return; }
    const request = indexedDB.open(name, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains("items")) db.createObjectStore("items", { keyPath: "id" });
      if (!db.objectStoreNames.contains("spaces")) db.createObjectStore("spaces", { keyPath: "id" });
      if (!db.objectStoreNames.contains("tombstones")) db.createObjectStore("tombstones", { keyPath: "id" });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("Could not open local storage."));
  });
  dbCache.set(name, opening);
  return opening;
}

function requestResult<T>(request: IDBRequest<T>) {
  return new Promise<T>((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("Local storage request failed."));
  });
}

function transactionDone(transaction: IDBTransaction) {
  return new Promise<void>((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error ?? new Error("Local storage write failed."));
    transaction.onabort = () => reject(transaction.error ?? new Error("Local storage write was cancelled."));
  });
}

export async function loadItems(scope: string): Promise<MindItem[]> {
  let records: MindItem[];
  try {
    const db = await database(scope);
    const transaction = db.transaction("items", "readonly");
    records = await requestResult(transaction.objectStore("items").getAll()) as MindItem[];
  } catch { records = memoryItems.get(scope) ?? []; }
  if (records.length) return records.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
  // Preserve genuine items saved with the previous web preview, but never migrate its bundled demo cards.
  if (scope === "guest" && typeof localStorage !== "undefined") {
    try {
      const old = JSON.parse(localStorage.getItem("keepit-web-items-v1") ?? "[]") as MindItem[];
      const userItems = Array.isArray(old) ? old.filter((item) => item && typeof item.id === "string" && !item.id.startsWith("demo-") && typeof item.title === "string") : [];
      if (userItems.length) { await replaceItems(scope, userItems); return userItems; }
    } catch { /* Ignore invalid old browser cache. */ }
  }
  return [];
}

export async function replaceItems(scope: string, items: MindItem[]): Promise<void> {
  memoryItems.set(scope, items);
  try {
    const db = await database(scope);
    const transaction = db.transaction("items", "readwrite");
    const store = transaction.objectStore("items");
    store.clear();
    for (const item of items) store.put(item);
    await transactionDone(transaction);
  } catch { /* Memory fallback keeps the current session usable in restricted browser contexts. */ }
}

export async function loadSpaces(scope: string): Promise<KeepItSpace[] | null> {
  let result: KeepItSpace[];
  try {
    const db = await database(scope);
    const transaction = db.transaction("spaces", "readonly");
    result = await requestResult(transaction.objectStore("spaces").getAll()) as KeepItSpace[];
  } catch { result = memorySpaces.get(scope) ?? []; }
  if (result.length) return result;
  if (scope === "guest" && typeof localStorage !== "undefined") {
    try {
      const old = JSON.parse(localStorage.getItem("keepit-web-spaces-v1") ?? "[]") as KeepItSpace[];
      if (Array.isArray(old) && old.every((space) => space && typeof space.id === "string" && typeof space.name === "string")) {
        await replaceSpaces(scope, old);
        return old;
      }
    } catch { /* Ignore invalid old browser cache. */ }
  }
  return null;
}

export async function replaceSpaces(scope: string, spaces: KeepItSpace[]): Promise<void> {
  memorySpaces.set(scope, spaces);
  try {
    const db = await database(scope);
    const transaction = db.transaction("spaces", "readwrite");
    const store = transaction.objectStore("spaces");
    store.clear();
    for (const space of spaces) store.put(space);
    await transactionDone(transaction);
  } catch { /* Memory fallback keeps the current session usable in restricted browser contexts. */ }
}

export async function loadTombstones(scope: string): Promise<Map<string, number>> {
  try {
    const db = await database(scope);
    const transaction = db.transaction("tombstones", "readonly");
    const records = await requestResult(transaction.objectStore("tombstones").getAll()) as LocalTombstone[];
    const loaded = new Map(records.map((record) => [record.id, record.deletedAtMs]));
    memoryTombstones.set(scope, loaded);
    return loaded;
  } catch { return memoryTombstones.get(scope) ?? new Map(); }
}

export async function setTombstone(scope: string, id: string, deletedAtMs: number): Promise<void> {
  const values = memoryTombstones.get(scope) ?? new Map<string, number>();
  values.set(id, deletedAtMs);
  memoryTombstones.set(scope, values);
  try {
    const db = await database(scope);
    const transaction = db.transaction("tombstones", "readwrite");
    transaction.objectStore("tombstones").put({ id, deletedAtMs } satisfies LocalTombstone);
    await transactionDone(transaction);
  } catch { /* Memory fallback. */ }
}

export async function clearTombstone(scope: string, id: string): Promise<void> {
  memoryTombstones.get(scope)?.delete(id);
  try {
    const db = await database(scope);
    const transaction = db.transaction("tombstones", "readwrite");
    transaction.objectStore("tombstones").delete(id);
    await transactionDone(transaction);
  } catch { /* Memory fallback. */ }
}
