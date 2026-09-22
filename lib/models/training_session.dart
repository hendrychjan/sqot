import 'package:sqot/models/data_point.dart';

class TrainingSession {
  final String id;
  final String? title;
  final String trainingTypeTitle;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<DataPoint> dataPoints;

  TrainingSession({
    required this.id,
    this.title,
    required this.trainingTypeTitle,
    required this.startedAt,
    required this.endedAt,
    required this.dataPoints,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'trainingTypeTitle': trainingTypeTitle,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'dataPoints': dataPoints.map((point) => _dataPointToJson(point)).toList(),
    };
  }

  static Map<String, dynamic> _dataPointToJson(DataPoint point) {
    return <String, dynamic>{
      'timestamp': point.timestamp.toIso8601String(),
      'topic': point.topic,
      'fields': point.fields,
    };
  }

  factory TrainingSession.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['dataPoints'] as List<dynamic>? ?? <dynamic>[];

    return TrainingSession(
      id:
          (json['id'] as String?) ??
          ((json['startedAt'] as String?) ?? DateTime.now().toIso8601String()),
      title: (json['title'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['title'] as String),
      trainingTypeTitle: (json['trainingTypeTitle'] as String?) ?? 'Unknown',
      startedAt:
          DateTime.tryParse((json['startedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endedAt:
          DateTime.tryParse((json['endedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dataPoints: rawPoints
          .whereType<Map<String, dynamic>>()
          .map(_dataPointFromJson)
          .toList(),
    );
  }

  static DataPoint _dataPointFromJson(Map<String, dynamic> json) {
    return DataPoint(
      timestamp:
          DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      topic: (json['topic'] as String?) ?? '',
      fields: Map<String, Object?>.from(
        (json['fields'] as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{}).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      ),
    );
  }
}
