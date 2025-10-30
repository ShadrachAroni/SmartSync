class RoomModel {
  final String id;
  final String name;
  final String icon;
  final List<String> deviceIds;
  final String? imageUrl;

  RoomModel({
    required this.id,
    required this.name,
    required this.icon,
    this.deviceIds = const [],
    this.imageUrl,
  });

  factory RoomModel.fromMap(String id, Map<String, dynamic> data) {
    return RoomModel(
      id: id,
      name: data['name'] ?? '',
      icon: data['icon'] ?? 'home',
      deviceIds: List<String>.from(data['deviceIds'] ?? []),
      imageUrl: data['imageUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'icon': icon,
      'deviceIds': deviceIds,
      'imageUrl': imageUrl,
    };
  }
}
