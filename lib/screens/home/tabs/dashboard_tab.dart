// lib/screens/home/tabs/dashboard_tab.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/device.dart';
import '../../../services/ble_service.dart';
import '../../../services/log_service.dart';
import '../../../services/device_registry.dart';
import '../../home/device_detail_page.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab>
    with TickerProviderStateMixin {
  final rooms = const ['Living', 'Kitchen', 'Bedroom', 'Office'];
  String selected = 'Living';

  double temp = 0;
  StreamSubscription<double>? _tempSub;

  late final AnimationController spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..repeat();

  late Map<String, List<Device>> catalog;

  @override
  void initState() {
    super.initState();
    catalog = {
      'Living': [
        Device(
            id: 'bulb1',
            room: 'Living',
            name: 'Smart Bulb',
            type: DeviceType.bulb,
            image: 'assets/images/bulb.png',
            icon: Icons.lightbulb_outline,
            level: 45,
            power: true,
            bleId: 'BLE_LAMP_1'),
        Device(
            id: 'fan1',
            room: 'Living',
            name: 'Ceiling Fan',
            type: DeviceType.fan,
            image: 'assets/images/fan.png',
            icon: Icons.toys_outlined,
            level: 35,
            power: true,
            bleId: 'BLE_FAN_1'),
        Device(
            id: 'tv1',
            room: 'Living',
            name: 'Smart TV',
            type: DeviceType.tv,
            image: 'assets/images/tv.png',
            icon: Icons.tv_outlined,
            power: false),
        Device(
            id: 'lock1',
            room: 'Living',
            name: 'Door Lock',
            type: DeviceType.lock,
            image: 'assets/images/lock.png',
            icon: Icons.lock_outline),
      ],
      'Kitchen': [
        Device(
            id: 'bulb2',
            room: 'Kitchen',
            name: 'Ceiling Lights',
            type: DeviceType.bulb,
            image: 'assets/images/ceiling_bulb.png',
            icon: Icons.light_mode_outlined,
            level: 70,
            power: true,
            bleId: 'BLE_LAMP_2'),
      ],
      'Bedroom': [
        Device(
            id: 'bulb3',
            room: 'Bedroom',
            name: 'Bed Lamp',
            type: DeviceType.bulb,
            image: 'assets/images/bedlamp.png',
            icon: Icons.nightlight,
            level: 25,
            power: true,
            bleId: 'BLE_LAMP_3'),
        Device(
            id: 'fan3',
            room: 'Bedroom',
            name: 'Bed Fan',
            type: DeviceType.fan,
            image: 'assets/images/fan.png',
            icon: Icons.toys_outlined,
            level: 20,
            power: false,
            bleId: 'BLE_FAN_3'),
      ],
      'Office': [
        Device(
            id: 'fan4',
            room: 'Office',
            name: 'Desk Fan',
            type: DeviceType.fan,
            image: 'assets/images/fan.png',
            icon: Icons.toys_outlined,
            level: 50,
            power: true,
            bleId: 'BLE_FAN_4'),
        Device(
            id: 'bulb4',
            room: 'Office',
            name: 'Desk Lamp',
            type: DeviceType.bulb,
            image: 'assets/images/bulb.png',
            icon: Icons.lightbulb_outline,
            level: 60,
            power: true,
            bleId: 'BLE_LAMP_4'),
      ],
    };

    _tempSub =
        BLEService().tempStream.stream.listen((t) => setState(() => temp = t));
  }

  @override
  void dispose() {
    _tempSub?.cancel();
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 8),
        _topStrip(context),
        const SizedBox(height: 12),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _gridForRoom(selected, key: ValueKey(selected), cs: cs),
          ),
        ),
      ],
    );
  }

  Widget _topStrip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.thermostat, color: cs.primary),
                const SizedBox(width: 6),
                Text('${temp.toStringAsFixed(1)}°C',
                    style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 40,
            child: ListView.separated(
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              itemCount: rooms.length,
              itemBuilder: (_, i) {
                final r = rooms[i];
                final selected = r == this.selected;
                return ChoiceChip(
                  label: Text(r),
                  selected: selected,
                  onSelected: (_) => setState(() => this.selected = r),
                  backgroundColor: cs.surface,
                  selectedColor: cs.primary.withOpacity(.12),
                  labelStyle:
                      TextStyle(color: selected ? cs.primary : cs.onSurface),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridForRoom(String room, {Key? key, required ColorScheme cs}) {
    final items = catalog[room] ?? [];
    return GridView.builder(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: .98),
      itemBuilder: (_, i) => _tile(items[i], cs),
    );
  }

  Widget _tile(Device d, ColorScheme cs) {
    final Animation<double> rotation =
        Tween<double>(begin: 0, end: 2 * math.pi).animate(spin);
    final isFan = d.type == DeviceType.fan;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        if (d.bleId != null) {
          final r = await showModalBottomSheet<String>(
            context: context,
            builder: (_) => _RoomPicker(current: d.room),
          );
          if (r != null) {
            await DeviceRegistry.bind(bleId: d.bleId!, room: r, label: d.name);
            setState(() {
              d.room = r; // ✅ mutable update
            });
            await LogService.addRoom(r, '${d.name} reassigned to $r');
          }
        }

        await Navigator.of(context).push(PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, a, __) => FadeTransition(
            opacity: a,
            child: ScaleTransition(
                scale: Tween<double>(begin: .98, end: 1).animate(
                    CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                child: DeviceDetailPage(device: d)),
          ),
        ));
        setState(() {});
      },
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
                color: cs.shadow.withOpacity(0.08),
                blurRadius: 18,
                offset: const Offset(0, 10))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Hero(
                      tag: 'device-img-${d.id}',
                      child: _deviceVisual(d, rotation)),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: d.power
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16)),
                    child: Text(d.power ? 'On' : 'Off',
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(d.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.tune, size: 18),
                  const SizedBox(width: 6),
                  Text(
                      isFan
                          ? 'Speed ${d.level}%'
                          : (d.type == DeviceType.bulb
                              ? 'Intensity ${d.level}%'
                              : 'Ready'),
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceVisual(Device d, Animation<double> rotation,
      {double size = 40}) {
    final isFan = d.type == DeviceType.fan;
    final img = Image.asset(d.image,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(d.icon, size: size));
    Widget base = AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: d.power ? 1 : 0.85,
        child: img);
    base = AnimatedScale(
        duration: const Duration(milliseconds: 200),
        scale: d.power ? 1.05 : 1.0,
        child: base);

    if (d.type == DeviceType.bulb) {
      final overlay = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color:
                  Colors.amber.withOpacity((d.level.clamp(0, 100)) / 140.0)));
      return Stack(alignment: Alignment.center, children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: base),
        overlay
      ]);
    }

    if (isFan) {
      return AnimatedBuilder(
        animation: rotation,
        builder: (_, child) {
          final factor = d.power ? (0.2 + (d.level / 100) * 1.4) : 0.15;
          return Transform.rotate(angle: rotation.value * factor, child: child);
        },
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: base),
      );
    }

    return ClipRRect(borderRadius: BorderRadius.circular(12), child: base);
  }
}

/// Simple modal to pick a room
class _RoomPicker extends StatelessWidget {
  final String current;
  const _RoomPicker({required this.current});

  @override
  Widget build(BuildContext context) {
    const rooms = ['Living', 'Kitchen', 'Bedroom', 'Office'];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in rooms)
            ListTile(
              title: Text(r),
              trailing: r == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(r),
            ),
        ],
      ),
    );
  }
}
