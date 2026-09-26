const fs = require("node:fs");
const path = require("node:path");

const rawUrl = (process.env.KEEPIT_WEB_URL || "").trim();
if (!rawUrl) {
  console.error("KEEPIT_WEB_URL is required. Set it to the deployed KeepIt Vercel URL, for example https://keepit-your-team.vercel.app");
  process.exit(1);
}

let parsed;
try {
  parsed = new URL(rawUrl);
} catch {
  console.error(`KEEPIT_WEB_URL is not a valid URL: ${rawUrl}`);
  process.exit(1);
}

const localHost = ["localhost", "127.0.0.1"].includes(parsed.hostname);
if ((parsed.protocol !== "https:" && !(localHost && parsed.protocol === "http:")) || parsed.username || parsed.password || parsed.search || parsed.hash || parsed.pathname !== "/") {
  console.error("KEEPIT_WEB_URL must be an HTTPS origin (local HTTP is allowed only for localhost), without credentials, a path, query, or hash.");
  process.exit(1);
}

const config = { keepItWebUrl: parsed.origin };
fs.writeFileSync(path.join(__dirname, "..", "app-config.json"), `${JSON.stringify(config, null, 2)}\n`);
console.log(`Configured KeepIt desktop to load ${config.keepItWebUrl}`);
