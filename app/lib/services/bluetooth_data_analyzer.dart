import 'dart:typed_data';
import '../core/utils/logger.dart';
import '../core/utils/error_diagnostics.dart';
import 'package:flutter/foundation.dart';

/// Advanced Bluetooth data analyzer to diagnose parsing issues
class BluetoothDataAnalyzer {
  static final List<DataPacket> _packetHistory = [];
  static const int _maxHistory = 100;
  static int _decodeErrorCount = 0;
  static DateTime? _lastDecodeErrorTime;
  
  /// Analyze incoming data packet
  /// CRITICAL: Must check for binary data FIRST to prevent UI blocking
  static void analyzePacket({
    required List<int> rawData,
    required int bufferSize,
    String? decodedString,
    bool? decodeSuccess,
    bool? parseSuccess,
    Object? decodeError,
    Object? parseError,
  }) {
    // CRITICAL: Check for binary data BEFORE creating packet or doing ANY work
    // This prevents all processing for binary data
    if (_isBinaryPattern(Uint8List.fromList(rawData))) {
      // Binary data detected - skip ALL processing to prevent UI blocking
      return;
    }
    
    // Additional fast check: known binary patterns
    if (rawData.length >= 4) {
      final b0 = rawData[0];
      final b1 = rawData[1];
      final b2 = rawData[2];
      final b3 = rawData[3];
      
      // Known binary patterns from logs
      if (b2 == 0xfc && b3 == 0x3f) {
        if ((b0 == 0xc0 && b1 == 0xd9) ||
            (b0 == 0xe8 && b1 == 0xdb) ||
            (b0 == 0x28 && b1 == 0xdc)) {
          return; // Skip analysis for known binary patterns
        }
      }
    }
    
    final packet = DataPacket(
      timestamp: DateTime.now(),
      rawData: Uint8List.fromList(rawData),
      bufferSize: bufferSize,
      decodedString: decodedString,
      decodeSuccess: decodeSuccess ?? false,
      parseSuccess: parseSuccess ?? false,
      decodeError: decodeError?.toString(),
      parseError: parseError?.toString(),
    );
    
    _packetHistory.add(packet);
    if (_packetHistory.length > _maxHistory) {
      _packetHistory.removeAt(0);
    }
    
    // Analyze for issues (only non-binary data reaches here)
    _analyzePacket(packet);
  }
  
  /// Analyze packet for common issues
  static void _analyzePacket(DataPacket packet) {
    // CRITICAL: Check for binary data FIRST - skip all analysis if binary
    // This check must be fast and happen before ANY logging
    bool isBinary = _isBinaryPattern(packet.rawData);
    if (isBinary) {
      // Binary data detected - skip ALL analysis and logging to prevent UI blocking
      // ABSOLUTELY NO LOGGING - silently return
      return;
    }
    
    // Additional check: if decode already failed and we have the known binary pattern bytes
    if (!packet.decodeSuccess && packet.rawData.length >= 4) {
      final b0 = packet.rawData[0];
      final b1 = packet.rawData[1];
      final b2 = packet.rawData[2];
      final b3 = packet.rawData[3];
      
      // Known binary patterns - skip analysis
      if ((b0 == 0xc0 && b1 == 0xd9 && b2 == 0xfc && b3 == 0x3f) ||
          (b0 == 0xe8 && b1 == 0xdb && b2 == 0xfc && b3 == 0x3f) ||
          (b0 == 0x28 && b1 == 0xdc && b2 == 0xfc && b3 == 0x3f)) {
        return; // Skip analysis for known binary patterns
      }
    }
    
    // Check for UTF-8 decode failures
    if (!packet.decodeSuccess && packet.decodeError != null) {
      // Rate limit error diagnostics to prevent spam
      final now = DateTime.now();
      
      if (_lastDecodeErrorTime == null || 
          now.difference(_lastDecodeErrorTime!) > const Duration(seconds: 5)) {
        _decodeErrorCount = 0;
        _lastDecodeErrorTime = now;
      }
      
      _decodeErrorCount++;
      if (_decodeErrorCount > 10) {
        // Too many errors - skip logging to prevent UI blocking
        return;
      }
      
      ErrorDiagnostics.captureError(
        category: 'bluetooth_decode',
        message: 'UTF-8 decode failed',
        error: packet.decodeError,
        context: {
          'bufferSize': packet.bufferSize,
          'rawDataLength': packet.rawData.length,
          'rawDataHex': _bytesToHex(packet.rawData.take(50).toList()),
          'rawDataAscii': _bytesToAscii(packet.rawData.take(50).toList()),
        },
      );
      
      // Log detailed analysis ONLY if not binary data and within rate limit
      if (kDebugMode && _decodeErrorCount <= 3) {
        Logger.warning('🔍 Data Analysis: UTF-8 decode failed');
        Logger.debug('  Buffer size: ${packet.bufferSize} bytes');
        Logger.debug('  Raw data length: ${packet.rawData.length} bytes');
        Logger.debug('  First 50 bytes (hex): ${_bytesToHex(packet.rawData.take(50).toList())}');
        Logger.debug('  First 50 bytes (ASCII): ${_bytesToAscii(packet.rawData.take(50).toList())}');
        
        // Check if it looks like partial JSON
        if (packet.rawData.isNotEmpty) {
          final asciiAttempt = String.fromCharCodes(
            packet.rawData.where((b) => b >= 32 && b <= 126),
          );
          if (asciiAttempt.isNotEmpty) {
            Logger.debug('  ASCII attempt: ${asciiAttempt.substring(0, asciiAttempt.length > 100 ? 100 : asciiAttempt.length)}');
            if (asciiAttempt.contains('{') || asciiAttempt.contains('[')) {
              Logger.info('  ⚠️ Contains JSON-like characters - might be partial message');
            }
          }
        }
      }
    }
    
    // Check for JSON parse failures
    if (packet.decodeSuccess && !packet.parseSuccess && packet.parseError != null) {
      ErrorDiagnostics.captureError(
        category: 'bluetooth_parse',
        message: 'JSON parse failed',
        error: packet.parseError,
        context: {
          'decodedString': packet.decodedString?.substring(0, packet.decodedString!.length > 200 ? 200 : packet.decodedString!.length),
          'decodedLength': packet.decodedString?.length ?? 0,
          'bufferSize': packet.bufferSize,
        },
      );
      
      if (kDebugMode && packet.decodedString != null) {
        Logger.warning('🔍 Data Analysis: JSON parse failed');
        Logger.debug('  Decoded string length: ${packet.decodedString!.length}');
        Logger.debug('  First 200 chars: ${packet.decodedString!.substring(0, packet.decodedString!.length > 200 ? 200 : packet.decodedString!.length)}');
        
        // Check JSON structure
        final openBraces = packet.decodedString!.split('{').length - 1;
        final closeBraces = packet.decodedString!.split('}').length - 1;
        final openBrackets = packet.decodedString!.split('[').length - 1;
        final closeBrackets = packet.decodedString!.split(']').length - 1;
        
        Logger.debug('  JSON structure:');
        Logger.debug('    Open braces: $openBraces, Close braces: $closeBraces');
        Logger.debug('    Open brackets: $openBrackets, Close brackets: $closeBrackets');
        
        if (openBraces != closeBraces || openBrackets != closeBrackets) {
          Logger.warning('  ⚠️ Unbalanced JSON structure - incomplete message');
        }
      }
    }
    
    // Check for suspicious patterns
    if (packet.rawData.length > 0) {
      // Check if all bytes are the same (might indicate connection issue)
      final firstByte = packet.rawData[0];
      if (packet.rawData.every((b) => b == firstByte) && packet.rawData.length > 10) {
        Logger.warning('⚠️ Suspicious pattern: All bytes are the same (0x${firstByte.toRadixString(16)})');
        ErrorDiagnostics.captureError(
          category: 'bluetooth_pattern',
          message: 'Suspicious data pattern detected',
          context: {
            'pattern': 'all_bytes_same',
            'byteValue': firstByte,
            'length': packet.rawData.length,
          },
        );
      }
      
      // Check for null bytes (might indicate padding or corruption)
      final nullByteCount = packet.rawData.where((b) => b == 0).length;
      if (nullByteCount > packet.rawData.length * 0.5) {
        Logger.warning('⚠️ Suspicious pattern: >50% null bytes');
        ErrorDiagnostics.captureError(
          category: 'bluetooth_pattern',
          message: 'High null byte count',
          context: {
            'nullByteCount': nullByteCount,
            'totalBytes': packet.rawData.length,
            'percentage': (nullByteCount / packet.rawData.length * 100).toStringAsFixed(1),
          },
        );
      }
    }
  }
  
  /// Convert bytes to hex string
  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }
  
  /// Convert bytes to ASCII (with non-printable as dots)
  static String _bytesToAscii(List<int> bytes) {
    return bytes.map((b) => b >= 32 && b <= 126 ? String.fromCharCode(b) : '.').join('');
  }
  
  /// Check if data has binary repeating pattern (like c0 d9 fc 3f)
  /// CRITICAL: Must be fast and accurate
  static bool _isBinaryPattern(Uint8List data) {
    if (data.length < 4) return false;
    
    final b0 = data[0];
    final b1 = data[1];
    final b2 = data[2];
    final b3 = data[3];
    
    // Fast check: Known binary patterns (most common)
    if ((b0 == 0xc0 && b1 == 0xd9 && b2 == 0xfc && b3 == 0x3f) ||
        (b0 == 0xe8 && b1 == 0xdb && b2 == 0xfc && b3 == 0x3f) ||
        (b0 == 0x28 && b1 == 0xdc && b2 == 0xfc && b3 == 0x3f)) {
      return true;
    }
    
    // Check for repeating 4-byte pattern
    if (data.length >= 8) {
      if (data[4] == b0 && data[5] == b1 && data[6] == b2 && data[7] == b3) {
        return true; // Repeating pattern detected
      }
    }
    
    return false;
  }
  
  /// Get analysis summary
  static AnalysisSummary getSummary() {
    final total = _packetHistory.length;
    final decodeFailures = _packetHistory.where((p) => !p.decodeSuccess).length;
    final parseFailures = _packetHistory.where((p) => p.decodeSuccess && !p.parseSuccess).length;
    final successes = _packetHistory.where((p) => p.parseSuccess).length;
    
    return AnalysisSummary(
      totalPackets: total,
      decodeFailures: decodeFailures,
      parseFailures: parseFailures,
      successes: successes,
      successRate: total > 0 ? (successes / total * 100) : 0.0,
      recentPackets: _packetHistory.take(20).toList(),
    );
  }
  
  /// Clear history
  static void clear() {
    _packetHistory.clear();
  }
}

class DataPacket {
  final DateTime timestamp;
  final Uint8List rawData;
  final int bufferSize;
  final String? decodedString;
  final bool decodeSuccess;
  final bool parseSuccess;
  final String? decodeError;
  final String? parseError;
  
  DataPacket({
    required this.timestamp,
    required this.rawData,
    required this.bufferSize,
    this.decodedString,
    required this.decodeSuccess,
    required this.parseSuccess,
    this.decodeError,
    this.parseError,
  });
}

class AnalysisSummary {
  final int totalPackets;
  final int decodeFailures;
  final int parseFailures;
  final int successes;
  final double successRate;
  final List<DataPacket> recentPackets;
  
  AnalysisSummary({
    required this.totalPackets,
    required this.decodeFailures,
    required this.parseFailures,
    required this.successes,
    required this.successRate,
    required this.recentPackets,
  });
}

