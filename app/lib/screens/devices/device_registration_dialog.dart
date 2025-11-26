import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/device_model.dart';
import '../../models/room_model.dart';
import '../../models/sensor_data.dart';
import '../../services/firebase_service.dart';
import '../../services/bluetooth_service.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/device_type_detector.dart';

class DeviceRegistrationDialog extends ConsumerStatefulWidget {
  final String deviceId; // BLE remoteId
  final String deviceName; // BLE advertisement name
  final SensorData?
      initialSensorData; // Optional initial sensor data for detection

  const DeviceRegistrationDialog({
    super.key,
    required this.deviceId,
    required this.deviceName,
    this.initialSensorData,
  });

  @override
  ConsumerState<DeviceRegistrationDialog> createState() =>
      _DeviceRegistrationDialogState();
}

class _DeviceRegistrationDialogState
    extends ConsumerState<DeviceRegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  DeviceType _selectedType = DeviceType.sensor;
  String? _selectedRoomId;
  bool _isSaving = false;
  bool _isDetecting = true;
  double _detectionConfidence = 0.0;
  String? _detectionMethod;

  @override
  void initState() {
    super.initState();
    // Pre-fill device name from BLE advertisement
    _nameController.text =
        widget.deviceName.isNotEmpty ? widget.deviceName : 'SmartSync Device';

    // Attempt automatic detection
    _detectDeviceType();
  }

  Future<void> _detectDeviceType() async {
    setState(() => _isDetecting = true);

    try {
      // Try to get device status from Bluetooth if connected
      Map<String, dynamic>? deviceStatus;
      final bluetoothService = BluetoothService();
      if (bluetoothService.isConnected &&
          bluetoothService.connectedDeviceId == widget.deviceId) {
        try {
          // Request device status
          await bluetoothService.requestStatus();
          // Note: Status response would need to be handled via a callback
          // For now, we'll use available data
        } catch (e) {
          Logger.warning(
              'DeviceRegistrationDialog: Could not request device status: $e');
        }
      }

      // Perform automatic detection
      final detectedType = DeviceTypeDetector.detectDeviceType(
        deviceName: widget.deviceName,
        initialSensorData: widget.initialSensorData,
        deviceStatus: deviceStatus,
      );

      final confidence = DeviceTypeDetector.getDetectionConfidence(
        deviceName: widget.deviceName,
        initialSensorData: widget.initialSensorData,
        deviceStatus: deviceStatus,
      );

      // Determine detection method for display
      String? method;
      if (DeviceTypeDetector.detectFromName(widget.deviceName) ==
          detectedType) {
        method = 'Device name';
      } else if (widget.initialSensorData != null &&
          DeviceTypeDetector.detectFromSensorData(widget.initialSensorData!) ==
              detectedType) {
        method = 'Sensor data';
      } else {
        method = 'Default';
      }

      if (mounted) {
        setState(() {
          _selectedType = detectedType;
          _detectionConfidence = confidence;
          _detectionMethod = method;
          _isDetecting = false;
        });

        if (confidence > 0.5) {
          Logger.info(
              'DeviceRegistrationDialog: Auto-detected ${detectedType.name} with ${(confidence * 100).toStringAsFixed(0)}% confidence via $method');
        } else {
          Logger.info(
              'DeviceRegistrationDialog: Low confidence detection (${(confidence * 100).toStringAsFixed(0)}%), user should verify');
        }
      }
    } catch (e) {
      Logger.error('DeviceRegistrationDialog: Error during auto-detection: $e');
      if (mounted) {
        setState(() {
          _isDetecting = false;
          _detectionConfidence = 0.0;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveDevice() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppNotifications.showSnackBar(
        context,
        message: 'Please log in to add devices',
        type: AppNotificationType.error,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final firebaseService = FirebaseService();

      // Create device model
      final device = DeviceModel(
        id: widget.deviceId, // Use BLE remoteId as device ID
        name: _nameController.text.trim(),
        type: _selectedType,
        roomId: _selectedRoomId ?? '',
        isOn: false,
        value: 0,
        isOnline: true,
        lastSeen: DateTime.now(),
        metadata: {
          'bleName': widget.deviceName,
          'registeredAt': DateTime.now().toIso8601String(),
        },
      );

      // Add device to Firebase first (device must exist before room assignment)
      await firebaseService.addDevice(user.uid, device);
      Logger.info(
          'DeviceRegistrationDialog: Device ${widget.deviceId} added to Firebase');

      // If room is selected, assign device to room
      // This updates both the room's deviceIds array and ensures the device's roomId is set
      if (_selectedRoomId != null && _selectedRoomId!.isNotEmpty) {
        try {
          await firebaseService.addDeviceToRoom(
            user.uid,
            _selectedRoomId!,
            widget.deviceId,
          );
          Logger.info(
              'DeviceRegistrationDialog: Device ${widget.deviceId} successfully assigned to room $_selectedRoomId');
        } catch (e, stackTrace) {
          Logger.error(
              'DeviceRegistrationDialog: Error assigning device to room: $e',
              e,
              stackTrace);
          // Show error but don't fail the entire registration
          // The device is already registered with the roomId set
          if (mounted) {
            AppNotifications.showSnackBar(
              context,
              message:
                  'Device registered, but room assignment failed. You can assign it manually later.',
              type: AppNotificationType.warning,
            );
          }
        }
      } else {
        Logger.info(
            'DeviceRegistrationDialog: No room selected for device ${widget.deviceId}');
      }

      if (mounted) {
        // Invalidate providers to refresh UI
        ref.invalidate(userRoomsProvider);

        AppNotifications.showSnackBar(
          context,
          message: 'Device registered successfully!',
          type: AppNotificationType.success,
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      Logger.error('DeviceRegistrationDialog: Error saving device: $e');
      if (mounted) {
        AppNotifications.showSnackBar(
          context,
          message: 'Failed to register device: ${e.toString()}',
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(userRoomsProvider);

    return Dialog(
      backgroundColor: const Color(0xFF1A1F3A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Register Device',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add this device to your SmartSync network',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Device ID (read-only)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bluetooth, color: Colors.blue.shade300),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Device ID',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.deviceId,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Device Name
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'Device Name',
                      labelStyle:
                          TextStyle(color: Colors.white.withOpacity(0.7)),
                      hintText: 'e.g., Living Room Hub',
                      hintStyle:
                          TextStyle(color: Colors.white.withOpacity(0.5)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF00BFA5),
                          width: 2,
                        ),
                      ),
                      prefixIcon: const Icon(Icons.label_outline,
                          color: Color(0xFF00BFA5)),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a device name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Device Type with Auto-Detection Indicator
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Device Type',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          if (_isDetecting) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF00BFA5),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Detecting...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else if (_detectionConfidence > 0.5) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: Color(0xFF00BFA5),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Auto-detected (${(_detectionConfidence * 100).toStringAsFixed(0)}%)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF00BFA5),
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_detectionMethod != null) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                message: 'Detected via $_detectionMethod',
                                child: Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                      if (!_isDetecting &&
                          _detectionConfidence > 0.5 &&
                          _detectionMethod != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Detected as ${_selectedType.name.toUpperCase()} via $_detectionMethod',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.6),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      DropdownButtonFormField<DeviceType>(
                        initialValue: _selectedType,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Select device type',
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.5)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF00BFA5),
                              width: 2,
                            ),
                          ),
                          prefixIcon: const Icon(Icons.category_outlined,
                              color: Color(0xFF00BFA5)),
                          suffixIcon: _detectionConfidence > 0.5
                              ? IconButton(
                                  icon: Icon(
                                    Icons.refresh,
                                    size: 20,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                  tooltip: 'Re-detect device type',
                                  onPressed: _detectDeviceType,
                                )
                              : null,
                        ),
                        dropdownColor: const Color(0xFF1A1F3A),
                        items: DeviceType.values.map((type) {
                          final isDetected = type == _selectedType &&
                              _detectionConfidence > 0.5;
                          return DropdownMenuItem(
                            value: type,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getDeviceIcon(type),
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    type.name.toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isDetected) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: Color(0xFF00BFA5),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedType = value;
                              _detectionConfidence = 0.0; // User override
                              _detectionMethod = null;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Room Selection
                  roomsAsync.when(
                    data: (rooms) {
                      if (rooms.isEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Room (Optional)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: Colors.orange.shade300),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'No rooms available. You can assign this device to a room later.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.orange.shade200,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Room (Optional)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedRoomId,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16),
                            decoration: InputDecoration(
                              hintText: 'Select a room (optional)',
                              hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.5)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.1),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.2),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF00BFA5),
                                  width: 2,
                                ),
                              ),
                              prefixIcon: const Icon(Icons.room_outlined,
                                  color: Color(0xFF00BFA5)),
                            ),
                            dropdownColor: const Color(0xFF1A1F3A),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text(
                                  'No Room',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                              ...rooms.map((room) {
                                return DropdownMenuItem(
                                  value: room.id,
                                  child: Row(
                                    children: [
                                      _getRoomImagePath(room.icon) != null
                                          ? Image.asset(
                                              _getRoomImagePath(room.icon)!,
                                              width: 20,
                                              height: 20,
                                              color: Colors.white70,
                                              colorBlendMode: BlendMode.srcIn,
                                            )
                                          : Icon(
                                              _getRoomIcon(room.icon),
                                              color: Colors.white70,
                                              size: 20,
                                            ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          room.name,
                                          style: const TextStyle(
                                              color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedRoomId = value);
                            },
                          ),
                        ],
                      );
                    },
                    loading: () => const Center(
                      child: LottieLoading.medium(),
                    ),
                    error: (_, __) => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Failed to load rooms',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.red.shade200,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Action Buttons - Using Wrap for flexible constraint handling
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveDevice,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00BFA5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const LottieLoading.small()
                            : const Text('Register Device'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getDeviceIcon(DeviceType type) {
    switch (type) {
      case DeviceType.light:
        return Icons.lightbulb_outline;
      case DeviceType.fan:
        return Icons.air;
      case DeviceType.airConditioner:
        return Icons.ac_unit;
      case DeviceType.camera:
        return Icons.videocam;
      case DeviceType.tv:
        return Icons.tv;
      case DeviceType.vacuum:
        return Icons.cleaning_services;
      case DeviceType.sensor:
        return Icons.sensors;
      case DeviceType.hub:
        return Icons.router;
    }
  }

  String? _getRoomImagePath(String iconName) {
    switch (iconName) {
      case 'living_room':
        return 'assets/rooms/living_room.png';
      case 'kitchen':
        return 'assets/rooms/kitchen.png';
      case 'bedroom':
        return 'assets/rooms/bedroom.png';
      case 'bathroom':
        return 'assets/rooms/bathroom.png';
      case 'office':
        return 'assets/rooms/office.png';
      case 'garage':
        return 'assets/rooms/garage.png';
      case 'garden':
        return 'assets/rooms/garden.png';
      default:
        return null;
    }
  }

  IconData _getRoomIcon(String iconName) {
    switch (iconName) {
      case 'living_room':
        return Icons.weekend_rounded;
      case 'kitchen':
        return Icons.kitchen_rounded;
      case 'bedroom':
        return Icons.bed_rounded;
      case 'bathroom':
        return Icons.bathtub_rounded;
      case 'office':
        return Icons.desk_rounded;
      case 'garage':
        return Icons.garage_rounded;
      case 'garden':
        return Icons.yard_rounded;
      default:
        return Icons.meeting_room_rounded;
    }
  }
}

// Provider for user rooms
final userRoomsProvider = StreamProvider.autoDispose<List<RoomModel>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream.value([]);
  }
  final firebaseService = FirebaseService();
  return firebaseService.getUserRooms(user.uid);
});
