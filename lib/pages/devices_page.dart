import 'package:flutter/material.dart';
import 'package:sqot/components/device_card.dart';
import 'package:sqot/models/device_type.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            DeviceCard(deviceType: DeviceType.heartRateMonitor),
            DeviceCard(deviceType: DeviceType.cyclingSpeedMonitor),
            DeviceCard(deviceType: DeviceType.cyclingCadenceMonitor),
          ],
        ),
      ),
    );
  }
}
