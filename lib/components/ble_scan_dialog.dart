import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqot/models/device.dart';
import 'package:sqot/models/device_type.dart';
import 'package:sqot/services/ble_service.dart' as app_ble;
import 'package:universal_ble/universal_ble.dart';

class BleScanDialog extends StatefulWidget {
  final DeviceType deviceType;
  const BleScanDialog({super.key, required this.deviceType});

  static Future<Device?> show({required DeviceType deviceType}) {
    return Get.bottomSheet<Device>(
      BleScanDialog(deviceType: deviceType),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isDismissible: true,
    ).whenComplete(() => app_ble.BleService.instance.forceStopScan());
  }

  @override
  State<BleScanDialog> createState() => _BleScanDialogState();
}

class _BleScanDialogState extends State<BleScanDialog> {
  static const Duration _scanDuration = Duration(seconds: 15);

  late Stream<BleDevice> _scanStream;
  final Map<String, BleDevice> _discoveredDevicesById = {};
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();

    _scanStream = UniversalBle.scanStream;
    _startScan();
  }

  @override
  void dispose() {
    app_ble.BleService.instance.forceStopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
    });

    try {
      await app_ble.BleService.instance.forceStopScan();
      await app_ble.BleService.instance.startScan(widget.deviceType);
      await Future<void>.delayed(_scanDuration);
      await app_ble.BleService.instance.forceStopScan();

      if (!mounted) {
        return;
      }

      setState(() {
        _isScanning = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isScanning = false;
      });

      Get.snackbar('Scanning failed', e.toString());
    }
  }

  Future<void> _rescan() async {
    await app_ble.BleService.instance.forceStopScan();
    if (!mounted) {
      return;
    }

    setState(() {
      _isScanning = false;
      _discoveredDevicesById.clear();
    });

    await _startScan();
  }

  Device _toAppDevice(BleDevice bleDevice) {
    final name = bleDevice.name?.trim();
    return Device(
      name: (name == null || name.isEmpty) ? 'Unknown device' : name,
      address: bleDevice.deviceId,
      bleId: bleDevice.deviceId,
    );
  }

  Future<void> _closeDialog({Device? result}) async {
    await app_ble.BleService.instance.forceStopScan();
    Get.back(result: result);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final textTheme = context.theme.textTheme;
    final screenHeight = context.mediaQuery.size.height;
    final sheetHeight = screenHeight * 0.92;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: sheetHeight,
        child: Material(
          color: colorScheme.surfaceContainerLow,
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Find Bluetooth device',
                          style: textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _closeDialog,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Nearby devices will appear here while scanning.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_isScanning) const LinearProgressIndicator(minHeight: 2),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<BleDevice>(
                    stream: _scanStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Scanning failed: ${snapshot.error}',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      final latest = snapshot.data;
                      if (latest != null) {
                        _discoveredDevicesById[latest.deviceId] = latest;
                      }

                      final devices = _discoveredDevicesById.values.toList(
                        growable: false,
                      );

                      if (devices.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _isScanning
                                  ? 'Scanning for nearby devices...'
                                  : 'No devices found. Tap Rescan to try again.',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                        itemCount: devices.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final bleDevice = devices[index];
                          final displayName =
                              (bleDevice.name == null ||
                                  bleDevice.name!.trim().isEmpty)
                              ? 'Unknown device'
                              : bleDevice.name!.trim();
                          final signal = bleDevice.rssi == null
                              ? 'RSSI N/A'
                              : 'RSSI ${bleDevice.rssi} dBm';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            leading: const Icon(Icons.bluetooth_rounded),
                            title: Text(displayName),
                            subtitle: Text('$signal • ${bleDevice.deviceId}'),
                            trailing: IconButton.filledTonal(
                              tooltip: 'Connect',
                              onPressed: () {
                                _closeDialog(result: _toAppDevice(bleDevice));
                              },
                              icon: const Icon(Icons.link_rounded),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (!_isScanning)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _rescan,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry scan'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
