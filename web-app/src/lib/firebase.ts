"use client";

import { getApp, getApps, initializeApp } from "firebase/app";
import { getAuth, GoogleAuthProvider, signInWithPopup, signInWithRedirect, getRedirectResult, signOut, type User } from "firebase/auth";
import { collection, doc, getFirestore, onSnapshot, serverTimestamp, setDoc, type Unsubscribe } from "firebase/firestore";
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

// Detect if running inside Electron desktop wrapper
function isDesktop(): boolean {
  try {
    // @ts-ignore
    return Boolean(window?.keepitDesktop?.isDesktop);
  } catch {
    return false;
  }
}

export async function connectGoogle(): Promise<User> {
  if (!auth) throw new Error("Cloud sync is not configured in this web build yet.");
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: "select_account" });

  // On desktop (Electron), popup flow can fail on Mac due to Google's
  // "This browser or app may not be secure" policy or sandbox issues.
  // We try popup first (fixed in main.cjs with sandbox:false), then fallback
  // to redirect flow if popup is blocked/closed.
  try {
    console.log("[KeepIt] Attempting signInWithPopup, isDesktop:", isDesktop());
    const result = await signInWithPopup(auth, provider);
    console.log("[KeepIt] Popup sign-in success:", result.user.email);
    return result.user;
  } catch (popupError: any) {
    console.warn("[KeepIt] Popup sign-in failed:", popupError?.code, popupError?.message);
    
    // Common Electron/Mac errors:
    // - auth/popup-closed-by-user (user closed popup, or popup failed to communicate)
    // - auth/popup-blocked
    // - auth/unauthorized-domain (127.0.0.1 not in Firebase authorized domains)
    // - auth/operation-not-supported-in-this-environment
    const code = popupError?.code || "";
    
    if (code === "auth/unauthorized-domain") {
      throw new Error(
        "Firebase: 127.0.0.1 is not in Authorized Domains. Go to Firebase Console -> Authentication -> Settings -> Authorized domains -> Add '127.0.0.1' and 'localhost', then rebuild the desktop app."
      );
    }
    
    if (isDesktop() && (code === "auth/popup-closed-by-user" || code === "auth/popup-blocked" || code.includes("popup"))) {
      // On Mac, Google sometimes blocks embedded Electron webview.
      // Try redirect flow as fallback - main.cjs will allow navigation to Google
      // and back to appOrigin.
      console.log("[KeepIt] Trying redirect flow as fallback for desktop...");
      try {
        // Check if there's already a redirect result pending (user just came back from Google)
        const redirectResult = await getRedirectResult(auth);
        if (redirectResult?.user) {
          console.log("[KeepIt] Redirect sign-in success:", redirectResult.user.email);
          return redirectResult.user;
        }
        // Initiate redirect - this will navigate main window to Google, then back
        await signInWithRedirect(auth, provider);
        // This line won't be reached as page will redirect, but TS needs return
        throw new Error("Redirecting to Google sign-in... If you see this, redirect failed.");
      } catch (redirectError: any) {
        console.warn("[KeepIt] Redirect flow also failed:", redirectError);
        // Final fallback: open system browser manually
        // User can copy-paste instructions
        throw new Error(
          `Google sign-in failed in embedded window (${code}). This is a known Mac/Electron issue where Google blocks embedded browsers. \n\n` +
          `WORKAROUND: \n` +
          `1. Firebase Console -> Authentication -> Settings -> Authorized domains -> Add '127.0.0.1' and 'localhost'\n` +
          `2. Rebuild desktop app with fixed main.cjs (sandbox:false for auth popup)\n` +
          `3. Or use web version at https://keepit-web-peach.vercel.app to sign in first, then cloud sync will work in desktop via same Firebase project.\n\n` +
          `Original error: ${popupError?.message || code}`
        );
      }
    }
    
    // Re-throw original error for web version
    throw popupError;
  }
}

// Call this on app startup to handle redirect result if user just came back from Google
export async function handleRedirectResult(): Promise<User | null> {
  if (!auth) return null;
  try {
    const result = await getRedirectResult(auth);
    if (result?.user) {
      console.log("[KeepIt] Handled redirect result:", result.user.email);
      return result.user;
    }
  } catch (e) {
    console.warn("[KeepIt] getRedirectResult failed:", e);
  }
  return null;
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
  await setDoc(doc(db, "users", uid, "items", id), {
    id,
    deleted: true,
    updatedAtMs: Math.trunc(deletedAtMs),
    serverUpdatedAt: serverTimestamp(),
  });
}
