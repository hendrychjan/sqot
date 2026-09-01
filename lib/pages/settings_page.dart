import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqot/services/influx_service.dart';
import 'package:sqot/services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService.instance;
  final InfluxService _influxService = InfluxService.instance;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _orgController = TextEditingController();
  final TextEditingController _bucketController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _wheelCircumferenceController =
      TextEditingController();

  bool _isLoading = true;
  bool _isSavingInflux = false;
  ThemeMode _selectedThemeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _orgController.dispose();
    _bucketController.dispose();
    _tokenController.dispose();
    _wheelCircumferenceController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (!_settingsService.isInitialized) {
      await _settingsService.loadSettings();
    }
    final currentSettings = _settingsService.getCurrentSettings();

    _selectedThemeMode = currentSettings.themeSettings.mode;
    _urlController.text = currentSettings.influxSettings.url;
    _orgController.text = currentSettings.influxSettings.org;
    _bucketController.text = currentSettings.influxSettings.bucket;
    _tokenController.text = currentSettings.influxSettings.token;
    _wheelCircumferenceController.text = currentSettings
        .devicesSettings
        .wheelCircumference
        .toString();

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
    });
  }

  bool get _isInfluxFormComplete {
    return _urlController.text.trim().isNotEmpty &&
        _orgController.text.trim().isNotEmpty &&
        _bucketController.text.trim().isNotEmpty &&
        _tokenController.text.trim().isNotEmpty;
  }

  String get _influxBadgeText {
    return _isInfluxFormComplete ? 'Complete' : 'Incomplete';
  }

  Color _influxBadgeColor(BuildContext context) {
    return _isInfluxFormComplete
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;
  }

  void _clearFocus() {
    FocusScope.of(context).unfocus();
  }

  Future<void> _updateThemeMode(ThemeMode? value) async {
    if (value == null) {
      return;
    }

    _clearFocus();

    setState(() {
      _selectedThemeMode = value;
    });

    await _settingsService.updateSetting(themeMode: value);

    Get.snackbar(
      "Settings updated",
      'Theme mode set to ${_themeModeLabel(value)}.',
    );
  }

  Future<void> _testAndSaveInfluxSettings() async {
    _clearFocus();
    FocusScope.of(context).unfocus();

    if (!_isInfluxFormComplete) {
      Get.snackbar(
        "Failed to setup Influx",
        'Please fill in all Influx fields before saving.',
      );
      return;
    }

    final uri = Uri.tryParse(_urlController.text.trim());
    final hasValidUrl = uri != null && uri.hasScheme && uri.host.isNotEmpty;
    if (!hasValidUrl) {
      Get.snackbar("Failed to setup Influx", 'Enter a valid Influx URL.');
      return;
    }

    final influxUrl = _urlController.text.trim();
    final influxOrg = _orgController.text.trim();
    final influxBucket = _bucketController.text.trim();
    final influxToken = _tokenController.text.trim();

    setState(() {
      _isSavingInflux = true;
    });

    try {
      await _influxService.testConnection(
        url: influxUrl,
        org: influxOrg,
        bucket: influxBucket,
        token: influxToken,
      );

      await _settingsService.updateSetting(
        influxUrl: influxUrl,
        influxOrg: influxOrg,
        influxBucket: influxBucket,
        influxToken: influxToken,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingInflux = false;
      });

      Get.snackbar(
        "Influx setup completed",
        'Connection successful. Influx settings saved.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingInflux = false;
      });

      Get.snackbar("Failed to setup Influx", e.toString());
    }
  }

  Future<void> _saveWheelCircumference() async {
    _clearFocus();

    final rawValue = _wheelCircumferenceController.text.trim();
    final parsedValue = int.tryParse(rawValue);

    if (parsedValue == null || parsedValue <= 0) {
      Get.snackbar(
        'Invalid wheel circumference',
        'Please enter a positive integer value in millimeters.',
      );
      return;
    }

    await _settingsService.updateSetting(wheelCircumference: parsedValue);

    if (!mounted) {
      return;
    }

    Get.snackbar(
      'Devices settings updated',
      'Wheel circumference saved as $parsedValue mm.',
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  Widget _buildSectionTitle(String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildThemeSection() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Theme'),
          const SizedBox(height: 12),
          DropdownButtonFormField<ThemeMode>(
            initialValue: _selectedThemeMode,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Theme mode',
            ),
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
            onChanged: _updateThemeMode,
          ),
        ],
      ),
    );
  }

  Widget _buildInfluxSection() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Influx',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _influxBadgeColor(context).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _influxBadgeColor(context)),
              ),
              child: Text(
                _influxBadgeText,
                style: TextStyle(
                  color: _influxBadgeColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            onTapOutside: (_) => _clearFocus(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Influx URL',
              hintText: 'https://your-influx-host:8086',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _orgController,
            onTapOutside: (_) => _clearFocus(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Organization',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bucketController,
            onTapOutside: (_) => _clearFocus(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Bucket',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            obscureText: true,
            onTapOutside: (_) => _clearFocus(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Token',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSavingInflux ? null : _testAndSaveInfluxSettings,
              icon: _isSavingInflux
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_done_outlined),
              label: Text(_isSavingInflux ? 'Testing...' : 'Test and save'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesSection() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Devices'),
          const SizedBox(height: 12),
          TextField(
            controller: _wheelCircumferenceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            onTapOutside: (_) => _clearFocus(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Wheel circumference (mm)',
              hintText: 'e.g. 2105',
              helperText: 'Use the tire circumference in millimeters',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saveWheelCircumference,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save wheel circumference'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildThemeSection(),
        const SizedBox(height: 16),
        _buildDevicesSection(),
        const SizedBox(height: 16),
        _buildInfluxSection(),
      ],
    );
  }
}
