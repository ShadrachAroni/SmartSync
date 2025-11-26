import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue;
import '../services/bluetooth_service.dart';
import '../services/firebase_service.dart';
import '../models/device_model.dart';
import '../core/utils/logger.dart';
import '../core/constants/ble_constants.dart';

/// Service to automatically reconnect hub devices when app reopens
class HubReconnectionService {
  static final HubReconnectionService _instance = HubReconnectionService._internal();
  factory HubReconnectionService() => _instance;

  final BluetoothService _bluetoothService = BluetoothService();
  final FirebaseService _firebaseService = FirebaseService();
  
  bool _isReconnecting = false;
  bool _isInitialized = false;
  Timer? _reconnectionTimer;
  Timer? _persistentReconnectTimer; // Persistent reconnection timer
  bool _persistentReconnectEnabled = true; // Enable persistent reconnection
  DateTime? _lastReconnectAttempt; // Track last reconnection attempt
  int _consecutiveFailures = 0; // Track consecutive failures
  static const Duration _reconnectCooldown = Duration(seconds: 60); // Cooldown after failures

  HubReconnectionService._internal();

  /// Initialize the service (call once when app starts)
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    Logger.info('HubReconnectionService: Initialized');
    
    // Start persistent reconnection timer - checks every 30 seconds
    _startPersistentReconnection();
  }
  
  /// Start persistent reconnection that keeps trying to connect
  void _startPersistentReconnection() {
    _stopPersistentReconnection();
    
    _persistentReconnectTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_persistentReconnectEnabled) return;
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // Only reconnect if not already connected
      if (_bluetoothService.isConnected) {
        _consecutiveFailures = 0; // Reset on successful connection
        return; // Already connected, no need to reconnect
      }
      
      // Don't interfere with active reconnection attempts
      if (_isReconnecting) {
        return;
      }
      
      // Check cooldown period after failures
      if (_lastReconnectAttempt != null && _consecutiveFailures >= 3) {
        final timeSinceLastAttempt = DateTime.now().difference(_lastReconnectAttempt!);
        if (timeSinceLastAttempt < _reconnectCooldown) {
          final remainingSeconds = (_reconnectCooldown - timeSinceLastAttempt).inSeconds;
          Logger.debug('HubReconnectionService: In cooldown period (${remainingSeconds}s remaining)');
          return;
        }
      }
      
      Logger.info('HubReconnectionService: Persistent reconnection check - attempting to reconnect...');
      await _reconnectDisconnectedHubs(user.uid);
    });
    
    Logger.info('HubReconnectionService: Persistent reconnection started (checks every 30s)');
  }
  
  /// Stop persistent reconnection
  void _stopPersistentReconnection() {
    _persistentReconnectTimer?.cancel();
    _persistentReconnectTimer = null;
  }
  
  /// Force reconnect to registered hubs (can be called manually)
  Future<bool> forceReconnect() async {
    // Prevent multiple simultaneous force reconnects
    if (_isReconnecting) {
      Logger.warning('HubReconnectionService: Reconnection already in progress');
      return _bluetoothService.isConnected;
    }
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Logger.warning('HubReconnectionService: Cannot force reconnect - no user');
      return false;
    }
    
    Logger.info('HubReconnectionService: Force reconnect requested');
    // Reset cooldown for manual reconnect
    _consecutiveFailures = 0;
    _lastReconnectAttempt = null;
    await _reconnectDisconnectedHubs(user.uid);
    return _bluetoothService.isConnected;
  }

  /// Handle app lifecycle change - called when app comes to foreground
  Future<void> onAppResumed() async {
    if (_isReconnecting) {
      Logger.debug('HubReconnectionService: Reconnection already in progress, skipping');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Logger.debug('HubReconnectionService: No user logged in, skipping reconnection');
      return;
    }

    // Wait a bit for Bluetooth to be ready
    await Future.delayed(const Duration(seconds: 2));

    Logger.info('HubReconnectionService: App resumed, checking for disconnected hubs...');
    await _reconnectDisconnectedHubs(user.uid);
  }

  /// Reconnect all disconnected hub devices for the user
  Future<void> _reconnectDisconnectedHubs(String userId) async {
    if (_isReconnecting) return;
    
    _isReconnecting = true;
    
    try {
      // Get all hub devices for the user
      final allDevices = await _firebaseService.fetchUserDevices(userId);
      final hubDevices = allDevices.where((d) => d.isHub).toList();

      if (hubDevices.isEmpty) {
        Logger.debug('HubReconnectionService: No hub devices found for user');
        _isReconnecting = false;
        return;
      }

      Logger.info('HubReconnectionService: Found ${hubDevices.length} hub device(s)');

      // Check which hubs are disconnected (simplified - no primary hub prioritization)
      final disconnectedHubs = <DeviceModel>[];
      
      for (final hub in hubDevices) {
        final isConnected = _bluetoothService.isConnected && 
                           _bluetoothService.connectedDeviceId == hub.id;
        
        if (!isConnected) {
          disconnectedHubs.add(hub);
          Logger.debug('HubReconnectionService: Hub ${hub.name} (${hub.id}) is disconnected');
        } else {
          Logger.debug('HubReconnectionService: Hub ${hub.name} (${hub.id}) is already connected');
        }
      }

      if (disconnectedHubs.isEmpty) {
        Logger.info('HubReconnectionService: All hubs are already connected');
        _isReconnecting = false;
        return;
      }

      Logger.info('HubReconnectionService: Attempting to reconnect ${disconnectedHubs.length} disconnected hub(s)');

      // Attempt to reconnect each disconnected hub (one at a time since BluetoothService only connects to one device)
      // Simple reconnection - no prioritization, just reconnect first available hub
      bool reconnected = false;
      for (final hub in disconnectedHubs) {
        Logger.info('HubReconnectionService: Attempting to reconnect hub: ${hub.name}');
        
        await _reconnectHub(hub);
        
        // Small delay between reconnection attempts to avoid overwhelming Bluetooth
        // Longer delay if we just connected (to let connection stabilize)
        if (_bluetoothService.isConnected && 
            _bluetoothService.connectedDeviceId == hub.id) {
          Logger.info('HubReconnectionService: Successfully reconnected to ${hub.name}, connection stabilized');
          _consecutiveFailures = 0; // Reset on success
          _lastReconnectAttempt = null; // Clear cooldown
          reconnected = true;
          await Future.delayed(const Duration(seconds: 5)); // Longer delay to let connection stabilize
          // If we successfully connected to a hub, stop trying others (only one connection at a time)
          break;
        } else {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
      
      // Track failures for cooldown
      if (!reconnected) {
        _consecutiveFailures++;
        _lastReconnectAttempt = DateTime.now();
        Logger.warning('HubReconnectionService: Reconnection failed (consecutive failures: $_consecutiveFailures)');
        if (_consecutiveFailures >= 3) {
          Logger.warning('HubReconnectionService: Entering cooldown period after $_consecutiveFailures failures');
        }
      }

      Logger.success('HubReconnectionService: Finished reconnection attempts');
    } catch (e, stackTrace) {
      Logger.error('HubReconnectionService: Error during reconnection: $e', e, stackTrace);
    } finally {
      _isReconnecting = false;
    }
  }

  /// Attempt to reconnect a specific hub device
  Future<void> _reconnectHub(DeviceModel hub) async {
    try {
      Logger.info('HubReconnectionService: Attempting to reconnect hub: ${hub.name} (${hub.id})');

      // Scan for the specific device
      flutter_blue.BluetoothDevice? foundDevice;
      
      try {
        await flutter_blue.FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 10),
          androidUsesFineLocation: false,
        );

        final completer = Completer<flutter_blue.BluetoothDevice?>();
        StreamSubscription<List<flutter_blue.ScanResult>>? subscription;
        Timer? timeoutTimer;

        subscription = flutter_blue.FlutterBluePlus.scanResults.listen((results) {
          for (final result in results) {
            final deviceId = result.device.remoteId.toString();
            final deviceName = result.device.advName;
            
            // Method 1: Match by device ID (most reliable for known device)
            final matchesId = deviceId == hub.id;
            
            // Method 2: Check if device name matches (for devices registered with name)
            final matchesName = deviceName.startsWith(BLEConstants.deviceNamePrefix);
            
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
              Logger.debug('Error checking service UUID in hub reconnect: $e');
            }

            if (matchesId || (matchesName && matchesServiceUuid && deviceId == hub.id)) {
              if (!completer.isCompleted) {
                Logger.info(
                  'HubReconnectionService: Found hub "$deviceName" (ID: $deviceId)',
                );
                completer.complete(result.device);
                timeoutTimer?.cancel();
              }
              break;
            }
          }
        });

        // Set timeout to complete with null if device not found
        timeoutTimer = Timer(const Duration(seconds: 10), () {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        });

        foundDevice = await completer.future;

        await subscription.cancel();
        if (timeoutTimer != null) {
          timeoutTimer.cancel();
        }
        await flutter_blue.FlutterBluePlus.stopScan();
      } catch (e) {
        Logger.warning('HubReconnectionService: Error during scan: $e');
        try {
          await flutter_blue.FlutterBluePlus.stopScan();
        } catch (_) {
          // Ignore stop scan errors
        }
      }

      if (foundDevice == null) {
        Logger.warning('HubReconnectionService: Hub ${hub.name} (${hub.id}) not found during scan');
        return;
      }

      Logger.info('HubReconnectionService: Found hub ${hub.name}, attempting connection...');

      // Attempt to connect with multiple retry strategies
      bool success = false;
      
      // Strategy 1: Direct connection attempt
      Logger.info('HubReconnectionService: Attempting direct connection...');
      success = await _bluetoothService.connectToDevice(
        foundDevice,
        isReconnect: true,
      );
      
      if (success) {
        Logger.success('HubReconnectionService: Successfully reconnected hub: ${hub.name}');
        return;
      }
      
      // Strategy 2: Force disconnect and retry (for stuck connections)
      Logger.info('HubReconnectionService: Direct connection failed, trying force disconnect and retry...');
      try {
        await foundDevice.disconnect();
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        Logger.debug('Error during force disconnect: $e');
      }
      
      success = await _bluetoothService.connectToDevice(
        foundDevice,
        isReconnect: true,
      );
      
      if (success) {
        Logger.success('HubReconnectionService: Successfully reconnected hub after force disconnect: ${hub.name}');
        return;
      }
      
      // Strategy 3: Reset Bluetooth service state and retry
      Logger.info('HubReconnectionService: Connection still failed, resetting Bluetooth state and retrying...');
      try {
        await _bluetoothService.resetConnectionState();
        await Future.delayed(const Duration(seconds: 3));
      } catch (e) {
        Logger.debug('Error resetting connection state: $e');
      }
      
      // Rescan to get fresh device reference
      try {
        await flutter_blue.FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 5),
          androidUsesFineLocation: false,
        );
        
        final completer2 = Completer<flutter_blue.BluetoothDevice?>();
        StreamSubscription<List<flutter_blue.ScanResult>>? subscription2;
        Timer? timeoutTimer2;
        
        subscription2 = flutter_blue.FlutterBluePlus.scanResults.listen((results) {
          for (final result in results) {
            if (result.device.remoteId.toString() == hub.id) {
              if (!completer2.isCompleted) {
                completer2.complete(result.device);
                timeoutTimer2?.cancel();
              }
              break;
            }
          }
        });
        
        timeoutTimer2 = Timer(const Duration(seconds: 5), () {
          if (!completer2.isCompleted) {
            completer2.complete(null);
          }
        });
        
        final freshDevice = await completer2.future;
        await subscription2.cancel();
        timeoutTimer2?.cancel();
        await flutter_blue.FlutterBluePlus.stopScan();
        
        if (freshDevice != null) {
          success = await _bluetoothService.connectToDevice(
            freshDevice,
            isReconnect: true,
          );
        }
      } catch (e) {
        Logger.warning('Error in rescan strategy: $e');
      }
      
      if (success) {
        Logger.success('HubReconnectionService: Successfully reconnected hub after reset: ${hub.name}');
      } else {
        Logger.warning('HubReconnectionService: All reconnection strategies failed for hub: ${hub.name}');
      }
    } catch (e, stackTrace) {
      Logger.error('HubReconnectionService: Error reconnecting hub ${hub.name}: $e', e, stackTrace);
    }
  }

  /// Cleanup
  void dispose() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    _stopPersistentReconnection();
    _isInitialized = false;
  }
}

