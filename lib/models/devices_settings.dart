import 'package:sqot/models/device.dart';
import 'package:sqot/models/device_type.dart';

class DevicesSettings {
  int wheelCircumference;
  late final Map<DeviceType, Device?> devices;

  static const int defaultWheelCircumference = 2105;

  DevicesSettings({required this.wheelCircumference}) {
    devices = {for (final type in DeviceType.values) type: null};
  }
}
