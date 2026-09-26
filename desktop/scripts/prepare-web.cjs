// Next.js standalone output does not copy static assets or public/ by default.
// Complete the server bundle before electron-builder copies it into resources/.
const fs = require("node:fs");
const path = require("node:path");

const web = path.resolve(__dirname, "../../web-app");
const standalone = path.join(web, ".next", "standalone");
const server = path.join(standalone, "server.js");
if (!fs.existsSync(server)) {
  console.error("Missing web-app/.next/standalone/server.js. Build the web app first: cd web-app && npm ci && npm run build");
  process.exit(1);
}
for (const [source, destination] of [
  [path.join(web, ".next", "static"), path.join(standalone, ".next", "static")],
  [path.join(web, "public"), path.join(standalone, "public")],
]) {
  if (!fs.existsSync(source)) {
    console.error(`Missing required web assets: ${source}`);
    process.exit(1);
  }
  // Older builds may have stale assets; always replace them together.
  fs.rmSync(destination, { recursive: true, force: true });
  fs.cpSync(source, destination, { recursive: true });
}
console.log(`Desktop web bundle ready: ${standalone}`);
