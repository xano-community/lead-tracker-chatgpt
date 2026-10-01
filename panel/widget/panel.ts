// Lead Tracker panel. Dependency-free so the bundle stays small (~10 KB).
// Works with ChatGPT's window.openai runtime and, as a fallback, the MCP Apps
// postMessage bridge (ui/initialize, ui/notifications/tool-result, tools/call).

type Stage = "New" | "Qualified" | "Proposal" | "Won";
interface Lead { id: number; name: string; company: string; deal_value: number; stage: Stage; updated_at: number; }
const STAGES: { key: Stage; color: string }[] = [
  { key: "New", color: "#94a3b8" },
  { key: "Qualified", color: "#38bdf8" },
  { key: "Proposal", color: "#f59e0b" },
  { key: "Won", color: "#22c55e" },
];

const state = {
  leads: [] as Lead[],
  loaded: false,
  saving: new Map<number, Stage>(),
  savedAt: new Map<number, number>(),
  lastSaved: -1,
  refreshing: false,
  error: "",
  mode: "inline" as string,
};

const w = window as any;
const esc = (s: string) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
const money = (n: number) => "$" + Number(n).toLocaleString("en-US", { maximumFractionDigits: 0 });
const initials = (n: string) => String(n).split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0]!.toUpperCase()).join("");

// ---------- host bridge ----------
let rpcId = 1;
const pending = new Map<number, (m: any) => void>();
const post = (msg: any) => window.parent?.postMessage({ jsonrpc: "2.0", ...msg }, "*");
const request = (method: string, params: any) =>
  new Promise<any>((resolve, reject) => {
    const id = rpcId++;
    pending.set(id, (m) => (m.error ? reject(new Error(m.error.message || "Host error")) : resolve(m.result)));
    post({ id, method, params });
    setTimeout(() => pending.has(id) && (pending.delete(id), reject(new Error("Host did not answer"))), 20000);
  });

async function callTool(name: string, args: Record<string, unknown>): Promise<any> {
  if (w.openai?.callTool) return w.openai.callTool(name, args);
  return request("tools/call", { name, arguments: args });
}

function sendContext(text: string) {
  try {
    if (w.openai?.setWidgetState) w.openai.setWidgetState({ note: text });
    else post({ method: "ui/update-model-context", id: rpcId++, params: { content: [{ type: "text", text }] } });
  } catch {}
}

function reportHeight() {
  const h = Math.ceil(document.getElementById("root")!.getBoundingClientRect().height);
  try { w.openai?.notifyIntrinsicHeight?.(h); } catch {}
  post({ method: "ui/notifications/size-changed", params: { width: document.documentElement.clientWidth, height: h } });
}

window.addEventListener("message", (e) => {
  const m = e.data;
  if (!m || typeof m !== "object" || m.jsonrpc !== "2.0") return;
  if (m.id != null && pending.has(m.id) && (m.result !== undefined || m.error)) {
    const fn = pending.get(m.id)!; pending.delete(m.id); fn(m); return;
  }
  if (m.method === "ui/notifications/tool-result") applyBoard(m.params);
  if (m.method === "ui/notifications/host-context-changed") { applyTheme(m.params?.theme); if (m.params?.displayMode) setMode(m.params.displayMode); }
});

function applyTheme(theme?: string) {
  if (theme === "dark" || theme === "light") document.documentElement.style.colorScheme = theme;
}

function setMode(mode?: string) {
  if (!mode || mode === state.mode) return;
  state.mode = mode; render();
}

async function toggleExpand() {
  const want = state.mode === "fullscreen" ? "inline" : "fullscreen";
  try {
    if (w.openai?.requestDisplayMode) {
      const r = await w.openai.requestDisplayMode({ mode: want });
      setMode(r?.mode ?? w.openai.displayMode);
    } else {
      const r = await request("ui/request-display-mode", { mode: want });
      setMode(r?.mode);
    }
  } catch {}
}

// ---------- board ----------
// Accepts structuredContent, a full CallToolResult (Xano MCP returns the board as JSON text), or a JSON string.
function toBoard(x: any): any {
  if (x == null) return null;
  if (typeof x === "string") { try { return toBoard(JSON.parse(x)); } catch { return null; } }
  if (Array.isArray(x.leads)) return x;
  if (x.structuredContent) return toBoard(x.structuredContent);
  if (Array.isArray(x.content)) { for (const c of x.content) { const b = c?.type === "text" ? toBoard(c.text) : null; if (b) return b; } }
  if (x.result) return toBoard(x.result);
  return null;
}

function applyBoard(raw: any, fromPoll = false) {
  const sc = toBoard(raw);
  if (!sc) return;
  if (fromPoll && state.loaded) {
    // Highlight what changed in Xano since the last read (a lead added or moved from the chat).
    const before = new Map(state.leads.map((l) => [l.id, l.stage]));
    const changed = sc.leads.find((l: Lead) => !before.has(l.id) || before.get(l.id) !== l.stage);
    if (!changed && sc.leads.length === state.leads.length) return;
    if (changed) { state.savedAt.set(changed.id, Date.now()); state.lastSaved = changed.id; }
  }
  state.leads = sc.leads;
  state.loaded = true;
  // A lead is marked saved only when the server reports Xano acknowledged the write.
  if (sc.saved && sc.lead?.id != null) {
    state.savedAt.set(sc.lead.id, Date.now());
    state.lastSaved = sc.lead.id;
  }
  render();
}

function footer(l: Lead) {
  if (state.saving.has(l.id)) return `<div class="card-foot"><span class="spin"></span>Saving to ${state.saving.get(l.id)}…</div>`;
  const t = state.savedAt.get(l.id);
  if (t && state.lastSaved === l.id) return `<div class="card-foot ok"><svg class="ok-ico" viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 6 9 17l-5-5"/></svg> Saved to Xano</div>`;
  return "";
}

function render() {
  const root = document.getElementById("root")!;
  const total = state.leads.reduce((a, l) => a + Number(l.deal_value || 0), 0);
  const cols = STAGES.map(({ key, color }) => {
    const items = state.leads.filter((l) => l.stage === key);
    const cards = items
      .map((l) => {
        const just = state.lastSaved === l.id;
        return `<div class="card${state.saving.has(l.id) ? " saving" : ""}${just ? " just-saved" : ""}" data-id="${l.id}">
      <div class="card-top"><div class="av">${esc(initials(l.name))}</div><div><div class="nm">${esc(l.name)}</div><div class="co">${esc(l.company)}</div></div></div>
      <div class="card-top"><div class="val">${money(l.deal_value)}</div>
        <select aria-label="Stage" data-move="${l.id}" ${state.saving.has(l.id) ? "disabled" : ""}>${STAGES.map((s) => `<option${s.key === (state.saving.get(l.id) ?? l.stage) ? " selected" : ""}>${s.key}</option>`).join("")}</select></div>
      ${footer(l)}</div>`;
      })
      .join("");
    return `<div class="col"><div class="col-h"><span class="dot" style="background:${color}"></span>${key}<span class="count">${items.length}</span></div>${cards}</div>`;
  }).join("");
  root.innerHTML = `<div class="lt${state.mode === "fullscreen" ? " full" : ""}">
    <div class="lt-head"><div><div class="lt-title">Lead Tracker</div><div class="lt-sub">${state.loaded ? `${state.leads.length} lead${state.leads.length === 1 ? "" : "s"} · ${money(total)} pipeline` : "Loading…"}</div></div>
      <div class="lt-spacer"></div><span class="chip"><i></i>Runs on Xano</span>
      <button class="iconbtn" id="refresh" ${state.refreshing ? "disabled" : ""}>${state.refreshing ? "Refreshing…" : "Refresh"}</button></div>
    <div class="board">${cols}</div>
    ${state.loaded && !state.leads.length ? `<div class="empty">No leads yet. Ask in the chat to add one.</div>` : ""}
    ${state.error ? `<div class="err">${esc(state.error)}</div>` : ""}
  </div>`;
  root.querySelector<HTMLButtonElement>("#refresh")!.onclick = refresh;
  root.querySelectorAll<HTMLSelectElement>("select[data-move]").forEach((sel) => {
    sel.onchange = () => move(Number(sel.dataset.move), sel.value as Stage);
  });
  requestAnimationFrame(reportHeight);
}

const textOf = (r: any) => (r?.content ?? []).map((c: any) => c.text ?? "").join(" ") || "Tool error";

async function refresh() {
  state.refreshing = true; state.error = ""; render();
  try {
    const r = await callTool("list_leads", {});
    if (r?.isError) throw new Error(textOf(r));
    applyBoard(r);
  } catch (e: any) {
    state.error = "Couldn't load leads: " + (e?.message ?? e);
  } finally {
    state.refreshing = false; render();
  }
}

async function move(id: number, stage: Stage) {
  const lead = state.leads.find((l) => l.id === id);
  if (!lead || lead.stage === stage) return;
  state.saving.set(id, stage); state.error = ""; render();
  try {
    const r = await callTool("update_lead_stage", { lead_id: id, stage });
    if (r?.isError) throw new Error(textOf(r));
    state.saving.delete(id);
    applyBoard(r);
    sendContext(`In the Lead Tracker panel the user moved ${lead.name} to ${stage}. Xano saved it.`);
  } catch (e: any) {
    state.saving.delete(id);
    state.error = `Not saved: ${e?.message ?? e}`;
    render();
  }
}

// Stay in sync with Xano while visible, so changes made from the chat show up here.
let polling = false;
async function poll() {
  if (polling || document.hidden || state.saving.size || !state.loaded) return;
  polling = true;
  try { const r = await callTool("list_leads", {}); if (!r?.isError) applyBoard(r, true); } catch {} finally { polling = false; }
}
setInterval(poll, 2000);

// ---------- start ----------
render();
if (w.openai) {
  applyTheme(w.openai.theme);
  if (w.openai.displayMode) state.mode = w.openai.displayMode;
  applyBoard(w.openai.toolOutput);
  window.addEventListener("openai:set_globals", (e: any) => {
    const g = e?.detail?.globals ?? {};
    if ("toolOutput" in g) applyBoard(g.toolOutput);
    if ("theme" in g) applyTheme(g.theme);
    if ("displayMode" in g) setMode(g.displayMode);
  });
}
// MCP Apps handshake (also delivers ui/notifications/tool-result with the full tool result).
request("ui/initialize", {
  protocolVersion: "2026-01-26",
  appInfo: { name: "Lead Tracker", version: "1.0.0" },
  appCapabilities: { availableDisplayModes: ["inline", "fullscreen"] },
})
  .then((res) => {
    if (!w.openai) { applyTheme(res?.hostContext?.theme); setMode(res?.hostContext?.displayMode); }
    post({ method: "ui/notifications/initialized", params: {} });
  })
  .catch(() => {});
// Opened without a tool result (sidebar, reopen): fetch the saved leads.
setTimeout(() => { if (!state.loaded) refresh(); }, 1500);
try { new ResizeObserver(() => reportHeight()).observe(document.getElementById("root")!); } catch {}
