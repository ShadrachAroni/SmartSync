import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import '../models/device.dart';
import '../providers/device_provider.dart';
import '../widgets/bottom_nav.dart';

class DeviceDetailScreen extends ConsumerWidget {
  final String deviceId;
  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(devicesProvider).firstWhere(
          (d) => d.id == deviceId,
          orElse: () => Device(
            id: 'unknown',
            name: 'Unknown Device',
            roomId: '',
            type: DeviceType.bulb,
            isOn: false,
            value: 0.0,
          ),
        );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true, // default back button
        title: Text(device.name),
        centerTitle: true,
        elevation: 2,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: device.type == DeviceType.fan
                ? Image.asset(
                    'assets/icons/fan.png',
                    width: 24,
                    height: 24,
                    color: device.isOn ? null : Colors.grey.shade400,
                    colorBlendMode: device.isOn ? null : BlendMode.modulate,
                  )
                : const Icon(Icons.lightbulb, size: 24),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNav(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _DeviceSummaryCard(device: device, ref: ref),
            const SizedBox(height: 24),
            _DeviceSliderCard(device: device, ref: ref),
            const SizedBox(height: 24),
            _DeviceActionButton(device: device, ref: ref),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _DeviceSummaryCard extends StatelessWidget {
  final Device device;
  final WidgetRef ref;
  const _DeviceSummaryCard({required this.device, required this.ref});

  @override
  Widget build(BuildContext context) {
    final deviceLabel = device.type == DeviceType.fan ? 'Fan' : 'Light';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: Center(
                child: device.type == DeviceType.fan
                    ? AnimatedFanWidget(
                        isOn: device.isOn,
                        speed: device.value.clamp(0.0, 1.0),
                        size: 96,
                      )
                    : Icon(
                        Icons.lightbulb,
                        size: 96,
                        color: device.isOn
                            ? Colors.amber.withOpacity(
                                device.value.clamp(0.2, 1.0),
                              )
                            : Colors.grey.shade400,
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(deviceLabel,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Status: ${device.isOn ? 'On' : 'Off'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: device.isOn ? Colors.green : Colors.redAccent,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: device.isOn,
                        onChanged: (_) => ref
                            .read(devicesProvider.notifier)
                            .toggle(device.id),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceSliderCard extends StatelessWidget {
  final Device device;
  final WidgetRef ref;
  const _DeviceSliderCard({required this.device, required this.ref});

  @override
  Widget build(BuildContext context) {
    final label =
        device.type == DeviceType.fan ? 'Fan Speed' : 'Light Intensity';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: device.value.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                    label: '${(device.value * 100).round()}%',
                    onChanged: device.isOn
                        ? (v) => ref
                            .read(devicesProvider.notifier)
                            .setValue(device.id, v)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${(device.value * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              device.isOn
                  ? 'Slide to adjust. Changes apply immediately.'
                  : 'Turn device on to enable adjustments.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceActionButton extends StatelessWidget {
  final Device device;
  final WidgetRef ref;
  const _DeviceActionButton({required this.device, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () =>
                ref.read(devicesProvider.notifier).toggle(device.id),
            icon: Icon(device.isOn ? Icons.power_off : Icons.power),
            label: Text(device.isOn ? 'Turn Off' : 'Turn On'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// Smooth fan animation using Ticker
class AnimatedFanWidget extends StatefulWidget {
  final bool isOn;
  final double speed;
  final double size;
  const AnimatedFanWidget({
    super.key,
    required this.isOn,
    required this.speed,
    this.size = 120,
  });

  @override
  State<AnimatedFanWidget> createState() => _AnimatedFanWidgetState();
}

class _AnimatedFanWidgetState extends State<AnimatedFanWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastTick;
  double _angle = 0.0;
  static const double _maxAngularVel = 2 * pi * 3.5;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == null) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick!).inMicroseconds / 1e6;
    _lastTick = elapsed;

    final angularVel =
        (widget.isOn ? widget.speed.clamp(0.0, 1.0) : 0.0) * _maxAngularVel;
    if (angularVel > 0.0) {
      _angle = (_angle + angularVel * dt) % (2 * pi);
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedFanWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ticker.muted = !widget.isOn && !oldWidget.isOn;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fanImage = Image.asset(
      'assets/icons/fan.png',
      width: widget.size * 0.7,
      height: widget.size * 0.7,
      color: widget.isOn ? null : Colors.grey.shade400,
      colorBlendMode: widget.isOn ? null : BlendMode.modulate,
    );

    return Transform.rotate(
      angle: _angle,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(child: fanImage),
      ),
    );
  }
}
