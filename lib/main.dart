import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqot/pages/main_page.dart';
import 'package:sqot/services/settings_service.dart';

void main() {
  runApp(const SqotApp());
}

class SqotApp extends StatefulWidget {
  const SqotApp({super.key});

  @override
  State<SqotApp> createState() => _SqotAppState();
}

class _SqotAppState extends State<SqotApp> {
  final SettingsService _settingsService = SettingsService.instance;

  @override
  void initState() {
    super.initState();
    _settingsService.loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: "Sqot",
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff001ff6)),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff001ff6),
          brightness: Brightness.dark,
        ),
      ),
      home: const MainPage(),
    );
  }
}
