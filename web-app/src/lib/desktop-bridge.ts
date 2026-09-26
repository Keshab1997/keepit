export type DesktopBridgeItem = {
  id: string;
  title: string;
  url?: string;
  content?: string;
  thumbnailUrl?: string;
  authorName?: string;
  type: "webArticle" | "quote" | "image" | "instagramReel" | "youtubeVideo" | "quickNote";
  tags: string[];
  isWatched: boolean;
  isTopMind: boolean;
  createdAt: string;
  updatedAt: string;
};

type QueueEntry = { item: DesktopBridgeItem; queuedAt: number };
type BridgeGlobal = typeof globalThis & { __keepitDesktopBridgeQueue?: QueueEntry[] };

function queue(): QueueEntry[] {
  const root = globalThis as BridgeGlobal;
  root.__keepitDesktopBridgeQueue ??= [];
  return root.__keepitDesktopBridgeQueue;
}

export function enqueueDesktopItem(item: DesktopBridgeItem) {
  const entries = queue();
  if (entries.length >= 50) entries.shift();
  entries.push({ item, queuedAt: Date.now() });
}

export function dequeueDesktopItem(): DesktopBridgeItem | null {
  const entries = queue();
  const cutoff = Date.now() - 10 * 60 * 1000;
  while (entries.length && entries[0].queuedAt < cutoff) entries.shift();
  return entries.shift()?.item ?? null;
}
