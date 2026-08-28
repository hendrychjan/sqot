import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqot/pages/devices_page.dart';
import 'package:sqot/pages/session_page.dart';
import 'package:sqot/pages/settings_page.dart';
import 'package:sqot/pages/stats_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    SessionPage(),
    DevicesPage(),
    StatsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chromeColor = colorScheme.surface;
    final isDarkChrome =
        ThemeData.estimateBrightnessForColor(chromeColor) == Brightness.dark;

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: chromeColor,
      statusBarIconBrightness: isDarkChrome
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: isDarkChrome ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: chromeColor,
      systemNavigationBarIconBrightness: isDarkChrome
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: chromeColor,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: chromeColor,
        body: SafeArea(
          top: true,
          bottom: false,
          child: IndexedStack(index: _currentIndex, children: _pages),
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: chromeColor,
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.directions_bike),
              label: 'Session',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bluetooth),
              label: "Devices",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              label: 'Stats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
