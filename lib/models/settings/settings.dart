import 'package:sqot/models/settings/devices_settings.dart';
import 'package:sqot/models/settings/influx_settings.dart';
import 'package:sqot/models/settings/theme_settings.dart';

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
