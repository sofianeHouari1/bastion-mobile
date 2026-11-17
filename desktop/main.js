// Appli de bureau Windows : une fenêtre sur l'espace du cabinet, qui reste active dans la zone de notification
// (à côté de l'horloge) quand on la ferme, pour recevoir les appels et les messages. Aucun pistage, aucun service tiers.
const { app, BrowserWindow, Tray, Menu, shell, session, Notification, desktopCapturer, ipcMain, nativeImage } = require("electron");
const path = require("path");
const cfg = require("./config.json");

const START = new URL(cfg.url);
const HOST = START.hostname;
const BASE = HOST.split(".").slice(-2).join(".");          // myselftherapy.eu : espace, connexion (auth.) et visio (meet.)
const ours = (u) => { try { const x = new URL(u); return x.protocol === "https:" && (x.hostname === BASE || x.hostname.endsWith("." + BASE)); } catch (e) { return false; } };
const ICON = path.join(__dirname, "icon.png");

app.setAppUserModelId(cfg.appId);                            // notifications Windows au nom de l'appli
if (!app.requestSingleInstanceLock()) { app.quit(); process.exit(0); }

let win = null, tray = null, quitting = false;
const startHidden = process.argv.includes("--hidden");

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
    { label: "Quitter (plus d'appels ni de notifications)", click: () => { quitting = true; app.quit(); } }
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
  buildTray();
  create(startHidden);
});

ipcMain.on("notify", (e, o) => {
  if (win && win.isVisible() && win.isFocused()) return;
  const n = new Notification({ title: o.title || cfg.name, body: o.body || "", icon: ICON });
  n.on("click", show); n.show();
});
let callNote = null;
ipcMain.on("incoming-call", (e, o) => {
  show(); if (win) { win.setAlwaysOnTop(true); setTimeout(() => win && win.setAlwaysOnTop(false), 1500); win.flashFrame(true); }
  try { callNote = new Notification({ title: "Appel entrant", body: o.name || "", icon: ICON, urgency: "critical", timeoutType: "never" }); callNote.on("click", show); callNote.show(); } catch (x) {}
});
ipcMain.on("call-ended", () => { if (win) win.flashFrame(false); try { callNote && callNote.close(); } catch (x) {} callNote = null; });
ipcMain.on("badge", (e, n) => { if (win) win.setTitle(n > 0 ? "(" + n + ") " + cfg.name : cfg.name); });
ipcMain.on("open-external", (e, u) => { if (/^https:\/\//.test(u)) shell.openExternal(u); });
