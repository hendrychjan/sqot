import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqot/models/monitors/ble_cycling_cadence_monitor.dart';
import 'package:sqot/models/monitors/ble_cycling_speed_monitor.dart';
import 'package:sqot/models/monitors/ble_generic_monitor.dart';
import 'package:sqot/models/monitors/ble_heartrate_monitor.dart';
import 'package:sqot/models/data_point.dart';
import 'package:sqot/models/device.dart';
import 'package:sqot/models/device_type.dart';
import 'package:sqot/services/ble_service.dart';
import 'package:sqot/services/csv_service.dart';
import 'package:sqot/services/influx_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class DeviceDetailsDialog extends StatefulWidget {
  final DeviceType deviceType;
  final Device? device;

  const DeviceDetailsDialog({
    super.key,
    required this.deviceType,
    required this.device,
  });

  static Future<void> show({
    required DeviceType deviceType,
    required Device? device,
  }) {
    return Get.bottomSheet<void>(
      DeviceDetailsDialog(deviceType: deviceType, device: device),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isDismissible: true,
    );
  }

  @override
  State<DeviceDetailsDialog> createState() => _DeviceDetailsDialogState();
}

class _DeviceDetailsDialogState extends State<DeviceDetailsDialog> {
  final BleService _bleService = BleService.instance;
  final InfluxService _influxService = InfluxService.instance;
  final CsvService _csvService = CsvService.instance;

  bool _wakeLockEnabled = false;
  BleGenericMonitor? _monitor;
  bool _isMonitorLoading = false;
  String? _monitorError;

  final Map<String, _RecordingSession> _recordingsBySource =
      <String, _RecordingSession>{};

  bool get _isConnected => widget.device != null;
  bool get _isRecording => _recordingsBySource.isNotEmpty;
  int get _recordedPointsCount => _recordingsBySource.values.fold<int>(
    0,
    (sum, session) => sum + session.recordedData.length,
  );

  bool _isRecordingSource(String sourceId) =>
      _recordingsBySource.containsKey(sourceId);

  String _formatNumericMetric(
    num value, {
    required int decimals,
    required String unit,
  }) {
    final rendered = decimals == 0
        ? value.toInt().toString()
        : value.toDouble().toStringAsFixed(decimals);
    return '$rendered $unit';
  }

  List<_MetricSeriesDescriptor> _metricSeriesForMonitor(
    BleGenericMonitor monitor,
  ) {
    return switch (monitor) {
      BleHeartrateMonitor(
        :final bpmStream,
        :final maxBpmStream,
        :final averageBpmStream,
        :final windowAverageBpmStream,
      ) =>
        <_MetricSeriesDescriptor>[
          _MetricSeriesDescriptor(
            sourceId: 'Heart rate',
            label: 'Heart rate',
            icon: Icons.favorite_outline,
            stream: bpmStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 0, unit: 'bpm'),
          ),
          _MetricSeriesDescriptor(
            sourceId: 'Heart rate max',
            label: 'Max heart rate',
            icon: Icons.north_outlined,
            stream: maxBpmStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 0, unit: 'bpm'),
          ),
          _MetricSeriesDescriptor(
            sourceId: 'Heart rate average',
            label: 'Average heart rate',
            icon: Icons.auto_graph_outlined,
            stream: averageBpmStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 0, unit: 'bpm'),
          ),
          _MetricSeriesDescriptor(
            sourceId: 'Heart rate last window average',
            label: 'Heart rate window average',
            icon: Icons.timelapse_outlined,
            stream: windowAverageBpmStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 0, unit: 'bpm'),
          ),
        ],
      BleCyclingSpeedMonitor(
        :final speedKphStream,
        :final maxSpeedKphStream,
        :final averageSpeedKphStream,
        :final windowAverageSpeedKphStream,
      ) =>
        <_MetricSeriesDescriptor>[
          _MetricSeriesDescriptor(
            sourceId: 'Speed',
            label: 'Speed',
            icon: Icons.speed_outlined,
            stream: speedKphStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 1, unit: 'km/h'),
          ),
          _MetricSeriesDescriptor(
            sourceId: 'Speed max',
            label: 'Max speed',
            icon: Icons.north_outlined,
            stream: maxSpeedKphStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 1, unit: 'km/h'),
          ),
          _MetricSeriesDescriptor(
            sourceId: 'Speed average',
            label: 'Average speed',
            icon: Icons.auto_graph_outlined,
            stream: averageSpeedKphStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 1, unit: 'km/h'),
          ),
          _MetricSeriesDescriptor(
            sourceId: 'Speed last window average',
            label: 'Speed window average',
            icon: Icons.timelapse_outlined,
            stream: windowAverageSpeedKphStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 1, unit: 'km/h'),
          ),
        ],
      BleCyclingCadenceMonitor(
        :final cadenceRpmStream,
        :final maxCadenceRpmStream,
        :final averageCadenceRpmStream,
        :final windowAverageCadenceRpmStream,
      ) =>
        <_MetricSeriesDescriptor>[
          _MetricSeriesDescriptor(
            sourceId: 'Cadence',
            label: 'Cadence',
            icon: Icons.cyclone_outlined,
            stream: cadenceRpmStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 0, unit: 'rpm'),
          ),
          _MetricSeriesDescriptor(
            sourceId: 'Cadence max',
            label: 'Max cadence',
            icon: Icons.north_outlined,
            stream: maxCadenceRpmStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 0, unit: 'rpm'),
          ),
          _MetricSeriesDescriptor(
            sourceId: 'Cadence average',
            label: 'Average cadence',
            icon: Icons.auto_graph_outlined,
            stream: averageCadenceRpmStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 0, unit: 'rpm'),
          ),
          _MetricSeriesDescriptor(
            sourceId: 'Cadence last window average',
            label: 'Cadence window average',
            icon: Icons.timelapse_outlined,
            stream: windowAverageCadenceRpmStream,
            valueFormatter: (value) =>
                _formatNumericMetric(value, decimals: 0, unit: 'rpm'),
          ),
        ],
      _ => <_MetricSeriesDescriptor>[],
    };
  }

  String get _recordingSummary {
    if (_recordingsBySource.isEmpty) {
      return 'attribute';
    }

    final parts = _recordingsBySource.values
        .map(
          (session) =>
              '${session.attributeName} (${session.recordedData.length})',
        )
        .join(', ');
    return parts;
  }

  @override
  void initState() {
    super.initState();
    _enableWakeLock();
    _initializeMonitor();
  }

  @override
  void dispose() {
    for (final session in _recordingsBySource.values) {
      session.subscription.cancel();
    }
    _monitor?.disconnect();
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

  DataPoint _buildRecordedDataPoint({
    required String attributeName,
    required Object? value,
  }) {
    return DataPoint(
      timestamp: DateTime.now(),
      topic: widget.deviceType.topic,
      fields: <String, Object?>{attributeName: value},
    );
  }

  Future<void> _startRecording({
    required String sourceId,
    required Stream<Object?> stream,
    required String Function(Object?) attributeNameBuilder,
    Object? Function(Object?)? valueMapper,
  }) async {
    if (_recordingsBySource.containsKey(sourceId)) {
      return;
    }

    final session = _RecordingSession(
      sourceId: sourceId,
      attributeName: sourceId,
      stream: stream,
      attributeNameBuilder: attributeNameBuilder,
      valueMapper: valueMapper,
      recordedData: <DataPoint>[],
      subscription: const Stream<Object?>.empty().listen(null),
    );

    session.subscription = stream.listen((rawSample) {
      final attributeName = attributeNameBuilder(rawSample);
      final value = valueMapper != null ? valueMapper(rawSample) : rawSample;

      session.attributeName = attributeName;
      session.recordedData.add(
        _buildRecordedDataPoint(attributeName: attributeName, value: value),
      );
      if (mounted) {
        setState(() {});
      }
    });

    _recordingsBySource[sourceId] = session;

    if (mounted) {
      setState(() {});
    }
    Get.snackbar('Recording started', 'Watching $sourceId');
  }

  Future<bool> _exportToInflux(List<DataPoint> payload) async {
    if (payload.isEmpty) {
      Get.snackbar('Export to Influx', 'No recorded data to export.');
      return false;
    }

    try {
      await _influxService.writeTopic(payload);
      Get.snackbar('Export to Influx', 'Export successful.');
      return true;
    } catch (e) {
      Get.snackbar('Export to Influx', 'Export failed: $e');
      return false;
    }
  }

  Future<bool> _exportToCsv(List<DataPoint> payload) async {
    if (payload.isEmpty) {
      Get.snackbar('Export to CSV', 'No recorded data to export.');
      return false;
    }

    try {
      await _csvService.exportDataPoints(payload);
      Get.snackbar('Export to CSV', 'Export successful.');
      return true;
    } catch (e) {
      Get.snackbar('Export to CSV', 'Export failed: $e');
      return false;
    }
  }

  Future<void> _showExportProgressDialog({
    required String title,
    required Future<bool> Function() export,
  }) async {
    if (!mounted) {
      return;
    }

    final dialogContext = context;
    final rootNavigator = Navigator.of(dialogContext, rootNavigator: true);

    unawaited(
      showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 12),
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Please wait…'),
              ],
            ),
          );
        },
      ),
    );

    try {
      await export();
    } finally {
      if (mounted) {
        rootNavigator.pop();
      }
    }
  }

  Future<void> _stopRecordingAndShowOptions(String sourceId) async {
    final pausedSession = _recordingsBySource[sourceId];
    if (pausedSession == null) {
      return;
    }

    await pausedSession.subscription.cancel();

    if (!mounted) {
      return;
    }

    setState(() {});

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Recording paused',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${pausedSession.recordedData.length} data points captured.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.play_arrow_rounded),
                  title: const Text('Continue recording'),
                  onTap: () => Navigator.of(context).pop('continue'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Finish and discard data'),
                  onTap: () => Navigator.of(context).pop('discard'),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Export to Influx'),
                  onTap: () async {
                    await _showExportProgressDialog(
                      title: 'Exporting to Influx…',
                      export: () => _exportToInflux(
                        List<DataPoint>.from(pausedSession.recordedData),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Export to CSV'),
                  onTap: () async {
                    await _showExportProgressDialog(
                      title: 'Exporting to CSV…',
                      export: () => _exportToCsv(
                        List<DataPoint>.from(pausedSession.recordedData),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    switch (choice) {
      case 'continue':
        await _resumeRecording(pausedSession);
        break;
      case 'discard':
        _recordingsBySource.remove(sourceId);
        setState(() {});
        Get.snackbar('Recording', 'Data discarded.');
        break;
      default:
        // Keep the paused recording available for later export/resume.
        setState(() {});
        break;
    }
  }

  Future<void> _resumeRecording(_RecordingSession session) async {
    final existingSession = _recordingsBySource[session.sourceId];
    if (existingSession != null && existingSession != session) {
      await existingSession.subscription.cancel();
    }

    session.subscription = session.stream.listen((rawSample) {
      final attributeName = session.attributeNameBuilder(rawSample);
      final value = session.valueMapper != null
          ? session.valueMapper!(rawSample)
          : rawSample;
      session.attributeName = attributeName;
      session.recordedData.add(
        _buildRecordedDataPoint(attributeName: attributeName, value: value),
      );

      if (mounted) {
        setState(() {});
      }
    });

    _recordingsBySource[session.sourceId] = session;
    if (mounted) {
      setState(() {});
    }
    Get.snackbar('Recording resumed', 'Watching ${session.sourceId}');
  }

  Future<void> _toggleStreamRecording({
    required String sourceId,
    required Stream<num> stream,
  }) async {
    if (_recordingsBySource.containsKey(sourceId)) {
      await _stopRecordingAndShowOptions(sourceId);
      return;
    }

    await _startRecording(
      sourceId: sourceId,
      stream: stream.map<Object?>((sample) => sample),
      attributeNameBuilder: (sample) {
        return sourceId;
      },
    );
  }

  Future<void> _toggleBatteryRecording(BleGenericMonitor monitor) async {
    if (_recordingsBySource.containsKey('Battery')) {
      await _stopRecordingAndShowOptions('Battery');
      return;
    }

    await _startRecording(
      sourceId: 'Battery',
      stream: monitor.batteryStream,
      attributeNameBuilder: (_) => 'Battery',
    );
  }

  Future<void> _toggleSignalRecording(BleGenericMonitor monitor) async {
    if (_recordingsBySource.containsKey('Signal strength')) {
      await _stopRecordingAndShowOptions('Signal strength');
      return;
    }

    await _startRecording(
      sourceId: 'Signal strength',
      stream: monitor.signalStrengthStream,
      attributeNameBuilder: (_) => 'Signal strength',
    );
  }

  Future<void> _initializeMonitor() async {
    final savedDevice = widget.device;
    if (savedDevice == null) {
      return;
    }

    setState(() {
      _isMonitorLoading = true;
      _monitorError = null;
    });

    try {
      final monitor = await _bleService.createMonitorFromSavedDevice(
        device: savedDevice,
        deviceType: widget.deviceType,
      );

      if (!mounted) {
        return;
      }

      if (monitor == null) {
        setState(() {
          _isMonitorLoading = false;
          _monitorError = 'Saved device was not found nearby.';
        });
        return;
      }

      await monitor.connect();

      if (!mounted) {
        return;
      }

      setState(() {
        _monitor = monitor;
        _isMonitorLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isMonitorLoading = false;
        _monitorError = 'Unable to start live monitoring: $e';
      });
    }
  }

  Widget _buildLiveMonitorSection(BuildContext context) {
    final textTheme = context.theme.textTheme;
    final colorScheme = context.theme.colorScheme;

    if (!_isConnected) {
      return _DetailTile(
        icon: Icons.sensors_off_outlined,
        label: 'Live data',
        value: 'Connect this device first to see live telemetry.',
      );
    }

    if (_isMonitorLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (_monitorError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          _monitorError!,
          style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
        ),
      );
    }

    final monitor = _monitor;
    if (monitor == null) {
      return const SizedBox.shrink();
    }

    final series = _metricSeriesForMonitor(monitor);

    return Column(
      children: [
        ...series.map((metricSeries) {
          return Column(
            children: [
              StreamBuilder<num>(
                stream: metricSeries.stream,
                builder: (context, snapshot) {
                  final current = snapshot.data;
                  return _DetailTile(
                    icon: metricSeries.icon,
                    label: metricSeries.label,
                    value: current == null
                        ? 'Waiting for data...'
                        : metricSeries.valueFormatter(current),
                    trailing: IconButton.filledTonal(
                      tooltip: _isRecordingSource(metricSeries.sourceId)
                          ? 'Stop recording'
                          : 'Record attribute',
                      onPressed: () => _toggleStreamRecording(
                        sourceId: metricSeries.sourceId,
                        stream: metricSeries.stream,
                      ),
                      icon: Icon(
                        _isRecordingSource(metricSeries.sourceId)
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record_rounded,
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
            ],
          );
        }),
        StreamBuilder<double>(
          stream: monitor.batteryStream,
          builder: (context, snapshot) {
            final battery = snapshot.data;
            final value = battery == null
                ? 'Waiting for data...'
                : '${battery.toStringAsFixed(0)}%';

            return _DetailTile(
              icon: Icons.battery_charging_full_outlined,
              label: 'Battery',
              value: value,
              trailing: IconButton.filledTonal(
                tooltip: _isRecordingSource('Battery')
                    ? 'Stop recording'
                    : 'Record attribute',
                onPressed: () => _toggleBatteryRecording(monitor),
                icon: Icon(
                  _isRecordingSource('Battery')
                      ? Icons.stop_rounded
                      : Icons.fiber_manual_record_rounded,
                ),
              ),
            );
          },
        ),
        const Divider(height: 1),
        StreamBuilder<int>(
          stream: monitor.signalStrengthStream,
          builder: (context, snapshot) {
            final rssi = snapshot.data;
            final value = rssi == null ? 'Waiting for data...' : '$rssi dBm';

            return _DetailTile(
              icon: Icons.network_cell_outlined,
              label: 'Signal strength',
              value: value,
              trailing: IconButton.filledTonal(
                tooltip: _isRecordingSource('Signal strength')
                    ? 'Stop recording'
                    : 'Record attribute',
                onPressed: () => _toggleSignalRecording(monitor),
                icon: Icon(
                  _isRecordingSource('Signal strength')
                      ? Icons.stop_rounded
                      : Icons.fiber_manual_record_rounded,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final textTheme = context.theme.textTheme;
    final screenHeight = context.mediaQuery.size.height;
    final sheetHeight = screenHeight * 0.92;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: sheetHeight,
        child: Material(
          color: colorScheme.surfaceContainerLow,
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.deviceType.label,
                          style: textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: Get.back,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      Icon(
                        _isConnected
                            ? Icons.link_rounded
                            : Icons.link_off_rounded,
                        size: 18,
                        color: _isConnected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isConnected
                            ? 'Saved device details'
                            : 'No saved device',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isRecording)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.fiber_manual_record_rounded,
                          size: 16,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Recording: $_recordingSummary • $_recordedPointsCount points total',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                    children: [
                      _DetailTile(
                        icon: Icons.badge_outlined,
                        label: 'Name',
                        value: widget.device?.name ?? 'Not connected',
                      ),
                      const Divider(height: 1),
                      _DetailTile(
                        icon: Icons.router_outlined,
                        label: 'Address',
                        value: widget.device?.address ?? 'Not available',
                      ),
                      const Divider(height: 1),
                      _DetailTile(
                        icon: Icons.memory_outlined,
                        label: 'BLE ID',
                        value: widget.device?.bleId ?? 'Not available',
                      ),
                      const Divider(height: 1),
                      _buildLiveMonitorSection(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = context.theme.textTheme;
    final colorScheme = context.theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        value,
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing,
    );
  }
}

class _MetricSeriesDescriptor {
  final String sourceId;
  final String label;
  final IconData icon;
  final Stream<num> stream;
  final String Function(num) valueFormatter;

  const _MetricSeriesDescriptor({
    required this.sourceId,
    required this.label,
    required this.icon,
    required this.stream,
    required this.valueFormatter,
  });
}

class _RecordingSession {
  final String sourceId;
  String attributeName;
  final Stream<Object?> stream;
  final String Function(Object?) attributeNameBuilder;
  final Object? Function(Object?)? valueMapper;
  final List<DataPoint> recordedData;
  StreamSubscription<Object?> subscription;

  _RecordingSession({
    required this.sourceId,
    required this.attributeName,
    required this.stream,
    required this.attributeNameBuilder,
    required this.valueMapper,
    required this.recordedData,
    required this.subscription,
  });
}
