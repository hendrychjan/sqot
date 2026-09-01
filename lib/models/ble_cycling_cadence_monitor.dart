import 'package:sqot/models/ble_generic_monitor.dart';
import 'package:sqot/models/ble_cycling_measurement.dart';
import 'package:universal_ble/universal_ble.dart';

class BleCyclingCadenceMonitor extends BleGenericMonitor {
  static const String _serviceUuid = '1816';
  static const String _characteristicUuid = '2A5B';

  BleCyclingCadenceMonitor({required super.bleDevice});

  late final Stream<int> cadenceRpmStream = _buildCadenceStream()
      .asBroadcastStream();

  @override
  Stream<Map<String, Object?>> get metricsStream =>
      cadenceRpmStream.map((rpm) => {'Cadence': rpm});

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
    int? previousCrankRevolutions;
    int? previousCrankEventTime;

    return UniversalBle.characteristicValueStream(
      bleDevice.deviceId,
      _characteristicUuid,
    ).map((value) {
      final measurement = BleCyclingMeasurement.fromBytes(value);
      final crankRevolutions = measurement.cumulativeCrankRevolutions;
      final crankEventTime = measurement.lastCrankEventTime;
      if (crankRevolutions == null || crankEventTime == null) {
        return 0;
      }

      if (previousCrankRevolutions == null || previousCrankEventTime == null) {
        previousCrankRevolutions = crankRevolutions;
        previousCrankEventTime = crankEventTime;
        return 0;
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
        return 0;
      }

      final rpm = deltaRevolutions * 60 * 1024 / deltaTicks;
      return rpm.round();
    });
  }
}
