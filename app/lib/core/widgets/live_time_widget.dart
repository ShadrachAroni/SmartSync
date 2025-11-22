import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:intl/intl.dart';
import '../utils/time_utils.dart';
import '../utils/logger.dart';

/// Widget that displays live time and day/night indicator
class LiveTimeWidget extends StatefulWidget {
  final bool showSeconds;
  final TextStyle? textStyle;
  final bool showDayNight;

  const LiveTimeWidget({
    super.key,
    this.showSeconds = false,
    this.textStyle,
    this.showDayNight = true,
  });

  @override
  State<LiveTimeWidget> createState() => _LiveTimeWidgetState();
}

class _LiveTimeWidgetState extends State<LiveTimeWidget> {
  Timer? _timer;
  DateTime _currentTime = DateTime.now();
  bool _isNight = TimeUtils.isNight();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _updateTime();
    // Update every second if showing seconds, otherwise every minute
    _timer = Timer.periodic(
      widget.showSeconds ? const Duration(seconds: 1) : const Duration(seconds: 60),
      (_) => _updateTime(),
    );
  }

  void _updateTime() {
    if (!mounted) return;
    setState(() {
      _currentTime = DateTime.now();
      _isNight = TimeUtils.isNight();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = widget.showSeconds
        ? TimeUtils.formatTime24Hour(_currentTime)
        : TimeUtils.formatTime24Hour(_currentTime).substring(0, 5);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date display
        Text(
          DateFormat('EEEE, MMMM d, yyyy').format(_currentTime),
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showDayNight) ...[
              Icon(
                _isNight ? Icons.nightlight_round : Icons.wb_sunny,
                color: _isNight ? Colors.blue.shade300 : Colors.amber.shade300,
                size: 24,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              timeFormat,
              style: widget.textStyle ??
                  const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
            ),
            if (widget.showDayNight) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isNight
                      ? Colors.blue.withOpacity(0.2)
                      : Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isNight ? Colors.blue : Colors.amber,
                    width: 1,
                  ),
                ),
                child: Text(
                  _isNight ? 'Night' : 'Day',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _isNight ? Colors.blue.shade300 : Colors.amber.shade300,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

