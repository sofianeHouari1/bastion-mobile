import 'package:flutter/material.dart';
import 'config.dart';
import 'notify_service.dart';
import 'web_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  await configureBackgroundService();
  runApp(BastionApp(config: config));
}

class BastionApp extends StatelessWidget {
  const BastionApp({super.key, required this.config});
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    // Charte Bastion : theme sombre par defaut (suit le systeme).
    const brand = Color(0xFF6FA3CF);
    return MaterialApp(
      title: 'Bastion',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F4E79)), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.dark, surface: const Color(0xFF161E25)),
        scaffoldBackgroundColor: const Color(0xFF0E1419),
        useMaterial3: true,
      ),
      home: WebShell(config: config),
    );
  }
}
