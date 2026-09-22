import 'dart:async';
import 'dart:collection';

import 'package:universal_ble/universal_ble.dart';

abstract class BleGenericMonitor {
  static const String _batteryServiceUuid = '180F';
  static const String _batteryLevelCharacteristicUuid = '2A19';
  static const Duration _telemetryPollInterval = Duration(seconds: 5);
  static const Duration _connectStatePollInterval = Duration(milliseconds: 200);
  static const Duration _connectStateTimeout = Duration(seconds: 12);
  static const Duration _discoverRetryDelay = Duration(milliseconds: 350);
  static const int _discoverRetryCount = 5;

  final BleDevice bleDevice;
  final Stream<double> batteryStream;
  final Stream<int> signalStrengthStream;

  bool _isConnected = false;
  bool _isListening = false;

  BleGenericMonitor({required this.bleDevice})
    : batteryStream = _createBatteryStream(
        bleDevice.deviceId,
      ).asBroadcastStream(),
      signalStrengthStream = _createSignalStrengthStream(
        bleDevice.deviceId,
      ).asBroadcastStream();

  Future<void> connect() async {
    if (_isConnected) {
      return;
    }

    await UniversalBle.connect(bleDevice.deviceId);
    await _waitUntilConnected();
    await _discoverServicesWithRetry();
    _isConnected = true;
    await startListening();
  }

  Future<void> startListening() async {
    if (_isListening) {
      return;
    }

    await onStartListening();
    _isListening = true;
  }

  Future<void> disconnect() async {
    await stopListening();

    if (!_isConnected) {
      return;
    }

    await UniversalBle.disconnect(bleDevice.deviceId);
    _isConnected = false;
  }

  Future<void> stopListening() async {
    if (!_isListening) {
      return;
    }

    try {
      await onStopListening();
    } finally {
      _isListening = false;
    }
  }

  Future<void> onStartListening();

  Future<void> onStopListening();

  Future<void> _waitUntilConnected() async {
    final start = DateTime.now();

    while (DateTime.now().difference(start) < _connectStateTimeout) {
      final state = await UniversalBle.getConnectionState(bleDevice.deviceId);
      if (state == BleConnectionState.connected) {
        return;
      }

      await Future<void>.delayed(_connectStatePollInterval);
    }

    throw StateError('Timed out waiting for BLE connection.');
  }

  Future<void> _discoverServicesWithRetry() async {
    Object? lastError;

    for (int attempt = 0; attempt < _discoverRetryCount; attempt++) {
      try {
        await UniversalBle.discoverServices(bleDevice.deviceId);
        return;
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(_discoverRetryDelay);
      }
    }

    throw StateError('Unable to discover BLE services: $lastError');
  }

  static Stream<double> _createBatteryStream(String deviceId) async* {
    while (true) {
      try {
        final value = await UniversalBle.read(
          deviceId,
          _batteryServiceUuid,
          _batteryLevelCharacteristicUuid,
        );

        if (value.isNotEmpty) {
          yield value.first.toDouble();
        }
      } catch (_) {
        // Optional telemetry characteristic, ignore if unavailable.
      }

      await Future<void>.delayed(_telemetryPollInterval);
    }
  }

  static Stream<int> _createSignalStrengthStream(String deviceId) async* {
    while (true) {
      try {
        final rssi = await UniversalBle.readRssi(deviceId);
        yield rssi;
      } catch (_) {
        // RSSI may fail intermittently; continue polling.
      }

      await Future<void>.delayed(_telemetryPollInterval);
    }
  }

  static Stream<double> createRunningMaxStream(Stream<num> source) {
    final controller = StreamController<double>.broadcast();
    double? maxValue;

    final subscription = source.listen(
      (value) {
        final sample = value.toDouble();
        if (!sample.isFinite) {
          return;
        }

        if (maxValue == null || sample > maxValue!) {
          maxValue = sample;
        }

        controller.add(maxValue!);
      },
      onError: controller.addError,
      onDone: () {
        controller.close();
      },
    );

    controller.onCancel = () async {
      await subscription.cancel();
    };

    return controller.stream;
  }

  static Stream<double> createRunningAverageStream(Stream<num> source) {
    final controller = StreamController<double>.broadcast();
    double sum = 0;
    int count = 0;

    final subscription = source.listen(
      (value) {
        final sample = value.toDouble();
        if (!sample.isFinite) {
          return;
        }

        sum += sample;
        count += 1;
        controller.add(sum / count);
      },
      onError: controller.addError,
      onDone: () {
        controller.close();
      },
    );

    controller.onCancel = () async {
      await subscription.cancel();
    };

    return controller.stream;
  }

  static Stream<double> createWindowAverageStream(
    Stream<num> source,
    Duration Function() windowDurationProvider,
  ) {
    final controller = StreamController<double>.broadcast();
    final samples = Queue<({DateTime timestamp, double value})>();

    Duration readWindowDuration() {
      final duration = windowDurationProvider();
      if (duration <= Duration.zero) {
        return const Duration(minutes: 1);
      }

      return duration;
    }

    void trimSamples(DateTime now, Duration windowDuration) {
      final cutoff = now.subtract(windowDuration);
      while (samples.isNotEmpty && samples.first.timestamp.isBefore(cutoff)) {
        samples.removeFirst();
      }
    }

    final subscription = source.listen(
      (value) {
        final sample = value.toDouble();
        if (!sample.isFinite) {
          return;
        }

        final now = DateTime.now();
        final windowDuration = readWindowDuration();
        samples.add((timestamp: now, value: sample));
        trimSamples(now, windowDuration);

        if (samples.isEmpty) {
          return;
        }

        final windowSum = samples.fold<double>(
          0,
          (sum, current) => sum + current.value,
        );
        controller.add(windowSum / samples.length);
      },
      onError: controller.addError,
      onDone: () {
        controller.close();
      },
    );

    controller.onCancel = () async {
      await subscription.cancel();
    };

    return controller.stream;
  }
}
