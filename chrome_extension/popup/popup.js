// KeepIt Chrome Extension - Popup Logic

async function sendMessage(type, payload = {}) {
  const response = await chrome.runtime.sendMessage({ type, ...payload });
  if (!response?.ok) {
    throw new Error(response?.error || 'KeepIt background service failed.');
  }
  return response.result;
}

function setStatus(element, message, error = false) {
  element.textContent = message;
  element.style.color = error ? '#DC2626' : '#10B981';
}

document.addEventListener('DOMContentLoaded', async () => {
  const pageTitleEl = document.getElementById('pageTitle');
  const pageUrlEl = document.getElementById('pageUrl');
  const tagsInput = document.getElementById('tagsInput');
  const saveBtn = document.getElementById('saveBtn');
  const statusMsg = document.getElementById('statusMsg');
  const cloudStatus = document.getElementById('cloudStatus');
  const connectBtn = document.getElementById('connectBtn');
  const syncBtn = document.getElementById('syncBtn');
  const suggestedTags = document.querySelectorAll('.tag-chip');

  let tab = null;
  try {
    [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab) {
      pageTitleEl.textContent = tab.title || 'Untitled Webpage';
      pageUrlEl.textContent = tab.url ? new URL(tab.url).hostname : '';
    }
  } catch (error) {
    pageTitleEl.textContent = 'Could not read current page';
    setStatus(statusMsg, error.message, true);
  }

  async function refreshCloudStatus() {
    try {
      const status = await sendMessage('get_sync_status');
      if (!status.configured) {
        cloudStatus.textContent = 'Local-only mode · add Firebase config to enable sync';
        connectBtn.style.display = 'none';
        syncBtn.style.display = 'none';
      } else if (status.signedIn) {
        cloudStatus.textContent = status.email
          ? `Synced as ${status.email}`
          : 'Connected to KeepIt cloud';
        connectBtn.textContent = 'Disconnect';
        syncBtn.style.display = 'inline-flex';
      } else {
        cloudStatus.textContent = 'Cloud sync is ready';
        connectBtn.textContent = 'Connect';
        syncBtn.style.display = 'none';
      }
    } catch (error) {
      setStatus(statusMsg, error.message, true);
    }
  }

  suggestedTags.forEach((chip) => {
    chip.addEventListener('click', () => {
      chip.classList.toggle('active');
      const tagText = chip.textContent.replace('#', '').trim();
      let currentTags = tagsInput.value.split(',').map((tag) => tag.trim()).filter(Boolean);
      if (currentTags.includes(tagText)) {
        currentTags = currentTags.filter((tag) => tag !== tagText);
      } else {
        currentTags.push(tagText);
      }
      tagsInput.value = currentTags.join(', ');
    });
  });

  connectBtn.addEventListener('click', async () => {
    connectBtn.disabled = true;
    try {
      const status = await sendMessage(
        connectBtn.textContent === 'Disconnect' ? 'disconnect_firebase' : 'connect_firebase',
      );
      setStatus(statusMsg, status?.uid ? 'Cloud sync connected.' : 'Disconnected.');
      await refreshCloudStatus();
    } catch (error) {
      setStatus(statusMsg, error.message, true);
    } finally {
      connectBtn.disabled = false;
    }
  });

  syncBtn.addEventListener('click', async () => {
    syncBtn.disabled = true;
    try {
      const result = await sendMessage('sync_now');
      setStatus(statusMsg, `Synced: ${result.pushed || 0} uploaded, ${result.pulled || 0} downloaded.`);
    } catch (error) {
      setStatus(statusMsg, error.message, true);
    } finally {
      syncBtn.disabled = false;
    }
  });

  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true;
    try {
      const rawTags = tagsInput.value.split(',').map((tag) => tag.trim()).filter(Boolean);
      const timestamp = new Date().toISOString();
      const result = await sendMessage('save_item', {
        item: {
          id: `web_${Date.now()}`,
          title: tab?.title || 'Saved Item',
          url: tab?.url || '',
          thumbnailUrl: tab?.favIconUrl || null,
          type: 'webArticle',
          tags: rawTags.length > 0 ? rawTags : ['quick-save'],
          createdAt: timestamp,
          updatedAt: timestamp,
        },
      });
      saveBtn.style.display = 'none';
      setStatus(
        statusMsg,
        result.duplicate ? '✨ Updated the existing KeepIt item!' : '✨ Saved to your KeepIt Brain!',
      );
      setTimeout(() => window.close(), 1200);
    } catch (error) {
      setStatus(statusMsg, error.message, true);
      saveBtn.disabled = false;
    }
  });

  await refreshCloudStatus();
});
