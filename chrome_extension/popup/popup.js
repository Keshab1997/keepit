// KeepIt Chrome Extension - Popup Logic

document.addEventListener('DOMContentLoaded', async () => {
  const pageTitleEl = document.getElementById('pageTitle');
  const pageUrlEl = document.getElementById('pageUrl');
  const tagsInput = document.getElementById('tagsInput');
  const saveBtn = document.getElementById('saveBtn');
  const statusMsg = document.getElementById('statusMsg');
  const suggestedTags = document.querySelectorAll('.tag-chip');

  // 1. Get current active browser tab
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  
  if (tab) {
    pageTitleEl.textContent = tab.title || "Untitled Webpage";
    pageUrlEl.textContent = tab.url ? new URL(tab.url).hostname : "";
  }

  // 2. Chip click toggles tag in input
  suggestedTags.forEach(chip => {
    chip.addEventListener('click', () => {
      chip.classList.toggle('active');
      const tagText = chip.textContent.replace('#', '').trim();
      let currentTags = tagsInput.value.split(',').map(t => t.trim()).filter(Boolean);
      
      if (currentTags.includes(tagText)) {
        currentTags = currentTags.filter(t => t !== tagText);
      } else {
        currentTags.push(tagText);
      }
      tagsInput.value = currentTags.join(', ');
    });
  });

  // 3. Save Button Handler
  saveBtn.addEventListener('click', async () => {
    const rawTags = tagsInput.value.split(',').map(t => t.trim()).filter(Boolean);
    const timestamp = new Date().toISOString();

    const newItem = {
      id: "web_" + Date.now(),
      title: tab ? tab.title : "Saved Item",
      url: tab ? tab.url : "",
      thumbnailUrl: tab && tab.favIconUrl ? tab.favIconUrl : null,
      type: "webArticle",
      tags: rawTags.length > 0 ? rawTags : ["quick-save"],
      createdAt: timestamp,
      updatedAt: timestamp,
      isSynced: false
    };

    // Save to local chrome storage
    const result = await chrome.storage.local.get({ keepit_items: [] });
    const items = result.keepit_items;
    items.unshift(newItem);
    await chrome.storage.local.set({ keepit_items: items });

    // UI feedback
    saveBtn.style.display = 'none';
    statusMsg.style.display = 'block';

    setTimeout(() => {
      window.close();
    }, 1200);
  });
});
