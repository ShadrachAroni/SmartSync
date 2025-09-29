import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Holds the currently connected Bluetooth device
final bluetoothDeviceProvider = StateProvider<BluetoothDevice?>((ref) => null);

/// Card widget for displaying a Bluetooth device and connect action
class DeviceConnectionCard extends ConsumerWidget {
  final BluetoothDevice device;
  final VoidCallback onConnect;

  const DeviceConnectionCard({
    super.key,
    required this.device,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.bluetooth, color: Colors.blue, size: 32),
        title: Text(
          device.name.isNotEmpty ? device.name : device.id.toString(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('ID: ${device.id}'),
        trailing: ElevatedButton.icon(
          icon: const Icon(Icons.link),
          label: const Text('Connect'),
          onPressed: onConnect,
        ),
      ),
    );
  }
}
