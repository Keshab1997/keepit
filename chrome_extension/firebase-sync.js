// Firebase Auth + Firestore REST sync for the KeepIt MV3 extension.
// The extension remains fully local-first when firebase-config.js is empty.
(function (global) {
  'use strict';

  const ITEMS_KEY = 'keepit_items';
  const AUTH_KEY = 'keepit_firebase_auth';
  const STATE_KEY = 'keepit_sync_state';
  const AUTH_SKEW_MS = 60 * 1000;
  let runningSync = null;

  const storageGet = (keys) => chrome.storage.local.get(keys);
  const storageSet = (values) => chrome.storage.local.set(values);

  function config() {
    return global.KEEPIT_FIREBASE_CONFIG || {};
  }

  function isConfigured() {
    const c = config();
    return Boolean(c.apiKey && c.projectId && c.oauthClientId);
  }

  async function getItems() {
    const result = await storageGet({ [ITEMS_KEY]: [] });
    return Array.isArray(result[ITEMS_KEY]) ? result[ITEMS_KEY] : [];
  }

  async function setItems(items) {
    await storageSet({ [ITEMS_KEY]: items });
  }

  async function getState() {
    const result = await storageGet({ [STATE_KEY]: {} });
    return result[STATE_KEY] && typeof result[STATE_KEY] === 'object'
      ? result[STATE_KEY]
      : {};
  }

  async function saveState(state) {
    await storageSet({ [STATE_KEY]: state });
  }

  async function getAuth() {
    const result = await storageGet({ [AUTH_KEY]: null });
    return result[AUTH_KEY] || null;
  }

  async function saveAuth(auth) {
    await storageSet({ [AUTH_KEY]: auth });
  }

  async function clearAuth() {
    await chrome.storage.local.remove(AUTH_KEY);
  }

  async function requestGoogleAccessToken() {
    const redirectUri = chrome.identity.getRedirectURL('keepit');
    const params = new URLSearchParams({
      client_id: config().oauthClientId,
      response_type: 'token',
      redirect_uri: redirectUri,
      scope: 'openid email profile',
      prompt: 'select_account',
    });
    const resultUrl = await chrome.identity.launchWebAuthFlow({
      url: `https://accounts.google.com/o/oauth2/v2/auth?${params}`,
      interactive: true,
    });
    const fragment = resultUrl.includes('#') ? resultUrl.split('#')[1] : '';
    const values = new URLSearchParams(fragment);
    const error = values.get('error');
    if (error) throw new Error(`Google sign-in failed: ${error}`);
    const accessToken = values.get('access_token');
    if (!accessToken) throw new Error('Google did not return an access token.');
    return accessToken;
  }

  async function exchangeGoogleToken(accessToken) {
    const response = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=${encodeURIComponent(config().apiKey)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          postBody: `access_token=${encodeURIComponent(accessToken)}&providerId=google.com`,
          requestUri: chrome.identity.getRedirectURL('keepit'),
          providerId: 'google.com',
          returnSecureToken: true,
          returnIdpCredential: false,
        }),
      },
    );
    const payload = await response.json();
    if (!response.ok || !payload.idToken) {
      throw new Error(payload.error?.message || 'Firebase Google sign-in failed.');
    }
    return {
      idToken: payload.idToken,
      refreshToken: payload.refreshToken,
      uid: payload.localId,
      email: payload.email || null,
      expiresAt: Date.now() + Number(payload.expiresIn || 3600) * 1000,
    };
  }

  async function refreshAuth(auth) {
    const response = await fetch(
      `https://securetoken.googleapis.com/v1/token?key=${encodeURIComponent(config().apiKey)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'refresh_token',
          refresh_token: auth.refreshToken,
        }),
      },
    );
    const payload = await response.json();
    if (!response.ok || !payload.id_token) {
      await clearAuth();
      throw new Error(payload.error?.message || 'Firebase session expired.');
    }
    const next = {
      ...auth,
      idToken: payload.id_token,
      refreshToken: payload.refresh_token || auth.refreshToken,
      uid: payload.user_id || auth.uid,
      expiresAt: Date.now() + Number(payload.expires_in || 3600) * 1000,
    };
    await saveAuth(next);
    return next;
  }

  async function ensureAuth(interactive) {
    if (!isConfigured()) return null;
    let auth = await getAuth();
    if (auth && auth.idToken && Number(auth.expiresAt) > Date.now() + AUTH_SKEW_MS) {
      return auth;
    }
    if (auth && auth.refreshToken) {
      try {
        return await refreshAuth(auth);
      } catch (_) {
        auth = null;
      }
    }
    if (!interactive) return null;
    const googleToken = await requestGoogleAccessToken();
    auth = await exchangeGoogleToken(googleToken);
    await saveAuth(auth);
    return auth;
  }

  async function authorizedFetch(url, options, auth, retry = true) {
    const headers = new Headers(options?.headers || {});
    headers.set('Authorization', `Bearer ${auth.idToken}`);
    const response = await fetch(url, { ...options, headers });
    if (response.status === 401 && retry && auth.refreshToken) {
      const refreshed = await refreshAuth(auth);
      return authorizedFetch(url, options, refreshed, false);
    }
    return response;
  }

  function firestoreValue(value) {
    if (value === null || value === undefined) return { nullValue: 'NULL_VALUE' };
    if (value instanceof Date) return { timestampValue: value.toISOString() };
    if (typeof value === 'boolean') return { booleanValue: value };
    if (typeof value === 'number' && Number.isInteger(value)) {
      return { integerValue: String(value) };
    }
    if (typeof value === 'number') return { doubleValue: value };
    if (Array.isArray(value)) {
      return { arrayValue: { values: value.map(firestoreValue) } };
    }
    if (typeof value === 'object') {
      return {
        mapValue: {
          fields: Object.fromEntries(
            Object.entries(value).map(([key, item]) => [key, firestoreValue(item)]),
          ),
        },
      };
    }
    return { stringValue: String(value) };
  }

  function fromFirestoreValue(value) {
    if (!value || typeof value !== 'object') return null;
    if ('nullValue' in value) return null;
    if ('stringValue' in value) return value.stringValue;
    if ('booleanValue' in value) return value.booleanValue;
    if ('integerValue' in value) return Number(value.integerValue);
    if ('doubleValue' in value) return Number(value.doubleValue);
    if ('timestampValue' in value) return value.timestampValue;
    if ('arrayValue' in value) return (value.arrayValue.values || []).map(fromFirestoreValue);
    if ('mapValue' in value) return fromFirestoreFields(value.mapValue.fields || {});
    return null;
  }

  function fromFirestoreFields(fields) {
    return Object.fromEntries(
      Object.entries(fields || {}).map(([key, value]) => [key, fromFirestoreValue(value)]),
    );
  }

  function firestoreBase(uid) {
    return `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(config().projectId)}/databases/(default)/documents/users/${encodeURIComponent(uid)}/items`;
  }

  function toFirestoreItem(item) {
    const normalized = global.KeepItSchema.normalizeItem(item);
    const copy = { ...normalized };
    delete copy.isSynced;
    return {
      ...copy,
      updatedAtMs: Number(normalized.updatedAtMs),
      deleted: normalized.deleted === true,
      // Flutter's incremental pull uses this field as its server cursor.
      serverUpdatedAt: new Date(),
    };
  }

  async function pushItem(auth, item) {
    const url = `${firestoreBase(auth.uid)}/${encodeURIComponent(item.id)}`;
    const response = await authorizedFetch(url, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields: Object.fromEntries(
        Object.entries(toFirestoreItem(item)).map(([key, value]) => [key, firestoreValue(value)]),
      ) }),
    }, auth);
    if (!response.ok) {
      const payload = await response.text();
      throw new Error(`Firestore write failed (${response.status}): ${payload.slice(0, 200)}`);
    }
  }

  async function listRemoteItems(auth) {
    const response = await authorizedFetch(`${firestoreBase(auth.uid)}?pageSize=1000`, {}, auth);
    if (!response.ok) {
      const payload = await response.text();
      throw new Error(`Firestore read failed (${response.status}): ${payload.slice(0, 200)}`);
    }
    const payload = await response.json();
    return (payload.documents || []).map((document) => {
      const fields = fromFirestoreFields(document.fields || {});
      const serverUpdatedAt = Date.parse(fields.serverUpdatedAt || '') || 0;
      return {
        ...global.KeepItSchema.normalizeItem(fields),
        id: fields.id || document.name.split('/').pop(),
        serverUpdatedAt,
        isSynced: true,
      };
    });
  }

  async function syncNow({ interactive = false } = {}) {
    if (runningSync) return runningSync;
    runningSync = (async () => {
      if (!isConfigured()) {
        return { skipped: true, reason: 'Firebase config is not set.' };
      }
      const auth = await ensureAuth(interactive);
      if (!auth) return { skipped: true, reason: 'Not signed in.' };

      const localItems = (await getItems()).map(global.KeepItSchema.normalizeItem);
      const byId = new Map(localItems.map((item) => [item.id, item]));
      const remoteItems = await listRemoteItems(auth);
      let cursorMs = Number((await getState()).cursorMs || 0);
      let pulled = 0;

      for (const remote of remoteItems) {
        cursorMs = Math.max(cursorMs, remote.serverUpdatedAt || 0);
        const local = byId.get(remote.id);
        if (remote.deleted) {
          if (!local || local.isSynced || local.updatedAtMs <= remote.updatedAtMs) {
            byId.delete(remote.id);
            if (local) pulled += 1;
          }
          continue;
        }
        if (!local || (remote.updatedAtMs > local.updatedAtMs && local.isSynced)) {
          byId.set(remote.id, remote);
          pulled += 1;
        }
      }

      const pending = [...byId.values()].filter((item) => !item.isSynced);
      let pushed = 0;
      for (const item of pending) {
        await pushItem(auth, item);
        byId.set(item.id, { ...item, isSynced: true });
        pushed += 1;
        cursorMs = Math.max(cursorMs, Date.now());
      }

      const nextItems = [...byId.values()]
        .filter((item) => !item.deleted)
        .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
      await setItems(nextItems);
      await saveState({ cursorMs, lastSyncAt: Date.now(), uid: auth.uid });
      return { skipped: false, pulled, pushed, uid: auth.uid };
    })();

    try {
      return await runningSync;
    } finally {
      runningSync = null;
    }
  }

  async function saveLocalItem(item) {
    const current = await getItems();
    const result = global.KeepItSchema.insertOrMerge(current, item);
    await setItems(result.items);
    // Background sync never opens an interactive login prompt.
    void syncNow({ interactive: false }).catch((error) => console.warn('KeepIt sync:', error));
    return result;
  }

  async function status() {
    const auth = await getAuth();
    const state = await getState();
    return {
      configured: isConfigured(),
      signedIn: Boolean(auth?.uid),
      email: auth?.email || null,
      lastSyncAt: state.lastSyncAt || null,
    };
  }

  global.KeepItFirebaseSync = Object.freeze({
    clearAuth,
    ensureAuth,
    isConfigured,
    saveLocalItem,
    status,
    syncNow,
  });
})(globalThis);
