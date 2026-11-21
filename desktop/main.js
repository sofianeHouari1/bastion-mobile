// Appli de bureau Windows : une fenêtre sur l'espace du cabinet, qui reste active dans la zone de notification
// (à côté de l'horloge) quand on la ferme, pour recevoir les appels et les messages. Aucun pistage, aucun service tiers.
const { app, BrowserWindow, Tray, Menu, shell, session, Notification, desktopCapturer, ipcMain, nativeImage } = require("electron");
const path = require("path");
const fs = require("fs"), crypto = require("crypto"), { spawn } = require("child_process");
const cfg = require("./config.json");

const START = new URL(cfg.url);
const HOST = START.hostname;
const BASE = HOST.split(".").slice(-2).join(".");          // myselftherapy.eu : espace, connexion (auth.) et visio (meet.)
const ours = (u) => { try { const x = new URL(u); return x.protocol === "https:" && (x.hostname === BASE || x.hostname.endsWith("." + BASE)); } catch (e) { return false; } };
const ICON = path.join(__dirname, "icon.png");

// Caméra : sur certains PC (pilotes Samsung notamment), la capture vidéo « Media Foundation » de Chromium échoue
// alors que Firefox voit la caméra. On force l'ancienne méthode (DirectShow), qui marche partout.
app.commandLine.appendSwitch("disable-features", "MediaFoundationVideoCapture");
app.setAppUserModelId(cfg.appId);                            // notifications Windows au nom de l'appli
if (!app.requestSingleInstanceLock()) { app.quit(); process.exit(0); }

let win = null, tray = null, quitting = false;
// après une mise à jour faite en arrière-plan, l'appli repart discrètement dans la zone de notification
const HIDDEN_FLAG = path.join(app.getPath("userData"), ".start-hidden");
const startHidden = process.argv.includes("--hidden") || (() => { try { fs.unlinkSync(HIDDEN_FLAG); return true; } catch (e) { return false; } })();

function show() {
  if (!win) return create(false);
  if (win.isMinimized()) win.restore();
  win.show(); win.focus();
}

function create(hidden) {
  win = new BrowserWindow({
    width: 1200, height: 820, minWidth: 380, minHeight: 520, title: cfg.name, icon: ICON, show: !hidden,
    autoHideMenuBar: true, backgroundColor: "#ffffff",
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, sandbox: true, backgroundThrottling: false, spellcheck: true }
  });
  win.removeMenu();
  const ua = win.webContents.getUserAgent().replace(/ Electron\/[\d.]+/, "").replace(/ bastion-desktop\/[\d.]+/i, "");
  win.webContents.setUserAgent(ua + " BastionDesktop/" + (cfg.build || 0));
  win.loadURL(cfg.url);
  win.on("close", (e) => { if (!quitting) { e.preventDefault(); win.hide(); } });   // fermer = rester joignable
  win.on("focus", () => win.flashFrame(false));
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (ours(url)) return { action: "allow", overrideBrowserWindowOptions: { autoHideMenuBar: true, icon: ICON } };
    if (/^https?:|^mailto:|^tel:/.test(url)) shell.openExternal(url);
    return { action: "deny" };
  });
  win.webContents.on("will-navigate", (e, url) => { if (!ours(url)) { e.preventDefault(); if (/^https?:/.test(url)) shell.openExternal(url); } });
  win.webContents.on("render-process-gone", () => { if (!quitting) setTimeout(() => win && win.reload(), 1500); });
}

function buildTray() {
  tray = new Tray(nativeImage.createFromPath(ICON).resize({ width: 16, height: 16 }));
  tray.setToolTip(cfg.name);
  const menu = () => Menu.buildFromTemplate([
    { label: "Ouvrir " + cfg.name, click: show },
    { label: "Lancer au démarrage de Windows", type: "checkbox", checked: app.getLoginItemSettings().openAtLogin,
      click: (it) => app.setLoginItemSettings({ openAtLogin: it.checked, args: ["--hidden"] }) },
    { type: "separator" },
    { label: "Quitter (plus d'appels ni de notifications)", click: () => { quitting = true; if (upd.ready && !callOn) runInstaller(false, false); app.quit(); } }
  ]);
  tray.setContextMenu(menu());
  tray.on("click", show);
  tray.on("right-click", () => tray.setContextMenu(menu()));
}

app.on("second-instance", show);
app.on("before-quit", () => { quitting = true; });
app.on("window-all-closed", (e) => { if (!quitting) e.preventDefault(); });

app.whenReady().then(() => {
  // micro, caméra, notifications, partage d'écran : uniquement pour l'espace du cabinet et sa visio
  const allowed = new Set(["media", "notifications", "display-capture", "clipboard-sanitized-write", "clipboard-read", "fullscreen", "speaker-selection"]);
  session.defaultSession.setPermissionRequestHandler((wc, perm, cb, details) => cb(allowed.has(perm) && ours(details.requestingUrl || wc.getURL())));
  session.defaultSession.setPermissionCheckHandler((wc, perm, origin) => allowed.has(perm) && ours(origin || (wc && wc.getURL()) || ""));
  session.defaultSession.setDisplayMediaRequestHandler((req, cb) => {
    desktopCapturer.getSources({ types: ["screen"] }).then((s) => cb(s.length ? { video: s[0] } : {})).catch(() => cb({}));
  });
  if (!app.getLoginItemSettings().openAtLogin && !require("fs").existsSync(path.join(app.getPath("userData"), ".installed"))) {
    app.setLoginItemSettings({ openAtLogin: true, args: ["--hidden"] });     // 1re ouverture : joignable dès l'allumage du PC
    try { require("fs").writeFileSync(path.join(app.getPath("userData"), ".installed"), "1"); } catch (e) {}
  }
  if (installPending(startHidden)) return;      // mise à jour téléchargée la dernière fois : on l'installe avant d'ouvrir
  buildTray();
  create(startHidden);
  setInterval(() => { if (upd.ready && !callOn && win && !win.isVisible()) runInstaller(true); }, 10 * 60 * 1000);
});

/* ---------- Mise à jour automatique ----------
   La page signale une nouvelle version (même serveur, même session) : l'appli la télécharge en arrière-plan, vérifie
   son empreinte, puis l'installe sans fenêtre quand elle est en veille dans la zone de notification (jamais pendant
   un appel), ou au prochain démarrage. */
const UPD_DIR = path.join(app.getPath("userData"), "maj"), UPD_META = path.join(UPD_DIR, "pending.json");
const upd = { busy: false, ready: null };
let callOn = false;
function installPending(hidden) {
  try {
    const p = JSON.parse(fs.readFileSync(UPD_META, "utf8"));
    if (p.n > (cfg.build || 0) && fs.existsSync(p.f)) { upd.ready = p; return runInstaller(hidden); }
    fs.rmSync(UPD_DIR, { recursive: true, force: true });                 // déjà installée : ménage
  } catch (e) {}
  return false;
}
function runInstaller(hiddenAfter, relaunch = true) {
  const p = upd.ready; if (!p) return false;
  try {
    fs.unlinkSync(UPD_META);
    if (hiddenAfter && relaunch) fs.writeFileSync(HIDDEN_FLAG, "1");
    // petite attente : l'appli se ferme, puis l'installateur remplace les fichiers sans fenêtre et relance l'appli
    spawn("cmd.exe", ["/d", "/c", 'ping -n 4 127.0.0.1 >nul & "' + p.f + '" /S' + (relaunch ? " --force-run" : "")],
      { detached: true, stdio: "ignore", windowsHide: true }).unref();
    upd.ready = null;
    if (relaunch) { quitting = true; app.quit(); }
    return true;
  } catch (e) { return false; }
}
async function fetchUpdate(o) {
  const n = parseInt(o && o.n, 10) || 0;
  if (!(n > (cfg.build || 0)) || upd.busy || (upd.ready && upd.ready.n >= n) || !ours(o.url)) return;
  upd.busy = true;
  try {
    const r = await session.defaultSession.fetch(o.url, { cache: "no-store" });
    if (!r.ok) throw new Error("HTTP " + r.status);
    const buf = Buffer.from(await r.arrayBuffer());
    if (buf.length < 1e6) throw new Error("fichier trop petit");
    if (o.sha && crypto.createHash("sha256").update(buf).digest("hex") !== String(o.sha).toLowerCase()) throw new Error("empreinte");
    fs.mkdirSync(UPD_DIR, { recursive: true });
    const f = path.join(UPD_DIR, "installation-" + n + ".exe");
    fs.writeFileSync(f, buf);
    upd.ready = { n, f };
    fs.writeFileSync(UPD_META, JSON.stringify(upd.ready));
  } catch (e) {} finally { upd.busy = false; }
}
ipcMain.on("auto-update", (e, o) => { fetchUpdate(o); });
ipcMain.on("call-state", (e, on) => { callOn = !!on; });

ipcMain.on("notify", (e, o) => {
  if (win && win.isVisible() && win.isFocused()) return;
  const n = new Notification({ title: o.title || cfg.name, body: o.body || "", icon: ICON });
  n.on("click", show); n.show();
});
let callNote = null;
ipcMain.on("incoming-call", (e, o) => {
  callOn = true;
  show(); if (win) { win.setAlwaysOnTop(true); setTimeout(() => win && win.setAlwaysOnTop(false), 1500); win.flashFrame(true); }
  try { callNote = new Notification({ title: "Appel entrant", body: o.name || "", icon: ICON, urgency: "critical", timeoutType: "never" }); callNote.on("click", show); callNote.show(); } catch (x) {}
});
ipcMain.on("call-ended", () => { callOn = false; if (win) win.flashFrame(false); try { callNote && callNote.close(); } catch (x) {} callNote = null; });
ipcMain.on("badge", (e, n) => { if (win) win.setTitle(n > 0 ? "(" + n + ") " + cfg.name : cfg.name); });
ipcMain.on("open-external", (e, u) => { if (/^https:\/\//.test(u)) shell.openExternal(u); });
