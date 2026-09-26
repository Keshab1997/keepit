export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const RELEASES_URL = "https://api.github.com/repos/Keshab1997/keepit/releases?per_page=30";
const VERSION_TAG = /^desktop-v(\d+)\.(\d+)\.(\d+)$/;

type DesktopRelease = {
  tag_name: string;
  html_url: string;
  draft: boolean;
  prerelease: boolean;
};

function versionParts(value: string): number[] | null {
  const match = value.match(/^(\d+)\.(\d+)\.(\d+)$/);
  return match ? match.slice(1).map(Number) : null;
}

function compareVersions(left: string, right: string): number {
  const a = versionParts(left);
  const b = versionParts(right);
  if (!a || !b) return 0;
  for (let index = 0; index < 3; index++) {
    if (a[index] !== b[index]) return a[index] - b[index];
  }
  return 0;
}

export async function GET() {
  // Do not show desktop-update notices on the hosted/local web app.
  const currentVersion = process.env.KEEPIT_DESKTOP_VERSION;
  if (!currentVersion || !process.env.KEEPIT_DESKTOP_BOOT_TOKEN) {
    return Response.json({ updateAvailable: false }, { headers: { "Cache-Control": "no-store" } });
  }

  try {
    const response = await fetch(RELEASES_URL, {
      headers: { Accept: "application/vnd.github+json", "User-Agent": "KeepIt-Desktop-Updater" },
      cache: "no-store",
      signal: AbortSignal.timeout(6000),
    });
    if (!response.ok) throw new Error(`GitHub releases returned HTTP ${response.status}`);

    const releases = await response.json() as DesktopRelease[];
    const latest = releases
      .filter((release) => !release.draft && !release.prerelease && VERSION_TAG.test(release.tag_name))
      .map((release) => ({
        version: release.tag_name.match(VERSION_TAG)![1] + "." + release.tag_name.match(VERSION_TAG)![2] + "." + release.tag_name.match(VERSION_TAG)![3],
        url: release.html_url,
      }))
      .sort((left, right) => compareVersions(right.version, left.version))[0];

    if (!latest || compareVersions(latest.version, currentVersion) <= 0) {
      return Response.json({ updateAvailable: false, currentVersion }, { headers: { "Cache-Control": "no-store" } });
    }

    return Response.json({
      updateAvailable: true,
      currentVersion,
      latestVersion: latest.version,
      releaseUrl: latest.url,
    }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    // Update checks are best-effort and must never block app startup or local saves.
    return Response.json({ updateAvailable: false, currentVersion }, { headers: { "Cache-Control": "no-store" } });
  }
}
