import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/logger.dart';
import '../models/sensor_data.dart';
import 'firebase_service.dart';

/// Service to debug and diagnose issues with sensor data queries
class DebugService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseService _firebaseService = FirebaseService();

  /// Comprehensive debug function to check why sensor data might not be appearing
  Future<Map<String, dynamic>> debugSensorData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'error': 'No user logged in',
        'success': false,
      };
    }

    final results = <String, dynamic>{
      'userId': user.uid,
      'timestamp': DateTime.now().toIso8601String(),
      'checks': <String, dynamic>{},
    };

    try {
      // Check 1: Total sensor logs for this user (no filters)
      Logger.info('🔍 Debug: Checking total sensor logs for user...');
      final allLogsSnapshot = await _firestore
          .collection('sensor_logs')
          .where('userId', isEqualTo: user.uid)
          .limit(100)
          .get();

      results['checks']['totalLogsForUser'] = {
        'count': allLogsSnapshot.docs.length,
        'sampleIds': allLogsSnapshot.docs.take(5).map((d) => d.id).toList(),
      };

      Logger.info('   Found ${allLogsSnapshot.docs.length} total logs for user');

      // Check 2: Check data structure of first few documents
      if (allLogsSnapshot.docs.isNotEmpty) {
        final sampleDoc = allLogsSnapshot.docs.first;
        final sampleData = sampleDoc.data();
        
        results['checks']['sampleDocument'] = {
          'id': sampleDoc.id,
          'fields': sampleData.keys.toList(),
          'userId': sampleData['userId'],
          'deviceId': sampleData['deviceId'],
          'timestamp': sampleData['timestamp']?.toString(),
          'timestampType': sampleData['timestamp']?.runtimeType.toString(),
          'hasTimestamp': sampleData.containsKey('timestamp'),
        };

        // Check if timestamp is a Firestore Timestamp
        final timestamp = sampleData['timestamp'];
        if (timestamp is Timestamp) {
          results['checks']['sampleDocument']['timestampDate'] = timestamp.toDate().toIso8601String();
          results['checks']['sampleDocument']['isValidTimestamp'] = true;
        } else {
          results['checks']['sampleDocument']['isValidTimestamp'] = false;
          results['checks']['sampleDocument']['timestampValue'] = timestamp?.toString();
        }

        Logger.info('   Sample document structure: ${sampleData.keys.join(", ")}');
      }

      // Check 3: Check user's devices
      Logger.info('🔍 Debug: Checking user devices...');
      final devices = await _firebaseService.fetchUserDevices(user.uid);
      results['checks']['userDevices'] = {
        'count': devices.length,
        'deviceIds': devices.map((d) => d.id).toList(),
        'deviceNames': devices.map((d) => d.name).toList(),
      };
      Logger.info('   Found ${devices.length} devices');

      // Check 4: Check logs by deviceId
      if (devices.isNotEmpty) {
        final deviceId = devices.first.id;
        Logger.info('🔍 Debug: Checking logs for device: $deviceId');
        final deviceLogsSnapshot = await _firestore
            .collection('sensor_logs')
            .where('deviceId', isEqualTo: deviceId)
            .limit(10)
            .get();

        results['checks']['logsByDeviceId'] = {
          'deviceId': deviceId,
          'count': deviceLogsSnapshot.docs.length,
        };
        Logger.info('   Found ${deviceLogsSnapshot.docs.length} logs for device $deviceId');
      }

      // Check 5: Check logs with timestamp filter (last 7 days)
      Logger.info('🔍 Debug: Checking logs with timestamp filter (last 7 days)...');
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final timestampFilterSnapshot = await _firestore
          .collection('sensor_logs')
          .where('userId', isEqualTo: user.uid)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
          .limit(10)
          .get();

      results['checks']['logsWithTimestampFilter'] = {
        'cutoffDate': cutoff.toIso8601String(),
        'count': timestampFilterSnapshot.docs.length,
        'queryUsed': 'userId == ${user.uid} AND timestamp > ${cutoff.toIso8601String()}',
      };
      Logger.info('   Found ${timestampFilterSnapshot.docs.length} logs with timestamp filter');

      // Check 6: Check logs with timestamp filter AND orderBy (what analytics uses)
      Logger.info('🔍 Debug: Checking logs with timestamp filter + orderBy...');
      try {
        final orderBySnapshot = await _firestore
            .collection('sensor_logs')
            .where('userId', isEqualTo: user.uid)
            .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
            .orderBy('timestamp', descending: false)
            .limit(10)
            .get();

        results['checks']['logsWithOrderBy'] = {
          'count': orderBySnapshot.docs.length,
          'success': true,
        };
        Logger.info('   Found ${orderBySnapshot.docs.length} logs with orderBy');
      } catch (e) {
        results['checks']['logsWithOrderBy'] = {
          'count': 0,
          'success': false,
          'error': e.toString(),
          'note': 'This might indicate a missing Firestore index',
        };
        Logger.warning('   OrderBy query failed: $e');
      }

      // Check 7: Check for logs with "test-device-1" deviceId
      Logger.info('🔍 Debug: Checking logs with test-device-1...');
      final testDeviceSnapshot = await _firestore
          .collection('sensor_logs')
          .where('userId', isEqualTo: user.uid)
          .where('deviceId', isEqualTo: 'test-device-1')
          .limit(10)
          .get();

      results['checks']['testDeviceLogs'] = {
        'count': testDeviceSnapshot.docs.length,
      };
      Logger.info('   Found ${testDeviceSnapshot.docs.length} logs with test-device-1');

      // Check 8: Check timestamp ranges
      if (allLogsSnapshot.docs.isNotEmpty) {
        final timestamps = <DateTime>[];
        for (var doc in allLogsSnapshot.docs) {
          final data = doc.data();
          final timestamp = data['timestamp'];
          if (timestamp is Timestamp) {
            timestamps.add(timestamp.toDate());
          }
        }
        
        if (timestamps.isNotEmpty) {
          timestamps.sort();
          final oldest = timestamps.first;
          final newest = timestamps.last;
          final now = DateTime.now();
          
          results['checks']['timestampRange'] = {
            'oldest': oldest.toIso8601String(),
            'newest': newest.toIso8601String(),
            'now': now.toIso8601String(),
            'oldestAgeHours': now.difference(oldest).inHours,
            'newestAgeHours': now.difference(newest).inHours,
            'allInPast': timestamps.every((t) => t.isBefore(now)),
            'anyInFuture': timestamps.any((t) => t.isAfter(now)),
          };
        }
      }

      // Check 9: Try to parse as SensorData
      if (allLogsSnapshot.docs.isNotEmpty) {
        int parseSuccess = 0;
        int parseFail = 0;
        String? parseError;
        
        for (var doc in allLogsSnapshot.docs.take(5)) {
          try {
            SensorData.fromJson(doc.data());
            parseSuccess++;
          } catch (e) {
            parseFail++;
            parseError = e.toString();
          }
        }
        
        results['checks']['dataParsing'] = {
          'parseSuccess': parseSuccess,
          'parseFail': parseFail,
          'parseError': parseError,
        };
      }

      // Check 10: Check what analytics query would return
      Logger.info('🔍 Debug: Testing analytics query (7 days)...');
      try {
        final analyticsQuery = await _firebaseService.getUserSensorHistory(user.uid, 7);
        results['checks']['analyticsQuery'] = {
          'count': analyticsQuery.length,
          'success': true,
        };
        Logger.info('   Analytics query returned ${analyticsQuery.length} results');
      } catch (e) {
        results['checks']['analyticsQuery'] = {
          'count': 0,
          'success': false,
          'error': e.toString(),
        };
        Logger.error('   Analytics query failed: $e');
      }

      results['success'] = true;
      Logger.success('✅ Debug check complete');
      
    } catch (e, stackTrace) {
      Logger.error('Debug check failed: $e', e, stackTrace);
      results['error'] = e.toString();
      results['success'] = false;
    }

    return results;
  }

  /// Format debug results as a readable string
  String formatDebugResults(Map<String, dynamic> results) {
    final buffer = StringBuffer();
    buffer.writeln('=== Sensor Data Debug Report ===');
    buffer.writeln('User ID: ${results['userId']}');
    buffer.writeln('Timestamp: ${results['timestamp']}');
    buffer.writeln('');

    if (results['success'] == false) {
      buffer.writeln('❌ Debug check failed: ${results['error']}');
      return buffer.toString();
    }

    final checks = results['checks'] as Map<String, dynamic>;

    // Total logs
    final totalLogs = checks['totalLogsForUser'] as Map<String, dynamic>?;
    if (totalLogs != null) {
      buffer.writeln('📊 Total Sensor Logs: ${totalLogs['count']}');
      if (totalLogs['count'] == 0) {
        buffer.writeln('   ⚠️  No sensor logs found for this user!');
      }
    }

    // Sample document
    final sampleDoc = checks['sampleDocument'] as Map<String, dynamic>?;
    if (sampleDoc != null) {
      buffer.writeln('');
      buffer.writeln('📄 Sample Document:');
      buffer.writeln('   ID: ${sampleDoc['id']}');
      buffer.writeln('   Fields: ${(sampleDoc['fields'] as List).join(", ")}');
      buffer.writeln('   userId: ${sampleDoc['userId']}');
      buffer.writeln('   deviceId: ${sampleDoc['deviceId']}');
      buffer.writeln('   timestamp type: ${sampleDoc['timestampType']}');
      buffer.writeln('   isValidTimestamp: ${sampleDoc['isValidTimestamp']}');
      if (sampleDoc['timestampDate'] != null) {
        buffer.writeln('   timestamp date: ${sampleDoc['timestampDate']}');
      }
    }

    // User devices
    final userDevices = checks['userDevices'] as Map<String, dynamic>?;
    if (userDevices != null) {
      buffer.writeln('');
      buffer.writeln('📱 User Devices: ${userDevices['count']}');
      if (userDevices['deviceIds'] != null) {
        final deviceIds = userDevices['deviceIds'] as List;
        for (int i = 0; i < deviceIds.length; i++) {
          buffer.writeln('   ${i + 1}. ${deviceIds[i]} (${(userDevices['deviceNames'] as List)[i]})');
        }
      }
    }

    // Timestamp filter
    final timestampFilter = checks['logsWithTimestampFilter'] as Map<String, dynamic>?;
    if (timestampFilter != null) {
      buffer.writeln('');
      buffer.writeln('⏰ Logs with timestamp filter (last 7 days): ${timestampFilter['count']}');
      buffer.writeln('   Query: ${timestampFilter['queryUsed']}');
      if (timestampFilter['count'] == 0 && totalLogs?['count'] != null && totalLogs!['count'] > 0) {
        buffer.writeln('   ⚠️  Data exists but timestamp filter excludes it!');
      }
    }

    // OrderBy
    final orderBy = checks['logsWithOrderBy'] as Map<String, dynamic>?;
    if (orderBy != null) {
      buffer.writeln('');
      if (orderBy['success'] == true) {
        buffer.writeln('✅ OrderBy query: ${orderBy['count']} results');
      } else {
        buffer.writeln('❌ OrderBy query failed: ${orderBy['error']}');
        buffer.writeln('   ${orderBy['note']}');
      }
    }

    // Analytics query
    final analyticsQuery = checks['analyticsQuery'] as Map<String, dynamic>?;
    if (analyticsQuery != null) {
      buffer.writeln('');
      if (analyticsQuery['success'] == true) {
        buffer.writeln('📈 Analytics Query (7 days): ${analyticsQuery['count']} results');
      } else {
        buffer.writeln('❌ Analytics Query failed: ${analyticsQuery['error']}');
      }
    }

    // Timestamp range
    final timestampRange = checks['timestampRange'] as Map<String, dynamic>?;
    if (timestampRange != null) {
      buffer.writeln('');
      buffer.writeln('📅 Timestamp Range:');
      buffer.writeln('   Oldest: ${timestampRange['oldest']} (${timestampRange['oldestAgeHours']} hours ago)');
      buffer.writeln('   Newest: ${timestampRange['newest']} (${timestampRange['newestAgeHours']} hours ago)');
      if (timestampRange['anyInFuture'] == true) {
        buffer.writeln('   ⚠️  Some timestamps are in the future!');
      }
    }

    buffer.writeln('');
    buffer.writeln('=== End of Debug Report ===');
    return buffer.toString();
  }
}

