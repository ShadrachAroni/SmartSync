import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as blue;

import '../services/bluetooth_service.dart';
import '../widgets/device_connection_card.dart';
import '../widgets/bottom_nav.dart';

/// Holds the currently connected Bluetooth device globally
final bluetoothDeviceProvider =
    StateProvider<blue.BluetoothDevice?>((ref) => null);

class DeviceConnectionScreen extends ConsumerStatefulWidget {
  const DeviceConnectionScreen({super.key});

  @override
  ConsumerState<DeviceConnectionScreen> createState() =>
      _DeviceConnectionScreenState();
}

class _DeviceConnectionScreenState
    extends ConsumerState<DeviceConnectionScreen> {
  bool _scanning = false;
  List<blue.BluetoothDevice> _devices = [];

  /// Starts a Bluetooth scan and updates the list of devices
  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _devices = [];
    });

    try {
      final list = await BluetoothService.scanForDevices(
        timeout: const Duration(seconds: 5),
      );

      // update UI
      if (mounted) {
        setState(() => _devices = list.cast<blue.BluetoothDevice>());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  /// Connect to a selected device and store it in Riverpod
  Future<void> _connect(blue.BluetoothDevice device) async {
    try {
      await BluetoothService.connect(device);
      ref.read(bluetoothDeviceProvider.notifier).state = device;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to ${device.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connect failed: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _startScan(); // automatically start scanning when the screen loads
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(bluetoothDeviceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Device Connect')),
      // add the bottom nav here
      bottomNavigationBar: const BottomNav(),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: Image.asset('assets/icons/bluetooth.png', width: 40),
                title: const Text('Bluetooth'),
                subtitle: Text(
                  connected == null
                      ? 'Not connected'
                      : 'Connected: ${connected.name}',
                ),
                trailing: ElevatedButton.icon(
                  onPressed: _scanning ? null : _startScan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Scan'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _scanning
                  ? const Center(child: CircularProgressIndicator())
                  : _devices.isEmpty
                      ? const Center(
                          child: Text(
                            'No devices found — ensure your device is advertising',
                          ),
                        )
                      : ListView.separated(
                          itemCount: _devices.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, i) {
                            final d = _devices[i];
                            return DeviceConnectionCard(
                              device: d,
                              onConnect: () => _connect(d),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
