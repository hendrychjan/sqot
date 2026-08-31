import 'package:sqot/models/devices_settings.dart';
import 'package:sqot/models/influx_settings.dart';
import 'package:sqot/models/theme_settings.dart';

class Settings {
  ThemeSettings themeSettings;
  InfluxSettings influxSettings;
  DevicesSettings devicesSettings;

  Settings({
    required this.themeSettings,
    required this.influxSettings,
    required this.devicesSettings,
  });
}
