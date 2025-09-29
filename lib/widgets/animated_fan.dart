import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AnimatedFan extends StatefulWidget {
  /// speed in range 0.0 - 1.0
  final double speed;
  final double size;
  const AnimatedFan({super.key, required this.speed, this.size = 140});

  @override
  State<AnimatedFan> createState() => _AnimatedFanState();
}

class _AnimatedFanState extends State<AnimatedFan>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastTick;
  double _angle = 0.0; // radians

  // Tunable: maximum angular velocity (radians per second).
  // e.g. 2 * pi * 4 => 4 rotations per second at speed == 1.0
  static const double _maxAngularVel = 2 * pi * 4;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    // first tick: initialize _lastTick
    if (_lastTick == null) {
      _lastTick = elapsed;
      return;
    }

    final dt = (elapsed - _lastTick!).inMicroseconds / 1e6; // seconds
    _lastTick = elapsed;

    // Compute instantaneous angular velocity from current widget.speed
    final speedValue = widget.speed.clamp(0.0, 1.0);
    final angularVel = speedValue * _maxAngularVel;

    if (angularVel > 0.0) {
      _angle += angularVel * dt;
      // keep angle bounded to avoid numeric drift
      _angle %= (2 * pi);
      // repaint:
      setState(() {});
    } else {
      // speed is zero -> no rotation. Still keep ticker running so changes take effect immediately.
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedFan oldWidget) {
    super.didUpdateWidget(oldWidget);
    // nothing special required here because _onTick reads widget.speed each frame.
    // If you want to pause the ticker entirely at speed == 0 for battery saving, you can:
    // if (widget.speed <= 0.0) _ticker.muted = true; else _ticker.muted = false;
    // (muted prevents ticks from firing but keeps the ticker alive)
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blade = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: Image.asset(
          'assets/icons/fan.png',
          width: widget.size * 0.8,
          height: widget.size * 0.8,
          fit: BoxFit.contain,
        ),
      ),
    );

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Transform.rotate(
        angle: _angle,
        child: blade,
      ),
    );
  }
}
