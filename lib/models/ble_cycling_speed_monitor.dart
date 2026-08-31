import 'package:sqot/models/ble_cycling_measurement.dart';
import 'package:sqot/models/ble_generic_monitor.dart';
import 'package:universal_ble/universal_ble.dart';

class BleCyclingSpeedMonitor extends BleGenericMonitor {
  static const String _serviceUuid = '1816';
  static const String _characteristicUuid = '2A5B';
  static const double _wheelCircumferenceMeters = 2.105;

  BleCyclingSpeedMonitor({required super.bleDevice});

  late final Stream<double> speedKphStream = _buildSpeedStream();

  @override
  Stream<Map<String, String>> get metricsStream => speedKphStream.map(
    (speedKph) => {'Speed': '${speedKph.toStringAsFixed(1)} km/h'},
  );

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
    int? previousWheelRevolutions;
    int? previousWheelEventTime;

    return UniversalBle.characteristicValueStream(
      bleDevice.deviceId,
      _characteristicUuid,
    ).map((value) {
      final measurement = BleCyclingMeasurement.fromBytes(value);
      final wheelRevolutions = measurement.cumulativeWheelRevolutions;
      final wheelEventTime = measurement.lastWheelEventTime;
      if (wheelRevolutions == null || wheelEventTime == null) {
        return 0;
      }

      if (previousWheelRevolutions == null || previousWheelEventTime == null) {
        previousWheelRevolutions = wheelRevolutions;
        previousWheelEventTime = wheelEventTime;
        return 0;
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
        return 0;
      }

      final seconds = deltaTicks / 1024.0;
      final meters = deltaRevolutions * _wheelCircumferenceMeters;
      final speedKph = (meters / seconds) * 3.6;
      return speedKph;
    });
  }
}
