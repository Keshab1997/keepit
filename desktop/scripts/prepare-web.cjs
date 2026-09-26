// Next.js standalone output does not copy static assets or public/ by default.
// Complete the server bundle before electron-builder copies it into resources/.
const fs = require("node:fs");
const path = require("node:path");

const web = path.resolve(__dirname, "../../web-app");
const standalone = path.join(web, ".next", "standalone");
const server = path.join(standalone, "server.js");
const bundledModules = path.join(standalone, "node_modules");
const nextPackage = path.join(bundledModules, "next", "package.json");
const runtimeModules = path.join(standalone, "runtime-deps");
if (!fs.existsSync(server)) {
  console.error("Missing web-app/.next/standalone/server.js. Build the web app first: cd web-app && npm ci && npm run build");
  process.exit(1);
}
if (!fs.existsSync(nextPackage)) {
  console.error(`The standalone bundle is missing its Next.js runtime: ${nextPackage}. Rebuild it with: npm run build:web`);
  process.exit(1);
}
// electron-builder applies the repository's .gitignore rules to extraResources;
// since node_modules/ is ignored, Next's traced dependencies were silently left
// out of the .app. Stage them under a non-ignored name and load them via NODE_PATH.
fs.rmSync(runtimeModules, { recursive: true, force: true });
fs.cpSync(bundledModules, runtimeModules, { recursive: true });
try {
  const moduleApi = require("node:module");
  process.env.NODE_PATH = [runtimeModules, process.env.NODE_PATH].filter(Boolean).join(path.delimiter);
  moduleApi.Module._initPaths();
  moduleApi.createRequire(server).resolve("next");
} catch (error) {
  console.error(`The standalone bundle cannot resolve Next.js from ${runtimeModules}: ${error.message}. Rebuild it with: npm run build:web`);
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
