import 'dart:typed_data';

import 'package:sqot/models/ble_generic_monitor.dart';
import 'package:universal_ble/universal_ble.dart';

class BleHeartrateMonitor extends BleGenericMonitor {
  static const String _serviceUuid = '180D';
  static const String _characteristicUuid = '2A37';

  BleHeartrateMonitor({required super.bleDevice});

  late final Stream<int> bpmStream = UniversalBle.characteristicValueStream(
    bleDevice.deviceId,
    _characteristicUuid,
  ).map(_parseHeartRateBpm);

  @override
  Stream<Map<String, String>> get metricsStream =>
      bpmStream.map((bpm) => {'Heart rate': '$bpm bpm'});

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

  int _parseHeartRateBpm(Uint8List value) {
    if (value.length < 2) {
      return 0;
    }

    final flags = value[0];
    final isUInt16 = (flags & 0x01) != 0;
    if (isUInt16 && value.length >= 3) {
      return value[1] | (value[2] << 8);
    }

    return value[1];
  }
}
