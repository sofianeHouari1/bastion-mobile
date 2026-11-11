"""Adapte le projet Android genere par `flutter create` : permissions, service d'arriere-plan, sonneries, activite principale."""
import glob, os, re, shutil

# --- Manifeste
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p).read()
names = ['INTERNET', 'CAMERA', 'RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS', 'ACCESS_NETWORK_STATE', 'BLUETOOTH_CONNECT', 'WAKE_LOCK',
         'POST_NOTIFICATIONS', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_REMOTE_MESSAGING', 'RECEIVE_BOOT_COMPLETED',
         'USE_FULL_SCREEN_INTENT', 'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS', 'VIBRATE']
perms = ''.join('    <uses-permission android:name="android.permission.%s"/>\n' % x for x in names)
s = s.replace('<application', perms + '    <application', 1)
s = s.replace('android:label="bastion_mobile"', 'android:label="Bastion"')
if 'xmlns:tools' not in s:
    s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
service = ('        <service android:name="id.flutter.flutter_background_service.BackgroundService" android:exported="true" '
           'android:foregroundServiceType="remoteMessaging" tools:replace="android:foregroundServiceType" tools:node="merge"/>\n')
s = s.replace('</application>', service + '    </application>', 1)
s = s.replace('<activity ', '<activity android:showWhenLocked="true" android:turnScreenOn="true" ', 1)
open(p, 'w').write(s)

# --- Sonneries natives
os.makedirs('android/app/src/main/res/raw', exist_ok=True)
for f in glob.glob('android_res/raw/*.wav'):
    shutil.copy(f, 'android/app/src/main/res/raw/')

# --- Desugaring (requis par flutter_local_notifications)
for g in ('android/app/build.gradle.kts', 'android/app/build.gradle'):
    if not os.path.exists(g):
        continue
    t = open(g).read()
    if g.endswith('.kts'):
        t = re.sub(r'compileOptions\s*\{', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', t, 1)
        t += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    else:
        t = re.sub(r'compileOptions\s*\{', 'compileOptions {\n        coreLibraryDesugaringEnabled true', t, 1)
        t += '\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n}\n'
    open(g, 'w').write(t)

# --- Activite principale (haut-parleur, effacement de la notification d'appel)
kt = glob.glob('android/app/src/main/kotlin/**/MainActivity.kt', recursive=True)[0]
pkg = re.search(r'package\s+([\w.]+)', open(kt).read()).group(1)
open(kt, 'w').write(open('android_res/MainActivity.kt.tmpl').read().replace('__PKG__', pkg))
print('patch Android applique, package', pkg)
