import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqot/components/shortcut_card.dart';
import 'package:sqot/pages/doctor_appointments_page.dart';
import 'package:sqot/pages/devices_page.dart';
import 'package:sqot/pages/health_indicators_diary_page.dart';
import 'package:sqot/pages/session_page.dart';
import 'package:sqot/pages/settings_page.dart';
import 'package:sqot/pages/stats_page.dart';
import 'package:sqot/pages/womens_cycle_page.dart';

enum _MainSection {
  home,
  training,
  devices,
  womensCycle,
  doctorAppointments,
  healthDiary,
  settings,
}

extension _MainSectionX on _MainSection {
  String get title {
    switch (this) {
      case _MainSection.home:
        return 'Home';
      case _MainSection.training:
        return 'Training';
      case _MainSection.devices:
        return 'Devices';
      case _MainSection.womensCycle:
        return "Woman's Cycle";
      case _MainSection.doctorAppointments:
        return 'Doctor Appointments';
      case _MainSection.healthDiary:
        return 'Health Diary';
      case _MainSection.settings:
        return 'Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case _MainSection.home:
        return Icons.home_outlined;
      case _MainSection.training:
        return Icons.directions_bike_outlined;
      case _MainSection.devices:
        return Icons.bluetooth_outlined;
      case _MainSection.womensCycle:
        return Icons.calendar_month_outlined;
      case _MainSection.doctorAppointments:
        return Icons.medical_services_outlined;
      case _MainSection.healthDiary:
        return Icons.sticky_note_2_outlined;
      case _MainSection.settings:
        return Icons.settings_outlined;
    }
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  _MainSection _currentSection = _MainSection.home;

  void _activateSection(_MainSection section) {
    setState(() {
      _currentSection = section;
    });
  }

  int get _currentIndex => _MainSection.values.indexOf(_currentSection);

  Widget _buildDrawer(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.secondaryContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'Sqot',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _buildDrawerItem(
              context,
              section: _MainSection.home,
              onTap: () => _activateSection(_MainSection.home),
            ),
            _buildDrawerItem(
              context,
              section: _MainSection.training,
              onTap: () => _activateSection(_MainSection.training),
            ),
            _buildDrawerItem(
              context,
              section: _MainSection.womensCycle,
              onTap: () => _activateSection(_MainSection.womensCycle),
            ),
            _buildDrawerItem(
              context,
              section: _MainSection.doctorAppointments,
              onTap: () => _activateSection(_MainSection.doctorAppointments),
            ),
            _buildDrawerItem(
              context,
              section: _MainSection.healthDiary,
              onTap: () => _activateSection(_MainSection.healthDiary),
            ),
            _buildDrawerItem(
              context,
              section: _MainSection.devices,
              onTap: () => _activateSection(_MainSection.devices),
            ),
            _buildDrawerItem(
              context,
              section: _MainSection.settings,
              onTap: () => _activateSection(_MainSection.settings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required _MainSection section,
    required VoidCallback onTap,
  }) {
    final isSelected = _currentSection == section;

    return ListTile(
      leading: Icon(section.icon),
      title: Text(section.title),
      selected: isSelected,
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }

  Widget _buildHome() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          spacing: 10,
          children: [
            Row(
              spacing: 10,
              children: [
                ShortcutCard(
                  icon: const Icon(Icons.directions_bike_outlined),
                  title: 'Training',
                  onTap: () => _activateSection(_MainSection.training),
                ),
                ShortcutCard(
                  icon: const Icon(Icons.calendar_month_outlined),
                  title: "Woman's Cycle",
                  onTap: () => _activateSection(_MainSection.womensCycle),
                ),
              ],
            ),
            Row(
              spacing: 10,
              children: [
                ShortcutCard(
                  icon: const Icon(Icons.medical_services_outlined),
                  title: 'Doctor Appointments',
                  onTap: () =>
                      _activateSection(_MainSection.doctorAppointments),
                ),
                ShortcutCard(
                  icon: const Icon(Icons.sticky_note_2_outlined),
                  title: 'Health Diary',
                  onTap: () => _activateSection(_MainSection.healthDiary),
                ),
              ],
            ),
            Row(
              spacing: 10,
              children: [
                ShortcutCard(
                  icon: const Icon(Icons.bluetooth_outlined),
                  title: 'Devices',
                  onTap: () => _activateSection(_MainSection.devices),
                ),
                ShortcutCard(
                  icon: const Icon(Icons.settings_outlined),
                  title: 'Settings',
                  onTap: () => _activateSection(_MainSection.settings),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
        appBar: AppBar(
          backgroundColor: chromeColor,
          surfaceTintColor: chromeColor,
          title: Text(_currentSection.title),
        ),
        drawer: _buildDrawer(context),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildHome(),
            const TrainingPage(),
            const DevicesPage(),
            const WomensCyclePage(),
            const DoctorAppointmentsPage(),
            const HealthIndicatorsDiaryPage(),
            const SettingsPage(),
          ],
        ),
      ),
    );
  }
}

enum _TrainingSection { session, stats }

extension _TrainingSectionX on _TrainingSection {
  String get title {
    switch (this) {
      case _TrainingSection.session:
        return 'Session';
      case _TrainingSection.stats:
        return 'Stats';
    }
  }

  IconData get icon {
    switch (this) {
      case _TrainingSection.session:
        return Icons.directions_bike_outlined;
      case _TrainingSection.stats:
        return Icons.bar_chart_outlined;
    }
  }
}

class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key});

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  _TrainingSection _currentSection = _TrainingSection.session;

  void _activateSection(_TrainingSection section) {
    setState(() {
      _currentSection = section;
    });
  }

  int get _currentIndex => _TrainingSection.values.indexOf(_currentSection);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [SessionPage(), StatsPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          _activateSection(_TrainingSection.values[index]);
        },
        destinations: [
          for (final section in _TrainingSection.values)
            NavigationDestination(
              icon: Icon(section.icon),
              label: section.title,
            ),
        ],
      ),
    );
  }
}
