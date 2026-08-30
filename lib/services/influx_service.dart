import 'dart:convert';
import 'dart:io';

import 'package:sqot/models/data_point.dart';
import 'package:sqot/services/settings_service.dart';

class InfluxService {
  InfluxService._();
  factory InfluxService() => instance;
  static final InfluxService instance = InfluxService._();

  final SettingsService _settingsService = SettingsService.instance;

  Future<void> writeTopic(List<DataPoint> payload) async {
    if (!_settingsService.isInfluxSettingsComplete) {
      throw StateError('Influx settings are incomplete.');
    }

    if (payload.isEmpty) {
      return;
    }

    final settings = _settingsService.getCurrentSettings().influxSettings;
    final influxUrl = Uri.parse(settings.url);
    final writeUri = influxUrl.replace(
      path: _joinPath(influxUrl.path, '/api/v2/write'),
      queryParameters: {
        'org': settings.org,
        'bucket': settings.bucket,
        'precision': 'ms',
      },
    );

    final client = HttpClient();

    try {
      final request = await client.postUrl(writeUri);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Token ${settings.token}',
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/plain; charset=utf-8',
      );

      final body = StringBuffer();
      for (final p in payload) {
        final line = _buildLineProtocol(
          p.topic,
          p.fields,
          timestamp: p.timestamp,
        );
        body.writeln(line);
      }

      request.add(utf8.encode(body.toString()));

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final responseBody = await utf8.decodeStream(response);
        throw HttpException(
          'Influx write failed (${response.statusCode}): $responseBody',
          uri: writeUri,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  String _buildLineProtocol(
    String topic,
    Map<String, Object?> fields, {
    DateTime? timestamp,
  }) {
    if (topic.trim().isEmpty) {
      throw ArgumentError.value(topic, 'topic', 'Topic must not be empty.');
    }
    if (fields.isEmpty) {
      throw ArgumentError.value(
        fields,
        'fields',
        'At least one field is required.',
      );
    }

    final validFieldEntries = fields.entries
        .where((entry) => entry.value != null)
        .toList();
    if (validFieldEntries.isEmpty) {
      throw ArgumentError.value(
        fields,
        'fields',
        'At least one non-null field is required.',
      );
    }

    final measurement = _escapeMeasurement(topic.trim());

    final fieldsPart = validFieldEntries
        .map((entry) {
          final key = _escapeTagOrFieldKey(entry.key.trim());
          final value = _formatFieldValue(entry.value);
          if (key.isEmpty || value == null) {
            return null;
          }
          return '$key=$value';
        })
        .whereType<String>()
        .join(',');

    if (fieldsPart.isEmpty) {
      throw ArgumentError.value(
        fields,
        'fields',
        'No serializable fields were provided.',
      );
    }

    final timestampMs = (timestamp ?? DateTime.now()).millisecondsSinceEpoch;

    return '$measurement $fieldsPart $timestampMs';
  }

  String _joinPath(String basePath, String addition) {
    if (basePath.isEmpty || basePath == '/') {
      return addition;
    }
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$normalizedBase$addition';
  }

  String _escapeMeasurement(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll(' ', r'\ ')
        .replaceAll(',', r'\,');
  }

  String _escapeTagOrFieldKey(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll(' ', r'\ ')
        .replaceAll(',', r'\,')
        .replaceAll('=', r'\=');
  }

  String? _formatFieldValue(Object? value) {
    if (value is bool) {
      return value ? 'true' : 'false';
    }
    if (value is int) {
      return '${value}i';
    }
    if (value is double) {
      if (!value.isFinite) {
        return null;
      }
      return value.toString();
    }
    if (value is num) {
      return value.toDouble().toString();
    }
    if (value is String) {
      final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      return '"$escaped"';
    }

    final encoded = jsonEncode(value);
    if (encoded == 'null') {
      return null;
    }
    final escaped = encoded.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
