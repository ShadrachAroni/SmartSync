// ignore_for_file: unused_field, unused_element
// These fields and methods are used but the analyzer doesn't detect usage across the large file
import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue;
import 'package:firebase_auth/firebase_auth.dart';
// DISABLED: BluetoothDataAnalyzer causes UI blocking
// import 'bluetooth_data_analyzer.dart';
import '../models/sensor_data.dart';
import '../models/schedule_model.dart';
import '../models/log_entry.dart';
import '../models/room_model.dart';
import '../core/constants/ble_constants.dart';
import '../core/utils/logger.dart';
import '../core/utils/error_diagnostics.dart';
// Removed: black_screen_diagnostic import (no longer needed)
import 'appliance_state_service.dart';
import 'firebase_service.dart';
import 'monitoring_service.dart';
import 'notification_service.dart';
import 'logging_service.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;

  flutter_blue.BluetoothDevice? _connectedDevice;
  flutter_blue.BluetoothCharacteristic? _rxCharacteristic;
  flutter_blue.BluetoothCharacteristic? _txCharacteristic;
  flutter_blue.BluetoothDevice? _lastConnectedDevice;
  StreamSubscription<flutter_blue.BluetoothConnectionState>?
      _connectionStateSub;
  StreamSubscription<List<int>>?
      _dataStreamSubscription; // Track data stream subscription

  Timer? _heartbeatTimer;
  Timer? _inactivityTimer;
  Timer? _sensorPollTimer;
  Timer? _keepaliveTimer; // Keepalive timer for connection stability
  bool _manualDisconnect = false;
  bool _isAutoReconnecting = false;
  bool _scanReconnectInProgress = false;
  bool _isConnecting = false; // CRITICAL: Prevent simultaneous connection attempts
  DateTime? _lastCommunicationTime;
  DateTime? _connectionEstablishedTime; // Track when connection was established
  bool _connectionGracePeriodActive = false; // Grace period after connection
  int _connectionFailureCount = 0; // Track consecutive connection failures for auto-shutdown
  static const int _maxConnectionFailures = 3; // Auto-shutdown after 3 consecutive failures

  // Data handling and buffering
  final List<int> _dataBuffer = [];
  DateTime? _lastDataReceivedTime;
  int _totalPacketsReceived = 0;
  int _totalPacketsProcessed = 0;
  int _totalPacketsDropped = 0;
  int _totalParseErrors = 0;
  // ignore: unused_field - Used in buffer size checks (lines 1390, 1412)
  static const int _maxBufferSize = 1024; // Max buffer size (1KB)
  // ignore: unused_field - Used in buffer timeout timer (line 1334)
  static const Duration _bufferTimeout =
      Duration(seconds: 2); // Clear buffer if no data for 2s
  Timer? _bufferTimeoutTimer;
  // ignore: unused_field - Used throughout for failure tracking
  int _consecutiveDecodeFailures = 0; // Track consecutive decode failures
  // ignore: unused_field - Used in failure threshold check (line 1467)
  static const int _maxConsecutiveFailures =
      5; // Clear buffer after 5 consecutive failures
  // ignore: unused_field - Used throughout for binary packet tracking
  int _consecutiveBinaryPackets = 0; // Track consecutive binary packets
  // ignore: unused_field - Used in circuit breaker check (line 1365)
  static const int _maxConsecutiveBinaryPackets =
      3; // Circuit breaker: stop processing after 3 consecutive binary packets
  // ignore: unused_field - Used in circuit breaker logic (lines 1343, 1366, etc.)
  bool _binaryDataCircuitBreaker =
      false; // Circuit breaker flag to stop processing binary data

  // Rate limiting and throttling for UI protection
  // ignore: unused_field - Used in throttling logic (lines 1304, 1305, 1312)
  DateTime? _lastDataProcessTime;
  // ignore: unused_field - Used in throttling window check (line 1306)
  static const Duration _dataThrottleWindow =
      Duration(milliseconds: 100); // Process max once per 100ms
  int _pendingPackets = 0; // Track pending packets in queue
  static const int _maxPendingPackets = 10; // Increased to allow more packets in queue
  DateTime? _lastWriteTime; // Track last write time to prevent rapid writes

  final StreamController<SensorData> _sensorDataController =
      StreamController<SensorData>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<String> _statusMessageController =
      StreamController<String>.broadcast();
  final StreamController<DateTime?> _activityController =
      StreamController<DateTime?>.broadcast();
  final LoggingService _loggingService = LoggingService();

  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get statusMessages => _statusMessageController.stream;
  Stream<DateTime?> get activityStream => _activityController.stream;
  bool get isConnected => _connectedDevice != null;
  bool get canReconnect => _lastConnectedDevice != null;
  String? get connectedDeviceId => _connectedDevice?.remoteId.toString();
  DateTime? get lastCommunicationTime => _lastCommunicationTime;

  // Data statistics getters
  int get totalPacketsReceived => _totalPacketsReceived;
  int get totalPacketsProcessed => _totalPacketsProcessed;
  int get totalPacketsDropped => _totalPacketsDropped;
  int get totalParseErrors => _totalParseErrors;
  double get packetSuccessRate {
    if (_totalPacketsReceived == 0) return 1.0;
    return _totalPacketsProcessed / _totalPacketsReceived;
  }

  // Connection health check
  bool get isConnectionHealthy {
    if (!isConnected) return false;
    if (_lastDataReceivedTime == null) return false;

    final timeSinceLastData = DateTime.now().difference(_lastDataReceivedTime!);
    // Consider unhealthy if no data received in last 60 seconds
    return timeSinceLastData.inSeconds < 60;
  }

  // Get connection health details
  Map<String, dynamic> getConnectionHealth() {
    return {
      'isConnected': isConnected,
      'isHealthy': isConnectionHealthy,
      'lastDataReceived': _lastDataReceivedTime?.toIso8601String(),
      'timeSinceLastData': _lastDataReceivedTime != null
          ? DateTime.now().difference(_lastDataReceivedTime!).inSeconds
          : null,
      'totalPacketsReceived': _totalPacketsReceived,
      'totalPacketsProcessed': _totalPacketsProcessed,
      'totalPacketsDropped': _totalPacketsDropped,
      'totalParseErrors': _totalParseErrors,
      'packetSuccessRate': packetSuccessRate,
      'bufferSize': _dataBuffer.length,
    };
  }

  BluetoothService._internal() {
    // Initialize stream controllers - they're final fields so already initialized
    // Don't emit initial state here to avoid any potential initialization issues
    // Initial state will be emitted when first accessed
  }

  /// Get the first sensor data reading (useful for device type detection)
  /// Returns null if no data is received within the timeout
  Future<SensorData?> getFirstSensorData({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      return await sensorDataStream.timeout(timeout).first;
    } catch (e) {
      Logger.warning('BluetoothService: Could not get first sensor data: $e');
      return null;
    }
  }

  // Scan for devices
  Future<List<flutter_blue.BluetoothDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Logger.info('Starting BLE scan...');
    _emitStatus('Scan started. Ensuring Bluetooth is ready...');
    List<flutter_blue.BluetoothDevice> devices = [];
    final Set<String> seenDeviceIds =
        {}; // Track devices by ID to avoid duplicates
    int totalDevicesScanned = 0; // For diagnostics

    try {
      await _ensureBluetoothReady();

      // Enhanced: Try UUID/GUID filtering, but don't rely solely on it
      // Some devices don't advertise service UUID in scan response (only after connection)
      // So we scan without filter first, then match manually for better device discovery
      final serviceUuid = flutter_blue.Guid(BLEConstants.serviceUUID);
      
      // Start scanning WITHOUT service UUID filter to catch all devices
      // We'll filter manually in the results (more reliable for devices that don't advertise UUID)
      await flutter_blue.FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
        // Removed withServices filter - some ESP32 devices don't advertise UUID in scan
        // Manual filtering in results is more reliable
      );

      // Listen to scan results
      final subscription =
          flutter_blue.FlutterBluePlus.scanResults.listen((results) {
        for (flutter_blue.ScanResult result in results) {
          totalDevicesScanned++;
          final deviceId = result.device.remoteId.toString();
          final deviceName = result.device.advName;
          final rssi = result.rssi;

          // Log all discovered devices for debugging (only first time we see them)
          if (!seenDeviceIds.contains(deviceId)) {
            seenDeviceIds.add(deviceId);

            // Enhanced diagnostic logging
            try {
              final advData = result.advertisementData;
              final serviceUuids =
                  advData.serviceUuids.map((u) => u.toString()).toList();
              final manufacturerData = advData.manufacturerData;

              Logger.info(
                '🔍 Discovered BLE device: name="$deviceName", id=$deviceId, rssi=$rssi',
              );

              // Enhanced logging: Show all service UUIDs for debugging
              if (serviceUuids.isNotEmpty) {
                Logger.info(
                  '  📋 Service UUIDs (${serviceUuids.length}): ${serviceUuids.join(", ")}',
                );
                // Check if any match our target
                final targetUuid = BLEConstants.serviceUUID.toLowerCase();
                bool hasMatch = false;
                for (final uuid in serviceUuids) {
                  if (uuid.toLowerCase() == targetUuid ||
                      uuid.toLowerCase().replaceAll('-', '') == targetUuid.replaceAll('-', '')) {
                    hasMatch = true;
                    Logger.info('  ✅ MATCHES SmartSync UUID!');
                    break;
                  }
                }
                if (!hasMatch) {
                  Logger.info('  ⚠️ No SmartSync UUID match. Looking for: ${BLEConstants.serviceUUID}');
                }
              } else {
                Logger.info('  ⚠️ No service UUIDs in advertisement (common for ESP32)');
              }

              if (manufacturerData.isNotEmpty) {
                Logger.info(
                  '  🏭 Manufacturer data: ${manufacturerData.length} bytes, IDs: ${manufacturerData.keys.join(", ")}',
                );
                // Check for ESP32 manufacturer ID
                for (final id in manufacturerData.keys) {
                  if (id == 0x02E5 || id == 741) {
                    Logger.info('  ✅ ESP32 device detected (manufacturer ID: $id)');
                  }
                }
              } else {
                Logger.info('  ℹ️ No manufacturer data');
              }

              // Check if any service UUID matches
              bool hasMatchingService = false;
              for (final uuid in serviceUuids) {
                if (uuid.toLowerCase() ==
                    BLEConstants.serviceUUID.toLowerCase()) {
                  hasMatchingService = true;
                  Logger.info(
                    '  ✅ Found matching service UUID: $uuid',
                  );
                  break;
                }
              }

              if (!hasMatchingService && serviceUuids.isNotEmpty) {
            Logger.debug(
                  '  ⚠️ No matching service UUID. Looking for: ${BLEConstants.serviceUUID}',
            );
              }
            } catch (e) {
              Logger.debug('Error analyzing advertisement data: $e');
            }
          }

          // Check if device matches SmartSync criteria
          bool isSmartSyncDevice = false;
          String matchReason = '';

          // Method 1: Enhanced UUID/GUID matching (highest priority - most reliable)
          // This is the most effective method as it matches the exact service UUID
          try {
            final advData = result.advertisementData;
            final targetUuid = BLEConstants.serviceUUID.toLowerCase();
            
            // Check all service UUIDs in advertisement data
            if (advData.serviceUuids.isNotEmpty) {
              for (final uuid in advData.serviceUuids) {
                final uuidString = uuid.toString().toLowerCase();
                
                // Exact match (most reliable)
                if (uuidString == targetUuid) {
                  isSmartSyncDevice = true;
                  matchReason = 'service UUID (exact match)';
                  break;
                }
                
                // Partial match (handle UUID format variations)
                // Remove dashes and compare
                final uuidNoDashes = uuidString.replaceAll('-', '');
                final targetNoDashes = targetUuid.replaceAll('-', '');
                if (uuidNoDashes == targetNoDashes) {
                  isSmartSyncDevice = true;
                  matchReason = 'service UUID (format variant)';
                  break;
                }
              }
            }
            
            // Also check service data for UUID matches
            if (!isSmartSyncDevice && advData.serviceData.isNotEmpty) {
              for (final entry in advData.serviceData.entries) {
                final uuidString = entry.key.toString().toLowerCase();
                if (uuidString == targetUuid ||
                    uuidString.replaceAll('-', '') == targetUuid.replaceAll('-', '')) {
                  isSmartSyncDevice = true;
                  matchReason = 'service UUID (in service data)';
                  break;
                }
              }
            }
          } catch (e) {
            Logger.debug('Error checking service UUIDs: $e');
          }

          // Method 2: Check device name (fallback)
          if (!isSmartSyncDevice && deviceName.isNotEmpty) {
            if (deviceName.startsWith(BLEConstants.deviceNamePrefix)) {
              isSmartSyncDevice = true;
              matchReason = 'device name';
            }
          }

          // Method 3: Check if device name contains SmartSync (case-insensitive fallback)
          if (!isSmartSyncDevice && deviceName.isNotEmpty) {
            if (deviceName.toLowerCase().contains(
                  BLEConstants.deviceNamePrefix.toLowerCase(),
                )) {
              isSmartSyncDevice = true;
              matchReason = 'device name (partial match)';
            }
          }

          // Method 4: Enhanced detection - ESP32 devices often have empty names
          // Check for ESP32 by manufacturer data or MAC address pattern
          if (!isSmartSyncDevice) {
            try {
              final advData = result.advertisementData;
              // ESP32 devices often have manufacturer data starting with 0x02E5 (Espressif)
              if (advData.manufacturerData.isNotEmpty) {
                final manufacturerId = advData.manufacturerData.keys.first;
                // Espressif manufacturer ID is 0x02E5 (741 in decimal)
                if (manufacturerId == 0x02E5 || manufacturerId == 741) {
                  // Enhanced: Check if manufacturer data contains SmartSync-specific patterns
                  // SmartSync hubs typically have custom service UUIDs in manufacturer data
                  final mfgData = advData.manufacturerData[manufacturerId];
                  bool hasSmartSyncPattern = false;
                  
                  // Check if manufacturer data contains any custom service UUID patterns
                  // (Some ESP32 devices embed service UUID in manufacturer data)
                  if (mfgData != null && mfgData.length >= 2) {
                    // Look for patterns that might indicate SmartSync hub
                    // ESP32 SmartSync hubs typically advertise with specific data patterns
                    hasSmartSyncPattern = true; // Assume ESP32 with manufacturer data is potential SmartSync
                  }
                  
                  // Likely ESP32 - include if RSSI is reasonable and has advertisement data
                  if (rssi > -90 && (hasSmartSyncPattern || advData.serviceUuids.isNotEmpty || advData.serviceData.isNotEmpty)) {
                    isSmartSyncDevice = true;
                    matchReason = 'ESP32 device (manufacturer ID + advertisement data)';
                    Logger.info('  ✅ ESP32 detected with manufacturer ID: $manufacturerId (RSSI: $rssi)');
                  }
                }
              }
            } catch (e) {
              Logger.debug('Error checking manufacturer data: $e');
            }
          }

          // Method 5: Enhanced - Include devices with empty names if they have reasonable RSSI
          // (ESP32 devices often don't advertise names or service UUIDs properly)
          // Prioritize devices that look like SmartSync hubs based on advertisement patterns
          if (!isSmartSyncDevice && deviceName.isEmpty && rssi > -85) {
            // Check if device has any service UUIDs or manufacturer data (indicates it's advertising)
            try {
              final advData = result.advertisementData;
              
              // Enhanced: Check for SmartSync-specific patterns
              bool hasCustomServices = advData.serviceUuids.isNotEmpty;
              bool hasManufacturerData = advData.manufacturerData.isNotEmpty;
              bool hasServiceData = advData.serviceData.isNotEmpty;
              
              // Prioritize devices with custom services (more likely to be SmartSync hub)
              if (hasCustomServices) {
                // Check if any service UUID looks like a custom UUID (not standard BLE)
                final standardServices = ['1800', '1801', '180a', '180f', '181a'];
                bool hasNonStandardService = false;
                for (final uuid in advData.serviceUuids) {
                  final uuidStr = uuid.toString().toLowerCase();
                  bool isStandard = false;
                  for (final std in standardServices) {
                    if (uuidStr.contains(std.toLowerCase())) {
                      isStandard = true;
                      break;
                    }
                  }
                  if (!isStandard) {
                    hasNonStandardService = true;
                    break;
                  }
                }
                
                if (hasNonStandardService) {
                  isSmartSyncDevice = true;
                  matchReason = 'unnamed BLE device with custom services (potential SmartSync hub)';
                  Logger.info(
                    '  ✅ Including unnamed device with custom services (RSSI: $rssi) - likely SmartSync hub',
                  );
                } else if (hasManufacturerData || hasServiceData) {
                  // Fallback: Include if it has manufacturer data or service data
                  isSmartSyncDevice = true;
                  matchReason = 'unnamed BLE device (potential ESP32 - no UUID in scan)';
                  Logger.info(
                    '  ℹ️ Including unnamed device (RSSI: $rssi) - may need connection to discover UUID',
                  );
                }
              } else if (hasManufacturerData || hasServiceData) {
                // Include if it has manufacturer data or service data (indicates active BLE device)
                isSmartSyncDevice = true;
                matchReason = 'unnamed BLE device (potential ESP32 - no UUID in scan)';
                Logger.info(
                  '  ℹ️ Including unnamed device (RSSI: $rssi) - may need connection to discover UUID',
                );
              }
            } catch (e) {
              Logger.debug('Error checking advertisement data: $e');
            }
          }
          
          // Method 6: Very lenient fallback - include any device with reasonable signal
          // This helps when device doesn't advertise properly but is actually a SmartSync device
          // Enhanced: Be more selective to reduce false positives
          if (!isSmartSyncDevice && rssi > -80) {
            // Only if we haven't matched by any other method and signal is strong
            // This is a last resort to catch devices that don't advertise correctly
            try {
              final advData = result.advertisementData;
              
              // Enhanced: Prioritize devices with actual advertisement data
              // Don't include devices with only txPowerLevel (too generic)
              bool hasRealAdvertisement = advData.serviceUuids.isNotEmpty || 
                  advData.manufacturerData.isNotEmpty ||
                  advData.serviceData.isNotEmpty;
              
              if (hasRealAdvertisement) {
                // Additional check: If it has manufacturer data, verify it's not a common device type
                if (advData.manufacturerData.isNotEmpty) {
                  final mfgId = advData.manufacturerData.keys.first;
                  // Include ESP32 devices (0x02E5) or devices with custom services
                  if (mfgId == 0x02E5 || mfgId == 741 || advData.serviceUuids.isNotEmpty) {
                    isSmartSyncDevice = true;
                    matchReason = 'strong signal BLE device with advertisement data (potential SmartSync hub)';
                    Logger.info(
                      '  ⚠️ Including device with strong signal and advertisement data (RSSI: $rssi) - verify manually',
                    );
                  }
                } else if (advData.serviceUuids.isNotEmpty) {
                  // Has services but no manufacturer data - likely a custom device
                  isSmartSyncDevice = true;
                  matchReason = 'strong signal BLE device with custom services (potential SmartSync hub)';
                  Logger.info(
                    '  ⚠️ Including device with strong signal and custom services (RSSI: $rssi) - verify manually',
                  );
                }
              }
            } catch (e) {
              Logger.debug('Error in fallback matching: $e');
            }
          }

          // Add device if it matches and not already in list
          if (isSmartSyncDevice) {
            // Check if device is already in list by ID
            final existingIndex = devices.indexWhere(
              (d) => d.remoteId.toString() == deviceId,
            );

            if (existingIndex == -1) {
              devices.add(result.device);
              Logger.info(
                '✅ Found SmartSync device: "$deviceName" (ID: $deviceId, RSSI: $rssi, matched by: $matchReason)',
              );
            } else {
              // Device already in list, log update if RSSI improved
              Logger.debug(
                'Updated device info for "$deviceName" (RSSI: $rssi)',
              );
            }
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(timeout);
      await subscription.cancel();
      await flutter_blue.FlutterBluePlus.stopScan();

      Logger.info(
        'Scan complete. Found ${devices.length} SmartSync device(s) out of $totalDevicesScanned total BLE device(s) scanned',
      );
      _emitStatus(
        'Scan finished. Found ${devices.length} SmartSync device(s).',
      );

      // Log diagnostic information if no devices found
      if (devices.isEmpty) {
        Logger.warning(
          '⚠️ No SmartSync devices found. Scanned $totalDevicesScanned BLE device(s).',
        );
        Logger.info(
          '💡 TIP: If your device is nearby but not found:',
        );
        Logger.info(
          '   1. Device may not advertise service UUID in scan (common with ESP32)',
        );
        Logger.info(
          '   2. Try connecting manually to any unnamed device with strong signal',
        );
        Logger.info(
          '   3. Service UUID may only be discoverable after connection',
        );
        Logger.info(
          '   4. Use "Scan All Devices" option to see all BLE devices',
        );
        _emitStatus(
          'No SmartSync devices found. Try connecting to unnamed devices manually.',
        );
      }

      return devices;
    } catch (e) {
      Logger.error('Scan error: $e');
      _emitStatus('Scan failed: $e');
      await flutter_blue.FlutterBluePlus.stopScan();
      rethrow;
    }
  }

  // Enhanced scan: Returns all BLE devices (not just SmartSync) for manual connection
  Future<List<flutter_blue.BluetoothDevice>> scanForAllDevices({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Logger.info('Starting enhanced BLE scan (all devices)...');
    _emitStatus('Scanning for all BLE devices...');
    List<flutter_blue.BluetoothDevice> devices = [];
    final Set<String> seenDeviceIds = {};
    int totalDevicesScanned = 0;

    try {
      await _ensureBluetoothReady();

      // For all-device scan, don't filter by UUID to show everything
      await flutter_blue.FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );

      final subscription =
          flutter_blue.FlutterBluePlus.scanResults.listen((results) {
        for (flutter_blue.ScanResult result in results) {
          totalDevicesScanned++;
          final deviceId = result.device.remoteId.toString();

          if (!seenDeviceIds.contains(deviceId)) {
            seenDeviceIds.add(deviceId);
            devices.add(result.device);
            Logger.debug(
              'Found BLE device: name="${result.device.advName}", id=$deviceId, rssi=${result.rssi}',
            );
          }
        }
      });

      await Future.delayed(timeout);
      await subscription.cancel();
      await flutter_blue.FlutterBluePlus.stopScan();

      Logger.info(
        'Enhanced scan complete. Found ${devices.length} BLE device(s)',
      );
      _emitStatus('Found ${devices.length} BLE device(s)');

      return devices;
    } catch (e) {
      Logger.error('Enhanced scan error: $e');
      _emitStatus('Enhanced scan failed: $e');
      await flutter_blue.FlutterBluePlus.stopScan();
      rethrow;
    }
  }

  // Connect to device
  Future<bool> connectToDevice(flutter_blue.BluetoothDevice device,
      {bool isReconnect = false}) async {
    // CRITICAL: Prevent simultaneous connection attempts
    if (_isConnecting) {
      Logger.warning('BluetoothService: Connection already in progress, ignoring duplicate request');
      return false;
    }

    _isConnecting = true;
    
    try {
      await _ensureBluetoothReady();
      _manualDisconnect = false;
      final action = isReconnect ? 'Reconnecting' : 'Connecting';
      Logger.info('$action to ${device.advName}...');
      _emitStatus('$action to ${device.advName}...');

      // CRITICAL: If connecting to a different device, disconnect current one first
      if (_connectedDevice != null && _connectedDevice!.remoteId != device.remoteId) {
        Logger.info('BluetoothService: Switching devices - disconnecting current device first');
        try {
          await _teardownConnection(
            manual: false,
            unexpected: false,
            deviceName: _connectedDevice!.advName,
            suppressNotification: true,
          );
          // Wait for cleanup to complete
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          Logger.warning('BluetoothService: Error disconnecting previous device: $e');
        }
      }

      // CRITICAL: Ensure any previous connection is properly closed before attempting new connection
      // This is especially important for status 133 errors (GATT connection failed)
      try {
        // Force disconnect if device shows as connected
        if (device.isConnected) {
          Logger.info('Device already connected, force disconnecting first...');
          try {
            await device.disconnect();
            // Wait longer for disconnect to fully complete
            await Future.delayed(const Duration(milliseconds: 1000));
          } catch (e) {
            Logger.warning('Error disconnecting existing connection: $e');
          }
        }
        
        // Additional check: Try to disconnect via flutter_blue_plus if needed
        try {
          final connectionState = await device.connectionState.first.timeout(
            const Duration(seconds: 2),
            onTimeout: () => flutter_blue.BluetoothConnectionState.disconnected,
          );
          if (connectionState == flutter_blue.BluetoothConnectionState.connected) {
            Logger.info('Device connection state shows connected, force disconnecting...');
            await device.disconnect();
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        } catch (e) {
          Logger.debug('Error checking connection state: $e');
        }
      } catch (e) {
        Logger.debug('Error checking/disconnecting existing connection: $e');
      }

      // Note: autoConnect and MTU are incompatible in flutter_blue_plus
      // When reconnecting, don't use autoConnect to avoid assertion error
      // Increased timeout and added better error handling with multiple retry strategies
      bool connectionSuccess = false;
      int retryAttempt = 0;
      const maxRetries = 3;
      
      while (!connectionSuccess && retryAttempt < maxRetries) {
        try {
          Logger.info('BluetoothService: Connection attempt ${retryAttempt + 1}/$maxRetries');
          
          // For ESP32, use longer timeout on first attempt, shorter on retries
          final timeout = retryAttempt == 0 
              ? BLEConstants.bleConnectionTimeout 
              : const Duration(seconds: 20);
          
          await device.connect(
            license: flutter_blue.License.free,
            timeout: timeout,
            autoConnect: false, // Always false to avoid MTU incompatibility
          );
          
          connectionSuccess = true;
          Logger.info('BluetoothService: Connection successful on attempt ${retryAttempt + 1}');
        } catch (connectError) {
          retryAttempt++;
          final errorString = connectError.toString();
          
          // Handle status 133 (GATT connection failed) specifically
          if (errorString.contains('133') || 
              errorString.contains('GATT') ||
              errorString.contains('status=133')) {
            Logger.warning('GATT error 133 detected on attempt $retryAttempt, attempting recovery...');
            
            // Force disconnect and wait before retry
            try {
              await device.disconnect();
              // Longer wait for GATT errors
              await Future.delayed(Duration(milliseconds: 2000 + (retryAttempt * 1000)));
            } catch (e) {
              Logger.debug('Error during recovery disconnect: $e');
            }
            
            // Continue to retry if we haven't exceeded max retries
            if (retryAttempt < maxRetries) {
              Logger.info('Retrying connection after GATT error recovery (attempt ${retryAttempt + 1})...');
              continue;
            }
          } else if (errorString.contains('timeout') || errorString.contains('Timed out')) {
            Logger.warning('Connection timeout on attempt $retryAttempt');
            
            // For timeout, try force disconnect and retry
            if (retryAttempt < maxRetries) {
              try {
                await device.disconnect();
                await Future.delayed(Duration(milliseconds: 1000 + (retryAttempt * 500)));
              } catch (e) {
                Logger.debug('Error during timeout recovery: $e');
              }
              Logger.info('Retrying connection after timeout (attempt ${retryAttempt + 1})...');
              continue;
            }
          }
          
          // If we've exhausted retries or it's a non-retryable error, rethrow
          if (retryAttempt >= maxRetries) {
            Logger.error('BluetoothService: Connection failed after $maxRetries attempts');
            rethrow;
          }
        }
      }
      
      if (!connectionSuccess) {
        throw Exception('Connection failed after $maxRetries attempts');
      }

      // CRITICAL: Clear previous device state before setting new connection
      // This ensures no stale data from previous hub connections
      await _clearPreviousDeviceState(device.remoteId.toString());
      
      _connectedDevice = device;
      _lastConnectedDevice = device;
      _connectionFailureCount = 0; // Reset failure count on successful connection
      _connectionEstablishedTime = DateTime.now(); // Track connection time
      _connectionGracePeriodActive = true; // Enable grace period
      _emitConnectionState(true);
      
      // Start grace period timer - don't monitor disconnections immediately after connection
      Timer(BLEConstants.connectionGracePeriod, () {
        _connectionGracePeriodActive = false;
        Logger.info('BluetoothService: Connection grace period ended, monitoring active');
      });
      
      _registerConnectionMonitor(device);

      // Discover services - CRITICAL: Must discover services before using characteristics
      print('🔍 [DEBUG] Starting service discovery...');
      Logger.info('🔍 Starting service discovery...');
      List<flutter_blue.BluetoothService> services;
      try {
        services = await device.discoverServices().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            Logger.error('Service discovery timed out after 10 seconds');
            throw TimeoutException('Service discovery timed out');
          },
        );
        print('🔍 [DEBUG] Service discovery completed: ${services.length} service(s) found');
        Logger.info('🔍 Service discovery completed: ${services.length} service(s) found');
      } catch (e, stackTrace) {
        Logger.error('🔍 [DEBUG] Service discovery failed: $e', e, stackTrace);
        print('🔍 [DEBUG] Service discovery exception: $e');
        print('🔍 [DEBUG] Stack trace: $stackTrace');
        rethrow;
      }

      // Enhanced: Log all discovered services for debugging (ALWAYS with print)
      print('📋 [BLE] ========== SERVICE DISCOVERY ==========');
      print('📋 [BLE] Discovered ${services.length} service(s) on device');
      Logger.info('📋 Discovered ${services.length} service(s) on device:');
      final targetServiceUuid = BLEConstants.serviceUUID.toLowerCase();
      bool foundSmartSyncService = false;
      final List<String> allServiceUuids = [];
      
      for (var service in services) {
        final serviceUuid = service.uuid.toString();
        final serviceUuidLower = serviceUuid.toLowerCase();
        Logger.info('  🔹 Service: $serviceUuid (${service.characteristics.length} characteristics)');
        
        // Check if this is the SmartSync service (case-insensitive, handle format variations)
        if (serviceUuidLower == targetServiceUuid ||
            serviceUuidLower.replaceAll('-', '') == targetServiceUuid.replaceAll('-', '')) {
          foundSmartSyncService = true;
          print('  ✅ [BLE] FOUND SmartSync service! UUID: $serviceUuid');
          Logger.info('  ✅ FOUND SmartSync service!');
        }
        
        // Log all characteristics in this service
        for (var char in service.characteristics) {
          final charUuid = char.uuid.toString();
          print('    - [BLE] Characteristic: $charUuid');
          Logger.debug('    - Characteristic: $charUuid');
        }
      }
      
      print('📋 [BLE] All service UUIDs: ${allServiceUuids.join(", ")}');
      print('📋 [BLE] Looking for: ${BLEConstants.serviceUUID}');
      print('📋 [BLE] =========================================');

      // Find SmartSync service (with improved matching)
      for (var service in services) {
        final serviceUuid = service.uuid.toString();
        final serviceUuidLower = serviceUuid.toLowerCase();
        final targetUuidLower = BLEConstants.serviceUUID.toLowerCase();
        
        // Enhanced matching: case-insensitive and handle format variations
        bool matches = serviceUuidLower == targetUuidLower ||
            serviceUuidLower.replaceAll('-', '') == targetUuidLower.replaceAll('-', '');
        
        if (matches) {
          Logger.info('✅ Found SmartSync service: $serviceUuid');

          // Enhanced: Log all characteristics and match with improved logic
          Logger.info('  📋 Checking ${service.characteristics.length} characteristic(s)...');
          final targetRxUuid = BLEConstants.rxCharacteristicUUID.toLowerCase();
          final targetTxUuid = BLEConstants.txCharacteristicUUID.toLowerCase();

          for (var characteristic in service.characteristics) {
            final charUuid = characteristic.uuid.toString();
            final charUuidLower = charUuid.toLowerCase();
            
            // Enhanced RX characteristic matching
            if (charUuidLower == targetRxUuid ||
                charUuidLower.replaceAll('-', '') == targetRxUuid.replaceAll('-', '')) {
              _rxCharacteristic = characteristic;
              Logger.info('  ✅ Found RX characteristic: $charUuid');
            }
            
            // Enhanced TX characteristic matching
            if (charUuidLower == targetTxUuid ||
                charUuidLower.replaceAll('-', '') == targetTxUuid.replaceAll('-', '')) {
              _txCharacteristic = characteristic;
              Logger.info('  ✅ Found TX characteristic: $charUuid');

              // Re-enabled: BLE data stream subscription
              Logger.info('Enabling BLE data stream subscription');
              print('🔍 [DEBUG] Enabling BLE data stream subscription');
              try {
                // CRITICAL: Ensure characteristic is valid before subscribing
                if (_txCharacteristic == null) {
                  throw Exception('TX characteristic is null - cannot enable notifications');
                }
                
                // CRITICAL: Cancel existing subscription first to prevent leaks
                await _dataStreamSubscription?.cancel();
                _dataStreamSubscription = null;
                print('🔍 [DEBUG] Previous subscription cancelled');
                
                // CRITICAL: Set notify value with timeout
                await _txCharacteristic!.setNotifyValue(true).timeout(
                  const Duration(seconds: 5),
                  onTimeout: () {
                    throw TimeoutException('setNotifyValue timed out after 5 seconds');
                  },
                );
                print('🔍 [DEBUG] setNotifyValue(true) completed');
                
                // CRITICAL: Create stream subscription with comprehensive error handling
                _dataStreamSubscription = _txCharacteristic!.value.listen(
                  (data) {
                    // CRITICAL: Wrap handler in try-catch to prevent stream errors from crashing
                    try {
                      // Record activity when data is received
                      _lastDataReceivedTime = DateTime.now();
                      _recordActivity(); // Restart inactivity watchdog
                      _handleIncomingData(data);
                    } catch (e, stackTrace) {
                      // CRITICAL: Never let handler errors crash the stream
                      Logger.error('🔍 [DEBUG] Error in BLE data handler: $e', e, stackTrace);
                      print('🔍 [DEBUG] BLE data handler exception: $e');
                      _totalParseErrors++;
                    }
                  },
                  onError: (error, stackTrace) {
                    // CRITICAL: Handle stream errors gracefully
                    print('🔍 [DEBUG] BLE data stream error: $error');
                    Logger.error('BLE data stream error: $error', error, stackTrace);
                    _totalParseErrors++;
                    
                    // CRITICAL: Don't cancel stream on error - let it continue
                    // The stream will automatically recover if possible
                    // Don't trigger disconnect on stream errors - they're often recoverable
                  },
                  cancelOnError: false, // CRITICAL: Don't cancel on error - keep stream alive
                  onDone: () {
                    print('🔍 [DEBUG] BLE data stream completed');
                    Logger.warning('BLE data stream completed - this may indicate disconnection');
                    // Only trigger disconnect if stream completes AND we're not in grace period
                    if (!_connectionGracePeriodActive && _connectedDevice != null) {
                      Future.delayed(const Duration(seconds: 2), () {
                        if (_connectedDevice != null && !_manualDisconnect) {
                          Logger.warning('Data stream ended, checking connection...');
                          // Verify connection state before disconnecting
                        }
                      });
                    }
                  },
                );
                print('🔍 [DEBUG] BLE data stream subscription created');
                Logger.info('✅ BLE data stream subscription active - ready to receive sensor data');
              } catch (e, stackTrace) {
                Logger.error('🔍 [DEBUG] Error setting up BLE data stream: $e', e, stackTrace);
                print('🔍 [DEBUG] BLE data stream setup exception: $e');
                print('🔍 [DEBUG] Stack trace: $stackTrace');
                // CRITICAL: Don't fail connection if stream setup fails - connection can still work
                Logger.warning('BLE data stream setup failed, but connection will continue');
              }

              // Reset data statistics for new connection
              _resetDataStatistics();
            }
          }
          break;
        }
      }

      // Fallback: If SmartSync service not found, try to use any custom service
      // This helps when firmware UUIDs don't match expected values
      if (_rxCharacteristic == null || _txCharacteristic == null) {
        print('⚠️ [BLE] SmartSync service not found, trying fallback to custom services...');
        Logger.warning('SmartSync service not found, attempting fallback connection');
        
        // Try to find any custom service (not standard BLE services: 1800, 1801, 180a, etc.)
        final standardServices = ['1800', '1801', '180a', '180f', '181a'];
        flutter_blue.BluetoothCharacteristic? fallbackRx;
        flutter_blue.BluetoothCharacteristic? fallbackTx;
        final List<flutter_blue.BluetoothService> customServices = [];
        
        // First pass: collect all custom services
        for (var service in services) {
          final serviceUuid = service.uuid.toString().toLowerCase();
          // Skip standard BLE services
          bool isStandard = false;
          for (final std in standardServices) {
            if (serviceUuid.contains(std.toLowerCase())) {
              isStandard = true;
              break;
            }
          }
          
          if (!isStandard && service.characteristics.isNotEmpty) {
            customServices.add(service);
            print('  🔄 [BLE] Found custom service: ${service.uuid.toString()} (${service.characteristics.length} chars)');
          }
        }
        
        // Second pass: find RX and TX characteristics across all custom services
        for (var service in customServices) {
          for (var char in service.characteristics) {
            final props = char.properties;
            final charUuid = char.uuid.toString();
            
            // TX: has notify/indicate property (for receiving data from device)
            if ((props.notify || props.indicate) && fallbackTx == null) {
              fallbackTx = char;
              print('    ✅ [BLE] Using as TX (notify): $charUuid from service ${service.uuid.toString()}');
            }
            // RX: has write property (for sending commands to device)
            if ((props.write || props.writeWithoutResponse) && fallbackRx == null) {
              fallbackRx = char;
              print('    ✅ [BLE] Using as RX (write): $charUuid from service ${service.uuid.toString()}');
            }
          }
        }
        
        // If we found both, use them
        if (fallbackRx != null && fallbackTx != null) {
          _rxCharacteristic = fallbackRx;
          _txCharacteristic = fallbackTx;
          print('✅ [BLE] Fallback connection successful! Using custom services.');
          Logger.info('Using fallback connection with custom services');
        } else if (fallbackRx != null || fallbackTx != null) {
          print('⚠️ [BLE] Found partial characteristics (RX: ${fallbackRx != null}, TX: ${fallbackTx != null})');
          Logger.warning('Fallback found partial characteristics');
        }
      }
      
      if (_rxCharacteristic == null || _txCharacteristic == null) {
        // Enhanced error message with diagnostic information
        print('❌ [BLE] ========== CONNECTION FAILED ==========');
        String errorMsg = 'SmartSync characteristics not found.\n';
        errorMsg += 'Looking for:\n';
        errorMsg += '  - Service UUID: ${BLEConstants.serviceUUID}\n';
        errorMsg += '  - RX Characteristic: ${BLEConstants.rxCharacteristicUUID}\n';
        errorMsg += '  - TX Characteristic: ${BLEConstants.txCharacteristicUUID}\n';
        errorMsg += '\nFound ${services.length} service(s):\n';
        
        // List all discovered services
        for (var service in services) {
          errorMsg += '  - Service: ${service.uuid.toString()} (${service.characteristics.length} chars)\n';
          print('  🔹 [BLE] Service: ${service.uuid.toString()} (${service.characteristics.length} chars)');
          for (var char in service.characteristics) {
            errorMsg += '    - Characteristic: ${char.uuid.toString()}\n';
            print('    - [BLE] Characteristic: ${char.uuid.toString()}');
          }
        }
        
        if (!foundSmartSyncService) {
          errorMsg += '\n💡 TIP: The device may be using different UUIDs. Check firmware configuration.';
          errorMsg += '\n💡 The SmartSync service UUID was not found in the discovered services.';
          errorMsg += '\n💡 Try reflashing the ESP32 with the correct firmware.';
          print('❌ [BLE] SmartSync service UUID NOT FOUND in discovered services!');
        } else {
          errorMsg += '\n💡 SmartSync service was found but characteristics are missing.';
          print('❌ [BLE] SmartSync service FOUND but characteristics missing!');
        }
        
        print('❌ [BLE] ERROR DETAILS:\n$errorMsg');
        print('❌ [BLE] =========================================');
        Logger.error(errorMsg);
        throw Exception(errorMsg);
      }

      // Verify this is actually a SmartSync hub by checking service characteristics
      // and attempting to get initial sensor data
      bool isVerifiedSmartSyncHub = foundSmartSyncService;
      String verificationDetails = '';
      
      try {
        print('🔍 [BLE] Verifying device is SmartSync hub...');
        Logger.info('Verifying connected device is SmartSync hub');
        
        // Method 1: Check if we found the SmartSync service UUID
        if (foundSmartSyncService) {
          isVerifiedSmartSyncHub = true;
          verificationDetails = 'SmartSync service UUID found';
          print('✅ [BLE] Device verified - SmartSync service UUID found');
        } else {
          // Method 2: Check if device has custom services with proper characteristics
          // (fallback connection means we're using custom services)
          if (_rxCharacteristic != null && _txCharacteristic != null) {
            // Check characteristic properties to verify they match SmartSync pattern
            final rxProps = _rxCharacteristic!.properties;
            final txProps = _txCharacteristic!.properties;
            
            // SmartSync RX should have write capability, TX should have notify
            bool hasCorrectProperties = (rxProps.write || rxProps.writeWithoutResponse) &&
                (txProps.notify || txProps.indicate);
            
            if (hasCorrectProperties) {
              isVerifiedSmartSyncHub = true;
              verificationDetails = 'Custom services with correct characteristics';
              print('✅ [BLE] Device verified - custom services with correct characteristics');
            } else {
              verificationDetails = 'Custom services but incorrect characteristics';
              print('⚠️ [BLE] Device has custom services but characteristics may not match SmartSync pattern');
            }
          }
        }
        
        // Method 3: Try to request sensor data to verify device responds
        // (Note: This requires BLE data stream to be enabled, which is currently disabled)
        // For now, we'll rely on service/characteristic verification
        
      } catch (e) {
        print('⚠️ [BLE] Hub verification error: $e');
        Logger.warning('Hub verification error: $e');
        // Don't fail connection if verification fails - allow user to try anyway
      }
      
      // Log connection details for debugging
      print('📋 [BLE] ========== CONNECTION SUMMARY ==========');
      print('  - Device ID: ${device.remoteId.toString()}');
      print('  - Device Name: ${device.advName.isEmpty ? "(unnamed)" : device.advName}');
      print('  - SmartSync Service Found: $foundSmartSyncService');
      print('  - Using Fallback Connection: ${!foundSmartSyncService && _rxCharacteristic != null && _txCharacteristic != null}');
      print('  - RX Characteristic: ${_rxCharacteristic?.uuid.toString() ?? "None"}');
      print('  - TX Characteristic: ${_txCharacteristic?.uuid.toString() ?? "None"}');
      print('  - Hub Verified: $isVerifiedSmartSyncHub');
      print('  - Verification Method: $verificationDetails');
      print('📋 [BLE] =========================================');
      Logger.info('Connection Summary - Device: ${device.advName}, Verified: $isVerifiedSmartSyncHub ($verificationDetails)');

      Logger.success(
          isReconnect ? 'Reconnected successfully' : 'Connected successfully');
      _emitStatus(
        isReconnect
            ? 'Reconnected to ${device.advName}'
            : 'Connected to ${device.advName}',
      );

      _logBluetoothEvent(
        action: 'Bluetooth Connected',
        reason: 'Connected to ${device.advName}${isVerifiedSmartSyncHub ? " (Verified SmartSync Hub)" : " (Unverified - may not be SmartSync hub)"}',
        manual: false,
        unexpected: false,
      );

      // Check if hub is properly registered (but don't disconnect - allow connection to stay open)
      // The UI will handle showing the registration dialog
      final deviceId = device.remoteId.toString();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final firebaseService = FirebaseService();
          final existingDevice = await firebaseService.getDeviceById(deviceId);
          
          // Check if this is a hub (by name or service UUID)
          final isHub = device.advName.contains('SmartSync') ||
              device.advName.contains('ESP32') ||
              device.advName.startsWith('SmartSync') ||
              (existingDevice != null && existingDevice.isHub);
          
          if (isHub) {
            // Hub must be registered with isHub=true and have a roomId
            if (existingDevice == null || !existingDevice.isHub || existingDevice.roomId.isEmpty) {
              Logger.info(
                'BluetoothService: Hub $deviceId is not registered. '
                'Connection will remain open - UI should show registration dialog.',
              );
              
              // DON'T disconnect - keep connection open so user can register
              // Just emit a status message that the UI can listen to
              _emitStatus(
                'Hub connected but not registered. Please register this hub to a room.',
              );
              
              // Emit a special event that UI can listen to for showing registration dialog
              // The UI layer (device_scan_screen or home_screen) should handle showing the dialog
              // We'll use the status message stream for this - UI can check for this pattern
            }
          }
        } catch (e) {
          Logger.warning(
            'BluetoothService: Error checking hub registration: $e. '
            'Continuing with connection...',
          );
          // Continue with connection if check fails (don't block on Firebase errors)
        }
      }

      if (!isReconnect) {
        try {
          final notificationService = NotificationService();
          await notificationService.showLocalNotification(
            id: DateTime.now().millisecondsSinceEpoch % 2147483647,
            title: '✅ Device Connected',
            body: 'Successfully connected to ${device.advName}',
            payload: jsonEncode({
              'type': 'device_connection',
              'status': 'connected',
              'deviceId': device.remoteId.toString(),
            }),
          );
        } catch (e) {
          Logger.warning('Failed to send connection notification: $e');
        }
      }

      print('🔍 [DEBUG] Connection established, starting timers and services');
      Logger.info('🔍 [DEBUG] Connection established, starting timers and services');
      
      try {
        _recordActivity();
        print('🔍 [DEBUG] Activity recorded');
      } catch (e) {
        Logger.error('🔍 [DEBUG] Error recording activity: $e');
        print('🔍 [DEBUG] Activity recording error: $e');
      }
      
      // Start timers for connection maintenance
      // Delay starting timers slightly to allow connection to stabilize
      // This prevents false disconnection triggers immediately after connection
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (_connectedDevice != null && _connectedDevice!.remoteId == device.remoteId) {
          try {
            _startHeartbeatTimer();
            print('🔍 [DEBUG] Heartbeat timer started');
          } catch (e) {
            Logger.error('🔍 [DEBUG] Error starting heartbeat timer: $e');
            print('🔍 [DEBUG] Heartbeat timer error: $e');
          }
          
          try {
            _startKeepaliveTimer(); // Start keepalive for connection stability
            print('🔍 [DEBUG] Keepalive timer started');
          } catch (e) {
            Logger.error('🔍 [DEBUG] Error starting keepalive timer: $e');
            print('🔍 [DEBUG] Keepalive timer error: $e');
          }
          
          try {
            _startSensorPolling();
            print('🔍 [DEBUG] Sensor polling started');
          } catch (e) {
            Logger.error('🔍 [DEBUG] Error starting sensor polling: $e');
            print('🔍 [DEBUG] Sensor polling error: $e');
          }
          
          try {
            _restartInactivityWatchdog();
            print('🔍 [DEBUG] Inactivity watchdog started');
          } catch (e) {
            Logger.error('🔍 [DEBUG] Error starting inactivity watchdog: $e');
            print('🔍 [DEBUG] Inactivity watchdog error: $e');
          }
          
          Logger.info('BluetoothService: Connection maintenance timers started after stabilization delay');
        }
      });

      // Initialize MonitoringService to ensure data collection and storage
      // Do this asynchronously to prevent blocking connection flow
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Initialize in background to prevent blocking UI
        Future.microtask(() async {
          try {
            final monitoringService = MonitoringService();
            await monitoringService.initialize(currentUser.uid);
            Logger.info(
                'BluetoothService: MonitoringService initialized for data collection');
          } catch (e) {
            Logger.warning(
                'BluetoothService: Failed to initialize MonitoringService: $e');
          }
        });
      }

      // CRITICAL: Wait for connection to fully stabilize before sending commands
      // ESP32 needs time to initialize BLE stack after connection
      // Sending commands too early causes GATT_ERROR (133) and disconnection
      Future.delayed(const Duration(seconds: 5), () async {
        // Verify connection is still active before sending commands
        if (_connectedDevice == null || 
            _connectedDevice!.remoteId != device.remoteId ||
            !_connectedDevice!.isConnected) {
          Logger.warning('BluetoothService: Connection lost before command initialization, skipping');
          return;
        }
        
        // Restore appliance state and sync schedules after connection is established
        // Do these sequentially with delays to prevent overwhelming the ESP32
        try {
          await _restoreApplianceState();
          // Small delay between operations
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          Logger.warning('BluetoothService: Failed to restore appliance state: $e');
        }
        
        // Verify connection still active
        if (_connectedDevice == null || 
            _connectedDevice!.remoteId != device.remoteId ||
            !_connectedDevice!.isConnected) {
          Logger.warning('BluetoothService: Connection lost during state restoration, skipping schedules');
          return;
        }
        
        try {
          await _syncSchedulesToDevice();
          // Small delay between operations
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          Logger.warning('BluetoothService: Failed to sync schedules: $e');
        }

        // Verify connection still active
        if (_connectedDevice == null || 
            _connectedDevice!.remoteId != device.remoteId ||
            !_connectedDevice!.isConnected) {
          Logger.warning('BluetoothService: Connection lost during schedule sync, skipping hub config');
          return;
        }

        // Send hub configuration (room name and primary status) to ESP32
        try {
          await _sendHubConfiguration();
        } catch (e) {
          Logger.warning('BluetoothService: Failed to send hub configuration: $e');
        }
      });

      _isConnecting = false;
      return true;
    } catch (e) {
      _isConnecting = false;
      Logger.error('Connection failed: $e');

      // Provide user-friendly error messages for common connection errors
      String errorMessage = 'Connection failed';
      final errorString = e.toString();

      // Enhanced error handling for common connection issues
      if (errorString.contains('android-code: 133') ||
          errorString.contains('status=133') ||
          errorString.contains('status: 133') ||
          errorString.contains('GATT_ERROR') ||
          errorString.contains('ANDROID_SPECIFIC_ERROR')) {
        errorMessage =
            'Connection failed (GATT error): Device may be connected to another app or Bluetooth stack issue. Please try again.';
        Logger.warning(
            'GATT_ERROR (133): Device may be connected elsewhere or Bluetooth stack issue - attempting recovery');
        
        // Attempt recovery: force disconnect and wait
        try {
          if (device.isConnected) {
            await device.disconnect();
          }
          await Future.delayed(const Duration(milliseconds: 2000));
          Logger.info('Recovery: Disconnected device, ready for retry');
        } catch (recoveryError) {
          Logger.debug('Recovery disconnect error: $recoveryError');
        }
      } else if (errorString.contains('timeout') ||
          errorString.contains('Timed out')) {
        errorMessage =
            'Connection timed out: Device may be out of range or not responding. Please ensure device is nearby and try again.';
        Logger.warning('Connection timeout: Device may be out of range');
      } else if (errorString.contains('already connected')) {
        errorMessage = 'Device is already connected.';
      } else {
        errorMessage = 'Connection failed: ${e.toString()}';
      }

      _emitStatus(errorMessage);

      // Ensure proper cleanup to prevent UI blocking
      // CRITICAL: Clear last device reference on connection failure during registration
      // This prevents state confusion where firmware thinks it's connected but app doesn't
      final shouldClearLastDevice = !isReconnect; // Clear on initial connection failures
      try {
      if (isReconnect) {
        await _teardownConnection(
          manual: false,
          suppressNotification: true,
          clearLastDevice: shouldClearLastDevice,
        );
      } else {
        await _teardownConnection(
          manual: true,
          suppressNotification: false,
          clearLastDevice: shouldClearLastDevice,
        );
      }
      } catch (cleanupError) {
        Logger.warning('Error during connection cleanup: $cleanupError');
      }

      return false;
    } finally {
      // CRITICAL: Always reset connection flag, even on exceptions
      _isConnecting = false;
    }
  }

  // Disconnect from device
  Future<void> disconnect({bool manual = true, bool clearLastDevice = false}) async {
    _manualDisconnect = manual;
    final deviceName = _connectedDevice?.advName ?? 'Device';
    try {
      final device = _connectedDevice;
      if (device != null) {
        await device.disconnect();
      }
    } catch (e) {
      Logger.error('Disconnect error: $e');
    } finally {
      await _teardownConnection(
        manual: manual,
        deviceName: deviceName,
        unexpected: !manual,
        clearLastDevice: clearLastDevice,
      );
    }
  }
  
  /// Fully reset connection state - useful when state gets confused
  /// This clears all connection state including _lastConnectedDevice
  Future<void> resetConnectionState() async {
    Logger.info('BluetoothService: Resetting connection state');
    try {
      // Stop any active scans first
      try {
        await flutter_blue.FlutterBluePlus.stopScan();
      } catch (e) {
        Logger.debug('Error stopping scan during reset: $e');
      }
      
      // Disconnect if connected
      if (_connectedDevice != null) {
        try {
          await _connectedDevice!.disconnect();
        } catch (e) {
          Logger.debug('Error disconnecting during reset: $e');
        }
      }
      
      // Full teardown with all flags cleared
      await _teardownConnection(
        manual: true,
        clearLastDevice: true, // Clear last device to fully reset state
        suppressNotification: true,
      );
      
      Logger.info('BluetoothService: Connection state fully reset');
    } catch (e) {
      Logger.error('Error resetting connection state: $e');
    }
  }

  Future<bool> reconnectToLastDevice({bool userInitiated = true}) async {
    final device = _lastConnectedDevice;
    if (device == null) {
      _emitStatus('No previously connected device available.');
      return false;
    }

    final label = userInitiated ? 'Reconnecting' : 'Auto-reconnecting';
    _emitStatus('$label to ${device.advName}...');
    return await connectToDevice(
      device,
      isReconnect: !userInitiated,
    );
  }

  // Handle incoming data with buffering and validation
  // CRITICAL: This method must never throw exceptions to prevent UI crashes
  // CRITICAL: This runs on the UI thread - must be extremely fast
  // ignore: unused_element
  void _handleIncomingData(List<int> data) {
    // CRITICAL: Validate input immediately (no logging for performance)
    if (data.isEmpty) {
      return; // Skip empty data silently
    }
    
    // CRITICAL: Throttling at handler level to prevent UI blocking
    // Drop packets only if queue is critically full (increased threshold)
    if (_pendingPackets >= _maxPendingPackets * 3) {
      // Emergency drop - queue is critically full
      _totalPacketsDropped++;
      return; // Drop immediately - no queuing, no logging (too expensive)
    }
    
    // CRITICAL: Quick binary data check (must be fast - no logging)
    if (data.length >= 4) {
      final b0 = data[0];
      final b1 = data[1];
      final b2 = data[2];
      final b3 = data[3];
      // Known binary pattern: drop immediately (silently for performance)
      if (b2 == 0xfc && b3 == 0x3f) {
        if ((b0 == 0xc0 && b1 == 0xd9) ||
            (b0 == 0xe8 && b1 == 0xdb) ||
            (b0 == 0x28 && b1 == 0xdc)) {
          _totalPacketsDropped++;
          return; // Drop binary data immediately - no logging
        }
      }
    }
    
    // CRITICAL: Increment pending counter before queuing
    _pendingPackets++;
    
    // CRITICAL: Process data asynchronously OFF the UI thread
    // Use Future.microtask to defer to next event loop cycle
    // This prevents blocking the UI thread
    Future.microtask(() {
      // CRITICAL: Wrap in try-catch to prevent any errors from crashing
      try {
        _pendingPackets--;
        if (_pendingPackets < 0) _pendingPackets = 0;
        
        // CRITICAL: Reduced delay to allow more packets through (sensor data needs to flow)
        // This prevents overwhelming the system while still allowing data processing
        Future.delayed(const Duration(milliseconds: 5), () {
          try {
            _processIncomingData(data);
          } catch (e, stackTrace) {
            // CRITICAL: Never let processing errors propagate
            Logger.error('🔍 [DEBUG] Error in _processIncomingData: $e', e, stackTrace);
            _totalParseErrors++;
          }
        });
      } catch (e, stackTrace) {
        // CRITICAL: Never let handler errors propagate
        Logger.error('🔍 [DEBUG] Error in _handleIncomingData microtask: $e', e, stackTrace);
        _totalParseErrors++;
        _pendingPackets--;
        if (_pendingPackets < 0) _pendingPackets = 0;
      }
    });
  }

  void _processIncomingData(List<int> data) {
    // Re-enabled: BLE data stream processing
    
    // DEBUG: Log data reception
    print('🔍 [SENSOR DEBUG] Received ${data.length} bytes');
    
    // CRITICAL: Aggressive rate limiting - process max once per throttle window
    final now = DateTime.now();
    if (_lastDataProcessTime != null) {
      final timeSinceLastProcess = now.difference(_lastDataProcessTime!);
      if (timeSinceLastProcess < _dataThrottleWindow) {
        // Skip this packet if processing too fast (prevents UI blocking)
        print('🔍 [SENSOR DEBUG] Throttled - ${timeSinceLastProcess.inMilliseconds}ms < ${_dataThrottleWindow.inMilliseconds}ms');
        _totalPacketsDropped++;
        return;
      }
    }
    _lastDataProcessTime = now;
    
    // Additional safety: If queue is still backing up, drop packets (increased threshold)
    if (_pendingPackets > _maxPendingPackets * 3) {
      _totalPacketsDropped++;
      return; // Emergency drop to prevent UI blocking
    }

    _totalPacketsReceived++;
    _lastDataReceivedTime = DateTime.now();

    // CRITICAL: Wrap entire handler in try-catch to prevent any exceptions from crashing UI
    try {
      // Skip empty data (likely initial notification or descriptor write)
      if (data.isEmpty) {
        Logger.debug(
            'Received empty data, skipping - likely initial notification or descriptor write');
        return;
      }

      // Reset buffer timeout timer
      _bufferTimeoutTimer?.cancel();
      _bufferTimeoutTimer = Timer(_bufferTimeout, () {
        if (_dataBuffer.isNotEmpty) {
          // Silent timeout - no logging to prevent UI blocking
          _dataBuffer.clear();
          _totalPacketsDropped++;
        }
      });

      // CRITICAL: Circuit breaker - if too many binary packets, stop processing entirely
      if (_binaryDataCircuitBreaker) {
        // Circuit breaker active - drop all data silently without any processing
        print('🔍 [SENSOR DEBUG] Circuit breaker active - dropping data');
        _totalPacketsDropped++;
        return;
      }

      // CRITICAL: Don't check for binary data on small packets - they're likely partial JSON
      // BLE notifications can be split into small chunks (4 bytes is common)
      // Only check for binary if we have enough data to be confident
      bool isIncomingBinary = false;
      
      // Only check for binary if packet is large enough (>= 8 bytes) or buffer is substantial
      if (data.length >= 8 || (_dataBuffer.length + data.length) >= 16) {
        isIncomingBinary = _isBinaryData(data);
        if (isIncomingBinary) {
          print('🔍 [SENSOR DEBUG] Detected binary data (${data.length} bytes)');
        }

        // Also check if buffer + incoming data would form binary pattern
        if (!isIncomingBinary && _dataBuffer.isNotEmpty) {
          final combined = [..._dataBuffer, ...data];
          // Only check combined if it's substantial enough
          if (combined.length >= 16) {
            isIncomingBinary = _isBinaryData(combined);
            if (isIncomingBinary) {
              print('🔍 [SENSOR DEBUG] Combined buffer+data is binary (${combined.length} bytes)');
            }
          }
        }
      } else {
        // Small packet - likely partial JSON, don't mark as binary
        print('🔍 [SENSOR DEBUG] Small packet (${data.length} bytes) - treating as potential partial JSON');
      }

      if (isIncomingBinary) {
        // Incoming data is binary - track consecutive binary packets
        _consecutiveBinaryPackets++;
        _consecutiveDecodeFailures = 0; // Reset decode failures
        print('🔍 [SENSOR DEBUG] Binary packet #$_consecutiveBinaryPackets');

        // Circuit breaker: if too many consecutive binary packets, stop processing
        if (_consecutiveBinaryPackets >= _maxConsecutiveBinaryPackets) {
          _binaryDataCircuitBreaker = true;
          // Clear everything and stop processing
          _bufferTimeoutTimer?.cancel();
          _dataBuffer.clear();
          _totalPacketsDropped++;
          print('🔍 [SENSOR DEBUG] Circuit breaker activated after $_consecutiveBinaryPackets binary packets');
          return;
        }

        // Drop binary data silently
        _bufferTimeoutTimer?.cancel();
        _dataBuffer.clear(); // Clear any accumulated binary data
        _totalPacketsDropped++;
        print('🔍 [SENSOR DEBUG] Dropping binary data');
        return;
      }

      // Reset binary packet counter on valid data
      _consecutiveBinaryPackets = 0;
      _binaryDataCircuitBreaker = false; // Reset circuit breaker on valid data

      // Add data to buffer only if it's not clearly binary
      // Memory protection: Limit buffer growth
      try {
        if (_dataBuffer.length + data.length > _maxBufferSize) {
          // Would exceed max - drop oldest data or skip
          final spaceAvailable = _maxBufferSize - _dataBuffer.length;
          if (spaceAvailable > 0) {
            _dataBuffer.addAll(data.take(spaceAvailable));
          }
          _totalPacketsDropped++;
          return;
        }
      _dataBuffer.addAll(data);
      } catch (e) {
        // Memory error - clear buffer and continue
        try {
          _dataBuffer.clear();
          _totalPacketsDropped++;
        } catch (_) {
          // Even clearing failed - continue silently
        }
        return;
      }

      // Prevent buffer overflow with memory protection
      if (_dataBuffer.length > _maxBufferSize) {
        // Silent overflow handling - no logging to prevent UI blocking
        try {
        _dataBuffer.clear();
        _totalPacketsDropped++;
        } catch (e) {
          // Even clearing failed - try to recover silently
          try {
            _dataBuffer.length = 0; // Alternative clear method
          } catch (_) {
            // If all else fails, create new buffer
            _dataBuffer.clear();
          }
        }
        return;
      }

      // Double-check accumulated buffer for binary patterns (only if buffer is substantial)
      // Don't check small buffers - they're likely incomplete JSON
      bool isBinaryData = false;
      if (_dataBuffer.length >= 16) {
        isBinaryData = _isBinaryData(_dataBuffer);
        if (isBinaryData) {
          print('🔍 [SENSOR DEBUG] Buffer contains binary data (${_dataBuffer.length} bytes) - clearing');
          _dataBuffer.clear();
          _bufferTimeoutTimer?.cancel();
          _consecutiveDecodeFailures = 0;
          _totalPacketsDropped++;
          return;
        }
      }

      // Try to decode and parse JSON
      String? jsonString;

      try {
        jsonString = utf8.decode(_dataBuffer, allowMalformed: false);
        print('🔍 [SENSOR DEBUG] Decoded JSON string: ${jsonString.length} chars');
        _consecutiveDecodeFailures = 0; // Reset on success
        _consecutiveBinaryPackets = 0; // Reset binary counter on success
        _binaryDataCircuitBreaker = false; // Reset circuit breaker on success
      } catch (e) {
        print('🔍 [SENSOR DEBUG] UTF-8 decode failed: $e (buffer size: ${_dataBuffer.length} bytes)');
        _consecutiveDecodeFailures++;
        
        // CRITICAL: Don't mark as binary if buffer is small - it's likely incomplete JSON
        // Only check for binary if buffer is substantial (>= 16 bytes)
        bool isBinaryData = false;
        if (_dataBuffer.length >= 16) {
          isBinaryData = _isBinaryData(_dataBuffer);
          if (isBinaryData) {
            print('🔍 [SENSOR DEBUG] Buffer detected as binary (${_dataBuffer.length} bytes)');
          }
        } else {
          print('🔍 [SENSOR DEBUG] Buffer too small (${_dataBuffer.length} bytes) - likely incomplete JSON, waiting for more data');
        }
        
        // If binary data detected on substantial buffer, clear immediately
        if (isBinaryData) {
          _dataBuffer.clear();
          _bufferTimeoutTimer?.cancel();
          _consecutiveDecodeFailures = 0;
          _totalPacketsDropped++;
          return;
        }

        // If we have too many consecutive failures AND substantial buffer, clear buffer
        if (_consecutiveDecodeFailures >= _maxConsecutiveFailures && _dataBuffer.length >= 32) {
          print('🔍 [SENSOR DEBUG] Too many decode failures (${_consecutiveDecodeFailures}) with substantial buffer, clearing');
          _dataBuffer.clear();
          _bufferTimeoutTimer?.cancel();
          _consecutiveDecodeFailures = 0;
          _totalPacketsDropped++;
          return;
        }
        
        // If UTF-8 decode fails on small buffer, it's likely incomplete data - wait for more
        print('🔍 [SENSOR DEBUG] Waiting for more data to complete JSON message (current buffer: ${_dataBuffer.length} bytes)');
        return;
      }

      // Try to parse JSON - check if we have a complete message
      // jsonString is guaranteed to be non-null here since decode succeeded
      Map<String, dynamic> json;
      
      try {
        json = jsonDecode(jsonString) as Map<String, dynamic>;
        print('🔍 [SENSOR DEBUG] JSON parsed successfully, type: ${json['type']}');
        // Successfully parsed - clear buffer
        _dataBuffer.clear();
        _bufferTimeoutTimer?.cancel();
        _totalPacketsProcessed++;
      } catch (e) {
        print('🔍 [SENSOR DEBUG] JSON parse failed: $e');
        // JSON parse failed - might be incomplete or malformed
        if (e is FormatException) {
          // Check if it's a JSON structure issue (incomplete)
          if (_isIncompleteJSON(jsonString)) {
            // Incomplete JSON - wait for more data silently
            return;
          } else {
            // Malformed JSON - clear buffer silently
            _dataBuffer.clear();
            _bufferTimeoutTimer?.cancel();
            _totalParseErrors++;
            _totalPacketsDropped++;
            return;
          }
        } else {
          // Unexpected error - clear silently
          _dataBuffer.clear();
          _bufferTimeoutTimer?.cancel();
          _totalParseErrors++;
          _totalPacketsDropped++;
          return;
        }
      }

      // Successfully parsed JSON - process message
      final messageType = json['type'] as String? ?? '';

      // Validate required fields based on message type
      if (!_validateMessage(json, messageType)) {
        _totalPacketsDropped++;
        return;
      }

      if (messageType == BLEConstants.eventHeartbeat) {
        _recordActivity();
        return;
      }

      if (messageType == BLEConstants.eventConnectionState) {
        _recordActivity();
        if ((json['connected'] as bool? ?? false) && !_manualDisconnect) {
          _emitStatus('Device confirmed active link.');
        }
        return;
      }

      if (messageType == 'sensor_data') {
        try {
          print('🔍 [SENSOR DEBUG] Processing sensor_data message');
          SensorData sensorData = SensorData(
            deviceId: _connectedDevice?.remoteId.toString() ?? '',
            userId: '', // Will be set from auth
            temperature: (json['temperature'] as num).toDouble(),
            humidity: (json['humidity'] as num).toDouble(),
            heatIndex: json['heat_index'] != null
                ? (json['heat_index'] as num).toDouble()
                : null,
            fanSpeed: json['fan_speed'] as int,
            ledBrightness: json['led_brightness'] as int,
            motionDetected: json['motion'] as bool,
            distance: (json['distance'] as num).toDouble(),
            securityEnabled: json['security_enabled'] as bool? ?? true,
            timestamp: DateTime.now(),
          );

          print('🔍 [SENSOR DEBUG] Emitting sensor data: temp=${sensorData.temperature}, humidity=${sensorData.humidity}');
          _emitSensorData(sensorData);
          _recordActivity();
          print('🔍 [SENSOR DEBUG] Sensor data emitted successfully');
        } catch (e, stackTrace) {
          print('🔍 [SENSOR DEBUG] Error processing sensor_data: $e');
          Logger.error('Error processing sensor_data', e, stackTrace);
          _totalPacketsDropped++;
        }
      } else if (messageType == 'ack') {
        // Handle acknowledgment messages silently
        _recordActivity();
      }
      // Unhandled message types are silently ignored
    } catch (e, stackTrace) {
      // CRITICAL: Never let exceptions propagate - they would crash the UI
      // NO LOGGING - silently handle errors to prevent UI blocking

      _totalParseErrors++;

      // Safely clear buffer on unexpected errors to prevent stuck state
      try {
      _dataBuffer.clear();
      _bufferTimeoutTimer?.cancel();
        _consecutiveDecodeFailures = 0;
      } catch (clearError) {
        // Even clearing failed - continue silently
      }
    }
  }

  // REMOVED: _shouldLogError - no longer needed since we removed all logging from data processing

  // Check if data is clearly binary (repeating patterns or no printable characters)
  // CRITICAL: This must be FAST and ACCURATE - called for every packet
  // ignore: unused_element
  bool _isBinaryData(List<int> data) {
    if (data.isEmpty) return false;
    
    // FAST PATH: Check for known binary patterns first (most common case)
    if (data.length >= 4) {
      final b0 = data[0];
      final b1 = data[1];
      final b2 = data[2];
      final b3 = data[3];

      // Known binary patterns from logs: c0 d9 fc 3f, e8 db fc 3f, 28 dc fc 3f
      // These are float representations that appear frequently
      if (b2 == 0xfc && b3 == 0x3f) {
        // Fast check: if bytes 2-3 match the pattern, check bytes 0-1
        if ((b0 == 0xc0 && b1 == 0xd9) ||
            (b0 == 0xe8 && b1 == 0xdb) ||
            (b0 == 0x28 && b1 == 0xdc)) {
          return true; // Known binary pattern
        }
      }

      // Check for repeating 4-byte patterns (fast check)
      if (data.length >= 8) {
        if (data[4] == b0 && data[5] == b1 && data[6] == b2 && data[7] == b3) {
          return true; // Repeating pattern detected - definitely binary
      }
    }
    }

    // SLOWER PATH: Only check if fast path didn't match
    // Check if there are very few printable ASCII characters
    if (data.length >= 8) {
    int printableCount = 0;
      final checkLength = data.length < 20
          ? data.length
          : 20; // Only check first 20 bytes for speed
      for (int i = 0; i < checkLength; i++) {
      if (data[i] >= 32 && data[i] <= 126) {
        printableCount++;
      }
    }
    
      // If less than 20% are printable, likely binary
      if (printableCount < checkLength * 0.2) {
      return true;
      }
    }
    
    return false;
  }

  // Check if JSON string appears incomplete (has unclosed brackets/braces)
  // ignore: unused_element
  bool _isIncompleteJSON(String jsonString) {
    if (jsonString.trim().isEmpty) return true;

    int openBraces = 0;
    int openBrackets = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < jsonString.length; i++) {
      final char = jsonString[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char == '\\') {
        escaped = true;
        continue;
      }

      if (char == '"' && !escaped) {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (char == '{') openBraces++;
      if (char == '}') openBraces--;
      if (char == '[') openBrackets++;
      if (char == ']') openBrackets--;
    }

    // If braces/brackets are unbalanced, JSON is incomplete
    return openBraces > 0 || openBrackets > 0;
  }

  // Validate message structure based on type
  // ignore: unused_element
  bool _validateMessage(Map<String, dynamic> json, String messageType) {
    switch (messageType) {
      case 'sensor_data':
        return json.containsKey('temperature') &&
            json.containsKey('humidity') &&
            json.containsKey('fan_speed') &&
            json.containsKey('led_brightness') &&
            json.containsKey('motion') &&
            json.containsKey('distance');

      case 'heartbeat':
        return json.containsKey('timestamp') && json.containsKey('uptime');

      case 'connection_state':
        return json.containsKey('connected') && json.containsKey('timestamp');

      case 'ack':
        return json.containsKey('cmd') && json.containsKey('status');

      default:
        // Unknown types are allowed but logged
        return true;
    }
  }

  // Reset data statistics (called on new connection)
  void _resetDataStatistics() {
    _totalPacketsReceived = 0;
    _totalPacketsProcessed = 0;
    _totalPacketsDropped = 0;
    _totalParseErrors = 0;
    _lastDataReceivedTime = null;
    _consecutiveDecodeFailures = 0;
    _consecutiveBinaryPackets = 0;
    _binaryDataCircuitBreaker = false;
    _dataBuffer.clear();
    _bufferTimeoutTimer?.cancel();
    // Statistics reset silently - only log in verbose debug mode
    // Removed dead code: if (kDebugMode && false) { ... }
  }

  /// Clear previous device state when connecting to a new hub
  /// This prevents stale data from previous connections from being displayed
  Future<void> _clearPreviousDeviceState(String newDeviceId) async {
    try {
      Logger.info('BluetoothService: Clearing previous device state for new hub: $newDeviceId');
      
      // Check if we're switching to a different device
      final previousDeviceId = _connectedDevice?.remoteId.toString();
      final isSwitchingDevices = previousDeviceId != null && previousDeviceId != newDeviceId;
      
      if (isSwitchingDevices) {
        Logger.info('BluetoothService: Switching from device $previousDeviceId to $newDeviceId - clearing state');
      }
      
      // Reset data statistics and buffers
      _resetDataStatistics();
      
      // Clear sensor data stream by emitting a reset signal
      // This ensures UI shows fresh state instead of stale data
      try {
        if (!_sensorDataController.isClosed) {
          // Emit a reset sensor data object with zero values to clear any cached data
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            _sensorDataController.add(SensorData(
              deviceId: newDeviceId,
              userId: user.uid,
              temperature: 0,
              humidity: 0,
              fanSpeed: 0,
              ledBrightness: 0,
              motionDetected: false,
              distance: 0,
              securityEnabled: false,
              timestamp: DateTime.now(),
            ));
          }
        }
      } catch (e) {
        Logger.debug('Error clearing sensor data stream: $e');
      }
      
      // Clear monitoring service state if switching devices
      if (isSwitchingDevices) {
        try {
          final monitoringService = MonitoringService();
          // Clear latest reading to prevent stale data
          monitoringService.clearLatestReading();
          Logger.info('BluetoothService: MonitoringService state cleared for new device');
        } catch (e) {
          Logger.warning('BluetoothService: Error clearing MonitoringService state: $e');
          // Don't fail connection if monitoring service reset fails
        }
      }
      
      // Clear last communication time
      _lastCommunicationTime = null;
      
      Logger.info('BluetoothService: Previous device state cleared successfully');
    } catch (e, stackTrace) {
      Logger.error('BluetoothService: Error clearing previous device state: $e', e, stackTrace);
      // Don't fail connection if state clearing fails - log and continue
    }
  }

  void _registerConnectionMonitor(flutter_blue.BluetoothDevice device) {
    try {
    _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen(
        (flutter_blue.BluetoothConnectionState state) {
          try {
      if (state == flutter_blue.BluetoothConnectionState.disconnected &&
          !_manualDisconnect) {
              // CRITICAL: Ignore disconnection events during grace period
              // This prevents false positives immediately after connection
              if (_connectionGracePeriodActive) {
                Logger.debug(
                    'BluetoothService: Ignoring disconnection during grace period');
                return;
              }
              
              // Additional check: Verify device is actually disconnected
              // Sometimes connectionState fires prematurely
              Future.delayed(const Duration(milliseconds: 500), () async {
                if (_connectedDevice != null && 
                    _connectedDevice!.remoteId == device.remoteId) {
                  // Check actual connection state
                  try {
                    final actualState = await device.connectionState.first.timeout(
                      const Duration(seconds: 1),
                      onTimeout: () => flutter_blue.BluetoothConnectionState.disconnected,
                    );
                    if (actualState == flutter_blue.BluetoothConnectionState.connected) {
                      Logger.info('BluetoothService: False disconnect event - device still connected');
                      return; // Device is still connected, ignore the event
                    }
                  } catch (e) {
                    Logger.debug('Error verifying connection state: $e');
                  }
                }
                
                // Only trigger disconnect if still disconnected after verification
                if (!_manualDisconnect && _connectedDevice?.remoteId == device.remoteId) {
                  Logger.warning(
                      'BluetoothService: Device disconnected unexpectedly');
                  unawaited(_handleUnexpectedDisconnect());
                }
              });
      }
          } catch (e) {
            // Safely handle connection state errors
            try {
              Logger.debug('Error handling connection state: $e');
            } catch (_) {
              // Continue silently
            }
          }
        },
        onError: (error, stackTrace) {
          // Safely handle stream errors
          try {
            Logger.error(
                'Connection state stream error: $error', error, stackTrace);
          } catch (_) {
            // Continue silently
          }
        },
        cancelOnError: false, // Keep listening even on errors
      );
    } catch (e) {
      // Safely handle subscription creation errors
      try {
        Logger.error('Error registering connection monitor: $e');
      } catch (_) {
        // Continue silently
      }
    }
  }

  Future<void> _handleUnexpectedDisconnect() async {
    if (_isAutoReconnecting) {
      return;
    }

    _isAutoReconnecting = true;
    _connectionFailureCount++;
    
    // CRITICAL: Auto-shutdown devices if connection is unstable (multiple failures)
    if (_connectionFailureCount >= _maxConnectionFailures) {
      Logger.warning('BluetoothService: Connection unstable after $_connectionFailureCount failures, shutting down devices');
      await _emergencyShutdownDevices();
      _connectionFailureCount = 0; // Reset counter after shutdown
    }
    
    _emitStatus('Connection lost. Attempting automatic reconnection...');

    await _teardownConnection(
      manual: false,
      unexpected: true,
      deviceName: _lastConnectedDevice?.advName,
      suppressNotification: true,
      clearLastDevice: false, // Keep last device for reconnection attempts
    );

    final device = _lastConnectedDevice;
    if (device == null) {
      _emitStatus('No known device to reconnect.');
      _isAutoReconnecting = false;
      return;
    }

    // CRITICAL: Check if manual connection started during auto-reconnect
    if (_isConnecting) {
      Logger.info('BluetoothService: Manual connection detected during auto-reconnect, aborting auto-reconnect');
      _isAutoReconnecting = false;
      return;
    }

    // CRITICAL: Immediate retry first (no delay) for faster reconnection
    Logger.info('BluetoothService: Immediate reconnect attempt');
    var success = await connectToDevice(device, isReconnect: true);
    if (success) {
      _emitStatus('Automatic reconnection succeeded.');
      _connectionFailureCount = 0; // Reset on successful reconnection
      _isAutoReconnecting = false;
      return;
    }

    // If immediate retry fails, try with exponential backoff
    for (int attempt = 2;
        attempt <= BLEConstants.maxConnectionAttempts;
        attempt++) {
      // CRITICAL: Check if manual connection started during retry loop
      if (_isConnecting) {
        Logger.info('BluetoothService: Manual connection detected during retry, aborting auto-reconnect');
        _isAutoReconnecting = false;
        return;
      }

      Logger.info('BluetoothService: Auto reconnect attempt $attempt');
      success = await connectToDevice(device, isReconnect: true);
      if (success) {
        _emitStatus('Automatic reconnection succeeded.');
        _connectionFailureCount = 0; // Reset on successful reconnection
        _isAutoReconnecting = false;
        return;
      }
      // Exponential backoff: 0.5s, 1s, 1.5s, 2s
      await Future.delayed(BLEConstants.connectionRetryDelay * attempt);
    }

    _emitStatus('Automatic reconnection failed. Please reconnect manually.');

    final scanned = await _scanForKnownDeviceAndReconnect();
    if (scanned) {
      _connectionFailureCount = 0; // Reset on successful scan reconnect
      _isAutoReconnecting = false;
      return;
    }

    try {
      final notificationService = NotificationService();
      await notificationService.showLocalNotification(
        id: (DateTime.now().millisecondsSinceEpoch + 3) % 2147483647,
        title: '⚠️ Device Disconnected',
        body: 'Lost connection to ${device.advName}. Tap to retry.',
        payload: jsonEncode({
          'type': 'device_connection',
          'status': 'disconnected',
        }),
      );
    } catch (e) {
      Logger.warning('Failed to send reconnection notification: $e');
    }

    _isAutoReconnecting = false;
  }

  // CRITICAL: Emergency shutdown of all devices when connection is unstable
  Future<void> _emergencyShutdownDevices() async {
    try {
      Logger.warning('BluetoothService: Executing emergency shutdown - turning off fan and LED');
      
      // Try to send shutdown commands if still connected
      if (isConnected && _rxCharacteristic != null) {
        try {
          // Send shutdown commands with timeout
          await Future.wait([
            setFanSpeed(0).timeout(const Duration(seconds: 2), onTimeout: () => false),
            setLEDBrightness(0).timeout(const Duration(seconds: 2), onTimeout: () => false),
          ]);
          Logger.info('BluetoothService: Emergency shutdown commands sent');
        } catch (e) {
          Logger.warning('BluetoothService: Failed to send shutdown commands: $e');
        }
      }
      
      // Also update Firebase state to ensure consistency
      try {
        final stateService = ApplianceStateService();
        await stateService.saveApplianceState(
          fanSpeed: 0,
          ledBrightness: 0,
          securityEnabled: false,
          autoMode: false,
        );
        Logger.info('BluetoothService: Emergency shutdown state saved to Firebase');
      } catch (e) {
        Logger.warning('BluetoothService: Failed to save shutdown state: $e');
      }
      
      // Show notification to user
      try {
        final notificationService = NotificationService();
        await notificationService.showLocalNotification(
          id: (DateTime.now().millisecondsSinceEpoch + 4) % 2147483647,
          title: '⚠️ Devices Shut Down',
          body: 'Connection unstable. All devices turned off for safety.',
          payload: jsonEncode({
            'type': 'emergency_shutdown',
            'reason': 'unstable_connection',
          }),
        );
      } catch (e) {
        Logger.warning('Failed to send shutdown notification: $e');
      }
    } catch (e, stackTrace) {
      Logger.error('BluetoothService: Error during emergency shutdown: $e', e, stackTrace);
    }
  }

  Future<bool> _scanForKnownDeviceAndReconnect() async {
    if (_scanReconnectInProgress) {
      return false;
    }

    final knownDeviceId = _lastConnectedDevice?.remoteId.toString();
    if (knownDeviceId == null) {
      return false;
    }

    _scanReconnectInProgress = true;
    _emitStatus('Scanning for known device to reconnect...');
    Logger.info('BluetoothService: scanning for $_lastConnectedDevice');

    flutter_blue.BluetoothDevice? discoveredDevice;
    StreamSubscription<List<flutter_blue.ScanResult>>? subscription;

    try {
      await flutter_blue.FlutterBluePlus.startScan(
        timeout: BLEConstants.scanReconnectTimeout,
        androidUsesFineLocation: false,
      );

      final completer = Completer<flutter_blue.BluetoothDevice?>();

      subscription = flutter_blue.FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final remoteId = result.device.remoteId.toString();
          final deviceName = result.device.advName;
          
          // Method 1: Match by device ID (most reliable for known device)
          final matchesId = remoteId == knownDeviceId;
          
          // Method 2: Match by device name
          final matchesName =
              _lastConnectedDevice?.advName.isNotEmpty == true &&
                  deviceName == _lastConnectedDevice?.advName;
          
          // Method 3: Match by service UUID (additional verification)
          bool matchesServiceUuid = false;
          try {
            final advData = result.advertisementData;
            if (advData.serviceUuids.isNotEmpty) {
              for (final uuid in advData.serviceUuids) {
                if (uuid.toString().toLowerCase() ==
                    BLEConstants.serviceUUID.toLowerCase()) {
                  matchesServiceUuid = true;
                  break;
                }
              }
            }
          } catch (e) {
            Logger.debug(
                'Error checking service UUID during reconnect scan: $e');
          }

          if (matchesId || (matchesName && matchesServiceUuid)) {
            if (!completer.isCompleted) {
              Logger.info(
                'BluetoothService: Found known device during reconnect scan - '
                'ID: $remoteId, Name: "$deviceName"',
              );
              completer.complete(result.device);
            }
            break;
          }
        }
      });

      discoveredDevice = await completer.future.timeout(
        BLEConstants.scanReconnectTimeout + const Duration(seconds: 2),
        onTimeout: () => null,
      );
    } catch (e) {
      Logger.error('BluetoothService: Scan reconnect failed: $e');
    } finally {
      await subscription?.cancel();
      await flutter_blue.FlutterBluePlus.stopScan();
      _scanReconnectInProgress = false;
    }

    if (discoveredDevice == null) {
      Logger.warning('BluetoothService: Known device not found during scan.');
      return false;
    }

    Logger.info('BluetoothService: Found known device, attempting reconnect.');
    return await connectToDevice(discoveredDevice, isReconnect: true);
  }

  void _startHeartbeatTimer() {
    _stopHeartbeatTimer();
    _heartbeatTimer = Timer.periodic(BLEConstants.heartbeatInterval, (_) async {
      // CRITICAL: Check connection state before proceeding
      if (!isConnected || _connectedDevice == null) {
        return;
      }

      // CRITICAL: Don't interfere with active connection attempts
      if (_isConnecting) {
        return;
      }

      // Check connection health - but be less aggressive during grace period
      if (!_connectionGracePeriodActive && !isConnectionHealthy) {
        Logger.warning(
            'BluetoothService: Connection health check failed - no data received recently');
        final health = getConnectionHealth();
        Logger.debug('Connection health: $health');

        // If we haven't received data in a while, try to request status
        // Increased threshold to 60 seconds to be less aggressive
        if (_lastDataReceivedTime != null) {
          final timeSinceLastData =
              DateTime.now().difference(_lastDataReceivedTime!);
          if (timeSinceLastData.inSeconds > 60) {
            Logger.warning(
                'No data received for ${timeSinceLastData.inSeconds}s, requesting status...');
            await requestStatus().timeout(
              const Duration(seconds: 3),
              onTimeout: () => false,
            );
          }
        } else if (_connectionEstablishedTime != null) {
          // If we just connected and haven't received data yet, give it more time
          final timeSinceConnection = 
              DateTime.now().difference(_connectionEstablishedTime!);
          if (timeSinceConnection.inSeconds > 30) {
            Logger.info('No data received yet after ${timeSinceConnection.inSeconds}s, requesting initial status...');
            await requestStatus().timeout(
              const Duration(seconds: 3),
              onTimeout: () => false,
            );
          }
        }
      }

      Logger.debug('BluetoothService: Sending heartbeat request');
      await requestStatus().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          Logger.debug('BluetoothService: Heartbeat request timed out');
          return false;
        },
      );
    });
  }

  void _stopHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // CRITICAL: Start keepalive timer for connection stability
  void _startKeepaliveTimer() {
    _stopKeepaliveTimer();
    _keepaliveTimer = Timer.periodic(BLEConstants.connectionKeepaliveInterval, (_) async {
      // CRITICAL: Check connection state before proceeding
      if (!isConnected || _connectedDevice == null) {
        return;
      }

      // CRITICAL: Don't interfere with active connection attempts
      if (_isConnecting) {
        return;
      }

      // Send a lightweight keepalive to maintain connection
      try {
        // Check if device is still connected (non-blocking check)
        // Use isConnected getter which checks if _connectedDevice is not null
        if (!isConnected || _connectedDevice == null) {
          Logger.warning('BluetoothService: Keepalive detected disconnection, triggering reconnect');
          if (!_isAutoReconnecting && !_isConnecting) {
            unawaited(_handleUnexpectedDisconnect());
          }
          return;
        }
        
        // Additional check: verify device is still in connected state
        // connectionState is a Stream, so we rely on the connection state subscription
        // If the device disconnected, _connectionStateSub will handle it via _registerConnectionMonitor

        // Send a lightweight status request to keep connection alive
        // Use timeout to prevent blocking
        await requestStatus().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            Logger.debug('BluetoothService: Keepalive request timed out');
            return false;
          },
        );
      } catch (e) {
        Logger.debug('BluetoothService: Keepalive error (non-critical): $e');
        // Don't trigger reconnect on keepalive errors - let heartbeat handle it
      }
    });
  }

  void _stopKeepaliveTimer() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
  }

  void _startSensorPolling() {
    _stopSensorPolling();
    _sensorPollTimer =
        Timer.periodic(BLEConstants.sensorPollInterval, (_) async {
      // CRITICAL: Check connection state before proceeding
      if (!isConnected || _connectedDevice == null) {
        return;
      }

      // CRITICAL: Don't interfere with active connection attempts
      if (_isConnecting) {
        return;
      }

      Logger.debug('BluetoothService: Polling latest sensor snapshot');
      await requestSensorSnapshot().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          Logger.debug('BluetoothService: Sensor poll request timed out');
          return false;
        },
      );
    });
  }

  void _stopSensorPolling() {
    _sensorPollTimer?.cancel();
    _sensorPollTimer = null;
  }

  void _restartInactivityWatchdog() {
    _stopInactivityWatchdog();
    _inactivityTimer = Timer(BLEConstants.inactivityGracePeriod, () async {
      if (!isConnected) {
        return;
      }
      _emitStatus('No BLE traffic detected. Sending keepalive...');
      await requestStatus();
      _restartInactivityWatchdog();
    });
  }

  void _stopInactivityWatchdog() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  void _recordActivity() {
    try {
    _lastCommunicationTime = DateTime.now();
    if (!_activityController.isClosed) {
      _activityController.add(_lastCommunicationTime);
    }
    _restartInactivityWatchdog();
    } catch (e) {
      // Safely handle activity recording errors
      try {
        Logger.debug('Error recording activity: $e');
      } catch (_) {
        // Even logging failed - continue silently
      }
    }
  }

  // Safe stream controller operations with error handling
  // ignore: unused_element
  void _emitSensorData(SensorData data) {
    try {
      if (!_sensorDataController.isClosed) {
        print('🔍 [SENSOR DEBUG] Adding sensor data to stream controller');
        _sensorDataController.add(data);
        print('🔍 [SENSOR DEBUG] Sensor data added to stream');
      } else {
        print('🔍 [SENSOR DEBUG] Stream controller is closed!');
      }
    } catch (e, stackTrace) {
      print('🔍 [SENSOR DEBUG] Error emitting sensor data: $e');
      Logger.error('Error emitting sensor data: $e', e, stackTrace);
    }
  }

  void _emitConnectionState(bool connected) {
    try {
      if (!_connectionController.isClosed) {
        _connectionController.add(connected);
      }
    } catch (e) {
      try {
        Logger.debug('Error emitting connection state: $e');
      } catch (_) {
        // Continue silently
      }
    }
  }

  void _emitStatus(String message) {
    try {
      if (!_statusMessageController.isClosed) {
        _statusMessageController.add(message);
      }
    } catch (e) {
      try {
        Logger.debug('Error emitting status: $e');
      } catch (_) {
        // Continue silently
      }
    }
  }

  Future<void> _teardownConnection({
    required bool manual,
    bool unexpected = false,
    String? deviceName,
    bool suppressNotification = false,
    bool clearLastDevice = false, // New parameter to clear _lastConnectedDevice
  }) async {
      // CRITICAL: Clear connection state first to prevent race conditions
      final wasConnected = _connectedDevice != null;
      final disconnectedDevice = _connectedDevice;
      // Clear immediately to prevent conflicts - this ensures isConnected returns false immediately
      _connectedDevice = null;
      _connectionEstablishedTime = null; // Clear connection time
      _connectionGracePeriodActive = false; // Clear grace period flag
    
    // CRITICAL: Clear _lastConnectedDevice if requested (e.g., during registration failures)
    // This prevents confusion where firmware thinks it's connected but app doesn't
    if (clearLastDevice) {
      _lastConnectedDevice = null;
      Logger.info('BluetoothService: Cleared last connected device reference');
    }

    // CRITICAL: Reset connection flags to allow new connections
    _isConnecting = false;
    _isAutoReconnecting = false;
    _manualDisconnect = false;
    
    // CRITICAL: Stop all timers FIRST to prevent them from interfering
    _stopHeartbeatTimer();
    _stopKeepaliveTimer();
    _stopInactivityWatchdog();
    _stopSensorPolling();
    
    // CRITICAL: Ensure any active scans are stopped to allow new scans
    try {
      await flutter_blue.FlutterBluePlus.stopScan();
    } catch (e) {
      Logger.debug('Error stopping scan during teardown: $e');
    }

    // Safely cancel all subscriptions and timers
    try {
    await _connectionStateSub?.cancel();
    _connectionStateSub = null;
    } catch (e) {
      Logger.debug('Error canceling connection state subscription: $e');
    }

    try {
      await _dataStreamSubscription?.cancel();
      _dataStreamSubscription = null;
    } catch (e) {
      Logger.debug('Error canceling data stream subscription: $e');
    }

    // Clean up data buffer and timers
    try {
    _bufferTimeoutTimer?.cancel();
    _bufferTimeoutTimer = null;
    _dataBuffer.clear();
    _consecutiveDecodeFailures = 0;
    } catch (e) {
      Logger.debug('Error cleaning up buffer: $e');
    }

    // Log connection statistics before clearing
    if (_totalPacketsReceived > 0) {
      Logger.info(
          'Connection statistics: ${_totalPacketsProcessed}/${_totalPacketsReceived} packets processed, '
          '${_totalPacketsDropped} dropped, ${_totalParseErrors} parse errors '
          '(${(packetSuccessRate * 100).toStringAsFixed(1)}% success rate)');
    }

    // CRITICAL: Clear device references (already cleared _connectedDevice above)
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _lastCommunicationTime = null;

    // Safely emit activity state
    try {
    if (!_activityController.isClosed) {
      _activityController.add(null);
      }
    } catch (e) {
      Logger.debug('Error emitting activity state: $e');
    }

    if (!_connectionController.isClosed) {
      _emitConnectionState(false);
    }

    _emitStatus(unexpected ? 'Connection lost' : 'Connection closed');

    if (!manual && !suppressNotification) {
      try {
        final notificationService = NotificationService();
        await notificationService.showLocalNotification(
          id: (DateTime.now().millisecondsSinceEpoch + 2) % 2147483647,
          title: '⚠️ Device Disconnected',
          body: 'Lost connection to ${deviceName ?? 'device'}',
          payload: jsonEncode({
            'type': 'device_connection',
            'status': 'disconnected',
          }),
        );
      } catch (e) {
        Logger.warning('Failed to send disconnection notification: $e');
      }
    }
  }

  // Send command
  Future<bool> sendCommand(String cmd, dynamic value) async {
    if (_rxCharacteristic == null) {
      Logger.error('Not connected to device');
      return false;
    }

    // Check if device is still connected before sending
    if (_connectedDevice == null || !_connectedDevice!.isConnected) {
      Logger.warning('Device not connected, cannot send command: $cmd');
      return false;
    }

    try {
      Map<String, dynamic> command = {
        'cmd': cmd,
        'value': value,
      };

      String jsonString = jsonEncode(command);
      List<int> bytes = utf8.encode(jsonString);

      // CRITICAL: Add delay between writes to prevent GATT_ERROR (133)
      // ESP32 needs more time between writes to process commands
      // Increased from 50ms to 200ms to prevent connection drops
      if (_lastWriteTime != null) {
        final timeSinceLastWrite = DateTime.now().difference(_lastWriteTime!);
        if (timeSinceLastWrite < const Duration(milliseconds: 200)) {
          await Future.delayed(Duration(milliseconds: 200 - timeSinceLastWrite.inMilliseconds));
        }
      }
      _lastWriteTime = DateTime.now();

      await _rxCharacteristic!.write(bytes, withoutResponse: false);
      Logger.debug('Sent command: $jsonString');
      _recordActivity();

      return true;
    } catch (e) {
      // Enhanced error handling for GATT errors
      final errorString = e.toString();

      // Track error for diagnostics
      ErrorDiagnostics.captureError(
        category: 'bluetooth_write',
        message: 'Failed to send command: $cmd',
        error: e,
        context: {
          'command': cmd,
          'value': value?.toString(),
          'errorType': errorString,
          'isConnected': _connectedDevice?.isConnected ?? false,
        },
      );

      // Handle specific GATT errors
      if (errorString.contains('android-code: 133') ||
          errorString.contains('GATT_ERROR') ||
          errorString.contains('device is disconnected')) {
        Logger.error(
            'Send command error: GATT_ERROR (133) - Device may have disconnected');

        // Mark connection as lost
        if (_connectedDevice != null) {
          await _teardownConnection(
            manual: false,
            unexpected: true,
            deviceName: _connectedDevice!.advName,
          );
        }

        return false;
      }

      Logger.error('Send command error: $e');
      return false;
    }
  }

  // Control methods
  Future<bool> setFanSpeed(int speed) async {
    int value = ((speed / 100) * 255).round().clamp(0, 255);

    // Get previous state for logging
    final stateService = ApplianceStateService();
    final currentState = await stateService.loadApplianceState();
    final previousSpeed = currentState?['fanSpeed'] ?? 0;
    final previousSpeedPercent = ((previousSpeed / 255) * 100).round();

    final success = await sendCommand(BLEConstants.cmdSetFan, value);
    if (success) {
      // Save state to Firebase
      await stateService.saveApplianceState(
        fanSpeed: value,
        ledBrightness: currentState?['ledBrightness'] ?? 0,
        securityEnabled: currentState?['securityEnabled'] ?? false,
        autoMode: currentState?['autoMode'],
      );

      // Log detailed action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: 'Fan Speed Changed',
        category: 'device_control',
        details:
            'Fan speed changed from $previousSpeedPercent% to $speed% (raw: $previousSpeed → $value)',
        metadata: {
          'deviceType': 'fan',
          'previousSpeed': previousSpeed,
          'previousSpeedPercent': previousSpeedPercent,
          'newSpeed': value,
          'newSpeedPercent': speed,
          'rawValue': value,
          'percentageValue': speed,
          'bleConnected': isConnected,
          'deviceId': connectedDeviceId,
          'actionType': 'fan_speed_change',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );

      // Send notification for manual device change
      try {
        final notificationService = NotificationService();
        await notificationService.showLocalNotification(
          id: DateTime.now().millisecondsSinceEpoch % 2147483647,
          title: '🔧 Device Updated',
          body: 'Fan speed set to ${speed}%',
          payload: jsonEncode({
            'type': 'device_change',
            'device': 'fan',
            'value': speed,
          }),
        );
      } catch (e) {
        Logger.warning('Failed to send notification: $e');
      }
    }
    return success;
  }

  Future<bool> setLEDBrightness(int brightness) async {
    int value = ((brightness / 100) * 255).round().clamp(0, 255);

    // Get previous state for logging
    final stateService = ApplianceStateService();
    final currentState = await stateService.loadApplianceState();
    final previousBrightness = currentState?['ledBrightness'] ?? 0;
    final previousBrightnessPercent =
        ((previousBrightness / 255) * 100).round();

    final success = await sendCommand(BLEConstants.cmdSetLED, value);
    if (success) {
      // Save state to Firebase
      await stateService.saveApplianceState(
        fanSpeed: currentState?['fanSpeed'] ?? 0,
        ledBrightness: value,
        securityEnabled: currentState?['securityEnabled'] ?? false,
        autoMode: currentState?['autoMode'],
      );

      // Log detailed action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: 'Ambient Light Level Changed',
        category: 'device_control',
        details:
            'Ambient lights changed from $previousBrightnessPercent% to $brightness% (raw: $previousBrightness → $value)',
        metadata: {
          'deviceType': 'light',
          'previousBrightness': previousBrightness,
          'previousBrightnessPercent': previousBrightnessPercent,
          'newBrightness': value,
          'newBrightnessPercent': brightness,
          'rawValue': value,
          'percentageValue': brightness,
          'bleConnected': isConnected,
          'deviceId': connectedDeviceId,
          'actionType': 'ambient_light_change',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );

      // Send notification for manual device change
      try {
        final notificationService = NotificationService();
        await notificationService.showLocalNotification(
          id: (DateTime.now().millisecondsSinceEpoch + 1) % 2147483647,
          title: '💡 Ambient Lights Updated',
          body: 'Ambient lights set to ${brightness}%',
          payload: jsonEncode({
            'type': 'device_change',
            'device': 'ambient_light',
            'value': brightness,
          }),
        );
      } catch (e) {
        Logger.warning('Failed to send notification: $e');
      }
    }
    return success;
  }

  Future<bool> setAutoMode(bool enabled) async {
    // Get previous state for logging
    final stateService = ApplianceStateService();
    final currentState = await stateService.loadApplianceState();
    final previousAutoMode = currentState?['autoMode'] ?? false;

    final success = await sendCommand(BLEConstants.cmdSetAutoMode, enabled);
    if (success) {
      // Save state to Firebase
      await stateService.saveApplianceState(
        fanSpeed: currentState?['fanSpeed'] ?? 0,
        ledBrightness: currentState?['ledBrightness'] ?? 0,
        securityEnabled: currentState?['securityEnabled'] ?? false,
        autoMode: enabled,
      );

      // Log detailed action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: enabled ? 'Auto Mode ENABLED' : 'Auto Mode DISABLED',
        category: 'settings',
        details:
            'Auto Mode ${enabled ? "enabled" : "disabled"} (previous state: ${previousAutoMode ? "enabled" : "disabled"})',
        metadata: {
          'feature': 'auto_mode',
          'previousState': previousAutoMode,
          'newState': enabled,
          'bleConnected': isConnected,
          'deviceId': connectedDeviceId,
          'actionType': 'auto_mode_toggle',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
    }
    return success;
  }

  Future<bool> setSecurityEnabled(bool enabled) async {
    if (!isConnected) {
      Logger.warning('BluetoothService: Cannot set security - not connected');
      return false;
    }

    // Get previous state for logging
    final stateService = ApplianceStateService();
    final currentState = await stateService.loadApplianceState();
    final previousSecurityState = currentState?['securityEnabled'] ?? false;

    Logger.info('BluetoothService: Setting security to ${enabled ? "ARMED" : "DISARMED"} (previous: ${previousSecurityState ? "ARMED" : "DISARMED"})');

    // Send boolean directly - firmware will handle it as data.is<bool>() or data["enabled"]
    // The firmware expects: data.is<bool>() OR data["enabled"] OR data["value"]
    // Since sendCommand wraps it as {"cmd": "...", "value": <payload>},
    // sending the boolean directly works because firmware checks data.is<bool>() first
    final success = await sendCommand(BLEConstants.cmdSetSecurity, enabled);
    
    if (success) {
      Logger.success('BluetoothService: Security command sent successfully');
      // Save state to Firebase
      await stateService.saveApplianceState(
        fanSpeed: currentState?['fanSpeed'] ?? 0,
        ledBrightness: currentState?['ledBrightness'] ?? 0,
        securityEnabled: enabled,
        autoMode: currentState?['autoMode'],
      );

      // Log detailed action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: enabled ? 'Security System ARMED' : 'Security System DISARMED',
        category: 'security',
        details:
            'Security system ${enabled ? "armed" : "disarmed"} (previous state: ${previousSecurityState ? "armed" : "disarmed"})',
        metadata: {
          'feature': 'security_system',
          'previousState': previousSecurityState,
          'newState': enabled,
          'bleConnected': isConnected,
          'deviceId': connectedDeviceId,
          'actionType': 'security_toggle',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
    } else {
      Logger.error('BluetoothService: Failed to send security command');
    }
    return success;
  }

  Future<bool> triggerSecurityAlarm({int durationMs = 5000}) async {
    final payload = {'duration': durationMs};
    return await sendCommand(BLEConstants.cmdSOS, payload);
  }

  Future<bool> requestStatus() async {
    return await sendCommand(BLEConstants.cmdGetStatus, null);
  }

  Future<bool> requestSensorSnapshot() async {
    return await sendCommand(BLEConstants.cmdGetSensor, null);
  }

  /// Send hub configuration (room name and primary hub status) to ESP32
  Future<bool> _sendHubConfiguration() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || connectedDeviceId == null) {
        return false;
      }

      final firebaseService = FirebaseService();

      // Get the hub device
      final hubDevice = await firebaseService.getDeviceById(connectedDeviceId!);
      if (hubDevice == null || !hubDevice.isHub) {
        return false; // Not a hub or device not found
      }

      // Get the room for this hub (simplified - no primary hub logic)
      String? roomName;

      if (hubDevice.roomId.isNotEmpty) {
        final rooms = await firebaseService.getUserRooms(user.uid).first;
        final room = rooms.firstWhere(
          (r) => r.id == hubDevice.roomId,
          orElse: () => rooms.firstWhere(
            (r) => r.hubId == connectedDeviceId,
            orElse: () => RoomModel(id: '', name: '', icon: 'home'),
          ),
        );

        roomName = room.name;
      }

      // Send configuration to ESP32 (simplified - no primary hub status)
      final payload = {
        'room_name': roomName ?? '',
        'is_primary': false, // Always false - primary hub logic disabled
      };

      final success = await sendCommand(BLEConstants.cmdSetHubConfig, payload);
      if (success) {
        Logger.info(
          'BluetoothService: Sent hub configuration - Room: $roomName',
        );
      }

      return success;
    } catch (e) {
      Logger.warning('BluetoothService: Failed to send hub configuration: $e');
      return false;
    }
  }

  /// Public method to update hub configuration (called when hub settings change)
  Future<bool> updateHubConfiguration() async {
    return await _sendHubConfiguration();
  }

  // Schedule synchronization methods
  /// Add a schedule to the device
  Future<bool> addScheduleToDevice(ScheduleModel schedule) async {
    if (!isConnected) {
      Logger.warning('BluetoothService: Cannot add schedule - not connected');
      return false;
    }

    try {
      // Convert Firebase document ID to uint8_t (0-255)
      // Use hash of ID to get consistent value
      int scheduleId = schedule.id.hashCode.abs() % 255;
      if (scheduleId == 0) scheduleId = 1; // Ensure non-zero ID

      final payload = {
        'id': scheduleId,
        'hour': schedule.hour,
        'minute': schedule.minute,
        'fan': ((schedule.fanSpeed / 100) * 255).round().clamp(0, 255),
        'led': ((schedule.brightness / 100) * 255).round().clamp(0, 255),
        'enabled': schedule.enabled,
        'repeat': schedule.repeatDaily,
      };

      final success = await sendCommand(BLEConstants.cmdAddSchedule, payload);
      if (success) {
        Logger.info(
            'BluetoothService: Schedule added to device - ID: $scheduleId, Time: ${schedule.hour}:${schedule.minute}');
      } else {
        Logger.error('BluetoothService: Failed to add schedule to device');
      }
      return success;
    } catch (e) {
      Logger.error('BluetoothService: Error adding schedule to device: $e');
      return false;
    }
  }

  /// Delete a schedule from the device
  Future<bool> deleteScheduleFromDevice(ScheduleModel schedule) async {
    if (!isConnected) {
      Logger.warning(
          'BluetoothService: Cannot delete schedule - not connected');
      return false;
    }

    try {
      // Convert Firebase document ID to uint8_t (0-255)
      int scheduleId = schedule.id.hashCode.abs() % 255;
      if (scheduleId == 0) scheduleId = 1; // Ensure non-zero ID

      final payload = {'id': scheduleId};
      final success =
          await sendCommand(BLEConstants.cmdDeleteSchedule, payload);
      if (success) {
        Logger.info(
            'BluetoothService: Schedule deleted from device - ID: $scheduleId');
      } else {
        Logger.error('BluetoothService: Failed to delete schedule from device');
      }
      return success;
    } catch (e) {
      Logger.error('BluetoothService: Error deleting schedule from device: $e');
      return false;
    }
  }

  /// Sync all schedules for the connected device from Firebase
  Future<void> _syncSchedulesToDevice() async {
    if (!isConnected) {
      Logger.warning('BluetoothService: Cannot sync schedules - not connected');
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Logger.warning('BluetoothService: No user, cannot sync schedules');
        return;
      }

      final deviceId = connectedDeviceId ?? '';
      if (deviceId.isEmpty) {
        Logger.warning('BluetoothService: No device ID, cannot sync schedules');
        return;
      }

      Logger.info('BluetoothService: Syncing schedules to device...');
      _emitStatus('Syncing schedules to device...');

      final firebaseService = FirebaseService();
      final schedules = await firebaseService
          .getSchedules(user.uid, deviceId: deviceId)
          .first
          .timeout(const Duration(seconds: 5));

      int syncedCount = 0;
      for (final schedule in schedules) {
        // Only sync schedules for this specific device
        if (schedule.deviceId == deviceId) {
          final success = await addScheduleToDevice(schedule).timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          );
          if (success) {
            syncedCount++;
            // Small delay between schedule sends to avoid overwhelming the device
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
      }

      Logger.success(
          'BluetoothService: Synced $syncedCount schedule(s) to device');
      _emitStatus('Synced $syncedCount schedule(s) to device');
    } catch (e) {
      Logger.error('BluetoothService: Error syncing schedules to device: $e');
      _emitStatus('Schedule sync failed: $e');
    }
  }

  /// Sync a single schedule (for real-time updates)
  Future<bool> syncScheduleToDevice(ScheduleModel schedule) async {
    return await addScheduleToDevice(schedule);
  }

  // Restore appliance state from Firebase
  Future<void> _restoreApplianceState() async {
    try {
      final stateService = ApplianceStateService();
      final state = await stateService.loadApplianceState();

      if (state != null && isConnected) {
        Logger.info(
            'BluetoothService: Restoring appliance state from Firebase');
        final fanSpeed = state['fanSpeed'] as int? ?? 0;
        final ledBrightness = state['ledBrightness'] as int? ?? 0;
        final securityEnabled = state['securityEnabled'] as bool? ?? false;
        final autoMode = state['autoMode'] as bool? ?? false;

        // Restore fan speed
        if (fanSpeed > 0) {
          await setFanSpeed(fanSpeed).timeout(
            const Duration(seconds: 3),
            onTimeout: () => false,
          );
        }

        // Restore ambient light level
        if (ledBrightness > 0) {
          await setLEDBrightness(ledBrightness).timeout(
            const Duration(seconds: 3),
            onTimeout: () => false,
          );
        }

        // Restore security state
        await setSecurityEnabled(securityEnabled).timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        );

        // Restore auto mode
        await setAutoMode(autoMode).timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        );

        Logger.info(
            'BluetoothService: Appliance state restored - Fan: $fanSpeed, LED: $ledBrightness, Security: $securityEnabled, AutoMode: $autoMode');
      }
    } catch (e) {
      Logger.error('BluetoothService: Error restoring state: $e');
    }
  }

  // Cleanup with comprehensive error handling
  void dispose() {
    try {
    _stopHeartbeatTimer();
    _stopInactivityWatchdog();
      _stopSensorPolling();

      // Safely cancel all subscriptions
    unawaited(_connectionStateSub?.cancel());
      unawaited(_dataStreamSubscription?.cancel());

      // Safely close all stream controllers
      try {
    if (!_activityController.isClosed) {
      _activityController.close();
    }
      } catch (e) {
        Logger.debug('Error closing activity controller: $e');
      }

      try {
        if (!_sensorDataController.isClosed) {
    _sensorDataController.close();
        }
      } catch (e) {
        Logger.debug('Error closing sensor data controller: $e');
      }

      try {
        if (!_connectionController.isClosed) {
    _connectionController.close();
        }
      } catch (e) {
        Logger.debug('Error closing connection controller: $e');
      }

      try {
        if (!_statusMessageController.isClosed) {
    _statusMessageController.close();
        }
      } catch (e) {
        Logger.debug('Error closing status message controller: $e');
      }

      // Clear buffers
      _dataBuffer.clear();
      _bufferTimeoutTimer?.cancel();
    } catch (e) {
      // Even dispose errors should be handled gracefully
      Logger.debug('Error during BluetoothService dispose: $e');
    }
  }

  Future<void> _ensureBluetoothReady() async {
    if (await flutter_blue.FlutterBluePlus.isSupported == false) {
      throw Exception('Bluetooth not supported on this device');
    }

    final adapterState = await flutter_blue.FlutterBluePlus.adapterState.first;

    if (adapterState != flutter_blue.BluetoothAdapterState.on) {
      throw Exception(
        adapterState == flutter_blue.BluetoothAdapterState.off
            ? 'Bluetooth is turned off. Please enable it.'
            : 'Bluetooth is not ready ($adapterState).',
      );
    }
  }

  // Duplicate removed - using safe version defined earlier

  void _logBluetoothEvent({
    required String action,
    String? reason,
    bool? manual,
    bool? unexpected,
  }) {
    final deviceName = _connectedDevice?.advName ??
        _lastConnectedDevice?.advName ??
        'Unknown Device';
    final deviceId = _connectedDevice?.remoteId.toString() ??
        _lastConnectedDevice?.remoteId.toString();

    unawaited(_loggingService.logAction(
      action: action,
      category: 'bluetooth',
      details: reason ?? '',
      metadata: {
        'deviceName': deviceName,
        'deviceId': deviceId,
        'manual': manual,
        'unexpected': unexpected,
        'timestamp': DateTime.now().toIso8601String(),
      },
      level: LogLevel.info,
    ));
  }
}
