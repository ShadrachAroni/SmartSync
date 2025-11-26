import 'error_diagnostics.dart';
import '../../services/bluetooth_data_analyzer.dart' as analyzer;

/// Command-line diagnostic tool for debugging
class DiagnosticCommand {
  /// Print comprehensive diagnostic report
  static void printFullReport() {
    print('\n═══════════════════════════════════════════════════════════');
    print('🔍 COMPREHENSIVE DIAGNOSTIC REPORT');
    print('═══════════════════════════════════════════════════════════\n');
    
    // Error diagnostics summary
    final errorSummary = ErrorDiagnostics.getSummary();
    print('📊 ERROR SUMMARY');
    print('───────────────────────────────────────────────────────────');
    print('Total Errors: ${errorSummary.totalErrors}');
    print('  🔴 Critical: ${errorSummary.critical}');
    print('  🟠 High: ${errorSummary.high}');
    print('  🟡 Medium: ${errorSummary.medium}');
    print('  ⚪ Low: ${errorSummary.low}');
    print('');
    
    if (errorSummary.byCategory.isNotEmpty) {
      print('Errors by Category:');
      errorSummary.byCategory.forEach((category, count) {
        print('  $category: $count');
      });
      print('');
    }
    
    // Recent critical errors
    final criticalErrors = errorSummary.recentErrors
        .where((e) => e.severity == ErrorSeverity.critical)
        .take(5)
        .toList();
    
    if (criticalErrors.isNotEmpty) {
      print('🔴 RECENT CRITICAL ERRORS');
      print('───────────────────────────────────────────────────────────');
      for (var error in criticalErrors) {
        print('${error.timestamp}: [${error.category}] ${error.message}');
        if (error.context.isNotEmpty) {
          error.context.forEach((key, value) {
            print('  $key: $value');
          });
        }
      }
      print('');
    }
    
    // Bluetooth data analysis
    final bluetoothSummary = analyzer.BluetoothDataAnalyzer.getSummary();
    print('📡 BLUETOOTH DATA ANALYSIS');
    print('───────────────────────────────────────────────────────────');
    print('Total Packets: ${bluetoothSummary.totalPackets}');
    print('  ✅ Successfully Parsed: ${bluetoothSummary.successes}');
    print('  ❌ Decode Failures: ${bluetoothSummary.decodeFailures}');
    print('  ⚠️ Parse Failures: ${bluetoothSummary.parseFailures}');
    print('  📈 Success Rate: ${bluetoothSummary.successRate.toStringAsFixed(1)}%');
    print('');
    
    if (bluetoothSummary.decodeFailures > 0 || bluetoothSummary.parseFailures > 0) {
      print('⚠️ DATA PARSING ISSUES DETECTED');
      print('───────────────────────────────────────────────────────────');
      
      if (bluetoothSummary.decodeFailures > 0) {
        print('UTF-8 Decode Failures: ${bluetoothSummary.decodeFailures}');
        print('  → Check if data is being received in correct format');
        print('  → Verify device is sending UTF-8 encoded JSON');
      }
      
      if (bluetoothSummary.parseFailures > 0) {
        print('JSON Parse Failures: ${bluetoothSummary.parseFailures}');
        print('  → Check if JSON messages are complete');
        print('  → Verify message format matches expected structure');
      }
      print('');
    }
    
    // Recommendations
    print('💡 RECOMMENDATIONS');
    print('───────────────────────────────────────────────────────────');
    
    if (errorSummary.critical > 0) {
      print('🔴 CRITICAL: Layout errors detected!');
      print('  → Check widget tree structure in device registration dialog');
      print('  → Verify all widgets have proper width constraints');
      print('  → Review recent critical errors above for details');
    }
    
    if (bluetoothSummary.successRate < 50) {
      print('🔴 CRITICAL: Bluetooth data parsing failing!');
      print('  → Check device communication protocol');
      print('  → Verify data format matches expected JSON structure');
      print('  → Check buffer timeout and size settings');
    } else if (bluetoothSummary.successRate < 80) {
      print('⚠️ WARNING: Bluetooth data parsing has issues');
      print('  → Review decode/parse failures above');
      print('  → Consider adjusting buffer settings');
    }
    
    if (errorSummary.critical == 0 && bluetoothSummary.successRate >= 80) {
      print('✅ System appears to be functioning normally');
    }
    
    print('═══════════════════════════════════════════════════════════\n');
  }
  
  /// Print quick status
  static void printQuickStatus() {
    final errorSummary = ErrorDiagnostics.getSummary();
    final bluetoothSummary = analyzer.BluetoothDataAnalyzer.getSummary();
    
    print('📊 Quick Status:');
    print('  Errors: ${errorSummary.totalErrors} (${errorSummary.critical} critical)');
    print('  Bluetooth: ${bluetoothSummary.successRate.toStringAsFixed(1)}% success rate');
    
    if (errorSummary.critical > 0) {
      print('  🔴 CRITICAL ISSUES DETECTED - Run full diagnostic!');
    } else if (bluetoothSummary.successRate < 50) {
      print('  🔴 BLUETOOTH PARSING FAILING - Run full diagnostic!');
    } else {
      print('  ✅ System OK');
    }
  }
}

