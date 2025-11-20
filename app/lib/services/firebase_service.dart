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
  final FirebaseStorage _storage = FirebaseStorage.instance;

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

  Future<void> addRoom(String userId, RoomModel room) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('rooms')
        .add(room.toMap());
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

  Future<void> addDeviceToRoom(
      String userId, String roomId, String deviceId) async {
    final roomRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('rooms')
        .doc(roomId);

    await roomRef.update({
      'deviceIds': FieldValue.arrayUnion([deviceId]),
    });

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
    await _firestore.collection('sensor_logs').add(data.toJson());
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

  Future<List<DailyAnalytics>> getDailyAnalytics(String userId, int days) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final snapshot = await _firestore
        .collection('daily_analytics')
        .where('userId', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('date', descending: false)
        .get();

    return snapshot.docs.map(DailyAnalytics.fromDoc).toList();
  }

  Future<List<SensorData>> getUserSensorHistory(
      String userId, int days, {int limit = 2000}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final snapshot = await _firestore
        .collection('sensor_logs')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: false)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => SensorData.fromJson(doc.data()))
        .toList();
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
          final aTime = (a.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
          final bTime = (b.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
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
          final nextTimestamp = (sortedLogs[i + 1].data()['timestamp'] as Timestamp?)?.toDate();
          if (nextTimestamp != null) {
            duration = nextTimestamp.difference(timestamp);
          } else {
            duration = const Duration(minutes: 5); // Default 5 minutes if next timestamp missing
          }
        } else {
          // Last log: use time until now or default 5 minutes
          duration = DateTime.now().difference(timestamp);
          if (duration.isNegative || duration.inMinutes > 60) {
            duration = const Duration(minutes: 5); // Cap at 5 minutes for last entry
          }
        }
        
        // Ensure minimum duration of 1 minute to avoid division issues
        final hours = duration.inSeconds.clamp(60, 3600) / 3600.0; // Convert to hours (min 1 min, max 1 hour)
        
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

      // Get all devices in the room
      final devicesSnapshot = await _firestore
          .collection('devices')
          .where('userId', isEqualTo: userId)
          .where('roomId', isEqualTo: roomId)
          .get();

      double totalEnergy = 0.0;

      for (var deviceDoc in devicesSnapshot.docs) {
        final logs = await _firestore
            .collection('sensor_logs')
            .where('deviceId', isEqualTo: deviceDoc.id)
            .where('timestamp', isGreaterThan: Timestamp.fromDate(startOfDay))
            .orderBy('timestamp', descending: false)
            .get();

        if (logs.docs.isEmpty) continue;

        // Sort logs by timestamp
        final sortedLogs = logs.docs.toList()
          ..sort((a, b) {
            final aTime = (a.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
            final bTime = (b.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
            return aTime.compareTo(bTime);
          });

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
            final nextTimestamp = (sortedLogs[i + 1].data()['timestamp'] as Timestamp?)?.toDate();
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
      }

      return totalEnergy;
    } catch (e) {
      return 0.0;
    }
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
          )
          .map(
            (snapshot) {
              final alerts = snapshot.docs
                  .map((doc) => AlertModel.fromFirestore(doc))
                  .toList();
              // Sort by timestamp descending in memory to avoid index requirement
              alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
              return alerts;
            },
          )
          .handleError((error) {
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
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // ==================== ROOM IMAGE UPLOAD ====================

  Future<String> uploadRoomImage({
    required String userId,
    required String roomId,
    required File imageFile,
  }) async {
    try {
      final ref = _storage
          .ref()
          .child('rooms')
          .child(userId)
          .child(roomId)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload room image: $e');
    }
  }
}

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService();
});
