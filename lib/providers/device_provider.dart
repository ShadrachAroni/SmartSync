import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// List of logical smart devices
final devicesProvider =
    StateNotifierProvider<DeviceListNotifier, List<Device>>((ref) {
  return DeviceListNotifier();
});

/// Currently connected Bluetooth device
final bluetoothDeviceProvider = StateProvider<BluetoothDevice?>((ref) => null);

class DeviceListNotifier extends StateNotifier<List<Device>> {
  DeviceListNotifier() : super(_initial);

  static final _initial = [
    Device(
        id: 'd1',
        name: 'Living Room Light',
        type: DeviceType.bulb,
        roomId: 'r1',
        isOn: true,
        value: 0.8),
    Device(
        id: 'd2',
        name: 'Fan',
        type: DeviceType.fan,
        roomId: 'r1',
        isOn: false,
        value: 0.2),
    Device(
        id: 'd3',
        name: 'Smart TV',
        type: DeviceType.tv,
        roomId: 'r1',
        isOn: false,
        value: 0.0),
    Device(
        id: 'd4',
        name: 'Bedroom Lamp',
        type: DeviceType.bulb,
        roomId: 'r4',
        isOn: true,
        value: 0.6),
  ];

  void toggle(String id) {
    state = [
      for (final d in state)
        if (d.id == id) d.copyWith(isOn: !d.isOn) else d
    ];
  }

  void setValue(String id, double newValue) {
    state = [
      for (final d in state)
        if (d.id == id) d.copyWith(value: newValue, isOn: newValue > 0.0) else d
    ];
  }

  void upsert(Device device) {
    final idx = state.indexWhere((d) => d.id == device.id);
    if (idx >= 0) {
      final copy = [...state];
      copy[idx] = device;
      state = copy;
    } else {
      state = [...state, device];
    }
  }

  Device? getById(String id) =>
      state.firstWhere((d) => d.id == id, orElse: () => state.first);
}
