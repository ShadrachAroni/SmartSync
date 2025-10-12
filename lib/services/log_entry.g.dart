// GENERATED-LITE: manual adapter to avoid build_runner
part of 'log_service.dart';

class LogEntryAdapter extends TypeAdapter<LogEntry> {
  @override
  final int typeId = 1;

  @override
  LogEntry read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < n; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return LogEntry(fields[0] as DateTime, fields[1] as String);
  }

  @override
  void write(BinaryWriter writer, LogEntry obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.at)
      ..writeByte(1)
      ..write(obj.message);
  }
}
