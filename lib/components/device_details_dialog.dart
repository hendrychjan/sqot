import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqot/models/ble_generic_monitor.dart';
import 'package:sqot/models/device.dart';
import 'package:sqot/models/device_type.dart';
import 'package:sqot/services/ble_service.dart';

class DeviceDetailsDialog extends StatefulWidget {
  final DeviceType deviceType;
  final Device? device;

  const DeviceDetailsDialog({
    super.key,
    required this.deviceType,
    required this.device,
  });

  static Future<void> show({
    required DeviceType deviceType,
    required Device? device,
  }) {
    return Get.bottomSheet<void>(
      DeviceDetailsDialog(deviceType: deviceType, device: device),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isDismissible: true,
    );
  }

  @override
  State<DeviceDetailsDialog> createState() => _DeviceDetailsDialogState();
}

class _DeviceDetailsDialogState extends State<DeviceDetailsDialog> {
  final BleService _bleService = BleService.instance;

  BleGenericMonitor? _monitor;
  bool _isMonitorLoading = false;
  String? _monitorError;

  bool get _isConnected => widget.device != null;

  @override
  void initState() {
    super.initState();
    _initializeMonitor();
  }

  @override
  void dispose() {
    _monitor?.disconnect();
    super.dispose();
  }

  Future<void> _initializeMonitor() async {
    final savedDevice = widget.device;
    if (savedDevice == null) {
      return;
    }

    setState(() {
      _isMonitorLoading = true;
      _monitorError = null;
    });

    try {
      final monitor = await _bleService.createMonitorFromSavedDevice(
        device: savedDevice,
        deviceType: widget.deviceType,
      );

      if (!mounted) {
        return;
      }

      if (monitor == null) {
        setState(() {
          _isMonitorLoading = false;
          _monitorError = 'Saved device was not found nearby.';
        });
        return;
      }

      await monitor.connect();

      if (!mounted) {
        return;
      }

      setState(() {
        _monitor = monitor;
        _isMonitorLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isMonitorLoading = false;
        _monitorError = 'Unable to start live monitoring: $e';
      });
    }
  }

  Widget _buildLiveMonitorSection(BuildContext context) {
    final textTheme = context.theme.textTheme;
    final colorScheme = context.theme.colorScheme;

    if (!_isConnected) {
      return _DetailTile(
        icon: Icons.sensors_off_outlined,
        label: 'Live data',
        value: 'Connect this device first to see live telemetry.',
      );
    }

    if (_isMonitorLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (_monitorError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          _monitorError!,
          style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
        ),
      );
    }

    final monitor = _monitor;
    if (monitor == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        StreamBuilder<Map<String, String>>(
          stream: monitor.metricsStream,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final entry = (data == null || data.isEmpty)
                ? null
                : data.entries.first;

            return _DetailTile(
              icon: Icons.monitor_heart_outlined,
              label: entry?.key ?? 'Metric',
              value: entry?.value ?? 'Waiting for data...',
            );
          },
        ),
        const Divider(height: 1),
        StreamBuilder<double>(
          stream: monitor.batteryStream,
          builder: (context, snapshot) {
            final battery = snapshot.data;
            final value = battery == null
                ? 'Waiting for data...'
                : '${battery.toStringAsFixed(0)}%';

            return _DetailTile(
              icon: Icons.battery_charging_full_outlined,
              label: 'Battery',
              value: value,
            );
          },
        ),
        const Divider(height: 1),
        StreamBuilder<int>(
          stream: monitor.signalStrengthStream,
          builder: (context, snapshot) {
            final rssi = snapshot.data;
            final value = rssi == null ? 'Waiting for data...' : '$rssi dBm';

            return _DetailTile(
              icon: Icons.network_cell_outlined,
              label: 'Signal strength',
              value: value,
            );
          },
        ),
      ],
    );
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
                          widget.deviceType.label,
                          style: textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: Get.back,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      Icon(
                        _isConnected
                            ? Icons.link_rounded
                            : Icons.link_off_rounded,
                        size: 18,
                        color: _isConnected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isConnected
                            ? 'Saved device details'
                            : 'No saved device',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                    children: [
                      _DetailTile(
                        icon: Icons.badge_outlined,
                        label: 'Name',
                        value: widget.device?.name ?? 'Not connected',
                      ),
                      const Divider(height: 1),
                      _DetailTile(
                        icon: Icons.router_outlined,
                        label: 'Address',
                        value: widget.device?.address ?? 'Not available',
                      ),
                      const Divider(height: 1),
                      _DetailTile(
                        icon: Icons.memory_outlined,
                        label: 'BLE ID',
                        value: widget.device?.bleId ?? 'Not available',
                      ),
                      const Divider(height: 1),
                      _buildLiveMonitorSection(context),
                    ],
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

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = context.theme.textTheme;
    final colorScheme = context.theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        value,
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
