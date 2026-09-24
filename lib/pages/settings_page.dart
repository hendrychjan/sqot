import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqot/components/app_snackbar.dart';
import 'package:sqot/services/gpx_route_parser.dart';
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
  final TextEditingController _statisticsWindowMinutesController =
      TextEditingController();

  bool _isLoading = true;
  bool _isSavingInflux = false;
  bool _isImportingRoute = false;
  bool _autoMapRotationEnabled = true;
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
    _statisticsWindowMinutesController.dispose();
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
    _statisticsWindowMinutesController.text = currentSettings
        .devicesSettings
        .statisticsWindowMinutes
        .toString();
    _autoMapRotationEnabled =
        currentSettings.devicesSettings.autoMapRotationEnabled;

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

    AppSnackbar.show(
      "Settings updated",
      'Theme mode set to ${_themeModeLabel(value)}.',
    );
  }

  Future<void> _testAndSaveInfluxSettings() async {
    _clearFocus();
    FocusScope.of(context).unfocus();

    if (!_isInfluxFormComplete) {
      AppSnackbar.show(
        "Failed to setup Influx",
        'Please fill in all Influx fields before saving.',
      );
      return;
    }

    final uri = Uri.tryParse(_urlController.text.trim());
    final hasValidUrl = uri != null && uri.hasScheme && uri.host.isNotEmpty;
    if (!hasValidUrl) {
      AppSnackbar.show("Failed to setup Influx", 'Enter a valid Influx URL.');
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

      AppSnackbar.show(
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

      AppSnackbar.show("Failed to setup Influx", e.toString());
    }
  }

  Future<void> _saveWheelCircumference() async {
    _clearFocus();

    final rawValue = _wheelCircumferenceController.text.trim();
    final parsedValue = int.tryParse(rawValue);

    if (parsedValue == null || parsedValue <= 0) {
      AppSnackbar.show(
        'Invalid wheel circumference',
        'Please enter a positive integer value in millimeters.',
      );
      return;
    }

    await _settingsService.updateSetting(wheelCircumference: parsedValue);

    if (!mounted) {
      return;
    }

    AppSnackbar.show(
      'Devices settings updated',
      'Wheel circumference saved as $parsedValue mm.',
    );
  }

  Future<void> _saveStatisticsWindowMinutes() async {
    _clearFocus();

    final rawValue = _statisticsWindowMinutesController.text.trim();
    final parsedValue = int.tryParse(rawValue);

    if (parsedValue == null || parsedValue <= 0) {
      AppSnackbar.show(
        'Invalid statistics window',
        'Please enter a positive integer value in minutes.',
      );
      return;
    }

    await _settingsService.updateSetting(statisticsWindowMinutes: parsedValue);

    if (!mounted) {
      return;
    }

    AppSnackbar.show(
      'Devices settings updated',
      'Statistics window saved as $parsedValue minute(s).',
    );
  }

  Future<void> _toggleAutoMapRotation(bool enabled) async {
    _clearFocus();

    setState(() {
      _autoMapRotationEnabled = enabled;
    });

    await _settingsService.updateSetting(autoMapRotationEnabled: enabled);

    if (!mounted) {
      return;
    }

    AppSnackbar.show(
      'Devices settings updated',
      enabled
          ? 'Automatic map rotation is enabled.'
          : 'Automatic map rotation is disabled.',
    );
  }

  Future<void> _importGpsRoute() async {
    _clearFocus();

    setState(() {
      _isImportingRoute = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gpx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _isImportingRoute = false;
        });
        return;
      }

      final pickedFile = result.files.single;
      final rawBytes = pickedFile.bytes;

      if (rawBytes == null || rawBytes.isEmpty) {
        throw Exception('The selected GPX file could not be read.');
      }

      final gpxContent = utf8.decode(rawBytes, allowMalformed: true).trim();
      final containsGpxTag = gpxContent.toLowerCase().contains('<gpx');

      if (!containsGpxTag) {
        throw Exception('The selected file does not look like a GPX route.');
      }

      await _settingsService.saveImportedRoute(
        fileName: pickedFile.name,
        gpxContent: gpxContent,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isImportingRoute = false;
      });

      AppSnackbar.show(
        'Route imported',
        '${pickedFile.name} is now available in settings.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isImportingRoute = false;
      });

      AppSnackbar.show('GPX import failed', e.toString());
    }
  }

  Future<void> _clearImportedRoute() async {
    _clearFocus();

    await _settingsService.clearImportedRoute();

    if (!mounted) {
      return;
    }

    setState(() {});

    AppSnackbar.show(
      'Route cleared',
      'The imported GPX route has been removed.',
    );
  }

  Future<void> _openRouteDetail(List<LatLng> routePoints) async {
    if (routePoints.length < 2) {
      AppSnackbar.show(
        'No route to preview',
        'Import a GPX route with at least 2 points to view details.',
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: _SettingsRouteDetailSheet(routePoints: routePoints),
        );
      },
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
          const SizedBox(height: 12),
          TextField(
            controller: _statisticsWindowMinutesController,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            onTapOutside: (_) => _clearFocus(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Statistics window (minutes)',
              hintText: 'e.g. 5',
              helperText: 'Window size used for last X minutes average streams',
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _autoMapRotationEnabled,
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto map rotation'),
            subtitle: const Text(
              'Rotate session maps based on device heading.',
            ),
            onChanged: _toggleAutoMapRotation,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveWheelCircumference,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save wheel size'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveStatisticsWindowMinutes,
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Save stats window'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGpsRouteSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final devicesSettings = _settingsService
        .getCurrentSettings()
        .devicesSettings;
    final importedRouteFileName = devicesSettings.importedRouteFileName;
    final routePoints = parseGpxRoute(devicesSettings.importedRouteGpxContent);
    final hasImportedRoute = importedRouteFileName != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('GPS route'),
          const SizedBox(height: 12),
          Text(
            hasImportedRoute ? importedRouteFileName : 'No GPX route imported.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isImportingRoute ? null : _importGpsRoute,
                  icon: _isImportingRoute
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          hasImportedRoute
                              ? Icons.swap_horiz_rounded
                              : Icons.upload_file_outlined,
                        ),
                  label: Text(
                    _isImportingRoute
                        ? 'Importing...'
                        : (hasImportedRoute ? 'Replace GPX' : 'Import GPX'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasImportedRoute ? _clearImportedRoute : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear route'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: routePoints.length >= 2
                  ? () => _openRouteDetail(routePoints)
                  : null,
              icon: const Icon(Icons.map_outlined),
              label: const Text('View route detail'),
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
        _buildGpsRouteSection(),
        const SizedBox(height: 16),
        _buildInfluxSection(),
      ],
    );
  }
}

class _SettingsRouteDetailSheet extends StatefulWidget {
  final List<LatLng> routePoints;

  const _SettingsRouteDetailSheet({required this.routePoints});

  @override
  State<_SettingsRouteDetailSheet> createState() =>
      _SettingsRouteDetailSheetState();
}

class _SettingsRouteDetailSheetState extends State<_SettingsRouteDetailSheet> {
  final MapController _mapController = MapController();

  LatLng get _center => _routeCenter(widget.routePoints);

  void _moveBy(double latFactor, double lonFactor) {
    final zoom = _mapController.camera.zoom;
    final step = 0.02 / math.pow(2, (zoom - 12).clamp(0, 8));
    final center = _mapController.camera.center;
    _mapController.move(
      LatLng(
        center.latitude + latFactor * step,
        center.longitude + lonFactor * step,
      ),
      zoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _center, initialZoom: 16),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'xyz.hendrychjan.sqot',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.routePoints,
                    strokeWidth: 5,
                    color: Colors.blueAccent,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.routePoints.first,
                    width: 34,
                    height: 34,
                    child: const Icon(
                      Icons.flag_circle,
                      color: Colors.green,
                      size: 28,
                    ),
                  ),
                  Marker(
                    point: widget.routePoints.last,
                    width: 34,
                    height: 34,
                    child: const Icon(
                      Icons.flag,
                      color: Colors.redAccent,
                      size: 28,
                    ),
                  ),
                ],
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            child: FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              label: const Text('Close'),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'settings-map-zoom-in',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'settings-map-zoom-out',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'settings-map-center',
                  onPressed: () =>
                      _mapController.move(_center, _mapController.camera.zoom),
                  child: const Icon(Icons.center_focus_strong_rounded),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            bottom: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'settings-map-up',
                  onPressed: () => _moveBy(1, 0),
                  child: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
                Row(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'settings-map-left',
                      onPressed: () => _moveBy(0, -1),
                      child: const Icon(Icons.keyboard_arrow_left_rounded),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton.small(
                      heroTag: 'settings-map-right',
                      onPressed: () => _moveBy(0, 1),
                      child: const Icon(Icons.keyboard_arrow_right_rounded),
                    ),
                  ],
                ),
                FloatingActionButton.small(
                  heroTag: 'settings-map-down',
                  onPressed: () => _moveBy(-1, 0),
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

LatLng _routeCenter(List<LatLng> points) {
  if (points.isEmpty) {
    return const LatLng(50.0755, 14.4378);
  }

  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  var minLon = points.first.longitude;
  var maxLon = points.first.longitude;

  for (final point in points.skip(1)) {
    minLat = math.min(minLat, point.latitude);
    maxLat = math.max(maxLat, point.latitude);
    minLon = math.min(minLon, point.longitude);
    maxLon = math.max(maxLon, point.longitude);
  }

  return LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
}
