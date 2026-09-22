import 'package:sqot/models/device.dart';
import 'package:sqot/models/device_type.dart';

class DevicesSettings {
  int wheelCircumference;
  int statisticsWindowMinutes;
  late final Map<DeviceType, Device?> devices;

  static const int defaultWheelCircumference = 2105;
  static const int defaultStatisticsWindowMinutes = 5;

  DevicesSettings({
    required this.wheelCircumference,
    required this.statisticsWindowMinutes,
  }) {
    devices = {for (final type in DeviceType.values) type: null};
  }
}
