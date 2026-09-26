const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync(`${__dirname}/keepit-schema.js`, 'utf8');
const context = { console, URL, Set, Date, Math };
vm.runInNewContext(source, context, { filename: 'keepit-schema.js' });
const schema = context.KeepItSchema;

assert.equal(
  schema.normalizeUrl('HTTPS://Example.com:443/path/?utm_source=x&b=2&fbclid=y&a=1#section'),
  'https://example.com/path?a=1&b=2',
);

const first = schema.insertOrMerge([], {
  id: 'first',
  title: 'Article',
  url: 'https://example.com/article?utm_campaign=launch',
  tags: ['read', '#dev'],
  type: 'webArticle',
});
assert.equal(first.duplicate, false);

const second = schema.insertOrMerge(first.items, {
  id: 'second',
  title: 'Article (updated)',
  url: 'https://example.com/article',
  tags: ['dev', 'important'],
  type: 'webArticle',
});
assert.equal(second.duplicate, true);
assert.equal(second.items.length, 1);
assert.equal(second.item.id, 'first');
assert.deepEqual(Array.from(second.item.tags), ['read', 'dev', 'important']);

const reel = schema.instagramReelInfo('https://www.instagram.com/reel/CrAb123/?igsh=abc&utm_source=share');
assert.equal(reel.shortcode, 'CrAb123');
assert.equal(reel.url, 'https://www.instagram.com/reel/CrAb123/');
assert.equal(schema.detectType('https://m.instagram.com/reels/CrAb123/?igsh=abc'), 'instagramReel');
assert.equal(schema.normalizeUrl('https://www.instagram.com/reel/CrAb123/?igsh=abc'), reel.url);
assert.equal(schema.detectType('https://youtube.com/shorts/abc123'), 'youtubeVideo');
const reelItem = schema.normalizeItem({ id: 'reel', title: 'Instagram', url: reel.url, type: 'webArticle' });
assert.equal(reelItem.type, 'instagramReel');
assert.equal(schema.normalizeItem({ id: 'quote', title: 'Quote', url: reel.url, type: 'quote' }).type, 'quote');
assert.equal(schema.instagramReelInfo('https://example.com/reel/CrAb123/'), null);

console.log('KeepIt extension schema tests passed.');
