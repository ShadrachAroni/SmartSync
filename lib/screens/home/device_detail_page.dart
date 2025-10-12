// lib/screens/home/device_detail_page.dart
import 'package:flutter/material.dart';
import '../../models/device.dart';
import '../../services/ble_service.dart';
import '../../services/log_service.dart';
import '../../services/device_registry.dart';
import '../../services/adaptive_scheduler.dart';

class DeviceDetailPage extends StatefulWidget {
  final Device device;
  const DeviceDetailPage({super.key, required this.device});

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  late bool power;
  late int level;

  @override
  void initState() {
    super.initState();
    power = widget.device.power;
    level = widget.device.level;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.device;
    final label = d.type == DeviceType.fan
        ? 'Speed'
        : (d.type == DeviceType.bulb ? 'Intensity' : 'Level');

    return Scaffold(
      appBar: AppBar(title: Text(d.name)),
      body: LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Hero(
                  tag: 'device-img-${d.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      color: cs.surfaceContainerHighest,
                      height: 170,
                      child: Center(
                        child: Image.asset(
                          d.image,
                          height: 130,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(d.icon,
                              size: 100, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: power ? cs.primaryContainer : cs.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          power ? Icons.power : Icons.power_settings_new,
                          color: cs.onPrimaryContainer,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          power ? 'Powered On' : 'Powered Off',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Switch(
                          value: power,
                          onChanged: (v) async {
                            setState(() => power = v);
                            await _sendPower(v);
                            await LogService.addRoom(
                                d.room, '${d.name} ${v ? "ON" : "OFF"}');
                            await AdaptiveScheduler.bump(
                                reason: 'device_power');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (d.type == DeviceType.fan || d.type == DeviceType.bulb)
                  Card(
                    elevation: 0,
                    color: cs.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$label • $level%',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Slider(
                            value: level.toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 20,
                            onChanged: !power
                                ? null
                                : (v) => setState(() => level = v.round()),
                            onChangeEnd: !power
                                ? null
                                : (v) async {
                                    await _sendLevel(v.round());
                                    await LogService.addRoom(d.room,
                                        '${d.name} $label -> ${v.round()}%');
                                    await AdaptiveScheduler.bump(
                                        reason: 'device_level');
                                  },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _presetsFor(d).map((p) {
                              return ActionChip(
                                label: Text(p['label'] as String),
                                onPressed: () async {
                                  final target = p['value'] as int;
                                  setState(() {
                                    power = true;
                                    level = target;
                                  });
                                  await _sendPower(true);
                                  await _sendLevel(target);
                                  await LogService.addRoom(
                                      d.room, '${d.name} preset -> $target%');
                                  await AdaptiveScheduler.bump(
                                      reason: 'device_preset');
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (d.bleId != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.home_work_outlined),
                    onPressed: () async {
                      // allow reassignment to another room
                      final r = await showModalBottomSheet<String>(
                        context: context,
                        builder: (_) => _RoomPicker(current: d.room),
                      );
                      if (r != null) {
                        await DeviceRegistry.bind(
                            bleId: d.bleId!, room: r, label: d.name);
                        setState(() {
                          widget.device.room = r; // room is mutable in Device
                        });
                        await LogService.addRoom(
                            r, '${d.name} reassigned to $r');
                        await AdaptiveScheduler.bump(
                            reason: 'device_room_reassign');
                      }
                    },
                    label: Text('Assign to room • ${d.room}'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, Object>> _presetsFor(Device d) {
    if (d.type == DeviceType.fan) {
      return const [
        {'label': 'Breeze 25%', 'value': 25},
        {'label': 'Normal 60%', 'value': 60},
        {'label': 'Turbo 90%', 'value': 90},
      ];
    }
    if (d.type == DeviceType.bulb) {
      return const [
        {'label': 'Warm 25%', 'value': 25},
        {'label': 'Read 60%', 'value': 60},
        {'label': 'Max 100%', 'value': 100},
      ];
    }
    return const [];
  }

  Future<void> _sendPower(bool on) async {
    final d = widget.device;
    if (d.type == DeviceType.fan) {
      await BLEService().setFanSpeed(on ? level : 0);
    } else if (d.type == DeviceType.bulb) {
      await BLEService().setBulbIntensity(on ? level : 0);
    }
    d.power = on;
  }

  Future<void> _sendLevel(int v) async {
    final d = widget.device;
    if (d.type == DeviceType.fan) {
      await BLEService().setFanSpeed(v);
    } else if (d.type == DeviceType.bulb) {
      await BLEService().setBulbIntensity(v);
    }
    d.level = v;
  }
}

class _RoomPicker extends StatelessWidget {
  final String current;
  const _RoomPicker({required this.current});
  @override
  Widget build(BuildContext context) {
    const rooms = ['Living', 'Kitchen', 'Bedroom', 'Office'];
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: rooms
            .map((r) => RadioListTile<String>(
                  value: r,
                  groupValue: current,
                  title: Text(r),
                  onChanged: (v) => Navigator.of(context).pop(v),
                ))
            .toList(),
      ),
    );
  }
}
