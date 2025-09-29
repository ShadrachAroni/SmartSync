enum DeviceType { bulb, fan, tv, sensor }

class Device {
  final String id;
  final String name;
  final DeviceType type;
  final String roomId;
  bool isOn;
  double value; // 0.0 - 1.0 for brightness or speed

  Device({
    required this.id,
    required this.name,
    required this.type,
    required this.roomId,
    this.isOn = false,
    this.value = 0.0,
  });

  Device copyWith({
    String? id,
    String? name,
    DeviceType? type,
    String? roomId,
    bool? isOn,
    double? value,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      roomId: roomId ?? this.roomId,
      isOn: isOn ?? this.isOn,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'room_id': roomId,
      'is_on': isOn,
      'value': value,
    };
  }

  factory Device.fromMap(Map<String, dynamic> m) {
    return Device(
      id: m['id'].toString(),
      name: m['name'].toString(),
      type: DeviceType.values.firstWhere(
          (e) => e.name == (m['type']?.toString() ?? 'bulb'),
          orElse: () => DeviceType.bulb),
      roomId: m['room_id'].toString(),
      isOn: m['is_on'] == true,
      value: (m['value'] is num) ? (m['value'] as num).toDouble() : 0.0,
    );
  }
}
