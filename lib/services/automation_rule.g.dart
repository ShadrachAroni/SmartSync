// GENERATED-LITE: manual adapter to avoid build_runner
part of 'automation_service.dart';

class AutomationRuleAdapter extends TypeAdapter<AutomationRule> {
  @override
  final int typeId = 2;

  @override
  AutomationRule read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < n; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return AutomationRule(
      id: fields[0] as String,
      name: fields[1] as String,
      at: fields[2] as DateTime?,
      daily: fields[3] as bool,
      action: (fields[4] as Map).cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, AutomationRule obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.at)
      ..writeByte(3)
      ..write(obj.daily)
      ..writeByte(4)
      ..write(obj.action);
  }
}
