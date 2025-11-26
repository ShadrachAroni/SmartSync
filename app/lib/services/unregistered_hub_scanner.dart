import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue;
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/logger.dart';
import '../core/constants/ble_constants.dart';
import 'firebase_service.dart';
import 'notification_service.dart';
import 'bluetooth_service.dart';

/// Service to periodically scan for unregistered hubs and prompt user to register them
class UnregisteredHubScanner {
  static final UnregisteredHubScanner _instance = UnregisteredHubScanner._internal();
  factory UnregisteredHubScanner() => _instance;
  UnregisteredHubScanner._internal();

  Timer? _scanTimer;
  bool _isScanning = false;
  final FirebaseService _firebaseService = FirebaseService();
  final Set<String> _notifiedHubIds = {}; // Track hubs we've already notified about
  final StreamController<Map<String, String>> _unregisteredHubController =
      StreamController<Map<String, String>>.broadcast();
  
  /// Stream of unregistered hubs (hubId -> hubName)
  Stream<Map<String, String>> get unregisteredHubsStream =>
      _unregisteredHubController.stream;

  /// Start periodic scanning for unregistered hubs
  void startPeriodicScan() {
    if (_scanTimer != null) {
      return; // Already running
    }

    Logger.info('UnregisteredHubScanner: Starting periodic scan for unregistered hubs');
    
    // Scan every 5 minutes
    _scanTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await _scanForUnregisteredHubs();
    });

    // Also do an initial scan after 30 seconds
    Future.delayed(const Duration(seconds: 30), () {
      _scanForUnregisteredHubs();
    });
  }

  /// Stop periodic scanning
  void stopPeriodicScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isScanning = false;
    Logger.info('UnregisteredHubScanner: Stopped periodic scan');
  }

  /// Scan for unregistered hubs
  Future<void> _scanForUnregisteredHubs() async {
    if (_isScanning) {
      return; // Already scanning
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return; // No user logged in
    }

    _isScanning = true;

    try {
      Logger.info('UnregisteredHubScanner: Scanning for unregistered hubs...');

      // Get all registered hub devices for this user
      final registeredDevices = await _firebaseService.fetchUserDevices(user.uid);
      final registeredHubIds = registeredDevices
          .where((d) => d.isHub)
          .map((d) => d.id)
          .toSet();

      // Scan for BLE devices
      final discoveredHubs = <String, flutter_blue.BluetoothDevice>{};
      
      try {
        await flutter_blue.FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 10),
          androidUsesFineLocation: false,
        );

        final completer = Completer<void>();
        StreamSubscription<List<flutter_blue.ScanResult>>? subscription;
        Timer? timeoutTimer;

        subscription = flutter_blue.FlutterBluePlus.scanResults.listen((results) {
          for (final result in results) {
            final deviceId = result.device.remoteId.toString();
            final deviceName = result.device.advName;
            
            // Check if this is a SmartSync hub
            final isHub = deviceName.contains('SmartSync') ||
                deviceName.contains('ESP32') ||
                deviceName.startsWith('SmartSync');
            
            // Also check by service UUID
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
              Logger.debug('Error checking service UUID: $e');
            }

            if (isHub || matchesServiceUuid) {
              // Check if this hub is registered
              if (!registeredHubIds.contains(deviceId)) {
                discoveredHubs[deviceId] = result.device;
                Logger.info(
                  'UnregisteredHubScanner: Found unregistered hub: $deviceName ($deviceId)',
                );
              }
            }
          }
        });

        timeoutTimer = Timer(const Duration(seconds: 10), () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        });

        await completer.future;
        await subscription.cancel();
        await flutter_blue.FlutterBluePlus.stopScan();
      } catch (e) {
        Logger.warning('UnregisteredHubScanner: Error during scan: $e');
        try {
          await flutter_blue.FlutterBluePlus.stopScan();
        } catch (_) {
          // Ignore stop scan errors
        }
      }

      // Notify about unregistered hubs (only once per hub and only if not currently connected)
      final bluetoothService = BluetoothService();
      final isCurrentlyConnected = bluetoothService.isConnected;
      final connectedDeviceId = bluetoothService.connectedDeviceId;
      
      for (final entry in discoveredHubs.entries) {
        final hubId = entry.key;
        final device = entry.value;
        
        // Don't notify if this hub is currently connected (connection flow will handle registration)
        if (isCurrentlyConnected && connectedDeviceId == hubId) {
          Logger.debug('UnregisteredHubScanner: Hub $hubId is currently connected, skipping notification');
          continue;
        }
        
        if (!_notifiedHubIds.contains(hubId)) {
          _notifiedHubIds.add(hubId);
          Logger.info(
            'UnregisteredHubScanner: Unregistered hub detected: ${device.advName} ($hubId)',
          );
          
          // Emit event for UI to listen to
          _unregisteredHubController.add({hubId: device.advName.isNotEmpty ? device.advName : 'SmartSync Hub'});
          
          // Only show notification if hub is not connected (connection flow will show dialog)
          if (!isCurrentlyConnected || connectedDeviceId != hubId) {
            try {
              final notificationService = NotificationService();
              await notificationService.showLocalNotification(
                id: (DateTime.now().millisecondsSinceEpoch + 6) % 2147483647,
                title: '🔍 Unregistered Hub Found',
                body: '${device.advName.isNotEmpty ? device.advName : "SmartSync Hub"} needs to be registered to a room.',
                payload: jsonEncode({
                  'type': 'unregistered_hub',
                  'deviceId': hubId,
                  'deviceName': device.advName.isNotEmpty ? device.advName : 'SmartSync Hub',
                }),
              );
            } catch (e) {
              Logger.warning('Failed to send unregistered hub notification: $e');
            }
          }
        }
      }

      if (discoveredHubs.isEmpty) {
        Logger.debug('UnregisteredHubScanner: No unregistered hubs found');
      } else {
        Logger.info(
          'UnregisteredHubScanner: Found ${discoveredHubs.length} unregistered hub(s)',
        );
      }
    } catch (e, stackTrace) {
      Logger.error(
        'UnregisteredHubScanner: Error scanning for unregistered hubs: $e',
        e,
        stackTrace,
      );
    } finally {
      _isScanning = false;
    }
  }

  /// Get list of unregistered hub IDs (for UI to check)
  Set<String> getNotifiedHubIds() {
    return Set.from(_notifiedHubIds);
  }

  /// Clear notification for a hub (after user registers it)
  void clearNotification(String hubId) {
    _notifiedHubIds.remove(hubId);
  }

  /// Cleanup
  void dispose() {
    stopPeriodicScan();
    _notifiedHubIds.clear();
    _unregisteredHubController.close();
  }
}

