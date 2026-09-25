// KeepIt Chrome Extension - MV3 Background Service Worker
// Local-first saves are handled here so context menus, shortcuts and the popup
// all use the same schema, duplicate detection and Firebase sync queue.

importScripts('keepit-schema.js', 'firebase-config.js', 'firebase-sync.js');

const SYNC_ALARM = 'keepit_periodic_sync';

function timestamp() {
  return new Date().toISOString();
}

function notifySaved(item, duplicate) {
  chrome.notifications.create({
    type: 'basic',
    iconUrl: 'icons/icon128.png',
    title: duplicate ? 'Updated in KeepIt' : 'Saved to KeepIt! 🧠',
    message: item.title,
  });
}

async function readPageMetadata(tabId) {
  if (!tabId) return {};
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId },
      func: () => {
        const meta = (selector) => document.querySelector(selector)?.content?.trim() || '';
        const first = (...selectors) => {
          for (const selector of selectors) {
            const value = meta(selector);
            if (value) return value;
          }
          return '';
        };
        return {
          title: first('meta[property="og:title"]', 'meta[name="twitter:title"]') || document.title,
          content: first(
            'meta[property="og:description"]',
            'meta[name="twitter:description"]',
            'meta[name="description"]',
          ),
          thumbnailUrl: first(
            'meta[property="og:image"]',
            'meta[name="twitter:image"]',
          ),
          authorName: first(
            'meta[property="article:author"]',
            'meta[name="author"]',
          ),
          siteName: first('meta[property="og:site_name"]'),
        };
      },
    });
    return results[0]?.result || {};
  } catch (_) {
    // chrome:// pages and restricted tabs do not allow script injection.
    return {};
  }
}

async function enrichPageItem(rawItem, tabId) {
  if (!tabId || rawItem.type !== 'webArticle') return rawItem;
  const metadata = await readPageMetadata(tabId);
  return {
    ...rawItem,
    title: metadata.title || rawItem.title,
    content: rawItem.content || metadata.content || null,
    thumbnailUrl: rawItem.thumbnailUrl || metadata.thumbnailUrl || null,
    authorName: rawItem.authorName || metadata.authorName || metadata.siteName || null,
  };
}

async function saveItem(rawItem, tabId) {
  const enriched = await enrichPageItem(rawItem, tabId);
  const result = await KeepItFirebaseSync.saveLocalItem(enriched);
  notifySaved(result.item, result.duplicate);
  return result;
}

function itemFromContext(info, tab) {
  const pageUrl = tab?.url || info.pageUrl || info.linkUrl || '';
  const base = {
    id: `item_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    createdAt: timestamp(),
    updatedAt: timestamp(),
    url: pageUrl,
    isSynced: false,
  };

  if (info.menuItemId === 'keepit_save_selection') {
    const selection = String(info.selectionText || '').trim();
    return {
      ...base,
      title: selection.slice(0, 80) || 'Saved quote',
      content: selection,
      type: 'quote',
      tags: ['quote', 'web'],
    };
  }
  if (info.menuItemId === 'keepit_save_image') {
    let hostname = 'web';
    try {
      hostname = new URL(pageUrl).hostname;
    } catch (_) {}
    return {
      ...base,
      title: `Saved image from ${hostname}`,
      thumbnailUrl: info.srcUrl || null,
      type: 'image',
      tags: ['image', 'visual'],
    };
  }
  if (info.menuItemId === 'keepit_save_link') {
    return {
      ...base,
      title: info.linkUrl || 'Saved link',
      url: info.linkUrl || pageUrl,
      type: 'webArticle',
      tags: ['link'],
    };
  }
  return {
    ...base,
    title: tab?.title || 'Saved webpage',
    type: 'webArticle',
    tags: ['bookmark'],
  };
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: 'keepit_save_page',
    title: '🧠 Save page to KeepIt',
    contexts: ['page'],
  });
  chrome.contextMenus.create({
    id: 'keepit_save_link',
    title: '🔗 Save link to KeepIt',
    contexts: ['link'],
  });
  chrome.contextMenus.create({
    id: 'keepit_save_selection',
    title: '📝 Save quote to KeepIt',
    contexts: ['selection'],
  });
  chrome.contextMenus.create({
    id: 'keepit_save_image',
    title: '🖼️ Save image to KeepIt',
    contexts: ['image'],
  });
  chrome.alarms.create(SYNC_ALARM, { periodInMinutes: 15 });
});

chrome.runtime.onStartup.addListener(() => {
  chrome.alarms.create(SYNC_ALARM, { periodInMinutes: 15 });
  void KeepItFirebaseSync.syncNow().catch((error) => console.warn('KeepIt sync:', error));
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === SYNC_ALARM) {
    void KeepItFirebaseSync.syncNow().catch((error) => console.warn('KeepIt sync:', error));
  }
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  try {
    await saveItem(itemFromContext(info, tab), tab?.id);
  } catch (error) {
    console.error('KeepIt save failed:', error);
  }
});

chrome.commands.onCommand.addListener(async (command) => {
  if (command !== 'save_current_page') return;
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) return;
  try {
    await saveItem({
      id: `item_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
      title: tab.title || 'Saved page',
      url: tab.url || '',
      type: 'webArticle',
      tags: ['bookmark', 'quick-save'],
      createdAt: timestamp(),
      updatedAt: timestamp(),
    }, tab?.id);
  } catch (error) {
    console.error('KeepIt shortcut save failed:', error);
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    if (message?.type === 'save_item') {
      return saveItem(message.item || {}, sender.tab?.id);
    }
    if (message?.type === 'sync_now') {
      return KeepItFirebaseSync.syncNow({ interactive: false });
    }
    if (message?.type === 'connect_firebase') {
      const auth = await KeepItFirebaseSync.ensureAuth(true);
      const result = await KeepItFirebaseSync.syncNow({ interactive: false });
      return { ...result, uid: auth?.uid || null };
    }
    if (message?.type === 'get_sync_status') {
      return KeepItFirebaseSync.status();
    }
    if (message?.type === 'disconnect_firebase') {
      await KeepItFirebaseSync.clearAuth();
      return KeepItFirebaseSync.status();
    }
    return { ok: false, reason: 'Unknown message.' };
  })()
    .then((result) => sendResponse({ ok: true, result }))
    .catch((error) => sendResponse({ ok: false, error: error.message || String(error) }));
  return true;
});
