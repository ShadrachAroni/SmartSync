class RoomModel {
  final String id;
  final String name;
  final String icon;
  final List<String> deviceIds;
  final String? imageUrl;
  final String? hubId; // The ESP32 hub ID that controls this room
  final bool isPrimaryHub; // True if this is the main/primary hub

  RoomModel({
    required this.id,
    required this.name,
    required this.icon,
    this.deviceIds = const [],
    this.imageUrl,
    this.hubId,
    this.isPrimaryHub = false,
  });

  factory RoomModel.fromMap(String id, Map<String, dynamic> data) {
    return RoomModel(
      id: id,
      name: data['name'] ?? '',
      icon: data['icon'] ?? 'home',
      deviceIds: List<String>.from(data['deviceIds'] ?? []),
      imageUrl: data['imageUrl'],
      hubId: data['hubId'],
      isPrimaryHub: data['isPrimaryHub'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'icon': icon,
      'deviceIds': deviceIds,
      'imageUrl': imageUrl,
      if (hubId != null) 'hubId': hubId,
      'isPrimaryHub': isPrimaryHub,
    };
  }
}
