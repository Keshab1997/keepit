// KeepIt Chrome Extension - Background Service Worker

// 1. Setup Context Menus on Installation
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "keepit_save_page",
    title: "🧠 Save page to KeepIt",
    contexts: ["page"]
  });

  chrome.contextMenus.create({
    id: "keepit_save_link",
    title: "🔗 Save link to KeepIt",
    contexts: ["link"]
  });

  chrome.contextMenus.create({
    id: "keepit_save_selection",
    title: "📝 Save quote to KeepIt",
    contexts: ["selection"]
  });

  chrome.contextMenus.create({
    id: "keepit_save_image",
    title: "🖼️ Save image to KeepIt",
    contexts: ["image"]
  });
});

// 2. Handle Context Menu Clicks
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const timestamp = new Date().toISOString();
  let newItem = {
    id: "item_" + Date.now(),
    createdAt: timestamp,
    updatedAt: timestamp,
    isSynced: false
  };

  if (info.menuItemId === "keepit_save_selection") {
    newItem.title = info.selectionText.slice(0, 80) + (info.selectionText.length > 80 ? "..." : "");
    newItem.content = info.selectionText;
    newItem.url = tab.url;
    newItem.type = "quote";
    newItem.tags = ["quote", "web"];
  } else if (info.menuItemId === "keepit_save_image") {
    newItem.title = "Saved Image from " + (new URL(tab.url).hostname);
    newItem.thumbnailUrl = info.srcUrl;
    newItem.url = tab.url;
    newItem.type = "image";
    newItem.tags = ["image", "visual"];
  } else if (info.menuItemId === "keepit_save_link") {
    newItem.title = info.linkUrl;
    newItem.url = info.linkUrl;
    newItem.type = "webArticle";
    newItem.tags = ["link"];
  } else {
    // Current Page
    newItem.title = tab.title || "Saved Webpage";
    newItem.url = tab.url;
    newItem.type = "webArticle";
    newItem.tags = ["bookmark"];
  }

  // Save to local chrome storage
  await saveToLocalKeepIt(newItem);

  // Show notification
  chrome.notifications.create({
    type: "basic",
    iconUrl: "icons/icon128.png",
    title: "Saved to KeepIt! 🧠",
    message: newItem.title
  });
});

// 3. Handle Keyboard Shortcuts (Alt + S)
chrome.commands.onCommand.addListener(async (command) => {
  if (command === "save_current_page") {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab) {
      const newItem = {
        id: "item_" + Date.now(),
        title: tab.title || "Saved Page",
        url: tab.url,
        type: "webArticle",
        tags: ["bookmark", "quick-save"],
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        isSynced: false
      };
      await saveToLocalKeepIt(newItem);
      chrome.notifications.create({
        type: "basic",
        iconUrl: "icons/icon128.png",
        title: "Saved to KeepIt! ⚡",
        message: tab.title
      });
    }
  }
});

async function saveToLocalKeepIt(item) {
  const result = await chrome.storage.local.get({ keepit_items: [] });
  const items = result.keepit_items;
  items.unshift(item);
  await chrome.storage.local.set({ keepit_items: items });
}
