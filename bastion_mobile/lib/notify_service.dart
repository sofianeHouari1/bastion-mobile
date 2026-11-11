import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notifications Bastion quand l'appli est fermee.
///
/// Principe (sans Google/Firebase) : un petit service Android reste connecte au serveur de l'instance
/// (flux SSE /api/notify/stream, authentifie avec la session de l'utilisateur) et affiche une
/// notification a l'arrivee d'un message ou d'un appel. Toucher la notification ouvre l'appli,
/// qui se reconnecte et decroche.
const kServiceChannel = 'bastion_service';
const kPrefCookie = 'bastion_cookie';
const kPrefServer = 'bastion_server_for_cookie';
const kPrefRing = 'bastion_ring';
const kPrefTone = 'bastion_tone';

final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

const _ringRaw = {
  'classique': 'ring_iphone',
  'doux': 'ring_doux',
  'cristal': 'ring_cristal',
  'sonar': 'ring_sonar',
};

/// Initialise le plugin de notifications (appele dans l'appli ET dans le service).
Future<void> initNotifications({void Function(NotificationResponse)? onTap}) async {
  await notifications.initialize(
    const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    onDidReceiveNotificationResponse: onTap,
  );
  final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(const AndroidNotificationChannel(
    kServiceChannel,
    'Connexion Bastion',
    description: 'Maintient la connexion pour recevoir vos appels et messages.',
    importance: Importance.low,
    playSound: false,
    showBadge: false,
  ));
  for (final e in _ringRaw.entries) {
    await android?.createNotificationChannel(AndroidNotificationChannel(
      'calls_${e.key}',
      'Appels (${e.key})',
      description: 'Appels entrants',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(e.value),
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    ));
  }
  await android?.createNotificationChannel(const AndroidNotificationChannel(
    'msg_sound',
    'Messages',
    description: 'Nouveaux messages',
    importance: Importance.high,
  ));
  await android?.createNotificationChannel(const AndroidNotificationChannel(
    'msg_silent',
    'Messages (silencieux)',
    description: 'Nouveaux messages, sans son',
    importance: Importance.high,
    playSound: false,
  ));
}

Future<void> configureBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: kServiceChannel,
      initialNotificationTitle: 'Bastion',
      initialNotificationContent: 'Connexion en cours…',
      foregroundServiceNotificationId: 4242,
      foregroundServiceTypes: [AndroidForegroundType.remoteMessaging],
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

/// Point d'entree du service (tourne dans son propre processus Dart).
@pragma('vm:entry-point')
Future<void> onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await initNotifications();

  var foreground = false;
  var stop = false;
  service.on('fg').listen((e) => foreground = (e?['v'] == true));
  service.on('stop').listen((e) {
    stop = true;
    service.stopSelf();
  });

  void status(String text) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(title: 'Bastion', content: text);
    }
  }

  var wait = 3;
  while (!stop) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final server = prefs.getString(kPrefServer) ?? '';
    final cookie = prefs.getString(kPrefCookie) ?? '';
    if (server.isEmpty || cookie.isEmpty) {
      status('Connectez-vous dans l\'appli pour recevoir les appels.');
      await Future<void>.delayed(const Duration(seconds: 20));
      continue;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('$server/api/notify/stream'));
      req.headers.set('Cookie', cookie);
      req.headers.set('Accept', 'text/event-stream');
      final resp = await req.close();
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        status('Session expirée : rouvrez Bastion pour vous reconnecter.');
        await resp.drain<void>();
        await Future<void>.delayed(const Duration(seconds: 60));
        continue;
      }
      if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
      status('Connecté · appels et messages actifs');
      wait = 3;
      await for (final line in resp.transform(utf8.decoder).transform(const LineSplitter())) {
        if (stop) break;
        if (!line.startsWith('data: ')) continue;
        try {
          final ev = jsonDecode(line.substring(6)) as Map<String, dynamic>;
          if (!foreground) await _show(ev, prefs);
        } catch (_) {}
      }
    } catch (_) {
      status('Hors connexion · nouvelle tentative…');
    } finally {
      client.close(force: true);
    }
    if (stop) break;
    await Future<void>.delayed(Duration(seconds: wait));
    wait = wait < 60 ? wait * 2 : 60;
  }
}

int _idFor(String s) => s.hashCode & 0x7fffffff;

Future<void> _show(Map<String, dynamic> ev, SharedPreferences prefs) async {
  final name = (ev['name'] ?? ev['from'] ?? 'Bastion').toString();
  final from = (ev['from'] ?? '').toString();
  if (ev['type'] == 'call') {
    final ring = _ringRaw.containsKey(prefs.getString(kPrefRing)) ? prefs.getString(kPrefRing)! : 'classique';
    final group = ev['group'] == true;
    final title = group ? 'Appel de groupe · ${ev['salon'] ?? 'Salon'}' : 'Appel de $name';
    await notifications.show(
      7001,
      title,
      group ? '$name vous appelle' : 'Appel entrant · Bastion',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'calls_$ring',
          'Appels ($ring)',
          channelDescription: 'Appels entrants',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: true,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(_ringRaw[ring]!),
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT : la sonnerie se repete
          timeoutAfter: 40000,
          actions: const [AndroidNotificationAction('accept', 'Décrocher', showsUserInterface: true)],
        ),
      ),
      payload: jsonEncode({'t': 'call', 'from': from}),
    );
  } else {
    final silent = prefs.getString(kPrefTone) == 'aucun';
    await notifications.show(
      _idFor('m$from'),
      name,
      (ev['preview'] ?? '').toString(),
      NotificationDetails(
        android: AndroidNotificationDetails(
          silent ? 'msg_silent' : 'msg_sound',
          silent ? 'Messages (silencieux)' : 'Messages',
          channelDescription: 'Nouveaux messages',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          playSound: !silent,
        ),
      ),
      payload: jsonEncode({'t': 'msg', 'from': from}),
    );
  }
}
