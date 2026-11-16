"""Appli en marque blanche : applique le nom, le serveur, les couleurs et les icônes d'une marque (dossier brands/<marque>).
À lancer après `flutter create` et `tools/patch_android.py` :  python3 tools/brand.py myselftherapy
Sans argument ou avec « bastion » : rien n'est changé (appli Bastion d'origine)."""
import glob, json, os, re, shutil, sys

m = (sys.argv[1] if len(sys.argv) > 1 else "bastion").strip().lower()
if m in ("", "bastion"):
    print("marque : Bastion (aucun changement)")
    sys.exit(0)
d = os.path.join("brands", m)
b = json.load(open(os.path.join(d, "brand.json"), encoding="utf-8"))
name, server, host = b["name"], b["server"], b["host"]

# --- textes visibles et serveur par défaut (le nom technique « BastionMobile » du navigateur intégré est gardé :
#     le serveur s'en sert pour reconnaître l'appli mobile)
for f in glob.glob("lib/*.dart"):
    s = open(f, encoding="utf-8").read()
    s = s.replace("https://bastion-secure.group", server)
    s = re.sub(r"(?<![A-Za-z])Bastion(?![A-Za-z/])", name, s)          # « Bastion » seul, pas BastionMobile/BastionApp
    s = s.replace("Color(0xFF1F4E79)", "Color(%s)" % b["seed"]).replace("Color(0xFF6FA3CF)", "Color(%s)" % b["seed_dark"])
    s = s.replace("'bastion_server_v2'", "'%s_server_v1'" % m)
    open(f, "w", encoding="utf-8").write(s)

# --- nom de l'appli et liens des e-mails
p = "android/app/src/main/AndroidManifest.xml"
s = open(p, encoding="utf-8").read()
s = s.replace('android:label="Bastion"', 'android:label="%s"' % name).replace('android:host="bastion-secure.group"', 'android:host="%s"' % host)
open(p, "w", encoding="utf-8").write(s)

# --- icônes
for src in glob.glob(os.path.join(d, "icons", "mipmap-*")):
    dest = os.path.join("android/app/src/main/res", os.path.basename(src))
    os.makedirs(dest, exist_ok=True)
    shutil.copy(os.path.join(src, "ic_launcher.png"), dest)
for src in glob.glob(os.path.join(d, "notif", "drawable-*")):
    dest = os.path.join("android/app/src/main/res", os.path.basename(src))
    os.makedirs(dest, exist_ok=True)
    for n in ("ic_stat_bastion.png", "ic_bg_service_small.png"):
        shutil.copy(os.path.join(src, "ic_stat_bastion.png"), os.path.join(dest, n))
print("marque appliquée :", name, server)
