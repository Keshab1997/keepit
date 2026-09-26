const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const handlers = { contextClick: null, command: null };
const saved = [];
const openedTabs = [];
const event = (key) => ({ addListener: (listener) => { handlers[key] = listener; } });
const chrome = {
  notifications: { create: () => {} },
  alarms: { create: () => {}, onAlarm: event('alarm') },
  runtime: { onInstalled: event('installed'), onStartup: event('startup'), onMessage: event('message') },
  contextMenus: { create: () => {}, onClicked: event('contextClick') },
  commands: { onCommand: event('command') },
  tabs: { create: async (tab) => openedTabs.push(tab), query: async () => [] },
  scripting: { executeScript: async () => [{ result: { title: 'Instagram', siteName: 'Instagram' } }] },
};
const context = {
  chrome,
  console,
  URL,
  Date,
  Math,
  Set,
  Promise,
  importScripts: () => {},
  KeepItFirebaseSync: {
    saveLocalItem: async (item) => {
      const normalized = context.KeepItSchema.normalizeItem(item);
      saved.push(normalized);
      return { item: normalized, duplicate: false };
    },
    syncNow: async () => ({}),
    status: async () => ({ configured: false }),
    ensureAuth: async () => null,
    clearAuth: async () => {},
  },
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(`${__dirname}/keepit-schema.js`, 'utf8'), context);
vm.runInContext(fs.readFileSync(`${__dirname}/background.js`, 'utf8'), context);

(async () => {
  const reelUrl = 'https://www.instagram.com/reel/CrAb123/?igsh=share-code';
  await handlers.contextClick({ menuItemId: 'keepit_save_page', pageUrl: reelUrl }, {
    id: 1, url: reelUrl, title: 'Instagram',
  });
  assert.equal(saved[0].type, 'instagramReel');
  assert.equal(saved[0].url, 'https://www.instagram.com/reel/CrAb123/');
  assert.match(saved[0].title, /Instagram Reel.*CrAb123/);

  await handlers.contextClick({ menuItemId: 'keepit_save_link', linkUrl: reelUrl }, {
    id: 2, url: 'https://example.com/story', title: 'An unrelated page',
  });
  assert.equal(saved[1].type, 'instagramReel');
  assert.equal(saved[1].url, 'https://www.instagram.com/reel/CrAb123/');
  assert.match(saved[1].title, /Instagram Reel.*CrAb123/);

  await handlers.command('open_keepit_web');
  assert.equal(openedTabs[0].url, 'https://keepit-web-peach.vercel.app');
  console.log('KeepIt extension background tests passed: Instagram page/link capture and web shortcut.');
})().catch((error) => { console.error(error); process.exitCode = 1; });
