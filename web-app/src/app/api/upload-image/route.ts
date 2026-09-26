import { Buffer } from "node:buffer";

export const runtime = "nodejs";
export const maxDuration = 60;

// Stay below Vercel Functions' 4.5 MB request-body cap, including multipart overhead.
const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const WINDOW_MS = 10 * 60 * 1000;
const MAX_UPLOADS_PER_WINDOW = 20;
const uploadWindows = new Map<string, { count: number; resetAt: number }>();

function jsonError(message: string, status: number) {
  return Response.json({ error: message }, { status, headers: { "Cache-Control": "no-store" } });
}

function isRateLimited(request: Request) {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",").at(-1)?.trim();
  const client = request.headers.get("x-real-ip") || forwarded || "unknown";
  const now = Date.now();
  let window = uploadWindows.get(client);
  if (!window || now >= window.resetAt) {
    window = { count: 0, resetAt: now + WINDOW_MS };
    uploadWindows.set(client, window);
  }
  window.count += 1;
  if (uploadWindows.size > 1000) {
    for (const [key, value] of uploadWindows) if (now >= value.resetAt) uploadWindows.delete(key);
  }
  return window.count > MAX_UPLOADS_PER_WINDOW;
}

export async function POST(request: Request) {
  if (request.headers.get("sec-fetch-site") === "cross-site") {
    return jsonError("Upload requests must come from KeepIt.", 403);
  }
  if (isRateLimited(request)) {
    return jsonError("Too many uploads from this network. Please try again in a few minutes.", 429);
  }

  const apiKey = process.env.IMGBB_API_KEY?.trim();
  if (!apiKey) {
    return jsonError("Image uploads are not configured yet. Add IMGBB_API_KEY to the web server environment.", 503);
  }

  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("multipart/form-data")) {
    return jsonError("Choose an image file to upload.", 415);
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return jsonError("Could not read the uploaded image.", 400);
  }
  const image = form.get("image");
  if (!(image instanceof File)) return jsonError("Choose an image file to upload.", 400);
  if (image.size === 0) return jsonError("The selected image is empty.", 400);
  if (image.size > MAX_IMAGE_BYTES) return jsonError("For this Vercel deployment, images must be 4 MB or smaller.", 413);
  if (!ALLOWED_IMAGE_TYPES.has(image.type)) {
    return jsonError("Use a JPEG, PNG, WebP or GIF image.", 415);
  }

  try {
    const bytes = Buffer.from(await image.arrayBuffer());
    const upload = new FormData();
    upload.set("key", apiKey);
    upload.set("image", bytes.toString("base64"));
    const safeName = image.name.trim().replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 120);
    if (safeName) upload.set("name", safeName);

    const response = await fetch("https://api.imgbb.com/1/upload", {
      method: "POST",
      body: upload,
      signal: AbortSignal.timeout(45_000),
      cache: "no-store",
    });
    const payload = await response.json().catch(() => null) as {
      success?: boolean;
      data?: { display_url?: string; url?: string };
    } | null;
    const imageUrl = payload?.data?.display_url || payload?.data?.url;
    if (!response.ok || payload?.success !== true || !imageUrl) {
      return jsonError("ImgBB could not accept this image. Check the file and API key, then try again.", 502);
    }
    const parsedUrl = new URL(imageUrl);
    if (parsedUrl.protocol !== "https:") return jsonError("ImgBB returned an invalid image URL.", 502);

    return Response.json({ url: parsedUrl.toString() }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return jsonError("Image upload failed. Check your connection and try again.", 502);
  }
}
