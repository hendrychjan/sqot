import 'package:flutter/material.dart';
import 'package:sqot/services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService.instance;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _orgController = TextEditingController();
  final TextEditingController _bucketController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

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
    super.dispose();
  }

  Future<void> _loadSettings() async {
    await _settingsService.loadSettings();
    final currentSettings = _settingsService.getCurrentSettings();

    _selectedThemeMode = currentSettings.themeSettings.mode;
    _urlController.text = currentSettings.influxSettings.url;
    _orgController.text = currentSettings.influxSettings.org;
    _bucketController.text = currentSettings.influxSettings.bucket;
    _tokenController.text = currentSettings.influxSettings.token;

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

  Future<void> _updateThemeMode(ThemeMode? value) async {
    if (value == null) {
      return;
    }

    setState(() {
      _selectedThemeMode = value;
    });

    await _settingsService.updateSetting(themeMode: value);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Theme updated to ${_themeModeLabel(value)}')),
    );
  }

  Future<void> _testAndSaveInfluxSettings() async {
    FocusScope.of(context).unfocus();

    if (!_isInfluxFormComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all Influx fields before saving.'),
        ),
      );
      return;
    }

    final uri = Uri.tryParse(_urlController.text.trim());
    final hasValidUrl = uri != null && uri.hasScheme && uri.host.isNotEmpty;
    if (!hasValidUrl) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Influx URL is not valid.')));
      return;
    }

    setState(() {
      _isSavingInflux = true;
    });

    await _settingsService.updateSetting(
      influxUrl: _urlController.text.trim(),
      influxOrg: _orgController.text.trim(),
      influxBucket: _bucketController.text.trim(),
      influxToken: _tokenController.text.trim(),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSavingInflux = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Influx settings tested and saved.')),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Theme'),
          const SizedBox(height: 12),
          DropdownButtonFormField<ThemeMode>(
            value: _selectedThemeMode,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Organization',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bucketController,
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
        _buildInfluxSection(),
      ],
    );
  }
}
