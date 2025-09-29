import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/device_provider.dart'; // contains devicesProvider + bluetoothDeviceProvider
import '../widgets/device_tile.dart';
import '../widgets/temperature_card.dart';
import '../services/temperature_service.dart';
import '../widgets/bottom_nav.dart';

class RoomDetailScreen extends ConsumerWidget {
  final String roomId;
  const RoomDetailScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices =
        ref.watch(devicesProvider).where((d) => d.roomId == roomId).toList();
    final connectedDevice = ref.watch(bluetoothDeviceProvider);

    // temperature stream (tries BLE if connected, otherwise falls back to simulated stream)
    final tempStream = connectedDevice != null
        ? TemperatureService.subscribeTemperature(connectedDevice)
        : TemperatureService.simulatedTemperatureStream();

    return Scaffold(
      appBar: AppBar(title: Text(_prettyRoomTitle(roomId))),
      bottomNavigationBar: const BottomNav(), // <-- added here
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            // Temperature card shows live updates
            StreamBuilder<double>(
              stream: tempStream,
              builder: (context, snap) {
                final temp = snap.data ?? 21.0;
                return TemperatureCard(temperature: temp);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Devices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pushNamed(context, '/logs'),
                  icon: const Icon(Icons.history),
                )
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: devices.isEmpty
                  ? const Center(child: Text('No devices in this room yet'))
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: devices.length,
                      itemBuilder: (context, index) =>
                          DeviceTile(device: devices[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Simple helper to make the app bar title friendlier — you can replace with a map if you have nice names elsewhere.
  String _prettyRoomTitle(String id) {
    switch (id.toLowerCase()) {
      case 'r1':
        return 'Living Room';
      case 'r2':
        return 'Kitchen';
      case 'r3':
        return 'Office';
      case 'r4':
        return 'Bedroom';
      case 'r5':
        return 'Bathroom';
      case 'r6':
        return 'Dining Room';
      default:
        // fallback: capitalize and replace underscores/dashes
        final t = id.replaceAll(RegExp(r'[_\-]'), ' ');
        return t.isEmpty ? 'Room' : '${t[0].toUpperCase()}${t.substring(1)}';
    }
  }
}
