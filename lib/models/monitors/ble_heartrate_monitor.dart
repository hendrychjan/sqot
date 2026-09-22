import 'dart:typed_data';

import 'package:sqot/models/monitors/ble_generic_monitor.dart';
import 'package:sqot/services/settings_service.dart';
import 'package:universal_ble/universal_ble.dart';

class BleHeartrateMonitor extends BleGenericMonitor {
  static const String _serviceUuid = '180D';
  static const String _characteristicUuid = '2A37';

  BleHeartrateMonitor({required super.bleDevice});

  final SettingsService _settingsService = SettingsService.instance;

  late final Stream<int> bpmStream = UniversalBle.characteristicValueStream(
    bleDevice.deviceId,
    _characteristicUuid,
  ).map(_parseHeartRateBpm).asBroadcastStream();

  late final Stream<double> maxBpmStream =
      BleGenericMonitor.createRunningMaxStream(bpmStream).asBroadcastStream();
  late final Stream<double> averageBpmStream =
      BleGenericMonitor.createRunningAverageStream(
        bpmStream,
      ).asBroadcastStream();
  late final Stream<double> windowAverageBpmStream =
      BleGenericMonitor.createWindowAverageStream(
        bpmStream,
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
