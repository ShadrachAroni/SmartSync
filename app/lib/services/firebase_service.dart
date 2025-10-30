import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/device_model.dart';
import '../models/room_model.dart';
import '../models/sensor_data.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Devices
  Stream<List<DeviceModel>> getUserDevices(String userId) {
    return _firestore
        .collection('devices')
        .where('userId', isEqualTo: userId)
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

  // Rooms
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

  // Sensor Data
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

  // Energy consumption
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
      totalEnergy += (data['fanSpeed'] ?? 0) * 0.001; // kWh
      totalEnergy += (data['ledBrightness'] ?? 0) * 0.0005;
    }

    return totalEnergy;
  }
}

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService();
});
