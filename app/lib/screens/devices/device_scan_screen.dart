import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue;
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/bluetooth_service.dart';
import '../../services/firebase_service.dart';
import '../../models/sensor_data.dart';
import '../../models/room_model.dart';
import '../../models/device_model.dart';
import '../../core/utils/logger.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../../providers/device_provider.dart';
import 'device_registration_dialog.dart';

// Provider for BLE scanning state
final isScanningProvider = StateProvider<bool>((ref) => false);
final scannedDevicesProvider =
    StateProvider<List<flutter_blue.BluetoothDevice>>((ref) => []);

class DeviceScanScreen extends ConsumerStatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  ConsumerState<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends ConsumerState<DeviceScanScreen> {
  final BluetoothService _bluetoothService = BluetoothService();
  bool _isConnecting = false;
  String? _connectingDeviceId;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // Check Bluetooth permissions
    if (await Permission.bluetoothScan.isDenied) {
      await Permission.bluetoothScan.request();
    }
    if (await Permission.bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    }
    if (await Permission.location.isDenied) {
      await Permission.location.request();
    }
  }

  Future<void> _startScan() async {
    try {
      // CRITICAL: Ensure any previous scans are stopped before starting new scan
      // This prevents "scan already in progress" errors
      try {
        await flutter_blue.FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 200)); // Brief delay for cleanup
      } catch (e) {
        Logger.debug('Error stopping previous scan (may not be running): $e');
      }
      
      // CRITICAL: Reset connection state if needed to allow scanning
      // If connection state is confused (firmware thinks connected but app doesn't), reset it
      if (!_bluetoothService.isConnected) {
        try {
          await _bluetoothService.resetConnectionState();
        } catch (e) {
          Logger.debug('Error resetting connection state: $e');
        }
      }
      
      ref.read(isScanningProvider.notifier).state = true;
      ref.read(scannedDevicesProvider.notifier).state = [];

      Logger.info('Starting BLE scan...');

      // First try SmartSync-specific scan
      var devices = await _bluetoothService.scanForDevices(
        timeout: const Duration(seconds: 15),
      );

      // Enhanced: If no SmartSync devices found, scan for all devices
      if (devices.isEmpty) {
        Logger.info('No SmartSync devices found, scanning for all BLE devices...');
        devices = await _bluetoothService.scanForAllDevices(
          timeout: const Duration(seconds: 10),
        );
      }

      if (mounted) {
        ref.read(scannedDevicesProvider.notifier).state = devices;
        ref.read(isScanningProvider.notifier).state = false;

        if (devices.isEmpty) {
          _showMessage('No BLE devices found nearby', isError: true);
        } else {
          _showMessage('Found ${devices.length} device(s)');
        }
      }
    } catch (e) {
      Logger.error('Scan error: $e');
      if (mounted) {
        ref.read(isScanningProvider.notifier).state = false;
        // Check if Bluetooth is turned off
        final errorMessage = e.toString().toLowerCase();
        if (errorMessage.contains('bluetooth is turned off') || 
            errorMessage.contains('bluetooth is not ready')) {
          _showMessage('Turn on Bluetooth to scan', isError: true);
        } else if (errorMessage.contains('scan already in progress') ||
                   errorMessage.contains('already scanning')) {
          // If scan is already in progress, try to stop and retry
          try {
            await flutter_blue.FlutterBluePlus.stopScan();
            await Future.delayed(const Duration(milliseconds: 500));
            // Retry scan after stopping
            _startScan();
          } catch (retryError) {
            _showMessage('Failed to scan: ${e.toString()}', isError: true);
          }
        } else {
          _showMessage('Failed to scan: ${e.toString()}', isError: true);
        }
      }
    }
  }

  Future<void> _connectToDevice(flutter_blue.BluetoothDevice device) async {
    // Prevent multiple simultaneous connection attempts
    if (_isConnecting) {
      Logger.warning('Connection already in progress, ignoring duplicate request');
      return;
    }

    final deviceId = device.remoteId.toString();
    
    // Check if already connected to this device
    if (_bluetoothService.isConnected && 
        _bluetoothService.connectedDeviceId == deviceId) {
      Logger.info('Already connected to ${device.advName}');
      _showMessage('Already connected to ${device.advName}');
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectingDeviceId = deviceId;
    });

    try {
      Logger.info('Connecting to ${device.advName}...');

      print('🔍 [DEBUG] Starting connection to device: ${device.advName}');
      Logger.info('🔍 [DEBUG] Starting connection to device: ${device.advName}');
      
      bool success = false;
      try {
        // CRITICAL: Wrap connection in try-catch with timeout
        success = await _bluetoothService.connectToDevice(device).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            Logger.error('Connection timed out after 30 seconds');
            print('🔍 [DEBUG] Connection timed out');
            return false;
          },
        );
      } catch (e, stackTrace) {
        Logger.error('🔍 [DEBUG] Connection exception: $e', e, stackTrace);
        print('🔍 [DEBUG] Connection exception: $e');
        success = false;
      }
      
      print('🔍 [DEBUG] Connection result: $success');
      Logger.info('🔍 [DEBUG] Connection result: $success');

      // CRITICAL: Check if widget is still mounted before any UI operations
      if (!mounted) {
        print('🔍 [DEBUG] Widget not mounted, aborting');
        Logger.warning('🔍 [DEBUG] Widget not mounted after connection, aborting');
        return;
      }

      print('🔍 [DEBUG] Widget still mounted, updating state');
      try {
        setState(() {
          _isConnecting = false;
          _connectingDeviceId = null;
        });
        print('🔍 [DEBUG] State updated');
      } catch (e, stackTrace) {
        Logger.error('🔍 [DEBUG] Error updating state: $e', e, stackTrace);
        print('🔍 [DEBUG] State update exception: $e');
      }

      // Check if device is a hub
      final deviceId = device.remoteId.toString();
      final isHub = device.advName.contains('SmartSync') ||
          device.advName.contains('ESP32') ||
          device.advName.startsWith('SmartSync');
      
      final user = FirebaseAuth.instance.currentUser;
      
      if (success) {
        print('🔍 [DEBUG] Connection successful, showing message');
        try {
          _showMessage('Connected to ${device.advName}!');
          print('🔍 [DEBUG] Message shown');
        } catch (e) {
          Logger.warning('🔍 [DEBUG] Error showing message: $e');
        }
        
        // CRITICAL: Check if device is registered in Firebase
        print('🔍 [DEBUG] Checking Firebase for device registration');
        if (user != null) {
          print('🔍 [DEBUG] User found: ${user.uid}');
            try {
              print('🔍 [DEBUG] Getting Firebase service');
              final firebaseService = FirebaseService();
              print('🔍 [DEBUG] Checking device in Firebase: $deviceId');
              final existingDevice = await firebaseService.getDeviceById(deviceId);
              print('🔍 [DEBUG] Firebase check result: ${existingDevice != null ? "Found" : "Not found"}');
              
              if (existingDevice == null) {
              // Check if this is an ESP32 hub (SmartSync device)
              // ESP32 hubs typically have "SmartSync" in their name or match the BLE prefix
              
              if (isHub) {
                // Auto-register hub to first available room
                Logger.info('Auto-registering hub $deviceId');
                final registered = await _autoRegisterHub(
                  deviceId,
                  device.advName.isNotEmpty ? device.advName : 'SmartSync Hub',
                );
                
                if (registered) {
                  _showMessage('Hub registered successfully!');
                } else {
                  _showMessage('Hub registration failed. Please try again.', isError: true);
                }
              } else {
                // Regular device registration
                SensorData? initialSensorData;
                try {
                  Logger.info('DeviceRegistration: Waiting for initial sensor data for auto-detection...');
                  initialSensorData = await _bluetoothService.getFirstSensorData(
                    timeout: const Duration(seconds: 3),
                  );
                  
                  if (initialSensorData != null) {
                    Logger.info('DeviceRegistration: Received initial sensor data for auto-detection');
                  }
                } catch (e) {
                  Logger.warning('DeviceRegistration: Could not get initial sensor data: $e');
                }
                
                // Show registration dialog with auto-detection
                Logger.info('DeviceRegistration: Device $deviceId not found, showing registration dialog');
                final registered = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => DeviceRegistrationDialog(
                    deviceId: deviceId,
                    deviceName: device.advName.isNotEmpty 
                        ? device.advName 
                        : 'SmartSync Device',
                    initialSensorData: initialSensorData,
                  ),
                );
                
                if (registered == true) {
                  _showMessage('Device registered successfully!');
                  // Invalidate device provider to refresh device list
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    ref.invalidate(deviceControllerProvider(user.uid));
                  }
                }
              }
            } else {
              // Device already exists in Firebase
              // Check if it's a hub and if it needs re-registration
              final isHubDevice = device.advName.contains('SmartSync') ||
                  device.advName.contains('ESP32') ||
                  device.advName.startsWith('SmartSync') ||
                  existingDevice.isHub;
              
              if (isHubDevice && (!existingDevice.isHub || existingDevice.roomId.isEmpty)) {
                // Hub exists but isn't properly registered as a hub or has no room
                // Auto-register to fix this
                Logger.info('Hub $deviceId exists but not properly registered, auto-registering');
                final registered = await _autoRegisterHub(
                  deviceId,
                  device.advName.isNotEmpty 
                      ? device.advName 
                      : existingDevice.name.isNotEmpty
                          ? existingDevice.name
                          : 'SmartSync Hub',
                );
                
                if (registered) {
                  _showMessage('Hub registration updated!');
                } else {
                  _showMessage('Hub registration update failed.', isError: true);
                }
              } else if (existingDevice.isHub) {
                Logger.info('Hub $deviceId already registered in room ${existingDevice.roomId}');
              } else {
                Logger.info('Device $deviceId already registered in room ${existingDevice.roomId}');
              }
            }
          } catch (e, stackTrace) {
            Logger.error('🔍 [DEBUG] Firebase check error: $e', e, stackTrace);
            print('🔍 [DEBUG] Firebase check exception: $e');
            print('🔍 [DEBUG] Stack trace: $stackTrace');
          }
        } else {
          print('🔍 [DEBUG] No user found');
        }
      } else {
        // Connection failed
        _showMessage('Connection failed. Please try again.', isError: true);
      }
      
      // CRITICAL: Navigate back to home screen with proper error handling
      print('🔍 [DEBUG] Preparing to navigate back to home screen');
      Logger.info('🔍 [DEBUG] Preparing to navigate back to home screen');
      
      // CRITICAL: Delay ensures home screen is ready before navigation
      // Also allows any pending operations to complete
      await Future.delayed(const Duration(milliseconds: 500));
      print('🔍 [DEBUG] Delay completed, checking if mounted');
      
      // CRITICAL: Multiple checks before navigation
      if (!mounted) {
        print('🔍 [DEBUG] Widget not mounted, skipping navigation');
        Logger.warning('🔍 [DEBUG] Widget not mounted, skipping navigation');
        return;
      }
      
      // CRITICAL: Check if context is still valid
      if (!context.mounted) {
        print('🔍 [DEBUG] Context not mounted, skipping navigation');
        Logger.warning('🔍 [DEBUG] Context not mounted, skipping navigation');
        return;
      }
      
      print('🔍 [DEBUG] Widget and context mounted, calling Navigator.pop()');
      Logger.info('🔍 [DEBUG] Calling Navigator.pop()');
      
      try {
        // CRITICAL: Use Navigator.maybePop for safer navigation
        final navigator = Navigator.of(context);
        final canPop = navigator.canPop();
        
        if (canPop) {
          navigator.pop();
          print('🔍 [DEBUG] Navigator.pop() completed');
          Logger.info('🔍 [DEBUG] Navigator.pop() completed successfully');
        } else {
          print('🔍 [DEBUG] Cannot pop - no routes to pop');
          Logger.warning('🔍 [DEBUG] Cannot pop - no routes to pop');
          // CRITICAL: If can't pop, try pushing home route instead
          try {
            navigator.pushReplacementNamed('/home');
            print('🔍 [DEBUG] Pushed home route as fallback');
          } catch (e) {
            Logger.error('🔍 [DEBUG] Failed to push home route: $e');
          }
        }
      } catch (e, stackTrace) {
        Logger.error('🔍 [DEBUG] Navigator.pop() error: $e', e, stackTrace);
        print('🔍 [DEBUG] Navigator.pop() exception: $e');
        print('🔍 [DEBUG] Stack trace: $stackTrace');
        
        // CRITICAL: Try alternative navigation method if pop fails
        try {
          if (mounted && context.mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/home',
              (route) => false,
            );
            print('🔍 [DEBUG] Used pushNamedAndRemoveUntil as fallback');
          }
        } catch (fallbackError) {
          Logger.error('🔍 [DEBUG] Fallback navigation also failed: $fallbackError');
          print('🔍 [DEBUG] Fallback navigation exception: $fallbackError');
        }
      }
    } catch (e) {
      Logger.error('Connection error: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectingDeviceId = null;
        });
        _showMessage('Connection failed: ${e.toString()}', isError: true);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    AppNotifications.showSnackBar(
      context,
      message: message,
      type: isError ? AppNotificationType.error : AppNotificationType.success,
    );
  }

  /// Auto-register hub to first available room (or create default room)
  /// This replaces the hub registration dialog for simplicity
  Future<bool> _autoRegisterHub(String hubId, String hubName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Logger.warning('Cannot auto-register hub: No user logged in');
      return false;
    }

    try {
      final firebaseService = FirebaseService();
      
      // Get all rooms for the user
      final rooms = await firebaseService.getUserRooms(user.uid).first;
      
      // Find first available room (room without a hub)
      RoomModel? targetRoom;
      for (var room in rooms) {
        if (room.hubId == null || room.hubId!.isEmpty) {
          targetRoom = room;
          break;
        }
      }
      
      String roomId;
      String roomName;
      
      // If no available room, create a default "Home" room
      if (targetRoom == null) {
        Logger.info('No available room found, creating default "Home" room');
        final defaultRoom = RoomModel(
          id: '', // Will be generated by Firestore
          name: 'Home',
          icon: 'home',
          deviceIds: [],
          hubId: hubId,
          isPrimaryHub: false, // Disabled for simplicity
        );
        roomId = await firebaseService.addRoom(user.uid, defaultRoom);
        roomName = 'Home';
        
        // Update the room with hubId after creation
        await firebaseService.updateRoom(user.uid, roomId, {
          'hubId': hubId,
        });
      } else {
        // Use existing room
        roomId = targetRoom.id;
        roomName = targetRoom.name;
        
        // Update room with hubId
        await firebaseService.updateRoom(user.uid, roomId, {
          'hubId': hubId,
        });
      }
      
      // Primary hub logic disabled for simplicity - just basic connection
      
      // Register the hub as a device
      final hubDevice = DeviceModel(
        id: hubId,
        name: hubName.isNotEmpty ? hubName : 'SmartSync Hub',
        type: DeviceType.hub,
        roomId: roomId,
        isOn: false,
        value: 0,
        isOnline: true,
        lastSeen: DateTime.now(),
        metadata: {
          'bleName': hubName,
          'registeredAt': DateTime.now().toIso8601String(),
          'isHub': true,
          'autoRegistered': true,
        },
        isHub: true,
      );
      
      await firebaseService.addDevice(user.uid, hubDevice);
      Logger.info('Auto-registered hub: Hub device $hubId registered in Firebase');
      
      // Create virtual devices for fan and light that belong to this hub
      final fanDevice = DeviceModel(
        id: '${hubId}_fan',
        name: '$roomName Fan',
        type: DeviceType.fan,
        roomId: roomId,
        isOn: false,
        value: 0,
        isOnline: true,
        lastSeen: DateTime.now(),
        metadata: {
          'hubId': hubId,
          'isVirtual': true,
        },
        hubId: hubId,
      );
      
      final lightDevice = DeviceModel(
        id: '${hubId}_light',
        name: '$roomName Light',
        type: DeviceType.light,
        roomId: roomId,
        isOn: false,
        value: 0,
        isOnline: true,
        lastSeen: DateTime.now(),
        metadata: {
          'hubId': hubId,
          'isVirtual': true,
        },
        hubId: hubId,
      );
      
      await firebaseService.addDevice(user.uid, fanDevice);
      await firebaseService.addDevice(user.uid, lightDevice);
      Logger.info('Auto-registered hub: Created virtual fan and light devices for hub $hubId');
      
      // Add all devices to room
      await firebaseService.addDeviceToRoom(user.uid, roomId, hubId);
      await firebaseService.addDeviceToRoom(user.uid, roomId, fanDevice.id);
      await firebaseService.addDeviceToRoom(user.uid, roomId, lightDevice.id);
      
      // Invalidate device provider to refresh device list
      ref.invalidate(deviceControllerProvider(user.uid));
      
      Logger.info('Auto-registered hub: Hub $hubId successfully registered to room $roomId ($roomName)');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Auto-register hub error: $e', e, stackTrace);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isScanning = ref.watch(isScanningProvider);
    final devices = ref.watch(scannedDevicesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: const Text(
          'Add Device',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final isSmallScreen = screenWidth < 360;
            final padding = isSmallScreen ? 16.0 : 24.0;
            final iconSize = isSmallScreen ? 40.0 : 48.0;
            final titleFontSize = isSmallScreen ? 18.0 : 22.0;
            final subtitleFontSize = isSmallScreen ? 12.0 : 14.0;
            final buttonHeight = isSmallScreen ? 48.0 : 56.0;
            
            return Column(
              children: [
                // Header Section
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(padding),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1A1F3A),
                        const Color(0xFF0F1419),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00BFA5).withOpacity(0.2),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00BFA5).withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.bluetooth_searching_rounded,
                          size: iconSize,
                          color: const Color(0xFF00BFA5),
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),
                      Text(
                        'Scan for SmartSync Devices',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 6 : 8),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 0),
                        child: Text(
                          'Make sure your device is powered on and nearby',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: subtitleFontSize,
                            color: Colors.white.withOpacity(0.7),
                            height: 1.5,
                          ),
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 16 : 24),

                      // Scan Button
                      SizedBox(
                        width: double.infinity,
                        height: buttonHeight,
                        child: ElevatedButton.icon(
                          onPressed:
                              isScanning || _isConnecting ? null : _startScan,
                          icon: Icon(
                            isScanning
                                ? Icons.refresh_rounded
                                : Icons.search_rounded,
                            size: isSmallScreen ? 20 : 24,
                          ),
                          label: Text(
                            isScanning ? 'Scanning...' : 'Start Scan',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 16 : 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00BFA5),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade700,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Devices List
                Expanded(
                  child: isScanning
                      ? _buildScanningIndicator()
                      : devices.isEmpty
                          ? _buildEmptyState()
                          : _buildDevicesList(devices),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildScanningIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const LottieLoading.medium(),
          const SizedBox(height: 32),
          const Text(
            'Searching for devices...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a few seconds',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isSmallScreen = screenWidth < 360;
        final iconSize = isSmallScreen ? 48.0 : 64.0;
        final titleFontSize = isSmallScreen ? 18.0 : 20.0;
        final textFontSize = isSmallScreen ? 12.0 : 14.0;
        final padding = isSmallScreen ? 16.0 : 24.0;
        
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding, vertical: isSmallScreen ? 16 : 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bluetooth_disabled_rounded,
                  size: iconSize,
                  color: Colors.white.withOpacity(0.3),
                ),
                SizedBox(height: isSmallScreen ? 16 : 20),
                Text(
                  'No Devices Found',
                  style: TextStyle(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 8 : 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 0),
                  child: Text(
                    'Make sure your SmartSync device is:\n• Powered on\n• Within 10 meters\n• Not connected to another device',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: textFontSize,
                      color: Colors.white.withOpacity(0.7),
                      height: 1.5,
                    ),
                  ),
                ),
                SizedBox(height: isSmallScreen ? 20 : 24),
                OutlinedButton.icon(
                  onPressed: _startScan,
                  icon: Icon(Icons.refresh_rounded, size: isSmallScreen ? 18 : 20),
                  label: Text('Scan Again', style: TextStyle(fontSize: isSmallScreen ? 14 : 16)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00BFA5),
                    side: const BorderSide(color: Color(0xFF00BFA5)),
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 24 : 32,
                      vertical: isSmallScreen ? 12 : 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDevicesList(List<flutter_blue.BluetoothDevice> devices) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isSmallScreen = screenWidth < 360;
        final padding = isSmallScreen ? 12.0 : 20.0;
        
        return ListView.builder(
          padding: EdgeInsets.all(padding),
          itemCount: devices.length,
          itemBuilder: (context, index) {
        final device = devices[index];
        final deviceId = device.remoteId.toString();
        final isConnecting = _isConnecting && _connectingDeviceId == deviceId;

            final iconSize = isSmallScreen ? 50.0 : 60.0;
            final iconInnerSize = isSmallScreen ? 28.0 : 32.0;
            final padding = isSmallScreen ? 16.0 : 20.0;
            final titleFontSize = isSmallScreen ? 16.0 : 18.0;
            final subtitleFontSize = isSmallScreen ? 11.0 : 12.0;
            
            return Container(
              margin: EdgeInsets.only(bottom: isSmallScreen ? 12 : 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1A1F3A),
                    const Color(0xFF0F1419),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isConnecting ? null : () => _connectToDevice(device),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: EdgeInsets.all(padding),
                    child: Row(
                      children: [
                        // Device Icon
                        Container(
                          width: iconSize,
                          height: iconSize,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00BFA5).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.router_rounded,
                            size: iconInnerSize,
                            color: const Color(0xFF00BFA5),
                          ),
                        ),
                        SizedBox(width: isSmallScreen ? 12 : 16),

                        // Device Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.advName.isNotEmpty
                                    ? device.advName
                                    : 'SmartSync Device',
                                style: TextStyle(
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: isSmallScreen ? 2 : 4),
                              Text(
                                deviceId,
                                style: TextStyle(
                                  fontSize: subtitleFontSize,
                                  color: Colors.white.withOpacity(0.7),
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: isSmallScreen ? 4 : 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.signal_cellular_alt_rounded,
                                    size: isSmallScreen ? 12 : 14,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                  SizedBox(width: isSmallScreen ? 3 : 4),
                                  Flexible(
                                    child: Text(
                                      'Ready to connect',
                                      style: TextStyle(
                                        fontSize: subtitleFontSize,
                                        color: Colors.white.withOpacity(0.7),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Connect Button
                        if (isConnecting)
                          const LottieLoading.small()
                        else
                          Container(
                            padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00BFA5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: isSmallScreen ? 18 : 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
