import 'dart:async';

import 'package:sqot/models/monitors/ble_generic_monitor.dart';
import 'package:sqot/models/ble_cycling_measurement.dart';
import 'package:sqot/services/settings_service.dart';
import 'package:universal_ble/universal_ble.dart';

class BleCyclingCadenceMonitor extends BleGenericMonitor {
  static const String _serviceUuid = '1816';
  static const String _characteristicUuid = '2A5B';

  BleCyclingCadenceMonitor({required super.bleDevice});

  final SettingsService _settingsService = SettingsService.instance;

  late final Stream<int> cadenceRpmStream = _buildCadenceStream()
      .asBroadcastStream();
  late final Stream<double> maxCadenceRpmStream =
      BleGenericMonitor.createRunningMaxStream(
        cadenceRpmStream,
      ).asBroadcastStream();
  late final Stream<double> averageCadenceRpmStream =
      BleGenericMonitor.createRunningAverageStream(
        cadenceRpmStream,
      ).asBroadcastStream();
  late final Stream<double> windowAverageCadenceRpmStream =
      BleGenericMonitor.createWindowAverageStream(
        cadenceRpmStream,
        () => Duration(
          minutes: _settingsService
              .getCurrentSettings()
              .devicesSettings
              .statisticsWindowMinutes,
        ),
      ).asBroadcastStream();

  @override
  Future<void> onStartListening() {
    return UniversalBle.subscribeNotifications(
      bleDevice.deviceId,
      _serviceUuid,
      _characteristicUuid,
    );
  }

  @override
  Future<void> onStopListening() async {
    try {
      await UniversalBle.unsubscribe(
        bleDevice.deviceId,
        _serviceUuid,
        _characteristicUuid,
      );
    } catch (_) {
      // Ignore unsupported/idle unsubscribe failures.
    }
  }

  Stream<int> _buildCadenceStream() {
    final controller = StreamController<int>.broadcast();
    int? previousCrankRevolutions;
    int? previousCrankEventTime;
    DateTime? lastValidSampleAt;
    bool lastEmittedWasZero = false;

    final subscription =
        UniversalBle.characteristicValueStream(
          bleDevice.deviceId,
          _characteristicUuid,
        ).listen((value) {
          final measurement = BleCyclingMeasurement.fromBytes(value);
          final crankRevolutions = measurement.cumulativeCrankRevolutions;
          final crankEventTime = measurement.lastCrankEventTime;
          if (crankRevolutions == null || crankEventTime == null) {
            return;
          }

          if (previousCrankRevolutions == null ||
              previousCrankEventTime == null) {
            previousCrankRevolutions = crankRevolutions;
            previousCrankEventTime = crankEventTime;
            lastValidSampleAt = DateTime.now();
            return;
          }

          int deltaRevolutions = crankRevolutions - previousCrankRevolutions!;
          int deltaTicks = crankEventTime - previousCrankEventTime!;

          if (deltaRevolutions < 0) {
            deltaRevolutions += 0x10000;
          }
          if (deltaTicks < 0) {
            deltaTicks += 0x10000;
          }

          previousCrankRevolutions = crankRevolutions;
          previousCrankEventTime = crankEventTime;

          if (deltaTicks <= 0 || deltaRevolutions <= 0) {
            return;
          }

          final rpm = deltaRevolutions * 60 * 1024 / deltaTicks;
          if (!rpm.isFinite) {
            return;
          }

          lastValidSampleAt = DateTime.now();
          if (rpm <= 0.5) {
            // Ignore low/invalid spikes; if telemetry goes silent while connected, the
            // watchdog below will emit 0 after the timeout.
            return;
          }

          lastEmittedWasZero = false;
          controller.add(rpm.round());
        });

    final watchdog = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final lastSampleAt = lastValidSampleAt;
      if (lastSampleAt == null) {
        return;
      }

      if (DateTime.now().difference(lastSampleAt) >=
          const Duration(seconds: 2)) {
        if (!lastEmittedWasZero) {
          lastEmittedWasZero = true;
          controller.add(0);
        }
      }
    });

    controller.onCancel = () async {
      await subscription.cancel();
      watchdog.cancel();
    };

    return controller.stream;
  }
}
