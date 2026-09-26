// Generate real desktop release notes from commit subjects. GitHub's built-in
// automatic notes often show only a compare link when changes were pushed
// directly to main instead of being merged via pull requests.
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const tag = process.env.GITHUB_REF_NAME || process.argv[3];
const repo = process.env.GITHUB_REPOSITORY || "Keshab1997/keepit";
const output = path.resolve(process.argv[2] || "release-notes.md");
const version = require("../package.json").version;
if (!tag || !/^desktop-v[\w.+-]+$/.test(tag)) {
  console.error("Expected a desktop-v* tag (set GITHUB_REF_NAME or pass as a second argument).");
  process.exit(1);
}
if (tag !== `desktop-v${version}`) {
  console.error(`Tag ${tag} does not match desktop/package.json version ${version}. Bump the package version first.`);
  process.exit(1);
}
function git(args) {
  return execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
}
const desktopTags = git(["tag", "--list", "desktop-v*", "--sort=-version:refname"])
  .split("\n").filter(Boolean);
let previous = desktopTags.find((candidate) => {
  if (candidate === tag) return false;
  try { git(["merge-base", "--is-ancestor", candidate, tag]); return true; }
  catch { return false; }
});
if (!previous) {
  // First desktop release: use the last reachable mobile release as the
  // baseline to avoid dumping the project's entire history into the notes.
  try { previous = git(["describe", "--tags", "--match", "v*", "--abbrev=0", `${tag}^`]); }
  catch { /* This repository may have no earlier tagged releases. */ }
}
const range = previous ? `${previous}..${tag}` : tag;
const messages = git([
  "log", "--no-merges", "--pretty=format:- %s", ...(previous ? [range] : ["-n", "20", tag]),
  "--", "desktop/", "web-app/", ".github/workflows/desktop-packages.yml", "README.md",
]);
const changes = messages || "- Desktop packaging and maintenance updates.";
const url = `https://github.com/${repo}/releases/download/${tag}`;
const lines = [
  `# KeepIt Desktop ${version}`,
  "",
  "Self-contained Windows and macOS installers. The KeepIt web app and its local server are bundled; no Vercel deployment or system Node.js installation is needed.",
  "",
  "## What's changed",
  changes,
  "",
  "## Download",
  `- Windows x64: [KeepIt-Setup-${version}.exe](${url}/KeepIt-Setup-${version}.exe)`,
  `- macOS Apple Silicon: [KeepIt-${version}-arm64.dmg](${url}/KeepIt-${version}-arm64.dmg)`,
  `- macOS Intel: [KeepIt-${version}-x64.dmg](${url}/KeepIt-${version}-x64.dmg)`,
  "",
  "## Before installing",
  "- These installers are not code-signed or notarized; Windows SmartScreen and macOS Gatekeeper may warn.",
  "- Saved notes and links work locally without a hosted site. Fetching new link previews, optional Firebase sync and ImgBB uploads still require internet/configuration.",
  "- This desktop version has its own local library; it does not automatically import bookmarks from your browser.",
  "",
  ...(previous ? [`**Changes since:** ${previous} ([compare](https://github.com/${repo}/compare/${previous}...${tag}))`, ""] : []),
];
fs.writeFileSync(output, lines.join("\n"));
console.log(`Generated ${output} (${messages.split("\n").filter(Boolean).length} commit subjects).`);
