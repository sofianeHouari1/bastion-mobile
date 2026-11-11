import 'package:shared_preferences/shared_preferences.dart';

/// Configuration : une seule adresse, celle de l'instance Bastion.
/// Keycloak, le canal SIP/Asterisk et les relais TURN sont fournis par l'instance elle-meme apres connexion.
class AppConfig {
  static const defaultServer = 'https://bastion-secure.group';
  static const _key = 'bastion_server_v2';

  String serverUrl;
  AppConfig({this.serverUrl = defaultServer});

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    return AppConfig(serverUrl: p.getString(_key) ?? defaultServer);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, normalize(serverUrl));
  }

  /// Ajoute https:// si absent, retire les espaces et le "/" final.
  static String normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return defaultServer;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// L'appli exige HTTPS : les communications ne doivent jamais circuler en clair.
  static bool isValid(String raw) {
    final u = Uri.tryParse(normalize(raw));
    return u != null && u.scheme == 'https' && u.host.contains('.');
  }
}
