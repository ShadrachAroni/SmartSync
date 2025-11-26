import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/sensor_data.dart';
import '../core/utils/logger.dart';
import 'firebase_service.dart';

/// Service to generate test sensor data for development/testing
/// 
/// This is useful when:
/// - No Bluetooth device is connected
/// - Testing analytics and ML features
/// - Demonstrating the app functionality
class TestDataGenerator {
  static final TestDataGenerator _instance = TestDataGenerator._internal();
  factory TestDataGenerator() => _instance;
  TestDataGenerator._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseService _firebaseService = FirebaseService();
  final math.Random _random = math.Random();

  /// Generate a Gaussian (normal) distributed random number using Box-Muller transform
  double _nextGaussian({double mean = 0.0, double stdDev = 1.0}) {
    // Box-Muller transform to generate Gaussian random numbers
    if (_hasSpare) {
      _hasSpare = false;
      return _spare * stdDev + mean;
    }
    
    _hasSpare = true;
    double u, v, s;
    do {
      u = _random.nextDouble() * 2.0 - 1.0;
      v = _random.nextDouble() * 2.0 - 1.0;
      s = u * u + v * v;
    } while (s >= 1.0 || s == 0.0);
    
    s = math.sqrt(-2.0 * math.log(s) / s);
    _spare = v * s;
    return u * s * stdDev + mean;
  }
  
  bool _hasSpare = false;
  double _spare = 0.0;

  /// Generate test sensor data for the past N hours or days
  /// 
  /// [hours] - Number of hours of data to generate (if days is null)
  /// [days] - Number of days of data to generate (takes precedence over hours)
  /// [deviceId] - Device ID to use (default: 'test-device-1')
  /// [intervalMinutes] - Interval between readings in minutes (default: 5)
  /// [generateForAllDevices] - If true, generates data for all user devices (default: false)
  Future<void> generateTestData({
    int? hours,
    int? days,
    String? deviceId,
    int intervalMinutes = 5,
    bool generateForAllDevices = false,
  }) async {
    // Calculate hours from days if provided
    // Default to 7 days (recommended for ML predictions) instead of 48 hours
    final finalHours = days != null ? days * 24 : (hours ?? 7 * 24);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Logger.error('TestDataGenerator: No user logged in');
      throw StateError('User must be logged in to generate test data');
    }

    // Get user's devices or use default
    List<String> deviceIds = [];
    if (generateForAllDevices) {
      try {
        final devices = await _firebaseService.fetchUserDevices(user.uid);
        if (devices.isNotEmpty) {
          deviceIds = devices.map((d) => d.id).toList();
          Logger.info('TestDataGenerator: Generating data for ${deviceIds.length} devices');
        } else {
          Logger.info('TestDataGenerator: No devices found, using test device ID');
          deviceIds = [deviceId ?? 'test-device-1'];
        }
      } catch (e) {
        Logger.warning('TestDataGenerator: Could not fetch devices: $e');
        deviceIds = [deviceId ?? 'test-device-1'];
      }
    } else {
      String finalDeviceId = deviceId ?? 'test-device-1';
      if (deviceId == null) {
        try {
          final devices = await _firebaseService.fetchUserDevices(user.uid);
          if (devices.isNotEmpty) {
            finalDeviceId = devices.first.id;
            Logger.info('TestDataGenerator: Using existing device: $finalDeviceId');
          } else {
            Logger.info('TestDataGenerator: No devices found, using test device ID');
          }
        } catch (e) {
          Logger.warning('TestDataGenerator: Could not fetch devices: $e');
        }
      }
      deviceIds = [finalDeviceId];
    }

    Logger.info('🧪 Generating test sensor data...');
    Logger.info('   User: ${user.uid}');
    Logger.info('   Devices: ${deviceIds.length} (${deviceIds.join(", ")})');
    Logger.info('   ${days != null ? "Days: $days" : "Hours: $finalHours"}');
    Logger.info('   Interval: $intervalMinutes minutes');

    final now = DateTime.now();
    final startTime = now.subtract(Duration(hours: finalHours));
    final totalReadingsPerDevice = (finalHours * 60 / intervalMinutes).round();
    final totalReadings = totalReadingsPerDevice * deviceIds.length;

    Logger.info('   Generating $totalReadings sensor readings (${totalReadingsPerDevice} per device)...');

    // Track state for realistic correlations (fan cooling effect, motion persistence)
    final deviceStates = <String, Map<String, dynamic>>{};
    for (final deviceId in deviceIds) {
      deviceStates[deviceId] = {
        'currentTemp': 22.0, // Track temperature for fan cooling effect
        'lastMotionTime': startTime,
        'motionActive': false,
      };
    }

    // Generate data in batches to avoid overwhelming Firestore
    const batchSize = 100;
    int totalGenerated = 0;

    // Generate for each device
    for (int deviceIndex = 0; deviceIndex < deviceIds.length; deviceIndex++) {
      final currentDeviceId = deviceIds[deviceIndex];
      int deviceGenerated = 0;
      final totalBatches = (totalReadingsPerDevice / batchSize).ceil();

      Logger.info('   📱 Generating data for device ${deviceIndex + 1}/${deviceIds.length}: $currentDeviceId');

      for (int batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
        final writeBatch = _firestore.batch();
        int batchCount = 0;

        for (int i = 0; i < batchSize && deviceGenerated < totalReadingsPerDevice; i++) {
          final readingTime = startTime.add(
            Duration(minutes: (deviceGenerated * intervalMinutes) + (deviceIndex * 5)),
          );

          // Skip future timestamps
          if (readingTime.isAfter(now)) break;

          final sensorData = _generateRealisticSensorData(
            timestamp: readingTime,
            deviceId: currentDeviceId,
            userId: user.uid,
            deviceState: deviceStates[currentDeviceId]!,
          );

          // Update device state for next reading
          deviceStates[currentDeviceId]!['currentTemp'] = sensorData.temperature;
          if (sensorData.motionDetected) {
            deviceStates[currentDeviceId]!['lastMotionTime'] = readingTime;
            deviceStates[currentDeviceId]!['motionActive'] = true;
          } else {
            // Motion persists for a short time after detection
            final timeSinceMotion = readingTime.difference(deviceStates[currentDeviceId]!['lastMotionTime'] as DateTime);
            if (timeSinceMotion.inMinutes > 10) {
              deviceStates[currentDeviceId]!['motionActive'] = false;
            }
          }

          final docRef = _firestore.collection('sensor_logs').doc();
          // Convert to JSON and ensure timestamp is a Firestore Timestamp
          final jsonData = sensorData.toJson();
          jsonData['timestamp'] = Timestamp.fromDate(readingTime);
          writeBatch.set(docRef, jsonData);
          batchCount++;
          deviceGenerated++;
          totalGenerated++;
        }

        if (batchCount > 0) {
          await writeBatch.commit();
          if (batchIndex % 10 == 0 || batchIndex == totalBatches - 1) {
            Logger.info('   ✅ Device $currentDeviceId: batch ${batchIndex + 1}/$totalBatches (Total: $totalGenerated/$totalReadings)');
          }
        }
      }
    }

    Logger.success('✅ Test data generation complete!');
    Logger.info('   Generated $totalGenerated sensor readings across ${deviceIds.length} device(s)');
    Logger.info('   Time range: ${startTime.toString().substring(0, 16)} to ${now.toString().substring(0, 16)}');
    Logger.info('   📊 Data is ready for analytics and ML predictions!');
  }

  /// Generate realistic sensor data with daily patterns, weekend variations, and peak usage hours
  SensorData _generateRealisticSensorData({
    required DateTime timestamp,
    required String deviceId,
    required String userId,
    Map<String, dynamic>? deviceState,
  }) {
    final hour = timestamp.hour;
    final dayOfWeek = timestamp.weekday;
    final isWeekend = dayOfWeek == 6 || dayOfWeek == 7;
    
    final motionActive = deviceState?['motionActive'] as bool? ?? false;

    // ========== TEMPERATURE ==========
    // Base temperature varies by time of day (cooler at night, warmer during day)
    // Weekend: slightly higher base (more activity, less AC usage)
    final tempBase = isWeekend ? 23.0 : 22.0;
    
    // Daily cycle: peaks around 2-4 PM, lowest around 4-6 AM
    final hourOffset = (hour - 14) % 24; // Center around 2 PM
    final tempVariation = 4.0 * math.cos(2 * math.pi * hourOffset / 24);
    
    // Add some randomness and occasional spikes (hot days, cold nights)
    double tempNoise = _nextGaussian(stdDev: 1.5);
    // 5% chance of extreme values for testing edge cases
    if (_random.nextDouble() < 0.05) {
      tempNoise += _random.nextBool() ? 3.0 : -3.0;
    }
    
    double temp = (tempBase + tempVariation + tempNoise).clamp(16.0, 30.0);
    
    // Fan cooling effect: if fan was running, temperature should decrease slightly
    final lastFanSpeed = deviceState?['lastFanSpeed'] as int? ?? 0;
    if (lastFanSpeed > 0) {
      final coolingEffect = (lastFanSpeed / 255.0) * 0.5; // Max 0.5°C cooling
      temp = (temp - coolingEffect).clamp(16.0, 30.0);
    }

    // ========== HUMIDITY ==========
    // Inverse correlation with temperature, higher in morning/evening
    final humidityBase = 55.0 - (temp - 22.0) * 2.5;
    final humidityVariation = 12.0 * math.sin(2 * math.pi * (hour - 6) / 24);
    double humidity = (humidityBase + humidityVariation + _nextGaussian(stdDev: 5.0))
        .clamp(25.0, 75.0);
    
    // Fan reduces humidity slightly
    if (lastFanSpeed > 100) {
      humidity = (humidity - 2.0).clamp(25.0, 75.0);
    }

    // ========== MOTION ==========
    // More realistic motion patterns with peak hours
    double motionProbability;
    if (isWeekend) {
      // Weekend: later wake up, more activity throughout day
      if (hour >= 8 && hour <= 23) {
        motionProbability = 0.35;
      } else {
        motionProbability = 0.08;
      }
    } else {
      // Weekday: morning rush (6-9 AM), lunch (12-1 PM), evening (5-10 PM)
      if ((hour >= 6 && hour <= 9) || (hour >= 12 && hour <= 13) || (hour >= 17 && hour <= 22)) {
        motionProbability = 0.45; // Peak activity hours
      } else if (hour >= 10 && hour <= 11 || hour >= 14 && hour <= 16) {
        motionProbability = 0.25; // Moderate activity
      } else if (hour >= 7 && hour <= 23) {
        motionProbability = 0.15; // Low activity
      } else {
        motionProbability = 0.03; // Night (very low)
      }
    }
    
    // Motion can persist for a few minutes after detection
    bool motionDetected;
    if (motionActive && _random.nextDouble() < 0.7) {
      motionDetected = true; // 70% chance to continue if recently active
    } else {
      motionDetected = _random.nextDouble() < motionProbability;
    }

    // ========== FAN SPEED ==========
    // More sophisticated fan logic: responds to temperature with hysteresis
    int fanSpeed = 0;
    final targetTemp = 23.0; // Comfortable temperature
    
    if (temp > targetTemp + 1.5) {
      // Hot: fan runs at high speed
      final tempDiff = temp - (targetTemp + 1.5);
      fanSpeed = ((tempDiff / 5.0) * 255).round().clamp(100, 255);
    } else if (temp > targetTemp + 0.5) {
      // Warm: fan runs at medium speed
      final tempDiff = temp - (targetTemp + 0.5);
      fanSpeed = ((tempDiff / 1.0) * 150).round().clamp(50, 150);
    } else if (temp > targetTemp) {
      // Slightly warm: fan runs at low speed
      fanSpeed = ((temp - targetTemp) / 0.5 * 50).round().clamp(20, 50);
    }
    // Add some variation (not always perfect response)
    if (fanSpeed > 0 && _random.nextDouble() < 0.1) {
      fanSpeed = (fanSpeed * (0.8 + _random.nextDouble() * 0.4)).round().clamp(0, 255);
    }
    
    // Store for next iteration
    if (deviceState != null) {
      deviceState['lastFanSpeed'] = fanSpeed;
    }

    // ========== AMBIENT LIGHT LEVEL ==========
    // More realistic lighting patterns
    int ledBrightness = 0;
    
    // Base brightness on time of day
    if (hour >= 18 && hour <= 23) {
      // Evening: bright if motion, moderate otherwise
      ledBrightness = motionDetected ? (180 + _random.nextInt(40)) : (80 + _random.nextInt(40));
    } else if (hour >= 6 && hour < 18) {
      // Daytime: moderate if motion, low otherwise
      ledBrightness = motionDetected ? (120 + _random.nextInt(60)) : (30 + _random.nextInt(40));
    } else {
      // Night: very low, only if motion
      ledBrightness = motionDetected ? (40 + _random.nextInt(30)) : (5 + _random.nextInt(10));
    }
    
    // Weekend: slightly brighter (more relaxed, home more)
    if (isWeekend && hour >= 10 && hour <= 22) {
      ledBrightness = (ledBrightness * 1.1).round().clamp(0, 255);
    }
    
    ledBrightness = ledBrightness.clamp(0, 255);

    // ========== DISTANCE ==========
    // Distance correlates with motion: closer when motion detected
    double distance;
    if (motionDetected) {
      // Motion detected: object is closer (30-150 cm)
      distance = 30.0 + _random.nextDouble() * 120.0;
    } else {
      // No motion: object is farther (150-400 cm)
      distance = 150.0 + _random.nextDouble() * 250.0;
    }

    return SensorData(
      deviceId: deviceId,
      userId: userId,
      temperature: temp,
      humidity: humidity,
      fanSpeed: fanSpeed,
      ledBrightness: ledBrightness,
      motionDetected: motionDetected,
      distance: distance,
      securityEnabled: true,
      timestamp: timestamp,
    );
  }

  /// Clear all test data for current user
  /// Deletes all sensor logs in batches to handle large datasets
  Future<int> clearTestData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Logger.error('TestDataGenerator: No user logged in');
      throw StateError('User must be logged in to clear test data');
    }

    Logger.info('🗑️  Clearing all test sensor data for user: ${user.uid}');

    try {
      int totalDeleted = 0;
      const batchSize = 500; // Firestore batch limit
      bool hasMore = true;

      while (hasMore) {
        final snapshot = await _firestore
            .collection('sensor_logs')
            .where('userId', isEqualTo: user.uid)
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
        Logger.info('   Deleted batch: ${snapshot.docs.length} entries (Total: $totalDeleted)');

        // If we got fewer than batchSize, we're done
        if (snapshot.docs.length < batchSize) {
          hasMore = false;
        }
      }

      if (totalDeleted == 0) {
        Logger.info('   No test data found to clear');
      } else {
        Logger.success('✅ Cleared $totalDeleted sensor log entries');
      }

      return totalDeleted;
    } catch (e) {
      Logger.error('TestDataGenerator: Failed to clear test data: $e');
      rethrow;
    }
  }
}

