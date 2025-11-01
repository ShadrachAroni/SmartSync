import 'package:flutter/material.dart';
import '../../models/room_model.dart';

class RoomCard extends StatelessWidget {
  final RoomModel room;

  const RoomCard({super.key, required this.room});

  IconData _getRoomIcon() {
    switch (room.icon) {
      case 'living_room':
        return Icons.weekend_rounded;
      case 'kitchen':
        return Icons.kitchen_rounded;
      case 'bedroom':
        return Icons.bed_rounded;
      case 'bathroom':
        return Icons.bathtub_rounded;
      case 'office':
        return Icons.desk_rounded;
      default:
        return Icons.meeting_room_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // FIX: Prevent overflow
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00BFA5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getRoomIcon(),
              color: const Color(0xFF00BFA5),
              size: 24,
            ),
          ),
          const SizedBox(height: 12), // FIX: Reduced spacing
          Text(
            room.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${room.deviceIds.length} devices',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
