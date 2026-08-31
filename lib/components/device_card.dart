import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqot/components/ble_scan_dialog.dart';
import 'package:sqot/components/device_details_dialog.dart';
import 'package:sqot/models/device.dart';
import 'package:sqot/models/device_type.dart';
import 'package:sqot/services/settings_service.dart';

class DeviceCard extends StatefulWidget {
  final DeviceType deviceType;
  const DeviceCard({super.key, required this.deviceType});

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  final SettingsService _settingsService = SettingsService.instance;

  Device? get _device => _settingsService
      .getCurrentSettings()
      .devicesSettings
      .devices[widget.deviceType];

  bool get _configured => _device != null;

  Future _handleConnectDevice() async {
    final device = await BleScanDialog.show(deviceType: widget.deviceType);
    if (device == null) return;

    await _settingsService.updateSetting(
      newDevice: (widget.deviceType, device),
    );

    setState(() {});
  }

  Future _handleDisconnectDevice() async {
    await _settingsService.updateSetting(newDevice: (widget.deviceType, null));

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _handleOpenDetails() async {
    await DeviceDetailsDialog.show(
      deviceType: widget.deviceType,
      device: _device,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _handleOpenDetails,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 5,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    spacing: 10,
                    children: [
                      Icon(widget.deviceType.icon),
                      Text(
                        widget.deviceType.label,
                        style: context.theme.textTheme.titleMedium,
                      ),
                    ],
                  ),

                  (!_configured)
                      ? IconButton.filled(
                          onPressed: _handleConnectDevice,
                          icon: Icon(Icons.add),
                        )
                      : IconButton.filled(
                          onPressed: _handleDisconnectDevice,
                          icon: Icon(Icons.link_off),
                        ),
                ],
              ),
              Text(
                !_configured ? "Not connected" : _device!.name,
                style: TextStyle(
                  fontStyle: !_configured ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
