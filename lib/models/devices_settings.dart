import 'package:sqot/models/device.dart';
import 'package:sqot/models/device_type.dart';

class DevicesSettings {
  late final Map<DeviceType, Device?> devices;

  DevicesSettings() {
    devices = {for (final type in DeviceType.values) type: null};
  }
}
