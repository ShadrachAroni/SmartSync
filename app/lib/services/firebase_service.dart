// app/lib/services/firebase_service.dart - UPDATED
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/device_model.dart';
import '../models/room_model.dart';
import '../models/sensor_data.dart';
import '../models/schedule_model.dart';
import '../models/alert_model.dart';
import '../models/daily_analytics.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // Use instanceFor to ensure correct bucket configuration
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(
    bucket: 'smartsync-cf370.firebasestorage.app',
  );

  // ==================== DEVICES ====================

  Stream<List<DeviceModel>> getUserDevices(String userId) {
    return _firestore
        .collection('devices')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DeviceModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<DeviceModel>> getRoomDevices(String userId, String roomId) {
    return _firestore
        .collection('devices')
        .where('userId', isEqualTo: userId)
        .where('roomId', isEqualTo: roomId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DeviceModel.fromFirestore(doc))
            .toList());
  }

  Future<void> addDevice(String userId, DeviceModel device) async {
    // Use device.id as document ID to ensure uniqueness
    await _firestore.collection('devices').doc(device.id).set({
      ...device.toFirestore(),
      'userId': userId,
    }, SetOptions(merge: true));
  }

  // Check if device exists by deviceId (BLE remoteId)
  Future<DeviceModel?> getDeviceById(String deviceId) async {
    try {
      final doc = await _firestore.collection('devices').doc(deviceId).get();
      if (doc.exists && doc.data() != null) {
        return DeviceModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateDevice(String deviceId, Map<String, dynamic> data) async {
    await _firestore.collection('devices').doc(deviceId).update(data);
  }

  Future<void> deleteDevice(String deviceId) async {
    await _firestore.collection('devices').doc(deviceId).delete();
  }

  Future<void> assignDeviceToRoom(String deviceId, String roomId) async {
    await _firestore.collection('devices').doc(deviceId).update({
      'roomId': roomId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==================== ROOMS ====================

  Stream<List<RoomModel>> getUserRooms(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('rooms')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RoomModel.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<String> addRoom(String userId, RoomModel room) async {
    final docRef = await _firestore
        .collection('users')
        .doc(userId)
        .collection('rooms')
        .add(room.toMap());
    return docRef.id;
  }

  Future<void> updateRoom(
      String userId, String roomId, Map<String, dynamic> data) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('rooms')
        .doc(roomId)
        .update(data);
  }

  Future<void> deleteRoom(String userId, String roomId) async {
    // First, unassign all devices from this room
    final devicesSnapshot = await _firestore
        .collection('devices')
        .where('userId', isEqualTo: userId)
        .where('roomId', isEqualTo: roomId)
        .get();

    final batch = _firestore.batch();

    for (var doc in devicesSnapshot.docs) {
      batch.update(doc.reference, {'roomId': ''});
    }

    // Delete the room
    batch.delete(
      _firestore
          .collection('users')
          .doc(userId)
          .collection('rooms')
          .doc(roomId),
    );

    await batch.commit();
  }

  // Get Firestore instance (for direct access when needed)
  FirebaseFirestore get firestore => _firestore;

  Future<void> addDeviceToRoom(
      String userId, String roomId, String deviceId) async {
    final roomRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('rooms')
        .doc(roomId);

    // Check if room exists first
    final roomDoc = await roomRef.get();
    if (!roomDoc.exists) {
      throw Exception('Room $roomId does not exist for user $userId');
    }

    // Update the room's deviceIds array
    await roomRef.update({
      'deviceIds': FieldValue.arrayUnion([deviceId]),
    });

    // Also update the device's roomId
    await assignDeviceToRoom(deviceId, roomId);
  }

  Future<void> removeDeviceFromRoom(
      String userId, String roomId, String deviceId) async {
    final roomRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('rooms')
        .doc(roomId);

    await roomRef.update({
      'deviceIds': FieldValue.arrayRemove([deviceId]),
    });

    await assignDeviceToRoom(deviceId, '');
  }

  // ==================== SENSOR DATA ====================

  Future<void> logSensorData(SensorData data) async {
    // Convert to JSON and ensure timestamp is a Firestore Timestamp
    final jsonData = data.toJson();
    jsonData['timestamp'] = Timestamp.fromDate(data.timestamp);
    await _firestore.collection('sensor_logs').add(jsonData);
  }

  Stream<List<SensorData>> getSensorLogs(String deviceId, int hours) {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    return _firestore
        .collection('sensor_logs')
        .where('deviceId', isEqualTo: deviceId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: true)
        .limit(1000)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SensorData.fromJson(doc.data()))
            .toList());
  }

  Future<List<DailyAnalytics>> getDailyAnalytics(
      String userId, int days) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final snapshot = await _firestore
        .collection('daily_analytics')
        .where('userId', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('date', descending: false)
        .get();

    return snapshot.docs.map(DailyAnalytics.fromDoc).toList();
  }

  /// Stream daily analytics for real-time updates
  Stream<List<DailyAnalytics>> watchDailyAnalytics(String userId, int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return _firestore
        .collection('daily_analytics')
        .where('userId', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('date', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(DailyAnalytics.fromDoc).toList());
  }

  Future<List<SensorData>> getUserSensorHistory(String userId, int days,
      {int limit = 2000}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final snapshot = await _firestore
        .collection('sensor_logs')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: false)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => SensorData.fromJson(doc.data())).toList();
  }

  /// Stream sensor history for real-time updates
  Stream<List<SensorData>> watchUserSensorHistory(String userId, int days,
      {int limit = 2000}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return _firestore
        .collection('sensor_logs')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: false)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SensorData.fromJson(doc.data()))
            .toList());
  }

  Future<List<DeviceModel>> fetchUserDevices(String userId) async {
    final snapshot = await _firestore
        .collection('devices')
        .where('userId', isEqualTo: userId)
        .get();

    return snapshot.docs.map((doc) => DeviceModel.fromFirestore(doc)).toList();
  }

  // Get latest sensor reading for a device
  Future<SensorData?> getLatestSensorData(String deviceId) async {
    final snapshot = await _firestore
        .collection('sensor_logs')
        .where('deviceId', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return SensorData.fromJson(snapshot.docs.first.data());
  }

  // ==================== SCHEDULES ====================

  Stream<List<ScheduleModel>> getSchedules(String userId, {String? deviceId}) {
    Query<Map<String, dynamic>> query =
        _firestore.collection('users').doc(userId).collection('schedules');

    if (deviceId != null) {
      query = query.where('deviceId', isEqualTo: deviceId);
    }

    return query.snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => ScheduleModel.fromFirestore(doc))
              .toList(),
        );
  }

  Future<void> addSchedule(String userId, ScheduleModel schedule) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('schedules')
        .add(schedule.toMap());
  }

  Future<void> updateSchedule(String userId, ScheduleModel schedule) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('schedules')
        .doc(schedule.id)
        .update(schedule.toMap());
  }

  Future<void> deleteSchedule(String userId, String scheduleId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('schedules')
        .doc(scheduleId)
        .delete();
  }

  // ==================== ENERGY CONSUMPTION ====================

  Future<double> getTodayEnergyConsumption(String userId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      final logs = await _firestore
          .collection('sensor_logs')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(startOfDay))
          .limit(1000) // Limit to prevent timeout
          .get();

      // Return 0 if no logs
      if (logs.docs.isEmpty) {
        return 0.0;
      }

      // Calculate energy consumption properly
      // Energy (kWh) = Power (kW) × Time (hours)
      // We need to account for time duration between logs
      double totalEnergy = 0.0;

      if (logs.docs.isEmpty) {
        return 0.0;
      }

      // Sort logs by timestamp
      final sortedLogs = logs.docs.toList()
        ..sort((a, b) {
          final aTime =
              (a.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
          final bTime =
              (b.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
          return aTime.compareTo(bTime);
        });

      // Calculate power consumption for each time interval
      for (int i = 0; i < sortedLogs.length; i++) {
        final data = sortedLogs[i].data();
        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

        if (timestamp == null) continue;

        // Calculate power in kW from device speeds
        // Fan: 0-50W (0.05kW max) based on speed (0-255)
        // LED: 0-10W (0.01kW max) based on brightness (0-255)
        final fanSpeed = (data['fanSpeed'] as num?)?.toInt() ?? 0;
        final ledBrightness = (data['ledBrightness'] as num?)?.toInt() ?? 0;

        final fanPowerKw = (fanSpeed / 255.0) * 0.05; // 0-0.05 kW
        final ledPowerKw = (ledBrightness / 255.0) * 0.01; // 0-0.01 kW
        final totalPowerKw = fanPowerKw + ledPowerKw;

        // Calculate time duration for this log entry
        // If this is the last log, use time until now, otherwise use time until next log
        Duration duration;
        if (i < sortedLogs.length - 1) {
          final nextTimestamp =
              (sortedLogs[i + 1].data()['timestamp'] as Timestamp?)?.toDate();
          if (nextTimestamp != null) {
            duration = nextTimestamp.difference(timestamp);
          } else {
            duration = const Duration(
                minutes: 5); // Default 5 minutes if next timestamp missing
          }
        } else {
          // Last log: use time until now or default 5 minutes
          duration = DateTime.now().difference(timestamp);
          if (duration.isNegative || duration.inMinutes > 60) {
            duration =
                const Duration(minutes: 5); // Cap at 5 minutes for last entry
          }
        }

        // Ensure minimum duration of 1 minute to avoid division issues
        final hours = duration.inSeconds.clamp(60, 3600) /
            3600.0; // Convert to hours (min 1 min, max 1 hour)

        // Energy = Power × Time
        totalEnergy += totalPowerKw * hours;
      }

      return totalEnergy;
    } catch (e) {
      // Return 0 on error instead of throwing
      return 0.0;
    }
  }

  Future<double> getRoomEnergyConsumption(String userId, String roomId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      // Get all devices in the room to find the hub device
      final devicesSnapshot = await _firestore
          .collection('devices')
          .where('userId', isEqualTo: userId)
          .where('roomId', isEqualTo: roomId)
          .get();

      // Find the hub device (sensor logs are stored with hub device ID)
      String? hubDeviceId;
      for (var deviceDoc in devicesSnapshot.docs) {
        final deviceData = deviceDoc.data();
        if (deviceData['isHub'] == true || deviceData['type'] == 'hub') {
          hubDeviceId = deviceDoc.id;
          break;
        }
      }

      // If no hub found, try to find any device that might be the hub
      // or use the first device as fallback
      if (hubDeviceId == null && devicesSnapshot.docs.isNotEmpty) {
        // Try to find a device that has sensor logs
        for (var deviceDoc in devicesSnapshot.docs) {
          final testLogs = await _firestore
              .collection('sensor_logs')
              .where('deviceId', isEqualTo: deviceDoc.id)
              .where('userId', isEqualTo: userId)
              .where('timestamp', isGreaterThan: Timestamp.fromDate(startOfDay))
              .limit(1)
              .get();
          if (testLogs.docs.isNotEmpty) {
            hubDeviceId = deviceDoc.id;
            break;
          }
        }
      }

      // If still no hub found, query by userId only (sensor logs have userId)
      if (hubDeviceId == null) {
        // Query all sensor logs for this user and room (if roomId is stored in logs)
        // Since roomId might not be in sensor logs, we'll query by userId
        final logs = await _firestore
            .collection('sensor_logs')
            .where('userId', isEqualTo: userId)
            .where('timestamp', isGreaterThan: Timestamp.fromDate(startOfDay))
            .orderBy('timestamp', descending: false)
            .get();

        if (logs.docs.isEmpty) return 0.0;

        // Calculate energy from all logs (assuming they're from this room's hub)
        return _calculateEnergyFromLogs(logs.docs);
      }

      // Query sensor logs by hub device ID
      final logs = await _firestore
          .collection('sensor_logs')
          .where('deviceId', isEqualTo: hubDeviceId)
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(startOfDay))
          .orderBy('timestamp', descending: false)
          .get();

      if (logs.docs.isEmpty) return 0.0;

      return _calculateEnergyFromLogs(logs.docs);
    } catch (e) {
      return 0.0;
    }
  }

  /// Helper method to calculate energy from sensor log documents
  double _calculateEnergyFromLogs(List<QueryDocumentSnapshot<Map<String, dynamic>>> logs) {
    // Sort logs by timestamp
    final sortedLogs = logs.toList()
      ..sort((a, b) {
        final aTime = (a.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
        final bTime = (b.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
        return aTime.compareTo(bTime);
      });

    double totalEnergy = 0.0;

    // Calculate energy for each time interval
    for (int i = 0; i < sortedLogs.length; i++) {
      final data = sortedLogs[i].data();
      final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

      if (timestamp == null) continue;

      // Calculate power in kW
      final fanSpeed = (data['fanSpeed'] as num?)?.toInt() ?? 0;
      final ledBrightness = (data['ledBrightness'] as num?)?.toInt() ?? 0;

      final fanPowerKw = (fanSpeed / 255.0) * 0.05; // 0-0.05 kW
      final ledPowerKw = (ledBrightness / 255.0) * 0.01; // 0-0.01 kW
      final totalPowerKw = fanPowerKw + ledPowerKw;

      // Calculate time duration
      Duration duration;
      if (i < sortedLogs.length - 1) {
        final nextTimestamp =
            (sortedLogs[i + 1].data()['timestamp'] as Timestamp?)?.toDate();
        if (nextTimestamp != null) {
          duration = nextTimestamp.difference(timestamp);
        } else {
          duration = const Duration(minutes: 5);
        }
      } else {
        duration = DateTime.now().difference(timestamp);
        if (duration.isNegative || duration.inMinutes > 60) {
          duration = const Duration(minutes: 5);
        }
      }

      final hours = duration.inSeconds.clamp(60, 3600) / 3600.0;
      totalEnergy += totalPowerKw * hours;
    }

    return totalEnergy;
  }

  // ==================== ALERTS ====================

  Future<void> createAlert({
    required String userId,
    required String type,
    required String severity,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    await _firestore.collection('alerts').add({
      'userId': userId,
      'type': type,
      'severity': severity,
      'message': message,
      'data': data ?? {},
      'read': false,
      'acknowledged': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AlertModel>> getAlerts(String userId) {
    try {
      return _firestore
          .collection('alerts')
          .where('userId', isEqualTo: userId)
          .snapshots()
          .timeout(
        const Duration(seconds: 30),
        onTimeout: (sink) {
          sink.addError('Request timed out. Please check your connection.');
        },
      ).map(
        (snapshot) {
          final alerts = snapshot.docs
              .map((doc) => AlertModel.fromFirestore(doc))
              .toList();
          // Sort by timestamp descending in memory to avoid index requirement
          alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return alerts;
        },
      ).handleError((error) {
        // Handle Firestore errors gracefully
        if (error.toString().contains('index')) {
          throw Exception(
              'Database index required. Please contact support or wait a few minutes for the index to be created automatically.');
        }
        throw error;
      });
    } catch (e) {
      return Stream.value(<AlertModel>[]);
    }
  }

  Future<void> markAlertRead(String alertId,
      {bool acknowledged = false}) async {
    await _firestore.collection('alerts').doc(alertId).update({
      'read': true,
      if (acknowledged) 'acknowledged': true,
    });
  }

  Stream<int> getUnreadAlertCount(String userId) {
    return _firestore
        .collection('alerts')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Delete a specific alert
  Future<void> deleteAlert(String alertId) async {
    await _firestore.collection('alerts').doc(alertId).delete();
  }

  /// Clear all alerts for a user
  Future<int> clearAllAlerts(String userId) async {
    try {
      int totalDeleted = 0;
      const batchSize = 500;
      bool hasMore = true;

      while (hasMore) {
        final snapshot = await _firestore
            .collection('alerts')
            .where('userId', isEqualTo: userId)
            .limit(batchSize)
            .get();

        if (snapshot.docs.isEmpty) {
          hasMore = false;
          break;
        }

        final batch = _firestore.batch();
        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
        totalDeleted += snapshot.docs.length;

        if (snapshot.docs.length < batchSize) {
          hasMore = false;
        }
      }

      return totalDeleted;
    } catch (e) {
      throw Exception('Failed to clear alerts: $e');
    }
  }

  /// Delete a specific activity log
  Future<void> deleteActivityLog(String logId) async {
    await _firestore.collection('activity_logs').doc(logId).delete();
  }

  /// Clear all activity logs for a user
  Future<int> clearAllActivityLogs(String userId) async {
    try {
      int totalDeleted = 0;
      const batchSize = 500;
      bool hasMore = true;

      while (hasMore) {
        final snapshot = await _firestore
            .collection('activity_logs')
            .where('userId', isEqualTo: userId)
            .limit(batchSize)
            .get();

        if (snapshot.docs.isEmpty) {
          hasMore = false;
          break;
        }

        final batch = _firestore.batch();
        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
        totalDeleted += snapshot.docs.length;

        if (snapshot.docs.length < batchSize) {
          hasMore = false;
        }
      }

      return totalDeleted;
    } catch (e) {
      throw Exception('Failed to clear activity logs: $e');
    }
  }

  // ==================== AUTOMATIONS ====================

  Stream<List<Map<String, dynamic>>> getRoomAutomations(
      String userId, String roomId) {
    return _firestore
        .collection('automations')
        .where('userId', isEqualTo: userId)
        .where('roomId', isEqualTo: roomId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data(),
                })
            .toList())
        .handleError((error) {
      // Handle Firestore errors gracefully
      if (error.toString().contains('permission-denied') ||
          error.toString().contains('permission denied')) {
        throw Exception(
            'Permission denied: You don\'t have access to view automations for this room.');
      } else if (error.toString().contains('index')) {
        throw Exception(
            'Database index required. Please wait a few minutes for the index to be created automatically.');
      }
      // Re-throw other errors as-is
      throw error;
    });
  }

  Stream<List<Map<String, dynamic>>> getUserAutomations(String userId) {
    return _firestore
        .collection('automations')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data(),
                })
            .toList());
  }

  Future<void> toggleAutomation(String automationId, bool enabled) async {
    await _firestore.collection('automations').doc(automationId).update({
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==================== STATISTICS ====================

  Future<Map<String, dynamic>> getRoomStatistics(
      String userId, String roomId) async {
    final devicesSnapshot = await _firestore
        .collection('devices')
        .where('userId', isEqualTo: userId)
        .where('roomId', isEqualTo: roomId)
        .get();

    final activeDevices = devicesSnapshot.docs
        .where((doc) => (doc.data())['isOn'] == true)
        .length;

    final totalDevices = devicesSnapshot.docs.length;

    final energy = await getRoomEnergyConsumption(userId, roomId);

    final automationsSnapshot = await _firestore
        .collection('automations')
        .where('userId', isEqualTo: userId)
        .where('roomId', isEqualTo: roomId)
        .get();

    return {
      'activeDevices': activeDevices,
      'totalDevices': totalDevices,
      'energyConsumption': energy,
      'automationCount': automationsSnapshot.docs.length,
    };
  }

  // ==================== BULK OPERATIONS ====================

  Future<void> toggleAllRoomDevices(
      String userId, String roomId, bool enabled) async {
    final devicesSnapshot = await _firestore
        .collection('devices')
        .where('userId', isEqualTo: userId)
        .where('roomId', isEqualTo: roomId)
        .get();

    final batch = _firestore.batch();

    for (var doc in devicesSnapshot.docs) {
      batch.update(doc.reference, {
        'isOn': enabled,
        // When disabling, set value to 0 for adjustable appliances
        'value': enabled ? (doc.data()['value'] ?? 0) : 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // ==================== HUB OPERATIONS ====================

  /// Set a hub as the primary hub, unsetting all others
  Future<void> setPrimaryHub(String userId, String hubId) async {
    try {
      // Get all rooms for this user
      final roomsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('rooms')
          .get();

      final batch = _firestore.batch();
      bool foundHubRoom = false;

      // Unset primary status from all rooms and find the hub room
      for (var doc in roomsSnapshot.docs) {
        final data = doc.data();
        if (data['hubId'] == hubId) {
          foundHubRoom = true;
          batch.update(doc.reference, {'isPrimaryHub': true});
        } else if (data['hubId'] != null) {
          // Unset primary status from other rooms with hubs
          batch.update(doc.reference, {'isPrimaryHub': false});
        }
      }

      if (!foundHubRoom) {
        // If room not found, try to find it by querying again (might be a timing issue)
        final hubRoomSnapshot = await _firestore
            .collection('users')
            .doc(userId)
            .collection('rooms')
            .where('hubId', isEqualTo: hubId)
            .limit(1)
            .get();

        if (hubRoomSnapshot.docs.isEmpty) {
          throw Exception('Room with hubId $hubId not found. Please ensure the hub is assigned to a room first.');
        }

        batch.update(hubRoomSnapshot.docs.first.reference, {'isPrimaryHub': true});
      }

      await batch.commit();
    } catch (e) {
      // Log error but don't throw - this is not critical for hub registration
      print('Error setting primary hub: $e');
      rethrow;
    }
  }

  /// Get the primary hub for a user
  Future<String?> getPrimaryHub(String userId) async {
    final roomsSnapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('rooms')
        .where('isPrimaryHub', isEqualTo: true)
        .limit(1)
        .get();

    if (roomsSnapshot.docs.isEmpty) return null;
    return roomsSnapshot.docs.first.data()['hubId'] as String?;
  }

  /// Get hub by room ID
  Future<String?> getHubByRoom(String userId, String roomId) async {
    final roomDoc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('rooms')
        .doc(roomId)
        .get();

    if (!roomDoc.exists) return null;
    return roomDoc.data()?['hubId'] as String?;
  }

  // ==================== ROOM IMAGE UPLOAD ====================

  Future<String> uploadRoomImage({
    required String userId,
    required String roomId,
    required File imageFile,
  }) async {
    try {
      // Check if file exists and is readable
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist');
      }

      // Create storage reference
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$timestamp.jpg';
      final ref = _storage
          .ref()
          .child('rooms')
          .child(userId)
          .child(roomId)
          .child(fileName);

      // Upload file with metadata
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
          'roomId': roomId,
        },
      );

      final uploadTask = ref.putFile(imageFile, metadata);

      // Wait for upload to complete and check state
      final snapshot = await uploadTask;

      // Verify upload completed successfully
      if (snapshot.state != TaskState.success) {
        throw Exception('Upload failed with state: ${snapshot.state}');
      }

      // Wait a brief moment to ensure the file is fully processed
      await Future.delayed(const Duration(milliseconds: 500));

      // Get download URL
      try {
        final downloadUrl = await snapshot.ref.getDownloadURL();
        return downloadUrl;
      } catch (urlError) {
        // If getting URL fails, try again after a short delay
        await Future.delayed(const Duration(seconds: 1));
        final downloadUrl = await snapshot.ref.getDownloadURL();
        return downloadUrl;
      }
    } on FirebaseException catch (e) {
      // Handle Firebase-specific errors
      String errorMessage = 'Failed to upload room image';
      switch (e.code) {
        case 'object-not-found':
          errorMessage =
              'Storage bucket not found. Please check Firebase Storage configuration.';
          break;
        case 'unauthorized':
          errorMessage =
              'Permission denied. Please check Firebase Storage rules.';
          break;
        case 'canceled':
          errorMessage = 'Upload was canceled.';
          break;
        case 'unknown':
          errorMessage = 'Unknown error occurred during upload.';
          break;
        default:
          errorMessage = 'Firebase Storage error: ${e.message}';
      }
      throw Exception('$errorMessage (Code: ${e.code})');
    } catch (e) {
      throw Exception('Failed to upload room image: $e');
    }
  }

  // ==================== PROFILE IMAGE UPLOAD ====================

  Future<String> uploadProfileImage({
    required String userId,
    required File imageFile,
  }) async {
    try {
      // Check if file exists and is readable
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist');
      }

      // Create storage reference
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$timestamp.jpg';
      final ref = _storage
          .ref()
          .child('profiles')
          .child(userId)
          .child(fileName);

      // Upload file with metadata
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
          'userId': userId,
        },
      );

      final uploadTask = ref.putFile(imageFile, metadata);

      // Wait for upload to complete and check state
      final snapshot = await uploadTask;

      // Verify upload completed successfully
      if (snapshot.state != TaskState.success) {
        throw Exception('Upload failed with state: ${snapshot.state}');
      }

      // Wait a brief moment to ensure the file is fully processed
      await Future.delayed(const Duration(milliseconds: 500));

      // Get download URL
      try {
        final downloadUrl = await snapshot.ref.getDownloadURL();
        return downloadUrl;
      } catch (urlError) {
        // If getting URL fails, try again after a short delay
        await Future.delayed(const Duration(seconds: 1));
        final downloadUrl = await snapshot.ref.getDownloadURL();
        return downloadUrl;
      }
    } on FirebaseException catch (e) {
      // Handle Firebase-specific errors
      String errorMessage = 'Failed to upload profile image';
      switch (e.code) {
        case 'object-not-found':
          errorMessage =
              'Storage bucket not found. Please check Firebase Storage configuration.';
          break;
        case 'unauthorized':
          errorMessage =
              'Permission denied. Please check Firebase Storage rules.';
          break;
        case 'canceled':
          errorMessage = 'Upload was canceled.';
          break;
        case 'unknown':
          errorMessage = 'Unknown error occurred during upload.';
          break;
        default:
          errorMessage = 'Firebase Storage error: ${e.message}';
      }
      throw Exception('$errorMessage (Code: ${e.code})');
    } catch (e) {
      throw Exception('Failed to upload profile image: $e');
    }
  }
}

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService();
});
