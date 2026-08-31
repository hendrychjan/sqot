import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqot/pages/main_page.dart';
import 'package:sqot/services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.loadSettings();
  runApp(const SqotApp());
}

class SqotApp extends StatefulWidget {
  const SqotApp({super.key});

  @override
  State<SqotApp> createState() => _SqotAppState();
}

class _SqotAppState extends State<SqotApp> with WidgetsBindingObserver {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: "Sqot",
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainPage(),
    );
  }
}
