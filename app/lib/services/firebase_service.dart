// app/lib/services/firebase_service.dart - UPDATED
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/device_model.dart';
import '../models/room_model.dart';
import '../models/sensor_data.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
    await _firestore.collection('devices').add({
      ...device.toFirestore(),
      'userId': userId,
    });
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

  // ==================== ENERGY CONSUMPTION ====================

  Future<double> getTodayEnergyConsumption(String userId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final logs = await _firestore
        .collection('sensor_logs')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(startOfDay))
        .get();

    // Calculate energy (simplified)
    double totalEnergy = 0;
    for (var doc in logs.docs) {
      final data = doc.data();
      // Assume average device power consumption
      totalEnergy += (data['fanSpeed'] ?? 0) * 0.001; // 1W per unit
      totalEnergy += (data['ledBrightness'] ?? 0) * 0.0005; // 0.5W per unit
    }

    return totalEnergy;
  }

  Future<double> getRoomEnergyConsumption(String userId, String roomId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    // Get all devices in the room
    final devicesSnapshot = await _firestore
        .collection('devices')
        .where('userId', isEqualTo: userId)
        .where('roomId', isEqualTo: roomId)
        .get();

    double totalEnergy = 0;

    for (var deviceDoc in devicesSnapshot.docs) {
      final logs = await _firestore
          .collection('sensor_logs')
          .where('deviceId', isEqualTo: deviceDoc.id)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(startOfDay))
          .get();

      for (var log in logs.docs) {
        final data = log.data();
        totalEnergy += (data['fanSpeed'] ?? 0) * 0.001;
        totalEnergy += (data['ledBrightness'] ?? 0) * 0.0005;
      }
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
}

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService();
});
