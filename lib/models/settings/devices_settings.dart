import 'package:sqot/models/device.dart';
import 'package:sqot/models/device_type.dart';

class DevicesSettings {
  int wheelCircumference;
  int statisticsWindowMinutes;
  bool autoMapRotationEnabled;
  String? importedRouteFileName;
  String? importedRouteGpxContent;
  late final Map<DeviceType, Device?> devices;

  static const int defaultWheelCircumference = 2105;
  static const int defaultStatisticsWindowMinutes = 5;
  static const bool defaultAutoMapRotationEnabled = true;

  DevicesSettings({
    required this.wheelCircumference,
    required this.statisticsWindowMinutes,
    required this.autoMapRotationEnabled,
    this.importedRouteFileName,
    this.importedRouteGpxContent,
  }) {
    devices = {for (final type in DeviceType.values) type: null};
  }
}
