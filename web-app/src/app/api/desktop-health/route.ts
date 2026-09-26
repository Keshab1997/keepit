// This endpoint is used only by the packaged Electron app to identify its own
// local Next.js process. In a web deployment it does not advertise anything.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(request: Request) {
  const secret = process.env.KEEPIT_DESKTOP_BOOT_TOKEN;
  if (!secret || request.headers.get("x-keepit-desktop-boot-token") !== secret) {
    return new Response(null, { status: 404, headers: { "Cache-Control": "no-store" } });
  }
  return Response.json({ ready: true }, { headers: { "Cache-Control": "no-store" } });
}
