// KeepIt Chrome Extension popup.

const KEEPIT_WEB_URL = 'https://keepit-web-peach.vercel.app';

async function sendMessage(type, payload = {}) {
  const response = await chrome.runtime.sendMessage({ type, ...payload });
  if (!response?.ok) throw new Error(response?.error || 'KeepIt background service failed.');
  return response.result;
}

function setStatus(element, message, error = false) {
  element.textContent = message;
  element.classList.toggle('error', error);
}

function pageItem(tab, tags) {
  const reel = KeepItSchema.instagramReelInfo(tab?.url || '');
  const type = KeepItSchema.detectType(tab?.url || '');
  const titleFromTab = String(tab?.title || '').trim();
  const title = reel && (!titleFromTab || titleFromTab.toLowerCase() === 'instagram')
    ? `Instagram Reel · ${reel.shortcode}`
    : (titleFromTab || 'Saved webpage');
  const now = new Date().toISOString();
  const fallbackTags = reel ? ['instagram', 'reels', 'video'] : type === 'youtubeVideo' ? ['youtube', 'video'] : ['bookmark'];
  return {
    id: `chrome_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    title,
    url: reel ? reel.url : KeepItSchema.normalizeUrl(tab?.url || ''),
    type,
    tags: tags.length ? tags : fallbackTags,
    isWatched: false,
    isTopMind: false,
    createdAt: now,
    updatedAt: now,
  };
}

function isWebTab(tab) {
  return Boolean(tab?.url && (tab.url.startsWith('https://') || tab.url.startsWith('http://')));
}

function hostname(rawUrl) {
  try {
    let host = new URL(rawUrl).hostname;
    if (host.startsWith('www.')) host = host.slice(4);
    return host;
  } catch { return ''; }
}

document.addEventListener('DOMContentLoaded', async () => {
  const pageTitleEl = document.getElementById('pageTitle');
  const pageUrlEl = document.getElementById('pageUrl');
  const siteLabel = document.getElementById('siteLabel');
  const typePill = document.getElementById('typePill');
  const tagsInput = document.getElementById('tagsInput');
  const saveBtn = document.getElementById('saveBtn');
  const statusMsg = document.getElementById('statusMsg');
  const cloudStatus = document.getElementById('cloudStatus');
  const cloudHint = document.getElementById('cloudHint');
  const connectBtn = document.getElementById('connectBtn');
  const syncBtn = document.getElementById('syncBtn');
  const sendPageBtn = document.getElementById('sendPageBtn');
  const sendSelectionBtn = document.getElementById('sendSelectionBtn');
  const openWebBtn = document.getElementById('openWebBtn');
  const openDesktopBtn = document.getElementById('openDesktopBtn');
  const desktopShortcut = document.getElementById('desktopShortcut');
  const tagChips = [...document.querySelectorAll('.chip[data-tag]')];

  let tab = null;
  try {
    [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab && isWebTab(tab)) {
      const reel = KeepItSchema.instagramReelInfo(tab.url);
      const type = KeepItSchema.detectType(tab.url);
      const currentTitle = String(tab.title || '').trim();
      const displayTitle = reel && (!currentTitle || currentTitle.toLowerCase() === 'instagram')
        ? `Instagram Reel · ${reel.shortcode}`
        : (currentTitle || 'Untitled webpage');
      pageTitleEl.textContent = displayTitle;
      siteLabel.textContent = hostname(tab.url) || 'Website';
      pageUrlEl.textContent = reel?.url || tab.url;
      typePill.textContent = type === 'instagramReel' ? 'Instagram Reel' : type === 'youtubeVideo' ? 'YouTube' : 'Web link';
      typePill.setAttribute('aria-label', typePill.textContent);
      if (!tagsInput.value) tagsInput.value = reel ? 'instagram, reels, video' : type === 'youtubeVideo' ? 'youtube, video' : 'bookmark';
    } else {
      pageTitleEl.textContent = tab?.title || 'This tab cannot be saved';
      siteLabel.textContent = 'Unsupported tab';
      pageUrlEl.textContent = 'Open a regular webpage to save it.';
      typePill.textContent = 'NOT WEB';
      saveBtn.disabled = true;
      sendPageBtn.disabled = true;
      sendSelectionBtn.disabled = true;
    }
  } catch (error) {
    pageTitleEl.textContent = 'Could not read current tab';
    siteLabel.textContent = 'Tab unavailable';
    setStatus(statusMsg, error.message || 'Could not read the active tab.', true);
  }

  const isMac = /Mac|iPhone|iPad/.test(navigator.platform || '');
  desktopShortcut.textContent = isMac ? 'Desktop app: ⌘⌥K' : 'Desktop app: Ctrl+Alt+K';

  function updateChips() {
    const active = new Set(KeepItSchema.cleanTags(tagsInput.value));
    for (const chip of tagChips) chip.classList.toggle('active', active.has(chip.dataset.tag));
  }
  updateChips();
  tagsInput.addEventListener('input', updateChips);
  for (const chip of tagChips) {
    chip.addEventListener('click', () => {
      const tag = chip.dataset.tag;
      const current = KeepItSchema.cleanTags(tagsInput.value);
      const next = current.some((value) => value.toLowerCase() === tag)
        ? current.filter((value) => value.toLowerCase() !== tag)
        : [...current, tag];
      tagsInput.value = next.join(', ');
      updateChips();
    });
  }

  async function refreshCloudStatus() {
    try {
      const status = await sendMessage('get_sync_status');
      if (!status.configured) {
        cloudStatus.textContent = 'Local-only mode';
        cloudHint.textContent = 'You can still save to this browser without signing in.';
        connectBtn.hidden = true;
        syncBtn.hidden = true;
      } else if (status.signedIn) {
        cloudStatus.textContent = status.email ? `Synced as ${status.email}` : 'KeepIt Cloud connected';
        cloudHint.textContent = 'Your saved items sync across devices.';
        connectBtn.textContent = 'Disconnect';
        connectBtn.hidden = false;
        syncBtn.hidden = false;
      } else {
        cloudStatus.textContent = 'Cloud sync is ready';
        cloudHint.textContent = 'Connect once to sync this browser with your account.';
        connectBtn.textContent = 'Connect';
        connectBtn.hidden = false;
        syncBtn.hidden = true;
      }
    } catch (error) {
      setStatus(statusMsg, error.message || 'Could not check cloud sync.', true);
    }
  }

  connectBtn.addEventListener('click', async () => {
    connectBtn.disabled = true;
    try {
      const action = connectBtn.textContent === 'Disconnect' ? 'disconnect_firebase' : 'connect_firebase';
      const result = await sendMessage(action);
      setStatus(statusMsg, result?.uid ? 'Cloud sync connected.' : 'Cloud account disconnected.');
      await refreshCloudStatus();
    } catch (error) {
      setStatus(statusMsg, error.message || 'Could not update cloud sync.', true);
    } finally { connectBtn.disabled = false; }
  });

  syncBtn.addEventListener('click', async () => {
    syncBtn.disabled = true;
    try {
      const result = await sendMessage('sync_now');
      setStatus(statusMsg, `Synced · ${result?.pushed || 0} uploaded, ${result?.pulled || 0} downloaded.`);
    } catch (error) {
      setStatus(statusMsg, error.message || 'Sync failed.', true);
    } finally { syncBtn.disabled = false; }
  });

  openWebBtn.addEventListener('click', async () => {
    try {
      await chrome.tabs.create({ url: KEEPIT_WEB_URL });
      setStatus(statusMsg, 'Opened KeepIt Web in a new tab.');
    } catch (error) {
      setStatus(statusMsg, error.message || 'Could not open KeepIt Web.', true);
    }
  });
  openDesktopBtn.addEventListener('click', () => {
    setStatus(statusMsg, 'Opening the installed KeepIt Desktop app…');
  });

  async function sendToDesktop(item, button, successMessage) {
    button.disabled = true;
    try {
      const response = await fetch('http://127.0.0.1:43819/api/desktop-bridge', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(item),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error || 'KeepIt Desktop is unavailable. Open the desktop app and try again.');
      setStatus(statusMsg, successMessage);
    } catch (error) {
      setStatus(statusMsg, error.message || 'Could not reach KeepIt Desktop.', true);
    } finally { button.disabled = false; }
  }

  saveBtn.addEventListener('click', async () => {
    if (!isWebTab(tab)) return;
    saveBtn.disabled = true;
    const oldText = saveBtn.textContent;
    saveBtn.textContent = 'Saving…';
    try {
      const item = pageItem(tab, KeepItSchema.cleanTags(tagsInput.value));
      const result = await sendMessage('save_item', { item, tabId: tab.id, tabUrl: tab.url });
      saveBtn.textContent = result?.duplicate ? 'Updated in KeepIt ✓' : 'Saved to KeepIt ✓';
      setStatus(statusMsg, result?.duplicate ? 'Found it already—refreshed its tags and details.' : 'Added to your KeepIt library.');
      window.setTimeout(() => { saveBtn.textContent = oldText; saveBtn.disabled = false; }, 1400);
    } catch (error) {
      saveBtn.textContent = oldText;
      saveBtn.disabled = false;
      setStatus(statusMsg, error.message || 'Could not save this page.', true);
    }
  });

  sendPageBtn.addEventListener('click', async () => {
    if (!isWebTab(tab)) return;
    await sendToDesktop(pageItem(tab, KeepItSchema.cleanTags(tagsInput.value)), sendPageBtn, 'Sent this page to KeepIt Desktop.');
  });

  sendSelectionBtn.addEventListener('click', async () => {
    if (!isWebTab(tab) || !tab?.id) return;
    sendSelectionBtn.disabled = true;
    try {
      const result = await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => window.getSelection()?.toString() || '',
      });
      const selection = String(result?.[0]?.result || '').trim().slice(0, 20_000);
      if (!selection) throw new Error('Select some page text first, then try again.');
      const now = new Date().toISOString();
      const item = {
        id: `chrome_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        title: selection.slice(0, 100) || 'Saved quote',
        url: KeepItSchema.normalizeUrl(tab.url), content: selection,
        type: 'quote', tags: ['quote', hostname(tab.url)],
        isWatched: false, isTopMind: false, createdAt: now, updatedAt: now,
      };
      await sendToDesktop(item, sendSelectionBtn, 'Sent your selection to KeepIt Desktop.');
    } catch (error) {
      setStatus(statusMsg, error.message || 'Could not read that selection.', true);
    } finally { sendSelectionBtn.disabled = false; }
  });

  await refreshCloudStatus();
});
