// Pont minimal entre la page et Windows : notifications, appel entrant (fenêtre au premier plan), liens externes.
const { contextBridge, ipcRenderer } = require("electron");
const s = (v, n) => String(v == null ? "" : v).slice(0, n);
contextBridge.exposeInMainWorld("bastionDesktop", {
  notify: (o) => ipcRenderer.send("notify", { title: s(o && o.title, 120), body: s(o && o.body, 300) }),
  incomingCall: (o) => ipcRenderer.send("incoming-call", { name: s(o && o.name, 120) }),
  callEnded: () => ipcRenderer.send("call-ended"),
  badge: (n) => ipcRenderer.send("badge", Number(n) || 0),
  openExternal: (u) => ipcRenderer.send("open-external", s(u, 2000))
});
