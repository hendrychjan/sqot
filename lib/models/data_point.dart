class DataPoint {
  final DateTime timestamp;
  final String topic;
  final Map<String, Object?> fields;

  DataPoint({
    required this.timestamp,
    required this.topic,
    required this.fields,
  });
}
