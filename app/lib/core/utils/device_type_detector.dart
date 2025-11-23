import 'logger.dart';
import '../../models/device_model.dart';
import '../../models/sensor_data.dart';

/// Utility class for automatically detecting device/appliance type
class DeviceTypeDetector {
  /// Detect device type from BLE advertisement name
  ///
  /// Supports patterns like:
  /// - "SmartSync-Fan"
  /// - "SmartSync-Light"
  /// - "SmartSync-Sensor"
  static DeviceType? detectFromName(String deviceName) {
    final name = deviceName.toLowerCase();

    if (name.contains('fan') || name.contains('ventilator')) {
      return DeviceType.fan;
    }
    if (name.contains('light') ||
        name.contains('led') ||
        name.contains('lamp')) {
      return DeviceType.light;
    }
    if (name.contains('ac') ||
        name.contains('air') ||
        name.contains('conditioner')) {
      return DeviceType.airConditioner;
    }
    if (name.contains('camera') || name.contains('cam')) {
      return DeviceType.camera;
    }
    if (name.contains('tv') || name.contains('television')) {
      return DeviceType.tv;
    }
    if (name.contains('vacuum') || name.contains('cleaner')) {
      return DeviceType.vacuum;
    }
    if (name.contains('sensor') ||
        name.contains('hub') ||
        name.contains('monitor')) {
      return DeviceType.sensor;
    }

    return null; // Could not detect from name
  }

  /// Detect device type from initial sensor data
  ///
  /// Analyzes the first sensor reading to infer device capabilities:
  /// - Fan devices typically have fan_speed > 0
  /// - Light devices typically have led_brightness > 0
  /// - Sensor hubs have both at 0 but active sensors
  static DeviceType? detectFromSensorData(SensorData sensorData) {
    final hasFan = sensorData.fanSpeed > 0;
    final hasLight = sensorData.ledBrightness > 0;
    final hasSensors = sensorData.temperature > 0 ||
        sensorData.humidity > 0 ||
        sensorData.motionDetected;

    // Priority: If both fan and light are active, prefer the one with higher value
    if (hasFan && hasLight) {
      // Prefer the one with higher value
      return sensorData.fanSpeed > sensorData.ledBrightness
          ? DeviceType.fan
          : DeviceType.light;
    }

    if (hasFan) {
      return DeviceType.fan;
    }

    if (hasLight) {
      return DeviceType.light;
    }

    // If only sensors are active, it's likely a sensor hub
    if (hasSensors) {
      return DeviceType.sensor;
    }

    return null; // Could not detect
  }

  /// Detect device type from device capabilities/status
  ///
  /// This would be called after requesting device status via GET_STATUS
  static DeviceType? detectFromCapabilities(Map<String, dynamic> status) {
    final hasFan = status['hasFan'] == true ||
        status['fanSpeed'] != null ||
        status['supportsFan'] == true;
    final hasLight = status['hasLight'] == true ||
        status['ledBrightness'] != null ||
        status['supportsLED'] == true;
    final hasSensors = status['hasSensors'] == true ||
        status['temperature'] != null ||
        status['humidity'] != null;

    if (hasFan && !hasLight) {
      return DeviceType.fan;
    }
    if (hasLight && !hasFan) {
      return DeviceType.light;
    }
    if (hasFan && hasLight) {
      // If both, prefer fan (most common SmartSync device)
      return DeviceType.fan;
    }
    if (hasSensors) {
      return DeviceType.sensor;
    }

    return null;
  }

  /// Comprehensive detection using all available methods
  ///
  /// Tries multiple detection methods in order of reliability:
  /// 1. BLE advertisement name
  /// 2. Initial sensor data (if available)
  /// 3. Device capabilities (if available)
  static DeviceType detectDeviceType({
    String? deviceName,
    SensorData? initialSensorData,
    Map<String, dynamic>? deviceStatus,
  }) {
    // Method 1: Try name-based detection
    if (deviceName != null) {
      final nameType = detectFromName(deviceName);
      if (nameType != null) {
        Logger.info(
            'DeviceTypeDetector: Detected ${nameType.name} from device name: $deviceName');
        return nameType;
      }
    }

    // Method 2: Try sensor data detection
    if (initialSensorData != null) {
      final sensorType = detectFromSensorData(initialSensorData);
      if (sensorType != null) {
        Logger.info(
            'DeviceTypeDetector: Detected ${sensorType.name} from sensor data');
        return sensorType;
      }
    }

    // Method 3: Try capabilities detection
    if (deviceStatus != null) {
      final capabilitiesType = detectFromCapabilities(deviceStatus);
      if (capabilitiesType != null) {
        Logger.info(
            'DeviceTypeDetector: Detected ${capabilitiesType.name} from device capabilities');
        return capabilitiesType;
      }
    }

    // Default fallback
    Logger.info(
        'DeviceTypeDetector: Could not auto-detect, defaulting to sensor');
    return DeviceType.sensor;
  }

  /// Get confidence level for detected type (0.0 to 1.0)
  static double getDetectionConfidence({
    String? deviceName,
    SensorData? initialSensorData,
    Map<String, dynamic>? deviceStatus,
  }) {
    int methodsUsed = 0;
    int methodsAgree = 0;
    DeviceType? detectedType;

    // Check name detection
    if (deviceName != null) {
      final nameType = detectFromName(deviceName);
      if (nameType != null) {
        methodsUsed++;
        detectedType = nameType;
        methodsAgree = 1;
      }
    }

    // Check sensor data detection
    if (initialSensorData != null) {
      final sensorType = detectFromSensorData(initialSensorData);
      if (sensorType != null) {
        methodsUsed++;
        if (detectedType == null) {
          detectedType = sensorType;
          methodsAgree = 1;
        } else if (detectedType == sensorType) {
          methodsAgree++;
        }
      }
    }

    // Check capabilities detection
    if (deviceStatus != null) {
      final capabilitiesType = detectFromCapabilities(deviceStatus);
      if (capabilitiesType != null) {
        methodsUsed++;
        if (detectedType == null) {
          detectedType = capabilitiesType;
          methodsAgree = 1;
        } else if (detectedType == capabilitiesType) {
          methodsAgree++;
        }
      }
    }

    if (methodsUsed == 0) return 0.0;
    return methodsAgree / methodsUsed;
  }
}
