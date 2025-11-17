import '../services/bluetooth_service.dart';
import '../core/utils/logger.dart';

class VoiceService {
  VoiceService._internal();
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;

  final BluetoothService _bluetoothService = BluetoothService();

  Future<String> handleCommand(String utterance) async {
    final text = utterance.toLowerCase();
    try {
      if (text.contains('fan')) {
        final value = _extractPercentage(text);
        await _bluetoothService.setFanSpeed(value);
        return 'Fan speed set to $value%';
      }
      if (text.contains('light') || text.contains('lamp')) {
        final value = _extractPercentage(text);
        await _bluetoothService.setLEDBrightness(value);
        return 'Light brightness set to $value%';
      }
      if (text.contains('auto')) {
        final enable = text.contains('on') || text.contains('enable');
        await _bluetoothService.setAutoMode(enable);
        return 'Auto mode ${enable ? 'enabled' : 'disabled'}';
      }
    } catch (e) {
      Logger.error('Voice command failed: $e');
      return 'Sorry, something went wrong.';
    }
    return "I didn't understand that command.";
  }

  int _extractPercentage(String text) {
    final match = RegExp(r'(\d{1,3})').firstMatch(text);
    if (match != null) {
      final value = int.parse(match.group(1)!);
      return value.clamp(0, 100);
    }
    if (text.contains('max') || text.contains('full')) return 100;
    if (text.contains('half')) return 50;
    if (text.contains('low')) return 25;
    return 70;
  }
}
