import 'dart:convert';
import 'dart:io';

import 'package:sqot/models/data_point.dart';
import 'package:sqot/services/settings_service.dart';

class InfluxService {
  InfluxService._();
  factory InfluxService() => instance;
  static final InfluxService instance = InfluxService._();

  final SettingsService _settingsService = SettingsService.instance;

  Future<void> testConnection({
    required String url,
    required String org,
    required String bucket,
    required String token,
  }) async {
    final influxUrl = Uri.parse(url.trim());
    final trimmedOrg = org.trim();
    final trimmedBucket = bucket.trim();
    final trimmedToken = token.trim();

    if (trimmedOrg.isEmpty || trimmedBucket.isEmpty || trimmedToken.isEmpty) {
      throw StateError('Influx URL, org, bucket, and token are required.');
    }

    final client = HttpClient();

    try {
      final healthUri = influxUrl.replace(
        path: _joinPath(influxUrl.path, '/health'),
      );
      final healthRequest = await client.getUrl(healthUri);
      healthRequest.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final healthResponse = await healthRequest.close();
      if (healthResponse.statusCode < 200 || healthResponse.statusCode >= 300) {
        final body = await utf8.decodeStream(healthResponse);
        throw HttpException(
          'Influx health check failed (${healthResponse.statusCode}): $body',
          uri: healthUri,
        );
      }

      await healthResponse.drain<void>();

      final bucketUri = influxUrl.replace(
        path: _joinPath(influxUrl.path, '/api/v2/buckets'),
        queryParameters: {
          'name': trimmedBucket,
          'org': trimmedOrg,
          'limit': '1',
        },
      );

      final bucketRequest = await client.getUrl(bucketUri);
      bucketRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Token $trimmedToken',
      );
      bucketRequest.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final bucketResponse = await bucketRequest.close();
      final bucketResponseBody = await utf8.decodeStream(bucketResponse);

      if (bucketResponse.statusCode == HttpStatus.unauthorized ||
          bucketResponse.statusCode == HttpStatus.forbidden) {
        throw HttpException(
          'Influx authentication failed (${bucketResponse.statusCode}).',
          uri: bucketUri,
        );
      }

      if (bucketResponse.statusCode < 200 || bucketResponse.statusCode >= 300) {
        throw HttpException(
          'Influx bucket lookup failed (${bucketResponse.statusCode}): $bucketResponseBody',
          uri: bucketUri,
        );
      }

      final decoded = jsonDecode(bucketResponseBody);
      final buckets = decoded is Map<String, dynamic>
          ? decoded['buckets'] as List<dynamic>?
          : null;

      final hasTargetBucket =
          buckets?.whereType<Map<String, dynamic>>().any((entry) {
            final bucketName = entry['name']?.toString();
            return bucketName == trimmedBucket;
          }) ??
          false;

      if (!hasTargetBucket) {
        throw StateError(
          'Bucket "$trimmedBucket" was not found for org "$trimmedOrg".',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

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
