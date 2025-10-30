import 'package:flutter/material.dart';
import '../../models/device_model.dart';

class DeviceCard extends StatefulWidget {
  final DeviceModel device;

  const DeviceCard({super.key, required this.device});

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  late bool _isOn;

  @override
  void initState() {
    super.initState();
    _isOn = widget.device.isOn;
  }

  void _toggleDevice() {
    setState(() {
      _isOn = !_isOn;
    });
    // TODO: Update Firebase
  }

  Color _getDeviceColor() {
    if (!_isOn) return Colors.grey.shade100;

    switch (widget.device.type) {
      case DeviceType.light:
        return const Color(0xFFFFF9C4);
      case DeviceType.fan:
        return const Color(0xFFB3E5FC);
      case DeviceType.airConditioner:
        return const Color(0xFFB2DFDB);
      case DeviceType.tv:
        return const Color(0xFFE1BEE7);
      default:
        return Colors.grey.shade100;
    }
  }

  IconData _getDeviceIcon() {
    return widget.device.icon;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleDevice,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _getDeviceColor(),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isOn ? Colors.transparent : Colors.grey.shade200,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isOn ? Colors.white : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getDeviceIcon(),
                    color:
                        _isOn ? const Color(0xFF00BFA5) : Colors.grey.shade600,
                    size: 24,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        _isOn ? const Color(0xFF00BFA5) : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isOn ? 'On' : 'Off',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _isOn ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.device.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isOn ? Colors.black87 : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.device.roomId.replaceAll('-', ' ').toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    color: _isOn ? Colors.grey.shade700 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
