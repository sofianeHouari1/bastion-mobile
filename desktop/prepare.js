// Prépare l'appli de bureau pour une marque : node prepare.js myselftherapy 21
// Écrit config.json (nom, adresse, numéro de compilation), l'icône, et les réglages de l'installateur.
const fs = require("fs"), path = require("path");
const m = (process.argv[2] || "bastion").toLowerCase().replace(/[^a-z0-9-]/g, "");
const build = parseInt(process.argv[3] || "0", 10) || 0;
const b = JSON.parse(fs.readFileSync(path.join(__dirname, "brands", m + ".json"), "utf8"));
fs.writeFileSync(path.join(__dirname, "config.json"), JSON.stringify({ name: b.name, url: b.url, appId: b.appId, build }, null, 1));
fs.mkdirSync(path.join(__dirname, "build"), { recursive: true });
fs.copyFileSync(path.join(__dirname, b.icon), path.join(__dirname, "icon.png"));
fs.copyFileSync(path.join(__dirname, b.icon), path.join(__dirname, "build", "icon.png"));
const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, "package.json"), "utf8"));
pkg.productName = b.name;
pkg.version = "1.0." + build;
pkg.build = {
  appId: b.appId,
  productName: b.name,
  artifactName: m + "-setup.exe",
  files: ["main.js", "preload.js", "config.json", "icon.png"],
  directories: { output: "dist", buildResources: "build" },
  win: { target: [{ target: "nsis", arch: ["x64"] }], icon: "build/icon.png" },
  nsis: { oneClick: true, perMachine: false, runAfterFinish: true, createDesktopShortcut: true, createStartMenuShortcut: true, shortcutName: b.name, deleteAppDataOnUninstall: false }
};
fs.writeFileSync(path.join(__dirname, "package.json"), JSON.stringify(pkg, null, 2));
console.log("marque :", b.name, "· compilation", build);
