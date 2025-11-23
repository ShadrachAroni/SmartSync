import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue;
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/bluetooth_service.dart';
import '../../services/firebase_service.dart';
import '../../models/sensor_data.dart';
import '../../core/utils/logger.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
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
      ref.read(isScanningProvider.notifier).state = true;
      ref.read(scannedDevicesProvider.notifier).state = [];

      Logger.info('Starting BLE scan...');

      final devices = await _bluetoothService.scanForDevices(
        timeout: const Duration(seconds: 15),
      );

      if (mounted) {
        ref.read(scannedDevicesProvider.notifier).state = devices;
        ref.read(isScanningProvider.notifier).state = false;

        if (devices.isEmpty) {
          _showMessage('No SmartSync devices found nearby', isError: true);
        } else {
          _showMessage('Found ${devices.length} device(s)');
        }
      }
    } catch (e) {
      Logger.error('Scan error: $e');
      if (mounted) {
        ref.read(isScanningProvider.notifier).state = false;
        _showMessage('Failed to scan: ${e.toString()}', isError: true);
      }
    }
  }

  Future<void> _connectToDevice(flutter_blue.BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _connectingDeviceId = device.remoteId.toString();
    });

    try {
      Logger.info('Connecting to ${device.advName}...');

      final success = await _bluetoothService.connectToDevice(device);

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectingDeviceId = null;
        });

        if (success) {
          _showMessage('Connected to ${device.advName}!');
          
          // Check if device is registered in Firebase
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final firebaseService = FirebaseService();
            final deviceId = device.remoteId.toString();
            final existingDevice = await firebaseService.getDeviceById(deviceId);
            
            if (existingDevice == null) {
              // Device not registered, try to get initial sensor data for auto-detection
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
              }
            } else {
              Logger.info('DeviceRegistration: Device $deviceId already registered in room ${existingDevice.roomId}');
            }
          }
          
          // Navigate back to home screen
          Navigator.of(context).pop();
        } else {
          _showMessage('Failed to connect to ${device.advName}', isError: true);
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
        child: Column(
          children: [
            // Header Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
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
                    padding: const EdgeInsets.all(20),
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
                    child: const Icon(
                      Icons.bluetooth_searching_rounded,
                      size: 48,
                      color: Color(0xFF00BFA5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Scan for SmartSync Devices',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure your device is powered on and nearby',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Scan Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed:
                          isScanning || _isConnecting ? null : _startScan,
                      icon: Icon(
                        isScanning
                            ? Icons.refresh_rounded
                            : Icons.search_rounded,
                        size: 24,
                      ),
                      label: Text(
                        isScanning ? 'Scanning...' : 'Start Scan',
                        style: const TextStyle(
                          fontSize: 18,
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
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bluetooth_disabled_rounded,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Devices Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Make sure your SmartSync device is:\n• Powered on\n• Within 10 meters\n• Not connected to another device',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan Again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00BFA5),
                side: const BorderSide(color: Color(0xFF00BFA5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesList(List<flutter_blue.BluetoothDevice> devices) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        final deviceId = device.remoteId.toString();
        final isConnecting = _isConnecting && _connectingDeviceId == deviceId;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
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
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Device Icon
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BFA5).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.router_rounded,
                        size: 32,
                        color: const Color(0xFF00BFA5),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Device Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.advName.isNotEmpty
                                ? device.advName
                                : 'SmartSync Device',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            deviceId,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.7),
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.signal_cellular_alt_rounded,
                                size: 14,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Ready to connect',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00BFA5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 20,
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
  }

  @override
  void dispose() {
    super.dispose();
  }
}
