import 'package:sqot/models/monitors/ble_cycling_cadence_monitor.dart';
import 'package:sqot/models/monitors/ble_cycling_speed_monitor.dart';
import 'package:sqot/models/monitors/ble_heartrate_monitor.dart';

class TrainingType {
  final String id;
  String title;
  bool usesHeartrateMonitor;
  bool usesCyclingSpeedMonitor;
  bool usesCyclingCadenceMonitor;
  bool? _usesLocationService;

  bool get usesLocationService => _usesLocationService ?? false;
  set usesLocationService(bool value) => _usesLocationService = value;

  BleHeartrateMonitor? heartrateMonitor;
  BleCyclingSpeedMonitor? cyclingSpeedMonitor;
  BleCyclingCadenceMonitor? cyclingCadenceMonitor;

  TrainingType({
    required this.id,
    required this.title,
    required this.usesHeartrateMonitor,
    required this.usesCyclingSpeedMonitor,
    required this.usesCyclingCadenceMonitor,
    required bool usesLocationService,
  }) : _usesLocationService = usesLocationService;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'usesHeartrateMonitor': usesHeartrateMonitor,
      'usesCyclingSpeedMonitor': usesCyclingSpeedMonitor,
      'usesCyclingCadenceMonitor': usesCyclingCadenceMonitor,
      'usesLocationService': usesLocationService,
    };
  }

  factory TrainingType.fromJson(Map<String, dynamic> json) {
    return TrainingType(
      id: (json['id'] as String?) ?? ((json['title'] as String?) ?? ''),
      title: (json['title'] as String?) ?? '',
      usesHeartrateMonitor: (json['usesHeartrateMonitor'] as bool?) ?? false,
      usesCyclingSpeedMonitor:
          (json['usesCyclingSpeedMonitor'] as bool?) ?? false,
      usesCyclingCadenceMonitor:
          (json['usesCyclingCadenceMonitor'] as bool?) ?? false,
      usesLocationService: (json['usesLocationService'] as bool?) ?? false,
    );
  }
}
