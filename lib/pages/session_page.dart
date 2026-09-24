import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqot/components/app_snackbar.dart';
import 'package:sqot/models/data_point.dart';
import 'package:sqot/models/device_type.dart';
import 'package:sqot/models/monitors/ble_cycling_cadence_monitor.dart';
import 'package:sqot/models/monitors/ble_cycling_speed_monitor.dart';
import 'package:sqot/models/monitors/ble_generic_monitor.dart';
import 'package:sqot/models/monitors/ble_heartrate_monitor.dart';
import 'package:sqot/models/settings/devices_settings.dart';
import 'package:sqot/models/training_session.dart';
import 'package:sqot/services/ble_service.dart';
import 'package:sqot/services/gpx_route_parser.dart';
import 'package:sqot/services/location_service.dart';
import 'package:sqot/services/settings_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final ValueNotifier<bool> sessionLayoutPreviewVisibleNotifier =
    ValueNotifier<bool>(false);
final ValueNotifier<bool> sessionRunningNotifier = ValueNotifier<bool>(false);

class _SessionMonitorSelection {
  final bool useHeartrate;
  final bool useCyclingSpeed;
  final bool useCyclingCadence;
  final bool useLocation;

  const _SessionMonitorSelection({
    this.useHeartrate = false,
    this.useCyclingSpeed = false,
    this.useCyclingCadence = false,
    this.useLocation = false,
  });

  bool get hasAnySelection =>
      useHeartrate || useCyclingSpeed || useCyclingCadence || useLocation;

  List<({DeviceType type, String label})> requiredDeviceTypes() {
    final required = <({DeviceType type, String label})>[];
    if (useHeartrate) {
      required.add((type: DeviceType.heartRateMonitor, label: 'Heart rate'));
    }
    if (useCyclingSpeed) {
      required.add((type: DeviceType.cyclingSpeedMonitor, label: 'Speed'));
    }
    if (useCyclingCadence) {
      required.add((type: DeviceType.cyclingCadenceMonitor, label: 'Cadence'));
    }
    return required;
  }

  String label() {
    final labels = <String>[];
    if (useHeartrate) labels.add('Heart rate');
    if (useCyclingSpeed) labels.add('Speed');
    if (useCyclingCadence) labels.add('Cadence');
    if (useLocation) labels.add('Location');
    return labels.isEmpty ? 'Custom session' : labels.join(', ');
  }
}

class SessionPage extends StatefulWidget {
  const SessionPage({super.key});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  static const double _dashboardPagePadding = 12;
  static const double _dashboardSectionSpacing = 12;

  final SettingsService _settingsService = SettingsService.instance;
  final LocationService _locationService = LocationService.instance;

  final List<StreamSubscription<dynamic>> _recordingSubscriptions =
      <StreamSubscription<dynamic>>[];
  final Map<String, num?> _latestMetricValues = <String, num?>{};
  final Map<String, StreamSubscription<dynamic>> _uiSubscriptions =
      <String, StreamSubscription<dynamic>>{};
  final Map<String, String> _monitorConnectionState = <String, String>{};
  final List<DataPoint> _sessionDataPoints = <DataPoint>[];
  final List<LatLng> _importedRoutePoints = <LatLng>[];

  bool _isLoadingSession = true;
  bool _isSessionPrepared = false;
  bool _isSessionRunning = false;
  bool _isSessionPaused = false;

  bool _isPreparingConnection = false;
  bool _prepareCancelled = false;
  String _prepareStatus = 'Waiting to start...';
  void Function(VoidCallback fn)? _prepareDialogSetState;
  bool _isStoppingSession = false;
  String _stopStatus = 'Stopping session...';
  void Function(VoidCallback fn)? _stopDialogSetState;
  bool _isStopDialogVisible = false;

  _SessionMonitorSelection? _selectedSessionMonitors;
  DateTime? _sessionStartedAt;
  final List<BleGenericMonitor> _preparedMonitors = <BleGenericMonitor>[];
  bool _wakeLockEnabled = false;
  LatLng? _currentLocation;
  double? _currentHeadingDegrees;
  double? _currentCompassHeadingDegrees;
  bool _autoMapRotationEnabled = DevicesSettings.defaultAutoMapRotationEnabled;

  @override
  void initState() {
    super.initState();
    SettingsService.devicesSettingsRevisionNotifier.addListener(
      _handleDevicesSettingsChanged,
    );
    _loadSessionRoute();
  }

  @override
  void dispose() {
    SettingsService.devicesSettingsRevisionNotifier.removeListener(
      _handleDevicesSettingsChanged,
    );
    _cancelUiSubscriptions();
    _cancelRecordingSubscriptions();
    for (final monitor in _preparedMonitors) {
      monitor.disconnect();
    }
    unawaited(_locationService.stop());
    sessionRunningNotifier.value = false;
    _disableWakeLock();
    super.dispose();
  }

  void _handleDevicesSettingsChanged() {
    unawaited(_loadSessionRoute());
  }

  Future<void> _enableWakeLock() async {
    if (_wakeLockEnabled) {
      return;
    }

    try {
      await WakelockPlus.enable();
      _wakeLockEnabled = true;
    } catch (_) {
      // Ignore unsupported platforms or wake lock failures.
    }
  }

  Future<void> _disableWakeLock() async {
    if (!_wakeLockEnabled) {
      return;
    }

    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Ignore unsupported platforms or wake lock failures.
    } finally {
      _wakeLockEnabled = false;
    }
  }

  Future<void> _loadSessionRoute() async {
    if (!_settingsService.isInitialized) {
      await _settingsService.loadSettings();
    }

    final settings = _settingsService.getCurrentSettings();
    _autoMapRotationEnabled = settings.devicesSettings.autoMapRotationEnabled;
    final routePoints = parseGpxRoute(
      settings.devicesSettings.importedRouteGpxContent,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _importedRoutePoints
        ..clear()
        ..addAll(routePoints);
      _isLoadingSession = false;
    });
  }

  Future<void> _startNewSessionFlow() async {
    await _resetTransientSessionState(clearSelection: true);
    final selected = await _selectSessionMonitorsDialog();
    if (selected == null || !mounted) {
      return;
    }

    _selectedSessionMonitors = selected;
    await _showPreparationDialog(selected);
  }

  Future<_SessionMonitorSelection?> _selectSessionMonitorsDialog() async {
    var useHeartrate = false;
    var useCyclingSpeed = false;
    var useCyclingCadence = false;
    var useLocation = false;
    String? error;

    return showDialog<_SessionMonitorSelection>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Choose monitors'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      value: useHeartrate,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Heart rate monitor'),
                      onChanged: (value) {
                        setDialogState(() {
                          useHeartrate = value;
                          error = null;
                        });
                      },
                    ),
                    SwitchListTile(
                      value: useCyclingSpeed,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cycling speed monitor'),
                      onChanged: (value) {
                        setDialogState(() {
                          useCyclingSpeed = value;
                          error = null;
                        });
                      },
                    ),
                    SwitchListTile(
                      value: useCyclingCadence,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cycling cadence monitor'),
                      onChanged: (value) {
                        setDialogState(() {
                          useCyclingCadence = value;
                          error = null;
                        });
                      },
                    ),
                    SwitchListTile(
                      value: useLocation,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Location'),
                      onChanged: (value) {
                        setDialogState(() {
                          useLocation = value;
                          error = null;
                        });
                      },
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    if (!(useHeartrate ||
                        useCyclingSpeed ||
                        useCyclingCadence ||
                        useLocation)) {
                      setDialogState(() {
                        error = 'Select at least one monitor or location.';
                      });
                      return;
                    }

                    Navigator.of(context).pop(
                      _SessionMonitorSelection(
                        useHeartrate: useHeartrate,
                        useCyclingSpeed: useCyclingSpeed,
                        useCyclingCadence: useCyclingCadence,
                        useLocation: useLocation,
                      ),
                    );
                  },
                  child: const Text('Start'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<({DeviceType type, String label})> _requiredDeviceTypes(
    _SessionMonitorSelection selection,
  ) {
    return selection.requiredDeviceTypes();
  }

  bool get _usesLocationServiceInSession {
    return _selectedSessionMonitors?.useLocation ?? false;
  }

  Future<void> _showPreparationDialog(
    _SessionMonitorSelection selection,
  ) async {
    final requiredDevices = _requiredDeviceTypes(selection);
    final settings = _settingsService.getCurrentSettings();

    for (final required in requiredDevices) {
      final saved = settings.devicesSettings.devices[required.type];
      if (saved == null) {
        AppSnackbar.show(
          'Missing device',
          'Saved device missing for ${required.label}.',
        );
        return;
      }
    }

    _prepareCancelled = false;
    _isPreparingConnection = true;
    _prepareStatus = 'Preparing monitors...';
    await _enableWakeLock();

    if (mounted) {
      setState(() {});
    }

    unawaited(_prepareSessionMonitors(selection));

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _prepareDialogSetState = setDialogState;
            return AlertDialog(
              title: const Text('Preparing session'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isPreparingConnection)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  Text(_prepareStatus),
                  const SizedBox(height: 12),
                  if (_isSessionPrepared)
                    const Text('All monitors connected. Press Start.'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await _cancelPreparedSession();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Cancel'),
                ),
                if (_isSessionPrepared)
                  FilledButton(
                    onPressed: () {
                      _startPreparedSession();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Start'),
                  ),
              ],
            );
          },
        );
      },
    );

    _prepareDialogSetState = null;
  }

  void _notifyPreparationUi() {
    if (mounted) {
      setState(() {});
    }
    final dialogSetState = _prepareDialogSetState;
    if (dialogSetState != null) {
      dialogSetState(() {});
    }
  }

  void _notifyStopUi() {
    if (mounted) {
      setState(() {});
    }
    final dialogSetState = _stopDialogSetState;
    if (dialogSetState != null) {
      dialogSetState(() {});
    }
  }

  Future<void> _prepareSessionMonitors(
    _SessionMonitorSelection selection,
  ) async {
    final requiredDevices = _requiredDeviceTypes(selection);
    final settings = _settingsService.getCurrentSettings();
    final newlyPrepared = <BleGenericMonitor>[];

    try {
      for (final required in requiredDevices) {
        if (_prepareCancelled) {
          throw StateError('Session preparation cancelled.');
        }

        _prepareStatus = 'Resolving ${required.label} monitor...';
        _notifyPreparationUi();

        final saved = settings.devicesSettings.devices[required.type];
        if (saved == null) {
          throw StateError(
            'Saved device missing for ${required.label}. Open settings and configure the device again.',
          );
        }
        final monitor = await BleService.instance.createMonitorFromSavedDevice(
          device: saved,
          deviceType: required.type,
        );

        if (monitor == null) {
          throw StateError('${required.label} monitor not found nearby.');
        }

        _prepareStatus = 'Connecting ${required.label} monitor...';
        _notifyPreparationUi();

        await monitor.connect();
        newlyPrepared.add(monitor);

        _prepareStatus = 'Waiting for ${required.label} stream...';
        _notifyPreparationUi();

        await _waitForFirstMetricSample(monitor);
      }

      if (selection.useLocation) {
        _prepareStatus = 'Requesting location access...';
        _notifyPreparationUi();

        final initialPosition = await _locationService.start();
        _currentLocation = LatLng(
          initialPosition.latitude,
          initialPosition.longitude,
        );
        _currentHeadingDegrees = _resolvedHeadingDegrees(
          initialPosition.heading,
          _currentCompassHeadingDegrees,
        );
        _prepareStatus = 'Location ready.';
        _notifyPreparationUi();
      }

      if (_prepareCancelled) {
        throw StateError('Session preparation cancelled.');
      }

      _preparedMonitors
        ..clear()
        ..addAll(newlyPrepared);
      _isSessionPrepared = true;
      _prepareStatus = 'Ready to start.';
    } catch (e) {
      for (final monitor in newlyPrepared) {
        await monitor.disconnect();
      }
      await _resetTransientSessionState(clearSelection: false);
      if (!_prepareCancelled) {
        _prepareStatus = 'Preparation failed: $e';
      }
    } finally {
      _isPreparingConnection = false;
      _notifyPreparationUi();
    }
  }

  Future<void> _waitForFirstMetricSample(BleGenericMonitor monitor) async {
    final stream = _primaryMetricStream(monitor);
    await stream.first.timeout(const Duration(seconds: 15));
  }

  Stream<num> _primaryMetricStream(BleGenericMonitor monitor) {
    return switch (monitor) {
      BleHeartrateMonitor(:final bpmStream) => bpmStream,
      BleCyclingSpeedMonitor(:final speedKphStream) => speedKphStream,
      BleCyclingCadenceMonitor(:final cadenceRpmStream) => cadenceRpmStream,
      _ => const Stream<num>.empty(),
    };
  }

  List<_SessionMetricSeries> _metricSeriesForMonitor(
    BleGenericMonitor monitor,
  ) {
    return switch (monitor) {
      BleHeartrateMonitor(
        :final bpmStream,
        :final maxBpmStream,
        :final averageBpmStream,
        :final windowAverageBpmStream,
      ) =>
        <_SessionMetricSeries>[
          _SessionMetricSeries(
            label: 'Heart rate',
            monitorLabel: 'Heart rate',
            kind: _SessionMetricKind.current,
            stream: bpmStream,
          ),
          _SessionMetricSeries(
            label: 'Max heart rate',
            monitorLabel: 'Heart rate',
            kind: _SessionMetricKind.max,
            stream: maxBpmStream,
          ),
          _SessionMetricSeries(
            label: 'Average heart rate',
            monitorLabel: 'Heart rate',
            kind: _SessionMetricKind.average,
            stream: averageBpmStream,
          ),
          _SessionMetricSeries(
            label: 'Window average heart rate',
            monitorLabel: 'Heart rate',
            kind: _SessionMetricKind.windowAverage,
            stream: windowAverageBpmStream,
          ),
        ],
      BleCyclingSpeedMonitor(
        :final speedKphStream,
        :final distanceKmStream,
        :final maxSpeedKphStream,
        :final averageSpeedKphStream,
        :final windowAverageSpeedKphStream,
      ) =>
        <_SessionMetricSeries>[
          _SessionMetricSeries(
            label: 'Speed',
            monitorLabel: 'Speed',
            kind: _SessionMetricKind.current,
            stream: speedKphStream,
          ),
          _SessionMetricSeries(
            label: 'Max speed',
            monitorLabel: 'Speed',
            kind: _SessionMetricKind.max,
            stream: maxSpeedKphStream,
          ),
          _SessionMetricSeries(
            label: 'Distance',
            monitorLabel: 'Distance',
            kind: _SessionMetricKind.distance,
            stream: distanceKmStream,
          ),
          _SessionMetricSeries(
            label: 'Average speed',
            monitorLabel: 'Speed',
            kind: _SessionMetricKind.average,
            stream: averageSpeedKphStream,
          ),
          _SessionMetricSeries(
            label: 'Window average speed',
            monitorLabel: 'Speed',
            kind: _SessionMetricKind.windowAverage,
            stream: windowAverageSpeedKphStream,
          ),
        ],
      BleCyclingCadenceMonitor(
        :final cadenceRpmStream,
        :final maxCadenceRpmStream,
        :final averageCadenceRpmStream,
        :final windowAverageCadenceRpmStream,
      ) =>
        <_SessionMetricSeries>[
          _SessionMetricSeries(
            label: 'Cadence',
            monitorLabel: 'Cadence',
            kind: _SessionMetricKind.current,
            stream: cadenceRpmStream,
          ),
          _SessionMetricSeries(
            label: 'Max cadence',
            monitorLabel: 'Cadence',
            kind: _SessionMetricKind.max,
            stream: maxCadenceRpmStream,
          ),
          _SessionMetricSeries(
            label: 'Average cadence',
            monitorLabel: 'Cadence',
            kind: _SessionMetricKind.average,
            stream: averageCadenceRpmStream,
          ),
          _SessionMetricSeries(
            label: 'Window average cadence',
            monitorLabel: 'Cadence',
            kind: _SessionMetricKind.windowAverage,
            stream: windowAverageCadenceRpmStream,
          ),
        ],
      _ => <_SessionMetricSeries>[],
    };
  }

  String _metricLabelForMonitor(BleGenericMonitor monitor) {
    return switch (monitor) {
      BleHeartrateMonitor() => 'Heart rate',
      BleCyclingSpeedMonitor() => 'Speed',
      BleCyclingCadenceMonitor() => 'Cadence',
      _ => 'Metric',
    };
  }

  String _formatMetric(String label, num? value) {
    if (value == null) {
      return '--';
    }

    final lowercaseLabel = label.toLowerCase();

    if (lowercaseLabel.contains('speed')) {
      return value.toDouble().toStringAsFixed(1);
    }
    if (lowercaseLabel.contains('distance')) {
      return value.toDouble().toStringAsFixed(2);
    }
    if (lowercaseLabel.contains('heart rate')) {
      return value.toInt().toString();
    }
    if (lowercaseLabel.contains('cadence')) {
      return value.toInt().toString();
    }

    return value.toString();
  }

  Future<void> _cancelPreparedSession() async {
    _prepareCancelled = true;
    _prepareStatus = 'Cancelling and disconnecting monitors...';
    _notifyPreparationUi();

    await _resetTransientSessionState(clearSelection: true);
    _isPreparingConnection = false;
    await _disableWakeLock();
  }

  Future<void> _resetTransientSessionState({
    required bool clearSelection,
  }) async {
    _cancelRecordingSubscriptions();
    _cancelUiSubscriptions();

    for (final monitor in _preparedMonitors) {
      await monitor.disconnect();
    }

    await _locationService.stop();

    _preparedMonitors.clear();
    _isSessionPrepared = false;
    _isSessionRunning = false;
    sessionRunningNotifier.value = false;
    _isSessionPaused = false;
    _latestMetricValues.clear();
    _monitorConnectionState.clear();
    _sessionDataPoints.clear();
    _sessionStartedAt = null;
    _currentLocation = null;
    _currentHeadingDegrees = null;
    _currentCompassHeadingDegrees = null;
    if (clearSelection) {
      _selectedSessionMonitors = null;
    }
  }

  void _startPreparedSession() {
    _isSessionRunning = true;
    sessionRunningNotifier.value = true;
    _isSessionPaused = false;
    _sessionStartedAt = DateTime.now();
    _sessionDataPoints.clear();

    if (_usesLocationServiceInSession) {
      final initialPosition = _locationService.lastPosition;
      if (initialPosition != null) {
        _sessionDataPoints.add(
          _buildLocationDataPoint(position: initialPosition),
        );
      }
    }

    _attachUiAndRecordingSubscriptions();
    if (mounted) {
      setState(() {});
    }
  }

  void _attachUiAndRecordingSubscriptions() {
    _cancelUiSubscriptions();
    _cancelRecordingSubscriptions();

    for (final monitor in _preparedMonitors) {
      final label = _metricLabelForMonitor(monitor);
      final series = _metricSeriesForMonitor(monitor);

      _monitorConnectionState[label] = monitor.isConnected
          ? 'online'
          : 'offline';

      for (final metricSeries in series) {
        _latestMetricValues[metricSeries.label] = null;

        final uiSub = metricSeries.stream.listen((value) {
          if (!mounted) {
            return;
          }
          setState(() {
            _latestMetricValues[metricSeries.label] = value;
            _monitorConnectionState[label] = monitor.isConnected
                ? 'online'
                : 'offline';
          });
        });
        _uiSubscriptions[metricSeries.label] = uiSub;

        final recordingSub = metricSeries.stream.listen((value) {
          _sessionDataPoints.add(
            DataPoint(
              timestamp: DateTime.now(),
              topic: 'training_session',
              fields: <String, Object?>{metricSeries.label: value},
            ),
          );
        });
        _recordingSubscriptions.add(recordingSub);
      }
    }

    if (_usesLocationServiceInSession) {
      _monitorConnectionState['Location'] = _locationService.isActive
          ? 'online'
          : 'offline';

      if (GetPlatform.isAndroid || GetPlatform.isIOS) {
        final headingSub = FlutterCompass.events?.listen(
          (event) {
            final heading = _normalizedHeadingDegrees(event.heading);
            if (!mounted || heading == null) {
              return;
            }

            setState(() {
              _currentCompassHeadingDegrees = heading;
              _currentHeadingDegrees = heading;
            });
          },
          onError: (error, stackTrace) {
            debugPrint('Compass stream UI error: $error');
          },
        );

        if (headingSub != null) {
          _uiSubscriptions['LocationHeading'] = headingSub;
        }
      }

      final uiSub = _locationService.positionStream.listen(
        (position) {
          final latLng = LatLng(position.latitude, position.longitude);
          if (!mounted) {
            return;
          }

          setState(() {
            _currentLocation = latLng;
            _currentHeadingDegrees = _resolvedHeadingDegrees(
              position.heading,
              _currentCompassHeadingDegrees,
            );
            _monitorConnectionState['Location'] = 'online';
          });
        },
        onError: (error, stackTrace) {
          debugPrint('Location stream UI error: $error');
          if (!mounted) {
            return;
          }
          setState(() {
            _monitorConnectionState['Location'] = 'offline';
          });
        },
      );
      _uiSubscriptions['Location'] = uiSub;

      final recordingSub = _locationService.positionStream.listen(
        (position) {
          _sessionDataPoints.add(_buildLocationDataPoint(position: position));
        },
        onError: (error, stackTrace) {
          debugPrint('Location stream recording error: $error');
        },
      );
      _recordingSubscriptions.add(recordingSub);
    }
  }

  DataPoint _buildLocationDataPoint({required Position position}) {
    return DataPoint(
      timestamp: DateTime.now(),
      topic: 'training_session',
      fields: <String, Object?>{
        'latitude': position.latitude,
        'longitude': position.longitude,
        'altitude': position.altitude,
        'location_speed': position.speed,
        'heading': _resolvedHeadingDegrees(
          position.heading,
          _currentCompassHeadingDegrees,
        ),
      },
    );
  }

  void _cancelUiSubscriptions() {
    for (final sub in _uiSubscriptions.values) {
      sub.cancel();
    }
    _uiSubscriptions.clear();
  }

  void _cancelRecordingSubscriptions() {
    for (final sub in _recordingSubscriptions) {
      sub.cancel();
    }
    _recordingSubscriptions.clear();
  }

  Future<void> _pauseOrResumeSession() async {
    if (!_isSessionRunning) {
      return;
    }

    if (_isSessionPaused) {
      _isSessionPaused = false;
      _attachUiAndRecordingSubscriptions();
    } else {
      _isSessionPaused = true;
      _cancelRecordingSubscriptions();
      _cancelUiSubscriptions();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _stopSession() async {
    if (!_isSessionRunning) {
      return;
    }

    const emptyTitleSentinel = '__sqot_empty_session_title__';
    String sessionTitleInput = '';
    final sessionTitleResult = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save session'),
          content: TextFormField(
            autofocus: true,
            initialValue: sessionTitleInput,
            onChanged: (value) {
              sessionTitleInput = value;
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Optional title',
              hintText: 'e.g. Morning intervals',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                final title = sessionTitleInput.trim();
                Navigator.of(
                  context,
                ).pop(title.isEmpty ? emptyTitleSentinel : title);
              },
              child: const Text('Save and stop'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (sessionTitleResult == null) {
      return;
    }

    final sessionTitle = sessionTitleResult == emptyTitleSentinel
        ? null
        : sessionTitleResult;

    _isStoppingSession = true;
    _stopStatus = 'Stopping active streams...';
    _notifyStopUi();
    var stopTaskStarted = false;

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _stopDialogSetState = setDialogState;
            _isStopDialogVisible = true;

            if (!stopTaskStarted) {
              stopTaskStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                unawaited(_finishStoppingSession(sessionTitle));
              });
            }

            return AlertDialog(
              title: const Text('Ending session'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isStoppingSession)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  Text(_stopStatus),
                ],
              ),
            );
          },
        );
      },
    );

    _stopDialogSetState = null;
    _isStopDialogVisible = false;
  }

  Future<void> _finishStoppingSession(String? sessionTitle) async {
    if (!_isSessionRunning) {
      _isStoppingSession = false;
      _stopStatus = 'Session already stopped.';
      _notifyStopUi();
      if (mounted) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (_isStopDialogVisible && navigator.canPop()) {
          navigator.pop();
        }
      }
      return;
    }

    TrainingSession? savedSession;
    try {
      final startedAt = _sessionStartedAt ?? DateTime.now();
      final endedAt = DateTime.now();
      final trainingTitle =
          _selectedSessionMonitors?.label() ?? 'Custom session';

      _stopStatus = 'Stopping active streams...';
      _notifyStopUi();
      _cancelRecordingSubscriptions();
      _cancelUiSubscriptions();

      savedSession = TrainingSession(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: sessionTitle,
        trainingTypeTitle: trainingTitle,
        startedAt: startedAt,
        endedAt: endedAt,
        dataPoints: List<DataPoint>.from(_sessionDataPoints),
      );

      _stopStatus = 'Saving session to device memory...';
      _notifyStopUi();
      await _settingsService.saveTrainingSession(savedSession);

      _stopStatus = 'Disconnecting monitors...';
      _notifyStopUi();
      for (final monitor in _preparedMonitors) {
        _stopStatus =
            'Disconnecting ${_metricLabelForMonitor(monitor)} monitor...';
        _notifyStopUi();
        await monitor.disconnect();
      }

      if (_usesLocationServiceInSession) {
        _stopStatus = 'Stopping location service...';
        _notifyStopUi();
        await _locationService.stop();
      }

      await _resetTransientSessionState(clearSelection: true);
      _stopStatus = 'Session ended.';
      await _disableWakeLock();
    } catch (e) {
      _stopStatus = 'Failed to end session: $e';
      _notifyStopUi();
      await _disableWakeLock();
      if (mounted) {
        AppSnackbar.show('Failed to end session', e.toString(), isError: true);
      }
    } finally {
      _isStoppingSession = false;
      if (mounted) {
        setState(() {});
        final navigator = Navigator.of(context, rootNavigator: true);
        if (_isStopDialogVisible && navigator.canPop()) {
          navigator.pop();
        }
      }
    }

    if (mounted && savedSession != null) {
      AppSnackbar.show(
        'Session saved',
        'Saved ${savedSession.dataPoints.length} datapoints to device memory.',
      );
    }
  }

  Widget _buildIdleState() {
    return ValueListenableBuilder<bool>(
      valueListenable: sessionLayoutPreviewVisibleNotifier,
      builder: (context, showPreview, child) {
        final startButton = ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280, minHeight: 64),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              textStyle: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            onPressed: _isLoadingSession ? null : _startNewSessionFlow,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start session'),
          ),
        );

        if (!showPreview) {
          return Center(child: startButton);
        }

        return _buildIdleLayoutPreview();
      },
    );
  }

  Widget _buildSessionMonitorCards({
    Map<String, num?>? metrics,
    Map<String, String>? monitorStates,
    bool? usesLocation,
    bool? isPaused,
    bool isInteractive = true,
    LatLng? currentLocation,
    double? currentHeadingDegrees,
    List<LatLng>? routePoints,
  }) {
    return ListView(
      padding: const EdgeInsets.all(_dashboardPagePadding),
      children: [
        _buildTopSummaryCard(metrics: metrics),
        const SizedBox(height: _dashboardSectionSpacing),
        _buildStatsOverviewRow(metrics: metrics),
        const SizedBox(height: _dashboardSectionSpacing),
        _buildAuxiliaryRow(
          metrics: metrics,
          currentLocation: currentLocation,
          currentHeadingDegrees: currentHeadingDegrees,
          routePoints: routePoints,
        ),
        const SizedBox(height: _dashboardSectionSpacing),
        _buildSessionControlsCard(
          monitorStates: monitorStates,
          usesLocation: usesLocation,
          isPaused: isPaused,
          isInteractive: isInteractive,
        ),
      ],
    );
  }

  Widget _buildIdleLayoutPreview() {
    final previewMetrics = <String, num?>{
      'Heart rate': 148,
      'Speed': 31.8,
      'Distance': 24.62,
      'Max heart rate': 176,
      'Max speed': 51.7,
      'Average heart rate': 142,
      'Average speed': 27.3,
      'Window average heart rate': 151,
      'Window average speed': 33.1,
      'Cadence': 89,
    };
    final previewMonitorStates = <String, String>{
      'Heart rate': 'online',
      'Speed': 'online',
      'Cadence': 'online',
      'Location': 'online',
    };
    final previewRoutePoints = _importedRoutePoints.isNotEmpty
        ? _importedRoutePoints
        : <LatLng>[
            const LatLng(50.0755, 14.4378),
            const LatLng(50.0762, 14.4393),
            const LatLng(50.0771, 14.4412),
            const LatLng(50.0784, 14.4431),
          ];
    final previewLocation = previewRoutePoints.length >= 2
        ? previewRoutePoints[previewRoutePoints.length ~/ 2]
        : previewRoutePoints.first;

    return _buildSessionMonitorCards(
      metrics: previewMetrics,
      monitorStates: previewMonitorStates,
      usesLocation: true,
      isPaused: false,
      isInteractive: true,
      currentLocation: previewLocation,
      currentHeadingDegrees: 36,
      routePoints: previewRoutePoints,
    );
  }

  _DashboardMetricState _metricState(
    String label, {
    Map<String, num?>? metrics,
  }) {
    final values = metrics ?? _latestMetricValues;
    final hasMetric = values.containsKey(label);
    final value = values[label];
    return _DashboardMetricState(
      isAvailable: hasMetric,
      text: hasMetric ? _formatMetric(label, value) : 'X',
      numericValue: value?.toDouble(),
    );
  }

  Widget _buildTopSummaryCard({Map<String, num?>? metrics}) {
    return Row(
      children: [
        Expanded(
          child: _TopMetricValue(
            icon: Icons.favorite_rounded,
            state: _metricState('Heart rate', metrics: metrics),
          ),
        ),
        const SizedBox(width: _dashboardSectionSpacing),
        Expanded(
          child: _TopMetricValue(
            icon: Icons.speed_rounded,
            state: _metricState('Speed', metrics: metrics),
          ),
        ),
        const SizedBox(width: _dashboardSectionSpacing),
        Expanded(
          child: _TopMetricValue(
            icon: Icons.route_rounded,
            state: _metricState('Distance', metrics: metrics),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsOverviewRow({Map<String, num?>? metrics}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StatsColumnCard(
            entries: [
              _StatsEntry(
                icon: Icons.favorite_rounded,
                state: _metricState('Max heart rate', metrics: metrics),
              ),
              _StatsEntry(
                icon: Icons.speed_rounded,
                state: _metricState('Max speed', metrics: metrics),
              ),
            ],
          ),
        ),
        const SizedBox(width: _dashboardSectionSpacing),
        Expanded(
          child: _StatsColumnCard(
            entries: [
              _StatsEntry(
                icon: Icons.favorite_rounded,
                state: _metricState('Average heart rate', metrics: metrics),
              ),
              _StatsEntry(
                icon: Icons.speed_rounded,
                state: _metricState('Average speed', metrics: metrics),
              ),
            ],
          ),
        ),
        const SizedBox(width: _dashboardSectionSpacing),
        Expanded(
          child: _StatsColumnCard(
            entries: [
              _StatsEntry(
                icon: Icons.favorite_rounded,
                state: _metricState(
                  'Window average heart rate',
                  metrics: metrics,
                ),
              ),
              _StatsEntry(
                icon: Icons.speed_rounded,
                state: _metricState('Window average speed', metrics: metrics),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuxiliaryRow({
    Map<String, num?>? metrics,
    LatLng? currentLocation,
    double? currentHeadingDegrees,
    List<LatLng>? routePoints,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _CadenceGaugeCard(
            state: _metricState('Cadence', metrics: metrics),
          ),
        ),
        const SizedBox(width: _dashboardSectionSpacing),
        Expanded(
          child: _SessionMapCard(
            currentLocation: currentLocation ?? _currentLocation,
            currentHeadingDegrees:
                currentHeadingDegrees ?? _currentHeadingDegrees,
            autoMapRotationEnabled: _autoMapRotationEnabled,
            routePoints: routePoints ?? _importedRoutePoints,
            onOpen: metrics != null ? () {} : _openExpandedMap,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChips({
    Map<String, String>? monitorStates,
    bool? usesLocation,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final monitors = <String>['Heart rate', 'Speed', 'Cadence'];
    final hasLocation = usesLocation ?? _usesLocationServiceInSession;
    final connectionStates = monitorStates ?? _monitorConnectionState;
    if (hasLocation) {
      monitors.add('Location');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final label in monitors)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: (connectionStates[label] ?? 'offline') == 'online'
                      ? colorScheme.primary
                      : (_hasMonitorLabel(label)
                            ? colorScheme.error
                            : colorScheme.outline),
                ),
                const SizedBox(width: 8),
                Icon(
                  _iconForMetricLabel(label),
                  size: 18,
                  color: (connectionStates[label] ?? 'offline') == 'online'
                      ? colorScheme.onSurface
                      : colorScheme.outline,
                ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _iconForMetricLabel(String label) {
    return switch (label) {
      'Heart rate' => Icons.favorite_rounded,
      'Speed' => Icons.speed_rounded,
      'Cadence' => Icons.pedal_bike_rounded,
      'Location' => Icons.my_location_rounded,
      'Distance' => Icons.route_rounded,
      _ => Icons.circle,
    };
  }

  bool _hasMonitorLabel(String label) {
    if (label == 'Location') {
      return _usesLocationServiceInSession;
    }

    return _preparedMonitors.any(
      (monitor) => _metricLabelForMonitor(monitor) == label,
    );
  }

  Future<void> _openExpandedMap() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: _ExpandedSessionMapSheet(
            initialLocation: _currentLocation,
            initialHeadingDegrees: _currentHeadingDegrees,
            autoMapRotationEnabled: _autoMapRotationEnabled,
            routePoints: _importedRoutePoints,
            positionStream: _usesLocationServiceInSession
                ? _locationService.positionStream
                : null,
          ),
        );
      },
    );
  }

  Widget _buildSessionControlsCard({
    Map<String, String>? monitorStates,
    bool? usesLocation,
    bool? isPaused,
    bool isInteractive = true,
  }) {
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusChips(
              monitorStates: monitorStates,
              usesLocation: usesLocation,
            ),
            const SizedBox(height: _dashboardSectionSpacing),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isInteractive ? _pauseOrResumeSession : null,
                    icon: Icon(
                      (isPaused ?? _isSessionPaused)
                          ? Icons.play_arrow_rounded
                          : Icons.pause,
                    ),
                    label: Text(
                      (isPaused ?? _isSessionPaused) ? 'Resume' : 'Pause',
                    ),
                  ),
                ),
                const SizedBox(width: _dashboardSectionSpacing),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isInteractive ? _stopSession : null,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                  ),
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
    if (_isLoadingSession) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isSessionRunning) {
      return _buildIdleState();
    }

    return _buildSessionMonitorCards();
  }
}

class _SessionMetricSeries {
  final String label;
  final String monitorLabel;
  final _SessionMetricKind kind;
  final Stream<num> stream;

  const _SessionMetricSeries({
    required this.label,
    required this.monitorLabel,
    required this.kind,
    required this.stream,
  });
}

enum _SessionMetricKind { current, distance, max, average, windowAverage }

class _DashboardMetricState {
  final String text;
  final bool isAvailable;
  final double? numericValue;

  const _DashboardMetricState({
    required this.text,
    required this.isAvailable,
    required this.numericValue,
  });
}

class _TopMetricValue extends StatelessWidget {
  final IconData icon;
  final _DashboardMetricState state;

  const _TopMetricValue({required this.icon, required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card.filled(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: colorScheme.onSurfaceVariant, size: 24),
            const SizedBox(height: 12),
            Text(
              state.text,
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.0,
                color: state.isAvailable
                    ? colorScheme.onSurface
                    : colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsEntry {
  final IconData icon;
  final _DashboardMetricState state;

  const _StatsEntry({required this.icon, required this.state});
}

class _StatsColumnCard extends StatelessWidget {
  final List<_StatsEntry> entries;

  const _StatsColumnCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              Icon(
                entries[i].icon,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(height: 8),
              Text(
                entries[i].state.text,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: entries[i].state.isAvailable
                      ? colorScheme.onSurface
                      : colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
              if (i != entries.length - 1) const SizedBox(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}

class _CadenceGaugeCard extends StatelessWidget {
  final _DashboardMetricState state;

  static const double _minCadence = 40;
  static const double _maxCadence = 130;
  static const List<({double start, double end, Color color})> _segments = [
    (start: 40, end: 60, color: Color(0xFFE53935)),
    (start: 60, end: 70, color: Color(0xFFFB8C00)),
    (start: 70, end: 80, color: Color(0xFFFBC02D)),
    (start: 80, end: 90, color: Color(0xFF43A047)),
    (start: 90, end: 95, color: Color(0xFF2E7D32)),
    (start: 95, end: 105, color: Color(0xFFFBC02D)),
    (start: 105, end: 120, color: Color(0xFFFB8C00)),
    (start: 120, end: 130, color: Color(0xFFE53935)),
  ];

  const _CadenceGaugeCard({required this.state});

  Color _zoneColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cadence = state.numericValue;

    if (cadence == null) {
      return colorScheme.outline;
    }
    if (cadence < 60) {
      return Colors.red.shade500;
    }
    if (cadence < 70) {
      return Colors.orange.shade500;
    }
    if (cadence < 80) {
      return Colors.amber.shade600;
    }
    if (cadence < 95) {
      return Colors.green.shade600;
    }
    if (cadence < 105) {
      return Colors.amber.shade600;
    }
    if (cadence < 120) {
      return Colors.orange.shade500;
    }
    return Colors.red.shade500;
  }

  double _normalizedCadence() {
    final cadence = state.numericValue;
    if (cadence == null) {
      return 0;
    }
    return ((cadence - _minCadence) / (_maxCadence - _minCadence)).clamp(
      0.0,
      1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final zoneColor = _zoneColor(context);
    final normalizedCadence = _normalizedCadence();

    return Container(
      height: 174,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final indicatorOffset =
                    normalizedCadence * constraints.maxWidth;

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    Row(
                      children: [
                        for (final segment in _segments)
                          Expanded(
                            flex: ((segment.end - segment.start) * 10).round(),
                            child: Container(height: 20, color: segment.color),
                          ),
                      ],
                    ),
                    Container(
                      height: 20,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    Positioned(
                      left: indicatorOffset.clamp(
                        0.0,
                        constraints.maxWidth - 4,
                      ),
                      child: Container(
                        width: 4,
                        height: 34,
                        decoration: BoxDecoration(
                          color: state.isAvailable
                              ? colorScheme.onSurface
                              : colorScheme.outline,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Icon(
            Icons.pedal_bike_rounded,
            size: 24,
            color: state.isAvailable ? zoneColor : colorScheme.outline,
          ),
          const SizedBox(height: 8),
          Text(
            state.text,
            style: textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: state.isAvailable ? zoneColor : colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SessionMapCard extends StatefulWidget {
  final LatLng? currentLocation;
  final double? currentHeadingDegrees;
  final bool autoMapRotationEnabled;
  final List<LatLng> routePoints;
  final VoidCallback onOpen;

  const _SessionMapCard({
    required this.currentLocation,
    required this.currentHeadingDegrees,
    required this.autoMapRotationEnabled,
    required this.routePoints,
    required this.onOpen,
  });

  @override
  State<_SessionMapCard> createState() => _SessionMapCardState();
}

class _SessionMapCardState extends State<_SessionMapCard> {
  final MapController _mapController = MapController();
  bool _isMapReady = false;

  final LatLng _fallbackCenter = const LatLng(50.0755, 14.4378);

  LatLng get _targetCenter {
    if (widget.currentLocation != null) {
      return widget.currentLocation!;
    }
    if (widget.routePoints.isNotEmpty) {
      return _routeCenter(widget.routePoints);
    }
    return _fallbackCenter;
  }

  @override
  void didUpdateWidget(covariant _SessionMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if ((oldWidget.currentLocation != widget.currentLocation ||
            oldWidget.currentHeadingDegrees != widget.currentHeadingDegrees) &&
        widget.currentLocation != null) {
      _followCurrentLocation();
    }
  }

  void _followCurrentLocation() {
    if (!_isMapReady || widget.currentLocation == null) {
      return;
    }

    final zoom = _mapController.camera.zoom;
    _mapController.move(widget.currentLocation!, zoom.isFinite ? zoom : 18);
    final heading = widget.currentHeadingDegrees;
    if (widget.autoMapRotationEnabled && heading != null) {
      _mapController.rotate(heading);
    } else if (!widget.autoMapRotationEnabled) {
      _mapController.rotate(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 174,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _targetCenter,
                initialZoom: widget.currentLocation != null ? 18 : 15,
                initialRotation: widget.autoMapRotationEnabled
                    ? (widget.currentHeadingDegrees ?? 0)
                    : 0,
                onMapReady: () {
                  _isMapReady = true;
                  _followCurrentLocation();
                },
                interactionOptions: const InteractionOptions(
                  flags:
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.scrollWheelZoom,
                ),
                onTap: (_, _) => widget.onOpen(),
              ),
              children: _buildMapLayers(showAttribution: false),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onOpen,
                  icon: const Icon(Icons.open_in_full_rounded),
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMapLayers({required bool showAttribution}) {
    return [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'xyz.hendrychjan.sqot',
      ),
      if (widget.routePoints.length >= 2)
        PolylineLayer(
          polylines: [
            Polyline(
              points: widget.routePoints,
              strokeWidth: 4,
              color: Colors.blueAccent,
            ),
          ],
        ),
      if (widget.currentLocation != null)
        MarkerLayer(
          markers: [
            Marker(
              point: widget.currentLocation!,
              width: 44,
              height: 44,
              child: Icon(
                widget.autoMapRotationEnabled
                    ? Icons.navigation_rounded
                    : Icons.circle,
                color: Colors.redAccent,
                size: widget.autoMapRotationEnabled ? 30 : 16,
              ),
            ),
          ],
        ),
      if (showAttribution)
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
          ],
        ),
    ];
  }
}

class _ExpandedSessionMapSheet extends StatefulWidget {
  final LatLng? initialLocation;
  final double? initialHeadingDegrees;
  final bool autoMapRotationEnabled;
  final List<LatLng> routePoints;
  final Stream<Position>? positionStream;

  const _ExpandedSessionMapSheet({
    required this.initialLocation,
    required this.initialHeadingDegrees,
    required this.autoMapRotationEnabled,
    required this.routePoints,
    required this.positionStream,
  });

  @override
  State<_ExpandedSessionMapSheet> createState() =>
      _ExpandedSessionMapSheetState();
}

class _ExpandedSessionMapSheetState extends State<_ExpandedSessionMapSheet> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  LatLng? _currentLocation;
  double? _currentHeadingDegrees;
  double? _currentCompassHeadingDegrees;
  bool _isMapReady = false;
  bool _isFollowingLocation = true;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.initialLocation;
    _currentHeadingDegrees = widget.initialHeadingDegrees;

    if (GetPlatform.isAndroid || GetPlatform.isIOS) {
      _compassSubscription = FlutterCompass.events?.listen(
        (event) {
          if (!mounted) {
            return;
          }

          final heading = _normalizedHeadingDegrees(event.heading);
          if (heading == null) {
            return;
          }

          setState(() {
            _currentCompassHeadingDegrees = heading;
            _currentHeadingDegrees = heading;
          });

          if (widget.autoMapRotationEnabled &&
              _isMapReady &&
              _isFollowingLocation) {
            _mapController.rotate(heading);
          }
        },
        onError: (error, stackTrace) {
          debugPrint('Expanded map compass stream error: $error');
        },
      );
    }

    _positionSubscription = widget.positionStream?.listen(
      (position) {
        if (!mounted) {
          return;
        }
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _currentHeadingDegrees = _resolvedHeadingDegrees(
            position.heading,
            _currentCompassHeadingDegrees,
          );
        });
        _followCurrentLocation();
      },
      onError: (error, stackTrace) {
        debugPrint('Expanded map location stream error: $error');
      },
    );
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  LatLng get _center {
    if (_currentLocation != null) {
      return _currentLocation!;
    }
    if (widget.routePoints.isNotEmpty) {
      return _routeCenter(widget.routePoints);
    }
    return const LatLng(50.0755, 14.4378);
  }

  void _followCurrentLocation({double? zoom}) {
    if (!_isMapReady || !_isFollowingLocation || _currentLocation == null) {
      return;
    }

    final targetZoom = zoom ?? _mapController.camera.zoom;
    _mapController.move(
      _currentLocation!,
      targetZoom.isFinite ? targetZoom : 16,
    );
    final heading = _currentHeadingDegrees;
    if (widget.autoMapRotationEnabled && heading != null) {
      _mapController.rotate(heading);
    } else if (!widget.autoMapRotationEnabled) {
      _mapController.rotate(0);
    }
  }

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
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 16,
              initialRotation: widget.autoMapRotationEnabled
                  ? (_currentHeadingDegrees ?? 0)
                  : 0,
              onMapReady: () {
                _isMapReady = true;
                _followCurrentLocation(zoom: 16);
              },
              onPositionChanged: (_, hasGesture) {
                if (!hasGesture || !_isFollowingLocation || !mounted) {
                  return;
                }
                setState(() {
                  _isFollowingLocation = false;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'xyz.hendrychjan.sqot',
              ),
              if (widget.routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.routePoints,
                      strokeWidth: 5,
                      color: Colors.blueAccent,
                    ),
                  ],
                ),
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
                      width: 48,
                      height: 48,
                      child: Icon(
                        widget.autoMapRotationEnabled
                            ? Icons.navigation_rounded
                            : Icons.circle,
                        color: Colors.redAccent,
                        size: widget.autoMapRotationEnabled ? 34 : 18,
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
                  heroTag: 'map-zoom-in',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map-zoom-out',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map-center',
                  onPressed: () {
                    setState(() {
                      _isFollowingLocation = true;
                    });
                    if (_currentLocation != null) {
                      _followCurrentLocation();
                    } else {
                      _mapController.move(_center, _mapController.camera.zoom);
                    }
                  },
                  child: const Icon(Icons.my_location_rounded),
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
                  heroTag: 'map-up',
                  onPressed: () => _moveBy(1, 0),
                  child: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
                Row(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'map-left',
                      onPressed: () => _moveBy(0, -1),
                      child: const Icon(Icons.keyboard_arrow_left_rounded),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton.small(
                      heroTag: 'map-right',
                      onPressed: () => _moveBy(0, 1),
                      child: const Icon(Icons.keyboard_arrow_right_rounded),
                    ),
                  ],
                ),
                FloatingActionButton.small(
                  heroTag: 'map-down',
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

double? _normalizedHeadingDegrees(double? heading) {
  if (heading == null || !heading.isFinite || heading < 0) {
    return null;
  }

  final wrappedHeading = heading % 360;
  if (wrappedHeading == 0) {
    return 0;
  }
  return wrappedHeading < 0 ? wrappedHeading + 360 : wrappedHeading;
}

double? _resolvedHeadingDegrees(double? gpsHeading, double? compassHeading) {
  return compassHeading ?? _normalizedHeadingDegrees(gpsHeading);
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
