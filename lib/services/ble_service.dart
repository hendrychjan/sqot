import 'dart:async';

import 'package:sqot/models/ble_cycling_cadence_monitor.dart';
import 'package:sqot/models/ble_cycling_speed_monitor.dart';
import 'package:sqot/models/ble_generic_monitor.dart';
import 'package:sqot/models/ble_heartrate_monitor.dart';
import 'package:sqot/models/device.dart';
import 'package:sqot/models/device_type.dart';
import 'package:universal_ble/universal_ble.dart';

class BleService {
  BleService._();
  factory BleService() => instance;
  static final BleService instance = BleService._();

  Future<void> startScan(DeviceType deviceType) async {
    assert(!(await UniversalBle.isScanning())); // Avoid duplicate scans

    // Check bluetooth availability
    AvailabilityState state =
        await UniversalBle.getBluetoothAvailabilityState();

    if (state != AvailabilityState.poweredOn) {
      throw StateError("Bluetooth is not available.");
    }

    // Start the scan
    await UniversalBle.startScan(
      scanFilter: ScanFilter(withServices: [deviceType.serviceGuid]),
    );
  }

  Future<void> forceStopScan() async {
    await UniversalBle.stopScan();
  }

  Future<BleDevice?> findSystemDeviceByBleId({
    required String bleId,
    required DeviceType deviceType,
  }) async {
    try {
      final devices = await UniversalBle.getSystemDevices(
        withServices: [deviceType.serviceGuid],
      );

      for (final bleDevice in devices) {
        if (bleDevice.deviceId == bleId) {
          return bleDevice;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<BleDevice?> resolveBleDevice({
    required Device device,
    required DeviceType deviceType,
    Duration scanTimeout = const Duration(seconds: 15),
  }) async {
    final systemDevice = await findSystemDeviceByBleId(
      bleId: device.bleId,
      deviceType: deviceType,
    );
    if (systemDevice != null) {
      return systemDevice;
    }

    try {
      await forceStopScan();
      await startScan(deviceType);

      return await UniversalBle.scanStream
          .firstWhere((bleDevice) => bleDevice.deviceId == device.bleId)
          .timeout(scanTimeout);
    } on TimeoutException {
      return null;
    } finally {
      await forceStopScan();
    }
  }

  BleGenericMonitor createMonitor({
    required BleDevice bleDevice,
    required DeviceType deviceType,
  }) {
    switch (deviceType) {
      case DeviceType.heartRateMonitor:
        return BleHeartrateMonitor(bleDevice: bleDevice);
      case DeviceType.cyclingSpeedMonitor:
        return BleCyclingSpeedMonitor(bleDevice: bleDevice);
      case DeviceType.cyclingCadenceMonitor:
        return BleCyclingCadenceMonitor(bleDevice: bleDevice);
    }
  }

  Future<BleGenericMonitor?> createMonitorFromSavedDevice({
    required Device device,
    required DeviceType deviceType,
  }) async {
    final bleDevice = await resolveBleDevice(
      device: device,
      deviceType: deviceType,
    );

    if (bleDevice == null) {
      return null;
    }

    return createMonitor(bleDevice: bleDevice, deviceType: deviceType);
  }
}
