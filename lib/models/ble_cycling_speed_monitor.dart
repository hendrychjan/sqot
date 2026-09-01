import 'dart:async';

import 'package:sqot/models/ble_cycling_measurement.dart';
import 'package:sqot/models/ble_generic_monitor.dart';
import 'package:sqot/services/settings_service.dart';
import 'package:universal_ble/universal_ble.dart';

class BleCyclingSpeedMonitor extends BleGenericMonitor {
  static const String _serviceUuid = '1816';
  static const String _characteristicUuid = '2A5B';

  BleCyclingSpeedMonitor({required super.bleDevice});

  final SettingsService _settingsService = SettingsService.instance;

  late final Stream<double> speedKphStream = _buildSpeedStream()
      .asBroadcastStream();

  @override
  Stream<Map<String, Object?>> get metricsStream =>
      speedKphStream.map((speedKph) => {'Speed': speedKph});

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

  Stream<double> _buildSpeedStream() {
    final controller = StreamController<double>.broadcast();
    int? previousWheelRevolutions;
    int? previousWheelEventTime;
    DateTime? lastValidSampleAt;
    bool lastEmittedWasZero = false;

    final subscription =
        UniversalBle.characteristicValueStream(
          bleDevice.deviceId,
          _characteristicUuid,
        ).listen((value) {
          final measurement = BleCyclingMeasurement.fromBytes(value);
          final wheelRevolutions = measurement.cumulativeWheelRevolutions;
          final wheelEventTime = measurement.lastWheelEventTime;
          if (wheelRevolutions == null || wheelEventTime == null) {
            return;
          }

          if (previousWheelRevolutions == null ||
              previousWheelEventTime == null) {
            previousWheelRevolutions = wheelRevolutions;
            previousWheelEventTime = wheelEventTime;
            lastValidSampleAt = DateTime.now();
            return;
          }

          int deltaRevolutions = wheelRevolutions - previousWheelRevolutions!;
          int deltaTicks = wheelEventTime - previousWheelEventTime!;

          if (deltaRevolutions < 0) {
            deltaRevolutions += 0x100000000;
          }
          if (deltaTicks < 0) {
            deltaTicks += 0x10000;
          }

          previousWheelRevolutions = wheelRevolutions;
          previousWheelEventTime = wheelEventTime;

          if (deltaTicks <= 0 || deltaRevolutions <= 0) {
            return;
          }

          final seconds = deltaTicks / 1024.0;
          final wheelCircumferenceMm = _settingsService
              .getCurrentSettings()
              .devicesSettings
              .wheelCircumference
              .toDouble();

          final meters = deltaRevolutions * (wheelCircumferenceMm / 1000.0);
          final speedKph = (meters / seconds) * 3.6;

          if (!speedKph.isFinite) {
            return;
          }

          lastValidSampleAt = DateTime.now();
          if (speedKph <= 0.5) {
            // Ignore low/invalid spikes; if telemetry goes silent while connected, the
            // watchdog below will emit 0.0 after the timeout.
            return;
          }

          lastEmittedWasZero = false;
          controller.add(speedKph);
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
          controller.add(0.0);
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
