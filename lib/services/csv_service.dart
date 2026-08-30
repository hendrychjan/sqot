import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:sqot/models/data_point.dart';

class CsvService {
  CsvService._();
  factory CsvService() => instance;
  static final CsvService instance = CsvService._();

  /// Creates an export from `dataPoints` and starts the sharing service to let
  /// the user download it
  Future<ShareResult> exportDataPoints(List<DataPoint> dataPoints) async {
    final bytes = _createExport(dataPoints);

    final params = ShareParams(
      files: [XFile.fromData(bytes, name: 'export.csv', mimeType: 'text/csv')],
    );

    return SharePlus.instance.share(params);
  }

  Uint8List _createExport(List<DataPoint> dataPoints) {
    final buffer = StringBuffer();

    // UTF-8 BOM for Excel compatibility.
    buffer.write('\uFEFF');

    buffer.writeln('timestamp;topic;field;value');

    for (final dataPoint in dataPoints) {
      for (final entry in dataPoint.fields.entries) {
        buffer
          ..write(_escape(dataPoint.timestamp.toUtc().toIso8601String()))
          ..write(';')
          ..write(_escape(dataPoint.topic))
          ..write(';')
          ..write(_escape(entry.key))
          ..write(';')
          ..writeln(_escape(_valueToString(entry.value)));
      }
    }

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  String _valueToString(Object? value) {
    if (value == null) return '';

    return switch (value) {
      DateTime value => value.toUtc().toIso8601String(),
      bool value => value ? 'true' : 'false',
      num value => value.toString(),
      String value => value,
      _ => value.toString(),
    };
  }

  String _escape(String value) {
    if (value.contains(';') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }

    return value;
  }
}
