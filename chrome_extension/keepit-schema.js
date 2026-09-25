// Shared KeepIt item schema and URL normalization helpers.
// Loaded by the MV3 service worker. It is intentionally dependency-free so the
// extension keeps working in local-only mode when Firebase is not configured.
(function (global) {
  'use strict';

  const ITEM_TYPES = new Set([
    'instagramReel',
    'youtubeVideo',
    'webArticle',
    'quote',
    'image',
    'quickNote',
  ]);

  const TRACKING_PARAMS = /^(utm_[^=]*|fbclid|gclid|dclid|igsh|si|mc_cid|mc_eid|ref|ref_src)$/i;

  function toIso(value, fallbackMs) {
    const parsed = value instanceof Date ? value.getTime() : Date.parse(value || '');
    const ms = Number.isFinite(parsed) ? parsed : fallbackMs;
    return new Date(ms).toISOString();
  }

  function normalizeUrl(value) {
    const input = String(value || '').trim();
    if (!input) return '';

    try {
      const url = new URL(input);
      if (url.protocol !== 'http:' && url.protocol !== 'https:') return input.toLowerCase();
      url.protocol = url.protocol.toLowerCase();
      url.hostname = url.hostname.toLowerCase();
      if ((url.protocol === 'https:' && url.port === '443') ||
          (url.protocol === 'http:' && url.port === '80')) {
        url.port = '';
      }
      url.hash = '';
      for (const key of [...url.searchParams.keys()]) {
        if (TRACKING_PARAMS.test(key)) url.searchParams.delete(key);
      }
      url.searchParams.sort();
      url.pathname = url.pathname.replace(/\/{2,}/g, '/').replace(/\/$/, '') || '/';
      return url.toString();
    } catch (_) {
      return input.toLowerCase().replace(/\/+$/, '');
    }
  }

  function cleanTags(tags) {
    const values = Array.isArray(tags) ? tags : String(tags || '').split(',');
    const result = [];
    const seen = new Set();
    for (const value of values) {
      const tag = String(value || '').trim().replace(/^#/, '');
      const key = tag.toLowerCase();
      if (!tag || seen.has(key)) continue;
      seen.add(key);
      result.push(tag);
    }
    return result.slice(0, 50);
  }

  function normalizeItem(raw) {
    const source = raw && typeof raw === 'object' ? raw : {};
    const now = Date.now();
    const updatedAtMs = Number.isFinite(Number(source.updatedAtMs))
      ? Number(source.updatedAtMs)
      : (Date.parse(source.updatedAt || '') || now);
    const createdAt = toIso(source.createdAt, now);
    const updatedAt = toIso(source.updatedAt, updatedAtMs);
    const url = source.url ? String(source.url).trim() : null;
    const title = String(source.title || url || 'Saved item').trim() || 'Saved item';
    const type = ITEM_TYPES.has(source.type) ? source.type : 'webArticle';

    return {
      id: String(source.id || `item_${now}_${Math.random().toString(36).slice(2, 8)}`),
      title: title.slice(0, 500),
      url: url ? url.slice(0, 4000) : null,
      content: source.content == null ? null : String(source.content).slice(0, 19000),
      thumbnailUrl: source.thumbnailUrl == null ? null : String(source.thumbnailUrl),
      authorName: source.authorName == null ? null : String(source.authorName),
      authorAvatar: source.authorAvatar == null ? null : String(source.authorAvatar),
      type,
      tags: cleanTags(source.tags),
      spaceId: source.spaceId == null ? null : String(source.spaceId),
      isWatched: source.isWatched === true,
      isTopMind: source.isTopMind === true,
      dominantColorHex: source.dominantColorHex == null ? null : String(source.dominantColorHex),
      createdAt,
      updatedAt,
      updatedAtMs,
      deleted: source.deleted === true,
      // Local-only flag. Firebase sync removes this before upload.
      isSynced: source.isSynced === true,
    };
  }

  function fingerprint(item) {
    const url = normalizeUrl(item && item.url);
    if (url) return `url:${url}`;
    return `text:${String(item && item.title || '').trim().toLowerCase()}`;
  }

  function mergeItems(existing, incoming) {
    const oldItem = normalizeItem(existing);
    const newItem = normalizeItem(incoming);
    const now = Date.now();
    return normalizeItem({
      ...oldItem,
      ...newItem,
      id: oldItem.id,
      createdAt: oldItem.createdAt,
      title: newItem.title || oldItem.title,
      url: newItem.url || oldItem.url,
      content: newItem.content || oldItem.content,
      thumbnailUrl: newItem.thumbnailUrl || oldItem.thumbnailUrl,
      tags: cleanTags([...oldItem.tags, ...newItem.tags]),
      updatedAt: new Date(now).toISOString(),
      updatedAtMs: now,
      deleted: false,
      isSynced: false,
    });
  }

  function insertOrMerge(items, rawItem) {
    const incoming = normalizeItem(rawItem);
    const list = Array.isArray(items) ? items.map(normalizeItem) : [];
    const index = list.findIndex((item) => fingerprint(item) === fingerprint(incoming));
    if (index < 0) return { items: [incoming, ...list], item: incoming, duplicate: false };

    const merged = mergeItems(list[index], incoming);
    const next = [...list];
    next[index] = merged;
    return { items: next, item: merged, duplicate: true };
  }

  global.KeepItSchema = Object.freeze({
    cleanTags,
    fingerprint,
    insertOrMerge,
    mergeItems,
    normalizeItem,
    normalizeUrl,
  });
})(globalThis);
