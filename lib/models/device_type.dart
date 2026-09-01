import 'package:flutter/material.dart';

enum DeviceType { heartRateMonitor, cyclingSpeedMonitor, cyclingCadenceMonitor }

extension XDeviceType on DeviceType {
  IconData get icon {
    switch (this) {
      case DeviceType.heartRateMonitor:
        return Icons.favorite;
      case DeviceType.cyclingSpeedMonitor:
        return Icons.speed;
      case DeviceType.cyclingCadenceMonitor:
        return Icons.sync;
    }
  }

  String get label {
    switch (this) {
      case DeviceType.heartRateMonitor:
        return 'Heart rate monitor';
      case DeviceType.cyclingSpeedMonitor:
        return 'Cycling speed monitor';
      case DeviceType.cyclingCadenceMonitor:
        return 'Cycling cadence monitor';
    }
  }

  String get topic {
    switch (this) {
      case DeviceType.heartRateMonitor:
        return 'heart_rate';
      case DeviceType.cyclingSpeedMonitor:
        return 'cycling';
      case DeviceType.cyclingCadenceMonitor:
        return 'cycling';
    }
  }

  String get serviceGuid {
    switch (this) {
      case DeviceType.heartRateMonitor:
        return '180D';

      case DeviceType.cyclingSpeedMonitor:
      case DeviceType.cyclingCadenceMonitor:
        return '1816';
    }
  }
}
