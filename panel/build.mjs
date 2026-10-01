// Bundles widget/panel.ts + CSS into one self-contained HTML file and writes it to ../frontend/panel.html,
// which is hosted at a public URL (PANEL_URL) and served to ChatGPT as the MCP App resource.
import { build } from "esbuild";
import { readFileSync, writeFileSync } from "node:fs";
const js = await build({ entryPoints: ["widget/panel.ts"], bundle: true, format: "iife", target: "es2022", minify: true, write: false, platform: "browser" });
const css = readFileSync("node_modules/@openai/mcp-extensions/styles.css", "utf8") + "\n" + readFileSync("widget/panel.css", "utf8");
const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Lead Tracker</title><style>${css}</style></head><body><div id="root"></div><script>${js.outputFiles[0].text.replace(/<\/script/g, "<\\/script")}</script></body></html>`;
writeFileSync("../frontend/panel.html", html);
console.log("../frontend/panel.html", (html.length / 1024).toFixed(1), "KB");
