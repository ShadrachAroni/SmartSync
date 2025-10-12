// lib/screens/home/bluetooth_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../services/permission_utils.dart';
import '../../services/ble_service.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});
  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  List<ScanResult> results = <ScanResult>[];
  bool scanning = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth devices')),
      floatingActionButton: FloatingActionButton(
        onPressed: scanning ? null : _scan,
        child: const Icon(Icons.search),
      ),
      body: ListView.builder(
        itemCount: results.length,
        itemBuilder: (_, i) {
          final r = results[i];
          final name = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : (r.device.platformName.isNotEmpty
                  ? r.device.platformName
                  : r.device.remoteId.str);
          return Card(
            child: ListTile(
              title: Text(name),
              subtitle: Text('RSSI: ${r.rssi} • ${r.device.remoteId.str}'),
              trailing: FilledButton(
                onPressed: () async {
                  await BLEService().connect(r.device);
                  if (mounted) Navigator.of(context).pop();
                },
                child: const Text('Connect'),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _scan() async {
    setState(() => scanning = true);
    final ok = await PermissionUtils.ensureBlePermissions();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Permissions denied')));
      }
      setState(() => scanning = false);
      return;
    }
    await BLEService().startScan((list) => setState(() => results = list));
    await Future.delayed(const Duration(seconds: 7));
    await BLEService().stopScan();
    setState(() => scanning = false);
  }
}
