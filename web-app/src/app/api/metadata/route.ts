import { isIP } from "node:net";
import { lookup } from "node:dns/promises";
import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function isPrivateAddress(address: string): boolean {
  const version = isIP(address);
  if (version === 4) {
    const parts = address.split(".").map(Number);
    const [a, b] = parts;
    return a === 0 || a === 10 || a === 127 || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
      (a === 100 && b >= 64 && b <= 127) || (a === 198 && (b === 18 || b === 19)) ||
      a >= 224;
  }
  if (version === 6) {
    const lower = address.toLowerCase();
    if (lower === "::" || lower === "::1" || lower.startsWith("fc") || lower.startsWith("fd") || /^fe[89ab]/.test(lower)) return true;
    if (lower.startsWith("::ffff:")) return isPrivateAddress(lower.slice(7));
  }
  return false;
}

async function assertPublicUrl(value: string): Promise<URL> {
  const url = new URL(value);
  if (!( ["http:", "https:"].includes(url.protocol)) || url.username || url.password) throw new Error("Only public HTTP or HTTPS links can be previewed.");
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (!host || host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local")) throw new Error("That address is not publicly reachable.");
  const literal = isIP(host);
  const addresses = literal ? [{ address: host }] : await lookup(host, { all: true, verbatim: true });
  if (!addresses.length || addresses.some(({ address }) => isPrivateAddress(address))) throw new Error("That address is not publicly reachable.");
  return url;
}

async function fetchPublicHead(initial: string) {
  let current = initial;
  for (let redirects = 0; redirects <= 4; redirects++) {
    const url = await assertPublicUrl(current);
    const response = await fetch(url, { method: "HEAD", redirect: "manual", signal: AbortSignal.timeout(2500), headers: { "user-agent": "KeepItLinkPreview/1.0 (+https://keepit.app)" } });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location || redirects === 4) throw new Error("This link redirects too many times.");
      current = new URL(location, url).toString();
      continue;
    }
    return { url: url.toString(), contentType: response.headers.get("content-type") ?? "", ok: response.ok };
  }
  throw new Error("Could not follow the link.");
}

async function fetchPublicPage(initial: string) {
  let current = initial;
  for (let redirects = 0; redirects <= 4; redirects++) {
    const url = await assertPublicUrl(current);
    const response = await fetch(url, {
      redirect: "manual",
      signal: AbortSignal.timeout(7000),
      headers: { "user-agent": "KeepItLinkPreview/1.0 (+https://keepit.app)", accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5" },
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location || redirects === 4) throw new Error("This link redirects too many times.");
      current = new URL(location, url).toString();
      continue;
    }
    if (!response.ok) throw new Error(`The website returned ${response.status}.`);
    const type = response.headers.get("content-type") ?? "";
    if (!type.includes("text/html") && !type.includes("application/xhtml+xml")) throw new Error("This link does not expose a web page preview.");
    const declaredSize = Number(response.headers.get("content-length") ?? 0);
    if (declaredSize > 1_500_000) throw new Error("That page is too large to preview.");
    const reader = response.body?.getReader();
    if (!reader) throw new Error("The page could not be read.");
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 1_500_000) { await reader.cancel(); throw new Error("That page is too large to preview."); }
      chunks.push(value);
    }
    return { html: Buffer.concat(chunks).toString("utf8"), finalUrl: url.toString() };
  }
  throw new Error("Could not follow the link.");
}

function safeCodePoint(value: number) { return value >= 0 && value <= 0x10ffff ? String.fromCodePoint(value) : ""; }
function decodeEntities(value: string): string {
  return value.replace(/&amp;/gi, "&").replace(/&quot;/gi, '"').replace(/&#39;|&apos;/gi, "'").replace(/&lt;/gi, "<").replace(/&gt;/gi, ">").replace(/&#(\d+);/g, (_, code: string) => safeCodePoint(Number(code))).replace(/&#x([\da-f]+);/gi, (_, code: string) => safeCodePoint(parseInt(code, 16))).replace(/\s+/g, " ").trim();
}

function attrs(tag: string): Record<string, string> {
  const result: Record<string, string> = {};
  const pattern = /([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g;
  for (const match of tag.matchAll(pattern)) result[match[1].toLowerCase()] = decodeEntities(match[2] ?? match[3] ?? match[4] ?? "");
  return result;
}

function firstMeta(html: string, keys: string[]): string | undefined {
  for (const tag of html.matchAll(/<meta\b[^>]*>/gi)) {
    const values = attrs(tag[0]);
    const key = (values.property ?? values.name ?? values.itemprop ?? "").toLowerCase();
    if (keys.includes(key) && values.content) return values.content;
  }
  return undefined;
}

function extractMetadata(html: string, finalUrl: string) {
  const titleTag = html.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i)?.[1]?.replace(/<[^>]*>/g, " ");
  const title = firstMeta(html, ["og:title", "twitter:title"]) ?? decodeEntities(titleTag ?? "");
  const description = firstMeta(html, ["og:description", "twitter:description", "description"]);
  const rawImage = firstMeta(html, ["og:image", "og:image:url", "twitter:image"]);
  const canonicalHref = html.match(/<link\b(?=[^>]*\brel\s*=\s*["'][^"']*canonical[^"']*["'])[^>]*>/i)?.[0];
  const canonical = canonicalHref ? attrs(canonicalHref).href : undefined;
  const author = firstMeta(html, ["author", "article:author"]);
  const siteName = firstMeta(html, ["og:site_name"]);
  let image: string | undefined;
  try {
    const candidateImage = rawImage ? new URL(rawImage, finalUrl) : null;
    if (candidateImage && ["http:", "https:"].includes(candidateImage.protocol)) image = candidateImage.toString();
  } catch { image = undefined; }
  let canonicalUrl = finalUrl;
  try {
    const candidate = new URL(canonical ?? finalUrl, finalUrl);
    if (["http:", "https:"].includes(candidate.protocol)) canonicalUrl = candidate.toString();
  } catch { /* Keep the verified source URL. */ }
  return { title: decodeEntities(title ?? "").slice(0, 240), description: decodeEntities(description ?? "").slice(0, 1800), image, authorName: author ? decodeEntities(author).slice(0, 100) : undefined, siteName: siteName ? decodeEntities(siteName).slice(0, 100) : undefined, canonicalUrl };
}

export async function GET(request: Request) {
  const value = new URL(request.url).searchParams.get("url");
  if (!value || value.length > 2048) return NextResponse.json({ error: "A valid link is required." }, { status: 400 });
  try {
    const requested = await assertPublicUrl(value);
    const requestedHost = requested.hostname.toLowerCase();
    if (/(^|\.)youtube\.com$|(^|\.)youtu\.be$/.test(requestedHost)) {
      // YouTube pages are script-heavy; use its bounded public oEmbed response instead.
      const endpoint = new URL("https://www.youtube.com/oembed");
      endpoint.searchParams.set("url", requested.toString());
      endpoint.searchParams.set("format", "json");
      try {
        const response = await fetch(endpoint, { signal: AbortSignal.timeout(5000), headers: { accept: "application/json" } });
        if (response.ok) {
          const preview = await response.json() as { title?: string; author_name?: string; thumbnail_url?: string };
          const safeImage = preview.thumbnail_url?.startsWith("https://") ? preview.thumbnail_url : undefined;
          return NextResponse.json({ title: preview.title || "YouTube video", authorName: preview.author_name || "YouTube", siteName: "YouTube", image: safeImage, canonicalUrl: requested.toString(), type: "youtubeVideo" }, { headers: { "Cache-Control": "private, max-age=300" } });
        }
      } catch { /* A private/unlisted video can still be saved without a preview. */ }
      return NextResponse.json({ title: "YouTube video", authorName: "YouTube", siteName: "YouTube", canonicalUrl: requested.toString(), type: "youtubeVideo" }, { headers: { "Cache-Control": "private, max-age=300" } });
    }
    try {
      const imageHead = await fetchPublicHead(requested.toString());
      if (imageHead.ok && imageHead.contentType.toLowerCase().startsWith("image/")) {
        const filename = decodeURIComponent(new URL(imageHead.url).pathname.split("/").pop() ?? "").replace(/[-_]+/g, " ").replace(/\.[^.]+$/, "").trim();
        const host = new URL(imageHead.url).hostname.replace(/^www\./, "");
        return NextResponse.json({ title: filename || `Image from ${host}`, description: `Image saved from ${host}.`, image: imageHead.url, canonicalUrl: imageHead.url, authorName: host, siteName: host, type: "image" }, { headers: { "Cache-Control": "private, max-age=300" } });
      }
    } catch { /* Some sites do not support HEAD; continue with regular page metadata. */ }
    const { html, finalUrl } = await fetchPublicPage(requested.toString());
    const metadata = extractMetadata(html, finalUrl);
    const host = new URL(finalUrl).hostname.toLowerCase();
    const type = /(^|\.)instagram\.com$/.test(host) ? "instagramReel" : "webArticle";
    return NextResponse.json({ ...metadata, title: metadata.title || new URL(finalUrl).hostname, type }, { headers: { "Cache-Control": "private, max-age=300" } });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not load a preview for this link.";
    const status = /publicly reachable|Only public|valid|too large|too many|does not expose/i.test(message) ? 400 : 422;
    return NextResponse.json({ error: message }, { status });
  }
}
