import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqot/models/data_point.dart';
import 'package:sqot/models/device_type.dart';
import 'package:sqot/models/monitors/ble_cycling_cadence_monitor.dart';
import 'package:sqot/models/monitors/ble_cycling_speed_monitor.dart';
import 'package:sqot/models/monitors/ble_generic_monitor.dart';
import 'package:sqot/models/monitors/ble_heartrate_monitor.dart';
import 'package:sqot/models/training_session.dart';
import 'package:sqot/models/training_type.dart';
import 'package:sqot/services/ble_service.dart';
import 'package:sqot/services/settings_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SessionPage extends StatefulWidget {
  const SessionPage({super.key});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  final SettingsService _settingsService = SettingsService.instance;

  final List<StreamSubscription<num>> _recordingSubscriptions =
      <StreamSubscription<num>>[];
  final Map<String, num?> _latestMetricValues = <String, num?>{};
  final Map<String, StreamSubscription<num>> _uiSubscriptions =
      <String, StreamSubscription<num>>{};
  final Map<String, String> _monitorConnectionState = <String, String>{};
  final List<DataPoint> _sessionDataPoints = <DataPoint>[];

  bool _isLoadingTrainingTypes = true;
  List<TrainingType> _trainingTypes = <TrainingType>[];

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

  TrainingType? _selectedTrainingType;
  DateTime? _sessionStartedAt;
  final List<BleGenericMonitor> _preparedMonitors = <BleGenericMonitor>[];
  bool _wakeLockEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadTrainingTypes();
  }

  @override
  void dispose() {
    _cancelUiSubscriptions();
    _cancelRecordingSubscriptions();
    for (final monitor in _preparedMonitors) {
      monitor.disconnect();
    }
    _disableWakeLock();
    super.dispose();
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

  Future<void> _loadTrainingTypes() async {
    if (!_settingsService.isInitialized) {
      await _settingsService.loadSettings();
    }

    _refreshTrainingTypesFromSettings();
  }

  void _refreshTrainingTypesFromSettings() {
    final settings = _settingsService.getCurrentSettings();
    if (!mounted) {
      return;
    }

    setState(() {
      _trainingTypes = settings.trainingTypes;
      _isLoadingTrainingTypes = false;
    });
  }

  Future<void> _startNewSessionFlow() async {
    _refreshTrainingTypesFromSettings();

    if (_trainingTypes.isEmpty) {
      Get.snackbar(
        'No training types',
        'Create a training type first in Training > Training types.',
      );
      return;
    }

    final selected = await _selectTrainingTypeDialog();
    if (selected == null || !mounted) {
      return;
    }

    _selectedTrainingType = selected;
    await _showPreparationDialog(selected);
  }

  Future<TrainingType?> _selectTrainingTypeDialog() async {
    return showDialog<TrainingType>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Select training type'),
          children: [
            for (final trainingType in _trainingTypes)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(trainingType),
                child: Text(trainingType.title),
              ),
          ],
        );
      },
    );
  }

  List<({DeviceType type, String label})> _requiredDeviceTypes(
    TrainingType type,
  ) {
    final required = <({DeviceType type, String label})>[];
    if (type.usesHeartrateMonitor) {
      required.add((type: DeviceType.heartRateMonitor, label: 'Heart rate'));
    }
    if (type.usesCyclingSpeedMonitor) {
      required.add((type: DeviceType.cyclingSpeedMonitor, label: 'Speed'));
    }
    if (type.usesCyclingCadenceMonitor) {
      required.add((type: DeviceType.cyclingCadenceMonitor, label: 'Cadence'));
    }
    return required;
  }

  Future<void> _showPreparationDialog(TrainingType type) async {
    final requiredDevices = _requiredDeviceTypes(type);
    final settings = _settingsService.getCurrentSettings();

    for (final required in requiredDevices) {
      final saved = settings.devicesSettings.devices[required.type];
      if (saved == null) {
        Get.snackbar(
          'Missing device',
          'Saved device missing for ${required.type.label}.',
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

    unawaited(_prepareSessionMonitors(type));

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

  Future<void> _prepareSessionMonitors(TrainingType type) async {
    final requiredDevices = _requiredDeviceTypes(type);
    final settings = _settingsService.getCurrentSettings();
    final newlyPrepared = <BleGenericMonitor>[];

    try {
      for (final required in requiredDevices) {
        if (_prepareCancelled) {
          throw StateError('Session preparation cancelled.');
        }

        _prepareStatus = 'Resolving ${required.label} monitor...';
        _notifyPreparationUi();

        final saved = settings.devicesSettings.devices[required.type]!;
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
      _preparedMonitors.clear();
      _isSessionPrepared = false;
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

    _cancelRecordingSubscriptions();
    _cancelUiSubscriptions();

    for (final monitor in _preparedMonitors) {
      await monitor.disconnect();
    }

    _preparedMonitors.clear();
    _isSessionPrepared = false;
    _isSessionRunning = false;
    _isSessionPaused = false;
    _isPreparingConnection = false;
    _latestMetricValues.clear();
    _monitorConnectionState.clear();
    await _disableWakeLock();
  }

  void _startPreparedSession() {
    _isSessionRunning = true;
    _isSessionPaused = false;
    _sessionStartedAt = DateTime.now();
    _sessionDataPoints.clear();

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
    final titleController = TextEditingController();
    final sessionTitleResult = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save session'),
          content: TextField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Optional title',
              hintText: 'e.g. Morning intervals',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
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
    titleController.dispose();

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

    unawaited(_finishStoppingSession(sessionTitle));

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
      return;
    }

    final startedAt = _sessionStartedAt ?? DateTime.now();
    final endedAt = DateTime.now();
    final trainingTitle = _selectedTrainingType?.title ?? 'Unknown';

    _stopStatus = 'Stopping active streams...';
    _notifyStopUi();
    _cancelRecordingSubscriptions();
    _cancelUiSubscriptions();

    final savedSession = TrainingSession(
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

    _preparedMonitors.clear();
    _isSessionPrepared = false;
    _isSessionRunning = false;
    _isSessionPaused = false;
    _latestMetricValues.clear();
    _monitorConnectionState.clear();
    _selectedTrainingType = null;
    _sessionStartedAt = null;
    _sessionDataPoints.clear();
    _isStoppingSession = false;
    _stopStatus = 'Session ended.';
    await _disableWakeLock();

    if (!mounted) {
      return;
    }

    setState(() {});
    final navigator = Navigator.of(context, rootNavigator: true);
    if (_isStopDialogVisible) {
      navigator.pop();
    }
    Get.snackbar(
      'Session saved',
      'Saved ${savedSession.dataPoints.length} datapoints to device memory.',
    );
  }

  Widget _buildIdleState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No active training session'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isLoadingTrainingTypes ? null : _startNewSessionFlow,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start new session'),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionMonitorCards() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      children: [
        _buildTopSummaryCard(),
        const SizedBox(height: 8),
        _buildStatsOverviewRow(),
        const SizedBox(height: 8),
        _buildAuxiliaryRow(),
        const SizedBox(height: 8),
        _buildSessionControlsCard(),
      ],
    );
  }

  bool _hasMetric(String label) {
    return _latestMetricValues.containsKey(label);
  }

  _DashboardMetricState _metricState(String label) {
    final hasMetric = _hasMetric(label);
    final value = _latestMetricValues[label];
    return _DashboardMetricState(
      isAvailable: hasMetric,
      text: hasMetric ? _formatMetric(label, value) : 'X',
      numericValue: value?.toDouble(),
    );
  }

  Widget _buildTopSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: _TopMetricValue(
                icon: Icons.favorite_rounded,
                state: _metricState('Heart rate'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TopMetricValue(
                icon: Icons.speed_rounded,
                state: _metricState('Speed'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TopMetricValue(
                icon: Icons.route_rounded,
                state: _metricState('Distance'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsOverviewRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StatsColumnCard(
            entries: [
              _StatsEntry(
                icon: Icons.favorite_rounded,
                state: _metricState('Max heart rate'),
              ),
              _StatsEntry(
                icon: Icons.speed_rounded,
                state: _metricState('Max speed'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatsColumnCard(
            entries: [
              _StatsEntry(
                icon: Icons.favorite_rounded,
                state: _metricState('Average heart rate'),
              ),
              _StatsEntry(
                icon: Icons.speed_rounded,
                state: _metricState('Average speed'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatsColumnCard(
            entries: [
              _StatsEntry(
                icon: Icons.favorite_rounded,
                state: _metricState('Window average heart rate'),
              ),
              _StatsEntry(
                icon: Icons.speed_rounded,
                state: _metricState('Window average speed'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuxiliaryRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _CadenceGaugeCard(state: _metricState('Cadence'))),
        const SizedBox(width: 8),
        const Expanded(child: _MapPlaceholderCard()),
      ],
    );
  }

  Widget _buildStatusChips() {
    final colorScheme = Theme.of(context).colorScheme;
    final monitors = <String>['Heart rate', 'Speed', 'Cadence'];

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
                  color:
                      (_monitorConnectionState[label] ?? 'offline') == 'online'
                      ? colorScheme.primary
                      : (_hasMonitorLabel(label)
                            ? colorScheme.error
                            : colorScheme.outline),
                ),
                const SizedBox(width: 8),
                Icon(
                  _iconForMetricLabel(label),
                  size: 18,
                  color:
                      (_monitorConnectionState[label] ?? 'offline') == 'online'
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
      'Distance' => Icons.route_rounded,
      _ => Icons.circle,
    };
  }

  bool _hasMonitorLabel(String label) {
    return _preparedMonitors.any(
      (monitor) => _metricLabelForMonitor(monitor) == label,
    );
  }

  Widget _buildSessionControlsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusChips(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pauseOrResumeSession,
                    icon: Icon(
                      _isSessionPaused ? Icons.play_arrow_rounded : Icons.pause,
                    ),
                    label: Text(_isSessionPaused ? 'Resume' : 'Pause'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _stopSession,
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
    if (_isLoadingTrainingTypes) {
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
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

    return Card(
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

class _MapPlaceholderCard extends StatelessWidget {
  const _MapPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 174,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Icon(Icons.map_outlined, size: 42, color: colorScheme.outline),
      ),
    );
  }
}
