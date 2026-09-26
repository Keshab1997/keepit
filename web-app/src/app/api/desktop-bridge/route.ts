import { enqueueDesktopItem, type DesktopBridgeItem } from "@/lib/desktop-bridge";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const EXTENSION_ORIGIN = /^chrome-extension:\/\/[a-p]{32}$/;
const ITEM_TYPES = new Set(["webArticle", "quote", "image", "instagramReel", "youtubeVideo", "quickNote"]);

function corsHeaders(origin: string) {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Private-Network": "true",
    "Access-Control-Max-Age": "600",
    "Vary": "Origin",
    "Cache-Control": "no-store",
  };
}

export function OPTIONS(request: Request) {
  const origin = request.headers.get("origin") ?? "";
  if (!EXTENSION_ORIGIN.test(origin)) return new Response(null, { status: 403 });
  return new Response(null, { status: 204, headers: corsHeaders(origin) });
}

export async function POST(request: Request) {
  const origin = request.headers.get("origin") ?? "";
  if (!process.env.KEEPIT_DESKTOP_BOOT_TOKEN) {
    return Response.json({ error: "Desktop bridge is unavailable." }, { status: 404 });
  }
  if (!EXTENSION_ORIGIN.test(origin)) {
    return Response.json({ error: "Only the KeepIt browser extension can send items." }, { status: 403 });
  }
  let body: string;
  try { body = await request.text(); }
  catch { return Response.json({ error: "Could not read request body." }, { status: 400, headers: corsHeaders(origin) }); }
  if (new TextEncoder().encode(body).byteLength > 256_000) {
    return Response.json({ error: "Item is too large." }, { status: 413, headers: corsHeaders(origin) });
  }

  let raw: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(body);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("object required");
    raw = parsed as Record<string, unknown>;
  } catch { return Response.json({ error: "Invalid JSON." }, { status: 400, headers: corsHeaders(origin) }); }

  const title = typeof raw.title === "string" ? raw.title.trim().slice(0, 300) : "";
  const id = typeof raw.id === "string" ? raw.id.trim().slice(0, 120) : "";
  const type = typeof raw.type === "string" && ITEM_TYPES.has(raw.type) ? raw.type as DesktopBridgeItem["type"] : "webArticle";
  if (!id || !title) return Response.json({ error: "A title and item id are required." }, { status: 400, headers: corsHeaders(origin) });

  let url: string | undefined;
  if (typeof raw.url === "string" && raw.url.trim()) {
    try {
      const parsed = new URL(raw.url.trim());
      if (!["http:", "https:"].includes(parsed.protocol)) throw new Error("unsupported URL");
      url = parsed.toString().slice(0, 2048);
    } catch {
      return Response.json({ error: "Only http/https links can be sent to desktop." }, { status: 400, headers: corsHeaders(origin) });
    }
  }

  const now = new Date().toISOString();
  const safeTags = Array.isArray(raw.tags)
    ? raw.tags.filter((tag): tag is string => typeof tag === "string").map((tag) => tag.trim().replace(/^#/, "").slice(0, 64)).filter(Boolean).slice(0, 20)
    : ["browser"];
  const item: DesktopBridgeItem = {
    id,
    title,
    ...(url ? { url } : {}),
    ...(typeof raw.content === "string" ? { content: raw.content.slice(0, 20_000) } : {}),
    ...(typeof raw.thumbnailUrl === "string" && /^https:\/\//i.test(raw.thumbnailUrl) ? { thumbnailUrl: raw.thumbnailUrl.slice(0, 2048) } : {}),
    ...(typeof raw.authorName === "string" ? { authorName: raw.authorName.slice(0, 200) } : {}),
    type,
    tags: safeTags,
    isWatched: raw.isWatched === true,
    isTopMind: raw.isTopMind === true,
    createdAt: typeof raw.createdAt === "string" && Number.isFinite(Date.parse(raw.createdAt)) ? raw.createdAt : now,
    updatedAt: typeof raw.updatedAt === "string" && Number.isFinite(Date.parse(raw.updatedAt)) ? raw.updatedAt : now,
  };

  enqueueDesktopItem(item);
  return Response.json({ queued: true }, { status: 202, headers: corsHeaders(origin) });
}

export async function GET(request: Request) {
  const token = process.env.KEEPIT_DESKTOP_BOOT_TOKEN;
  if (!token || request.headers.get("x-keepit-desktop-boot-token") !== token) {
    return new Response(null, { status: 404, headers: { "Cache-Control": "no-store" } });
  }

  const { dequeueDesktopItem } = await import("@/lib/desktop-bridge");
  const item = dequeueDesktopItem();
  return Response.json({ item }, { headers: { "Cache-Control": "no-store" } });
}
