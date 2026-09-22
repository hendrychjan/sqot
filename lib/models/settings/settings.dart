import 'package:sqot/models/settings/devices_settings.dart';
import 'package:sqot/models/settings/influx_settings.dart';
import 'package:sqot/models/settings/theme_settings.dart';
import 'package:sqot/models/training_type.dart';

class Settings {
  ThemeSettings themeSettings;
  InfluxSettings influxSettings;
  DevicesSettings devicesSettings;
  List<TrainingType> trainingTypes;

  Settings({
    required this.themeSettings,
    required this.influxSettings,
    required this.devicesSettings,
    required this.trainingTypes,
  });
}
