import 'package:flutter/material.dart';
import 'config.dart';

/// Ecran "Serveur" : l'adresse de l'instance Bastion (utile pour changer d'instance ou de client).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.config});
  final AppConfig config;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url = TextEditingController(text: widget.config.serverUrl);
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!AppConfig.isValid(_url.text)) {
      setState(() => _error = 'Adresse invalide. Exemple : https://bastion-secure.group (HTTPS obligatoire).');
      return;
    }
    widget.config.serverUrl = AppConfig.normalize(_url.text);
    await widget.config.save();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Serveur')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Adresse de votre instance Bastion', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: AppConfig.defaultServer,
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          const Text('Les connexions se font toujours en HTTPS. Les autres réglages (appels, messagerie) sont fournis par l\'instance.'),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
          TextButton(
            onPressed: () => setState(() {
              _url.text = AppConfig.defaultServer;
              _error = null;
            }),
            child: const Text('Remettre l\'adresse par défaut'),
          ),
        ],
      ),
    );
  }
}
