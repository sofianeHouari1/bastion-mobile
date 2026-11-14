import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notify_service.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'config.dart';
import 'settings_page.dart';

/// Coque Android : affiche l'interface Bastion de l'instance en plein ecran.
/// - la connexion Keycloak se fait dans la page, la session est conservee entre deux lancements ;
/// - camera et micro sont autorises pour les appels (apres l'accord Android de l'utilisateur) ;
/// - le navigateur integre s'annonce avec "BastionMobile/x.y" : le serveur sait ainsi que la connexion vient du mobile.
class WebShell extends StatefulWidget {
  const WebShell({super.key, required this.config});
  final AppConfig config;

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> with WidgetsBindingObserver {
  static const _native = MethodChannel('fr.bastion/native');
  InAppWebViewController? _web;
  double _progress = 0;
  String? _error;
  int _generation = 0; // change pour recreer la page apres un changement de serveur
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _askPermissions();
    _native.invokeMethod('clearNotifications').catchError((_) {});
    initNotifications(onTap: _onNotificationTap);
    _native.setMethodCallHandler((call) async {
      if (call.method == 'openLink') _openLink(call.arguments as String?);
      return null;
    });
  }

  /// Lien d'un e-mail Bastion (invitation, rappel) : on l'ouvre dans la page si c'est le meme serveur.
  void _openLink(String? link) {
    if (link == null || link.isEmpty) return;
    final u = Uri.tryParse(link);
    final server = Uri.tryParse(widget.config.serverUrl);
    if (u == null || server == null || u.scheme != 'https' || u.host != server.host) return;
    _web?.loadUrl(urlRequest: URLRequest(url: WebUri(link)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    _resumed = fg;
    if (fg) {
      // La page a pu etre mise en veille par Android : on la reveille et elle affiche tout de suite l'appel en cours.
      _web?.resumeTimers().catchError((_) {});
      _web?.evaluateJavascript(source: 'window.__bmResume && window.__bmResume();').catchError((_) => null);
    }
    FlutterBackgroundService().invoke('fg', {'v': fg});
    if (fg) {
      _native.invokeMethod('clearNotifications').catchError((_) {});
      Future.delayed(const Duration(seconds: 2), () => _native.invokeMethod('clearNotifications').catchError((_) {}));
    }
    _saveSession();
  }

  void _onNotificationTap(NotificationResponse r) {
    _native.invokeMethod('clearNotifications').catchError((_) {});
    try {
      final p = jsonDecode(r.payload ?? '{}') as Map<String, dynamic>;
      if (p['t'] == 'call') {
        // L'appel est deja en train de sonner cote serveur : on decroche des que la page le recoit.
        _web?.evaluateJavascript(source: 'window.__autoAccept = true;');
      }
    } catch (_) {}
  }

  /// Memorise la session (cookie) et les choix de sonnerie pour que le service d'arriere-plan puisse se connecter.
  Future<void> _saveSession() async {
    try {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(widget.config.serverUrl));
      final header = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      final prefs = await SharedPreferences.getInstance();
      if (header.isNotEmpty) {
        await prefs.setString(kPrefCookie, header);
        await prefs.setString(kPrefServer, widget.config.serverUrl);
        final svc = FlutterBackgroundService();
        if (!await svc.isRunning()) await svc.startService();
        svc.invoke('fg', {'v': WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed});
      }
    } catch (_) {}
  }

  Future<void> _askPermissions() async {
    // Demande au demarrage : l'utilisateur n'est plus interrompu au milieu du premier appel.
    await [Permission.camera, Permission.microphone, Permission.notification].request();
    // Sans cette exemption, Android coupe parfois la connexion en arriere-plan et les appels n'arrivent plus.
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SettingsPage(config: widget.config)));
    if (changed == true && mounted) {
      setState(() {
        _error = null;
        _progress = 0;
        _generation++;
      });
    }
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _progress = 0;
    });
    await _web?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(widget.config.serverUrl)?.host ?? '';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // 1) la page Bastion traite le retour elle-meme (ferme la discussion, une fenetre, revient a la liste)
        try {
          final r = await _web?.evaluateJavascript(source: 'window.__androidBack ? window.__androidBack() : false');
          if (r == true) return;
        } catch (_) {}
        // 2) pages de connexion (Keycloak) : retour classique du navigateur
        final url = (await _web?.getUrl())?.toString() ?? '';
        if (url.isNotEmpty && !url.startsWith(widget.config.serverUrl) && _web != null && await _web!.canGoBack()) {
          await _web!.goBack();
          return;
        }
        // 3) sur la liste des discussions : l'appli passe en arriere-plan (elle reste connectee pour les notifications)
        _native.invokeMethod('minimize').catchError((_) {});
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(children: [
            InAppWebView(
              key: ValueKey('web-$_generation-${widget.config.serverUrl}'),
              initialUrlRequest: URLRequest(url: WebUri(widget.config.serverUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                applicationNameForUserAgent: 'BastionMobile/0.3',
                useShouldOverrideUrlLoading: true,
                supportZoom: false,
                thirdPartyCookiesEnabled: true,
              ),
              onWebViewCreated: (c) {
                _web = c;
                _native.invokeMethod('initialLink').then((l) => _openLink(l as String?)).catchError((_) {});
                // Haut-parleur : renvoie l'etat reel obtenu (true = son sur le haut-parleur) pour que le bouton l'affiche.
                c.addJavaScriptHandler(handlerName: 'speaker', callback: (args) async {
                  try {
                    final r = await _native.invokeMethod('speaker', {'on': args.isNotEmpty && args[0] == true});
                    return r == true;
                  } catch (_) {
                    return null;
                  }
                });
                // Fin d'appel : rend le son au mode normal (sinon le telephone peut rester bloque sur le haut-parleur ou l'ecouteur).
                c.addJavaScriptHandler(handlerName: 'audioReset', callback: (args) async {
                  try { await _native.invokeMethod('audioReset'); } catch (_) {}
                  return true;
                });
                // Appel recu par la page : si l'appli n'est pas au premier plan, vraie notification d'appel (plein ecran + Decrocher).
                c.addJavaScriptHandler(handlerName: 'incomingCall', callback: (args) async {
                  if (_resumed) return false;
                  final m = (args.isNotEmpty && args[0] is Map) ? args[0] as Map : const {};
                  final prefs = await SharedPreferences.getInstance();
                  await showCallNotification(prefs, name: (m['name'] ?? 'Correspondant').toString(), from: (m['from'] ?? '').toString());
                  return true;
                });
                // Fin d'appel (decroche, refuse, raccroche) : on retire la notification et sa sonnerie.
                c.addJavaScriptHandler(handlerName: 'callEnded', callback: (args) async {
                  await notifications.cancel(kCallNotifId);
                  return true;
                });
                c.addJavaScriptHandler(handlerName: 'prefs', callback: (args) async {
                  if (args.isEmpty || args[0] is! Map) return;
                  final m = args[0] as Map;
                  final prefs = await SharedPreferences.getInstance();
                  if (m['ring'] is String) await prefs.setString(kPrefRing, m['ring']);
                  if (m['tone'] is String) await prefs.setString(kPrefTone, m['tone']);
                  _saveSession();
                });
              },
              onLoadStop: (c, u) => _saveSession(),
              onProgressChanged: (c, p) => setState(() => _progress = p / 100),
              onLoadStart: (c, u) => setState(() => _error = null),
              onReceivedError: (c, request, error) {
                // On ne signale que les echecs de la page principale (pas ceux d'une image ou d'un script).
                if (request.isForMainFrame ?? false) {
                  setState(() => _error = error.description);
                }
              },
              onPermissionRequest: (c, request) async {
                // La page Bastion de l'instance configuree peut utiliser camera et micro, rien d'autre.
                final ok = request.origin.host == host;
                return PermissionResponse(
                  resources: request.resources,
                  action: ok ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY,
                );
              },
              shouldOverrideUrlLoading: (c, action) async {
                final scheme = action.request.url?.scheme ?? '';
                // Seuls http(s) restent dans l'appli ; tel:, intent:, etc. sont ignores.
                return (scheme == 'https' || scheme == 'http') ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL;
              },
            ),
            if (_progress < 1 && _error == null) LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 3),
            if (_error != null) _ErrorView(message: _error!, server: widget.config.serverUrl, onRetry: _retry, onSettings: _openSettings),
          ]),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.server, required this.onRetry, required this.onSettings});
  final String message;
  final String server;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 56),
          const SizedBox(height: 16),
          const Text('Bastion est injoignable', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(server, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 24),
          FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          TextButton(onPressed: onSettings, child: const Text('Changer de serveur')),
        ]),
      ),
    );
  }
}
