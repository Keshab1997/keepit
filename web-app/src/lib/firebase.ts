"use client";

import { getApp, getApps, initializeApp } from "firebase/app";
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut, type User } from "firebase/auth";
import { collection, deleteDoc, doc, getFirestore, onSnapshot, serverTimestamp, setDoc, type Unsubscribe } from "firebase/firestore";
import type { MindItem } from "@/lib/items";

const config = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
};

export const firebaseReady = Boolean(config.apiKey && config.authDomain && config.projectId);
const app = firebaseReady ? (getApps().length ? getApp() : initializeApp(config)) : null;
export const auth = app ? getAuth(app) : null;
export const db = app ? getFirestore(app) : null;

export async function connectGoogle(): Promise<User> {
  if (!auth) throw new Error("Cloud sync is not configured in this web build yet.");
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: "select_account" });
  return (await signInWithPopup(auth, provider)).user;
}

export async function disconnectGoogle() {
  if (auth) await signOut(auth);
}

export type CloudTombstone = { id: string; updatedAtMs: number };

export function watchItems(uid: string, onItems: (items: MindItem[], initialSnapshot: boolean, deleted: CloudTombstone[]) => void, onError: (error: Error) => void): Unsubscribe {
  if (!db) throw new Error("Firebase is not configured.");
  let initialSnapshot = true;
  return onSnapshot(collection(db, "users", uid, "items"), (snapshot) => {
    const records: MindItem[] = [];
    const deletedRecords: CloudTombstone[] = [];
    snapshot.forEach((entry) => {
      const raw = entry.data();
      if (raw.deleted === true) {
        deletedRecords.push({ id: entry.id, updatedAtMs: Number(raw.updatedAtMs ?? 0) });
        return;
      }
      const { deleted: _deleted, updatedAtMs: _updatedAtMs, serverUpdatedAt: _serverUpdatedAt, isSynced: _isSynced, ...item } = raw;
      records.push({
        id: entry.id,
        title: typeof item.title === "string" ? item.title : "Untitled",
        type: item.type || "webArticle",
        tags: Array.isArray(item.tags) ? item.tags : [],
        isWatched: Boolean(item.isWatched),
        isTopMind: Boolean(item.isTopMind),
        createdAt: typeof item.createdAt === "string" ? item.createdAt : new Date().toISOString(),
        updatedAt: typeof item.updatedAt === "string" ? item.updatedAt : new Date().toISOString(),
        ...item,
      } as MindItem);
    });
    records.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    onItems(records, initialSnapshot, deletedRecords);
    initialSnapshot = false;
  }, (error) => onError(error));
}

export async function saveCloudItem(uid: string, item: MindItem) {
  if (!db) return;
  const { id, ...data } = item;
  const cleanData = Object.fromEntries(Object.entries(data).filter(([, value]) => value !== undefined));
  await setDoc(doc(db, "users", uid, "items", id), {
    ...cleanData,
    id,
    updatedAtMs: Math.trunc(Date.parse(item.updatedAt) || Date.now()),
    deleted: false,
    serverUpdatedAt: serverTimestamp(),
  });
}

export async function deleteCloudItem(uid: string, id: string, deletedAtMs = Date.now()) {
  if (!db) return;
  // Write the same tombstone marker consumed by KeepIt's mobile sync engine.
  await setDoc(doc(db, "users", uid, "items", id), {
    id,
    deleted: true,
    updatedAtMs: Math.trunc(deletedAtMs),
    serverUpdatedAt: serverTimestamp(),
  });
}
