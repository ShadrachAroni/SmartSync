import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/device.dart';
import '../providers/device_provider.dart';

class DeviceTile extends ConsumerWidget {
  final Device device;

  const DeviceTile({super.key, required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine the leading icon/widget based on device type
    Widget leadingIcon;
    switch (device.type) {
      case DeviceType.fan:
        leadingIcon = Image.asset(
          'assets/icons/fan.png',
          width: 28,
          height: 28,
        );
        break;
      case DeviceType.bulb:
        leadingIcon = const Icon(Icons.lightbulb_outline, size: 28);
        break;
      case DeviceType.tv:
        leadingIcon = const Icon(Icons.tv, size: 28);
        break;
      default:
        leadingIcon = const Icon(Icons.sensors, size: 28);
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: leadingIcon),
        ),
        title: Text(device.name),
        subtitle: Text(device.isOn ? 'On' : 'Off'),
        trailing: Switch(
          value: device.isOn,
          onChanged: (_) =>
              ref.read(devicesProvider.notifier).toggle(device.id),
        ),
        onTap: () {
          // Navigate to device detail using GoRouter
          GoRouter.of(context).push('/device/${device.id}');
        },
      ),
    );
  }
}
