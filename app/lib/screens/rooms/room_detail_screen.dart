// app/lib/screens/rooms/room_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'dart:async';
import '../../models/room_model.dart';
import '../../models/device_model.dart';
import '../../services/firebase_service.dart';
import '../../core/constants/routes.dart';
import '../../providers/device_provider.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../../core/utils/logger.dart';
import '../../services/appliance_state_service.dart';
import '../../providers/sensor_provider.dart';
import '../../services/logging_service.dart';
import '../../models/log_entry.dart';
import '../automations/add_scheduled_automation_screen.dart';
import '../../services/bluetooth_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue;

import 'package:image_picker/image_picker.dart';

// Provider for room devices
final roomDevicesProvider =
    StreamProvider.family<List<DeviceModel>, String>((ref, roomId) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);

  final firebaseService = FirebaseService();
  return firebaseService.getRoomDevices(user.uid, roomId);
});

final roomAutomationsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, roomId) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);
  return FirebaseService().getRoomAutomations(user.uid, roomId);
});

class RoomDetailScreen extends ConsumerStatefulWidget {
  final RoomModel room;

  const RoomDetailScreen({super.key, required this.room});

  @override
  ConsumerState<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends ConsumerState<RoomDetailScreen>
    with TickerProviderStateMixin {
  bool _allDevicesOn = false;
  double _fanSpeed = 50;
  double _masterBrightness = 50;
  bool _notificationShown = false; // Prevent notification loop
  bool _isReconnecting = false; // Track reconnection state
  late AnimationController _fanAnimationController;
  late AnimationController _bulbAnimationController;
  
  // Get BluetoothService instance
  BluetoothService get _bluetoothService => ref.read(bluetoothServiceProvider);

  @override
  void initState() {
    super.initState();
    _fanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _bulbAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadApplianceState();
    _updateAnimations();
  }

  Future<void> _loadApplianceState() async {
    final stateService = ApplianceStateService();
    final state = await stateService.loadApplianceState();

    if (state != null && mounted) {
      setState(() {
        _fanSpeed =
            ((state['fanSpeed'] as int? ?? 0) / 255 * 100).roundToDouble();
        _masterBrightness =
            ((state['ledBrightness'] as int? ?? 0) / 255 * 100).roundToDouble();
        _allDevicesOn = (_fanSpeed > 0 || _masterBrightness > 0);
        _updateAnimations();
      });
    } else {
      // Try to get from sensor data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final sensorData = ref.read(sensorStreamProvider);
        sensorData.whenData((data) {
          if (data != null && mounted) {
            setState(() {
              _fanSpeed = (data.fanSpeed / 255 * 100).roundToDouble();
              _masterBrightness =
                  (data.ledBrightness / 255 * 100).roundToDouble();
              _allDevicesOn = (_fanSpeed > 0 || _masterBrightness > 0);
              _updateAnimations();
            });
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _fanAnimationController.dispose();
    _bulbAnimationController.dispose();
    super.dispose();
  }

  void _updateAnimations() {
    // Update fan animation speed based on fan speed
    if (_fanSpeed > 0) {
      // Calculate new duration: faster fan = shorter duration (faster rotation)
      // Range: 200ms (100%) to 2000ms (0%)
      final newDuration = Duration(
        milliseconds: (2000 - (_fanSpeed / 100 * 1800)).round(),
      );
      
      // Stop and reset to apply new duration
      _fanAnimationController.stop();
      _fanAnimationController.reset();
      _fanAnimationController.duration = newDuration;
      _fanAnimationController.repeat();
    } else {
      _fanAnimationController.stop();
      _fanAnimationController.reset();
    }

    // Update bulb brightness animation
    _bulbAnimationController.animateTo(_masterBrightness / 100);
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(roomDevicesProvider(widget.room.id));
    final sensorData = ref.watch(sensorStreamProvider);

    // Sync master control with sensor data
    sensorData.whenData((data) {
      if (data != null && mounted) {
        final fanSpeedPercent = (data.fanSpeed / 255 * 100).roundToDouble();
        final brightnessPercent =
            (data.ledBrightness / 255 * 100).roundToDouble();
        final allOn = (fanSpeedPercent > 0 || brightnessPercent > 0);

        // If master controller is off, force values to 0
        final finalFanSpeed = allOn ? fanSpeedPercent : 0.0;
        final finalBrightness = allOn ? brightnessPercent : 0.0;

        if ((_fanSpeed != finalFanSpeed ||
            _masterBrightness != finalBrightness ||
            _allDevicesOn != allOn)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _fanSpeed = finalFanSpeed;
                _masterBrightness = finalBrightness;
                _allDevicesOn = allOn;
                _updateAnimations();
              });
            }
          });
        }
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: RefreshIndicator(
        onRefresh: () async {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            ref.invalidate(deviceControllerProvider(user.uid));
            // Invalidate any other providers if needed
            await Future.delayed(const Duration(milliseconds: 500));
          }
        },
        child: CustomScrollView(
          slivers: [
            // Custom App Bar with room image/gradient
            _buildSliverAppBar(),

            // Room controls and devices
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),

                  // Quick Room Stats
                  _buildQuickStats(),
                  const SizedBox(height: 24),

                  // Master Controls
                  _buildMasterControls(),
                  const SizedBox(height: 24),

                  // Devices Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Devices',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Device List
                  devicesAsync.when(
                    data: (devices) {
                      // Find hub device (if exists)
                      DeviceModel? hubDevice;
                      try {
                        hubDevice = devices.firstWhere((d) => d.isHub);
                      } catch (e) {
                        hubDevice = null;
                      }
                      
                      // Filter out hub from device list (only show non-hub devices)
                      final nonHubDevices = devices.where((d) => !d.isHub).toList();
                      
                      // Show reconnect hub card if hub exists, otherwise show empty state
                      return Column(
                        children: [
                          // Reconnect Hub Card (always show if hub exists)
                          if (hubDevice != null) ...[
                            _buildReconnectHubCard(hubDevice),
                            const SizedBox(height: 16),
                          ],
                          // Non-hub devices list
                          if (nonHubDevices.isEmpty)
                            _buildEmptyDevices()
                          else
                            _buildDevicesList(nonHubDevices),
                        ],
                      );
                    },
                    loading: () => const Center(
                      child: LottieLoading.medium(),
                    ),
                    error: (error, _) => _buildErrorState(),
                  ),

                  const SizedBox(height: 24),

                  // Room Automations Section
                  _buildAutomationsSection(),
                  const SizedBox(height: 24),

                  // Room Settings
                  _buildRoomSettings(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      backgroundColor: _getRoomColor(widget.room.icon),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.photo_camera_rounded, color: Colors.white),
          onPressed: _uploadRoomImage,
          tooltip: 'Upload Room Image',
        ),
        IconButton(
          icon: const Icon(Icons.edit_rounded, color: Colors.white),
          onPressed: () {
            Navigator.pushNamed(
              context,
              Routes.editRoom,
              arguments: widget.room,
            );
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  SizedBox(width: 12),
                  Text('Delete Room', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: _handleMenuAction,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Room image or gradient background
            widget.room.imageUrl != null
                ? Image.network(
                    widget.room.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _getRoomColor(widget.room.icon),
                              _getRoomColor(widget.room.icon).withOpacity(0.7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      );
                    },
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _getRoomColor(widget.room.icon),
                          _getRoomColor(widget.room.icon).withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),

            // Dark overlay for better text readability
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.5),
                  ],
                ),
              ),
            ),

            // Pattern overlay (only if no image)
            if (widget.room.imageUrl == null)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.1,
                  child: Icon(
                    _getRoomIcon(widget.room.icon),
                    size: 200,
                    color: Colors.white,
                  ),
                ),
              ),

            // Room info
            Positioned(
              bottom: 60,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getRoomIcon(widget.room.icon),
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.room.name,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Consumer(
                    builder: (context, ref, child) {
                      // Count active appliances (fan + light) from sensor data - same logic as active card
                      final sensorData = ref.watch(sensorStreamProvider);
                      final activeCount = sensorData.when(
                        data: (data) {
                          if (data == null) return 0;
                          final fanActive = (data.fanSpeed > 0) ? 1 : 0;
                          final lightActive = (data.ledBrightness > 0) ? 1 : 0;
                          return fanActive + lightActive;
                        },
                        loading: () => 0,
                        error: (_, __) => 0,
                      );
                      return Text(
                        '$activeCount ${activeCount == 1 ? 'appliance' : 'appliances'} on',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    final devicesAsync = ref.watch(roomDevicesProvider(widget.room.id));
    final automationsAsync = ref.watch(roomAutomationsProvider(widget.room.id));
    final sensorDataAsync = ref.watch(sensorStreamProvider);
    final user = FirebaseAuth.instance.currentUser;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Active Devices (count appliances from sensor data: fan + light)
          Expanded(
            child: sensorDataAsync.when(
              data: (sensorData) {
                // Count active appliances from sensor data (fan and light separately)
                // Fan is active if fanSpeed > 0, Light is active if ledBrightness > 0
                // Use the same logic as hero section for consistency
                if (sensorData == null) {
                  return _buildStatCard(
                    icon: Icons.power_settings_new_rounded,
                    label: 'Active',
                    value: '0',
                    color: const Color(0xFF00BFA5),
                    zeroReason: 'All devices off',
                  );
                }
                final fanActive = sensorData.fanSpeed > 0 ? 1 : 0;
                final lightActive = sensorData.ledBrightness > 0 ? 1 : 0;
                final activeCount = fanActive + lightActive;
                return _buildStatCard(
                  icon: Icons.power_settings_new_rounded,
                  label: 'Active',
                  value: '$activeCount',
                  color: const Color(0xFF00BFA5),
                  zeroReason: activeCount == 0 
                      ? 'All devices off' 
                      : null,
                );
              },
              loading: () => _buildStatCard(
                icon: Icons.power_settings_new_rounded,
                label: 'Active',
                value: '-',
                color: const Color(0xFF00BFA5),
              ),
              error: (_, __) {
                // Fallback to device count if sensor data unavailable
                return devicesAsync.when(
              data: (devices) {
                final activeCount = devices.where((d) => !d.isHub && d.isOn).length;
                return _buildStatCard(
                  icon: Icons.power_settings_new_rounded,
                  label: 'Active',
                  value: '$activeCount',
                  color: const Color(0xFF00BFA5),
                  zeroReason: activeCount == 0 
                      ? 'All devices off' 
                      : null,
                );
              },
              loading: () => _buildStatCard(
                icon: Icons.power_settings_new_rounded,
                label: 'Active',
                value: '-',
                color: const Color(0xFF00BFA5),
              ),
              error: (_, __) => _buildStatCard(
                icon: Icons.power_settings_new_rounded,
                label: 'Active',
                value: '0',
                color: const Color(0xFF00BFA5),
              ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          // Energy Consumption
          Expanded(
            child: user != null
                ? FutureBuilder<double>(
                    future: FirebaseService().getRoomEnergyConsumption(
                      user.uid,
                      widget.room.id,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildStatCard(
                          icon: Icons.flash_on_rounded,
                          label: 'Energy',
                          value: '-',
                          color: const Color(0xFFFFA726),
                        );
                      }
                      final energy = snapshot.data ?? 0.0;
                      return _buildStatCard(
                        icon: Icons.flash_on_rounded,
                        label: 'Energy',
                        value: '${energy.toStringAsFixed(1)} kWh',
                        color: const Color(0xFFFFA726),
                        zeroReason: energy == 0.0 
                            ? 'No device usage today' 
                            : null,
                      );
                    },
                  )
                : _buildStatCard(
                    icon: Icons.flash_on_rounded,
                    label: 'Energy',
                    value: '0 kWh',
                    color: const Color(0xFFFFA726),
                  ),
          ),
          const SizedBox(width: 12),
          // Schedules/Automations
          Expanded(
            child: automationsAsync.when(
              data: (automations) {
                return _buildStatCard(
                  icon: Icons.schedule_rounded,
                  label: 'Schedules',
                  value: '${automations.length}',
                  color: const Color(0xFF7C4DFF),
                );
              },
              loading: () => _buildStatCard(
                icon: Icons.schedule_rounded,
                label: 'Schedules',
                value: '-',
                color: const Color(0xFF7C4DFF),
              ),
              error: (_, __) => _buildStatCard(
                icon: Icons.schedule_rounded,
                label: 'Schedules',
                value: '0',
                color: const Color(0xFF7C4DFF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? zeroReason,
  }) {
    // Check if value is zero and needs explanation
    final isZero = value == '0' || value == '0.0' || value == '0.0 kWh' || value == '0 kWh';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1F3A),
            const Color(0xFF0F1419),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
          if (isZero && zeroReason != null) ...[
            const SizedBox(height: 4),
            Text(
              zeroReason,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.5),
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMasterControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
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
              color: Colors.blue.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text(
                    'Master Controls',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Switch(
                  value: _allDevicesOn,
                  onChanged: (value) {
                    setState(() {
                      _allDevicesOn = value;
                      if (value) {
                        // When turning on, set fan speed and brightness to 50%
                        _fanSpeed = 50;
                        _masterBrightness = 50;
                        _updateAnimations();
                      } else {
                        // When turning off, force to 0
                        _fanSpeed = 0;
                        _masterBrightness = 0;
                        _updateAnimations();
                      }
                    });
                    _toggleAllDevices(value);
                  },
                  activeThumbColor: Colors.blue,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Fan Control (replacing temperature)
            Row(
              children: [
                // Animated Fan Icon
                AnimatedBuilder(
                  animation: _fanAnimationController,
                  builder: (context, child) {
                    final isDisabled = !_allDevicesOn || _fanSpeed == 0;
                    return Opacity(
                      opacity: isDisabled ? 0.4 : 1.0,
                      child: Transform.rotate(
                      angle: _fanAnimationController.value * 2 * 3.14159,
                      child: Image.asset(
                        'assets/fan.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                          color: _fanSpeed > 0 && _allDevicesOn
                            ? Colors.blue
                                .withOpacity(0.8 + (_fanSpeed / 100 * 0.2))
                            : Colors.white70,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback to icon if image fails to load
                          Logger.warning(
                              'RoomDetailScreen: Failed to load fan.png: $error');
                          return Icon(
                            Icons.air_rounded,
                            size: 32,
                              color: _fanSpeed > 0 && _allDevicesOn
                                ? Colors.blue
                                    .withOpacity(0.8 + (_fanSpeed / 100 * 0.2))
                                : Colors.white70,
                          );
                        },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Fan Speed',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${(_allDevicesOn ? _fanSpeed : 0).round()}%',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _allDevicesOn ? _fanSpeed : 0.0,
                        min: 0,
                        max: 100,
                        activeColor: Colors.blue,
                        // Disable slider if master control is off
                        onChanged: _allDevicesOn
                            ? (value) {
                                setState(() {
                                  _fanSpeed = value;
                                  _updateAnimations();
                                });
                                _handleFanSpeedChange(value.round());
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Brightness control with animated bulb
            Row(
              children: [
                // Animated Bulb Icon
                AnimatedBuilder(
                  animation: _bulbAnimationController,
                  builder: (context, child) {
                    final brightness = _bulbAnimationController.value;
                    final isDisabled = !_allDevicesOn || _masterBrightness == 0;
                    return Opacity(
                      opacity: isDisabled ? 0.4 : 1.0,
                      child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withOpacity(brightness * 0.8),
                            blurRadius: 15 * brightness,
                            spreadRadius: 5 * brightness,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.lightbulb,
                        color: Color.lerp(
                          Colors.white70,
                          Colors.amber,
                          brightness,
                        ),
                        size: 28,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Brightness',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${(_allDevicesOn ? _masterBrightness : 0).round()}%',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _allDevicesOn ? _masterBrightness : 0.0,
                        min: 0,
                        max: 100,
                        activeColor: Colors.amber,
                        // Disable slider if master control is off
                        onChanged: _allDevicesOn
                            ? (value) {
                                setState(() {
                                  _masterBrightness = value;
                                  _updateAnimations();
                                });
                                _handleLightBrightnessChange(value.round());
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesList(List<DeviceModel> devices) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildDeviceListItem(devices[index]),
        );
      },
    );
  }

  Widget _buildDeviceListItem(DeviceModel device) {
    // CRITICAL: Check if device is currently connected via Bluetooth
    // Use direct service check for immediate state (provider may have delay)
    final isBluetoothConnected = _bluetoothService.isConnected;
    
    final isConnected = device.isHub && 
        isBluetoothConnected && 
        _bluetoothService.connectedDeviceId == device.id;
    final isDisconnected = device.isHub && !isConnected;

    // For hub devices, show a reconnection widget instead of a regular device card
    if (device.isHub) {
      return _buildHubReconnectionCard(device, isConnected, isDisconnected);
    }

    // For non-hub devices, show regular device card
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1F3A),
            const Color(0xFF0F1419),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: device.isOn
                      ? Colors.blue.withOpacity(0.2)
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  device.icon,
                  color: device.isOn ? Colors.blue : Colors.white70,
                  size: 24,
                ),
              ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  device.isOn ? 'On • ${device.value}%' : 'Off',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: device.isOn,
            onChanged: (value) => _toggleDevice(device, value),
            activeThumbColor: Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildHubReconnectionCard(
    DeviceModel hubDevice,
    bool isConnected,
    bool isDisconnected,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isConnected
              ? [
                  const Color(0xFF1A3A2A),
                  const Color(0xFF0F1914),
                ]
              : [
                  const Color(0xFF3A2A1A),
                  const Color(0xFF19140F),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? Colors.green.withOpacity(0.5)
              : Colors.orange.withOpacity(0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isConnected ? Colors.green : Colors.orange).withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Hub icon with connection status
          Stack(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isConnected
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.router,
                  color: isConnected ? Colors.green : Colors.orange,
                  size: 32,
                ),
              ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                  width: 16,
                  height: 16,
                    decoration: BoxDecoration(
                    color: isConnected ? Colors.green : Colors.orange,
                      shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                  child: isConnected
                      ? const Icon(
                          Icons.check,
                          size: 10,
                          color: Colors.white,
                        )
                      : const Icon(
                          Icons.close,
                          size: 10,
                          color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),

          // Hub info and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hubDevice.name,
                        style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                const SizedBox(height: 6),
                      Text(
                  isConnected
                      ? 'Connected via Bluetooth'
                      : 'Not connected to this room',
                        style: TextStyle(
                    fontSize: 13,
                    color: isConnected
                        ? Colors.green.shade200
                        : Colors.orange.shade200,
                          fontWeight: FontWeight.w500,
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  isConnected
                      ? 'Hub is ready to control devices'
                      : 'Tap to reconnect and control devices',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),

          // Reconnect button or connection indicator
          if (isDisconnected)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isReconnecting ? null : () => _reconnectHub(hubDevice),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: _isReconnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                      ),
                    )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.bluetooth_searching,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Reconnect',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade200,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Connected',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade200,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _reconnectHub(DeviceModel device) async {
    // CRITICAL: Prevent multiple simultaneous reconnection attempts
    if (_isReconnecting) {
      Logger.warning('RoomDetailScreen: Reconnection already in progress');
      return;
    }

    // CRITICAL: Check if already connected to this device
    if (_bluetoothService.isConnected && 
        _bluetoothService.connectedDeviceId == device.id) {
      if (mounted) {
        AppNotifications.showSnackBar(
          context,
          message: 'Already connected to ${device.name}',
          type: AppNotificationType.info,
        );
      }
      return;
    }

    setState(() {
      _isReconnecting = true;
    });

    try {
      Logger.info('RoomDetailScreen: Attempting to reconnect hub ${device.name} (${device.id})');

      // CRITICAL: Ensure Bluetooth is ready before scanning
      try {
        await flutter_blue.FlutterBluePlus.turnOn();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        Logger.warning('RoomDetailScreen: Error ensuring Bluetooth is on: $e');
      }

      // Scan for the device
      await flutter_blue.FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: false,
      );

      flutter_blue.BluetoothDevice? foundDevice;
      final completer = Completer<flutter_blue.BluetoothDevice?>();
      StreamSubscription<List<flutter_blue.ScanResult>>? subscription;
      Timer? timeoutTimer;

      subscription = flutter_blue.FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          if (result.device.remoteId.toString() == device.id) {
            foundDevice = result.device;
            if (!completer.isCompleted) {
              completer.complete(foundDevice);
            }
            break;
          }
        }
      });

      // Set timeout to complete the completer if device not found
      timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      foundDevice = await completer.future;

      timeoutTimer?.cancel();
      await subscription.cancel();
      await flutter_blue.FlutterBluePlus.stopScan();

      if (foundDevice != null) {
        final success = await _bluetoothService.connectToDevice(foundDevice!);
        if (success && mounted) {
          AppNotifications.showSnackBar(
            context,
            message: 'Successfully reconnected to ${device.name}',
            type: AppNotificationType.success,
          );
        } else if (mounted) {
          AppNotifications.showSnackBar(
            context,
            message: 'Failed to reconnect to ${device.name}',
            type: AppNotificationType.error,
          );
        }
      } else {
        if (mounted) {
          AppNotifications.showSnackBar(
            context,
            message: 'Device ${device.name} not found. Make sure it\'s powered on and nearby.',
            type: AppNotificationType.error,
          );
        }
      }
    } catch (e) {
      Logger.error('RoomDetailScreen: Error reconnecting hub: $e');
      if (mounted) {
        AppNotifications.showSnackBar(
          context,
          message: 'Reconnection error: ${e.toString()}',
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isReconnecting = false;
        });
      }
    }
  }

  Widget _buildReconnectHubCard(DeviceModel hubDevice) {
    final isBluetoothConnected = _bluetoothService.isConnected;
    
    final isConnected = isBluetoothConnected && 
        _bluetoothService.connectedDeviceId == hubDevice.id;
    final isDisconnected = !isConnected && !hubDevice.isOnline;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1F3A),
            const Color(0xFF0F1419),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected 
              ? Colors.green.withOpacity(0.3)
              : isDisconnected
                  ? Colors.orange.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
          width: isConnected || isDisconnected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isConnected ? Colors.green : Colors.blue).withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Hub icon with connection status
          Stack(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isConnected
                      ? Colors.green.withOpacity(0.2)
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hubDevice.icon,
                  color: isConnected ? Colors.green : Colors.white70,
                  size: 24,
                ),
              ),
              // Connection status indicator
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isConnected 
                        ? Colors.green 
                        : isDisconnected 
                            ? Colors.orange 
                            : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          
          // Hub info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hubDevice.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isConnected 
                      ? 'Connected' 
                      : isDisconnected
                          ? 'Disconnected'
                          : 'Unknown',
                  style: TextStyle(
                    fontSize: 13,
                    color: isConnected 
                        ? Colors.green.shade300 
                        : isDisconnected
                            ? Colors.orange.shade300
                            : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          
          // Reconnect button
          if (isDisconnected)
            IconButton(
              icon: _isReconnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    )
                  : const Icon(Icons.bluetooth_searching, color: Colors.blue),
              onPressed: _isReconnecting ? null : () => _reconnectHub(hubDevice),
              tooltip: 'Reconnect',
            )
          else if (isConnected)
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 24,
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyDevices() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(40),
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
            color: Colors.blue.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.devices_other_rounded,
            size: 64,
            color: Colors.white70,
          ),
          const SizedBox(height: 16),
          Text(
            'No Devices in ${widget.room.name}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Devices connected to the hub will appear here',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationsSection() {
    final automationsAsync = ref.watch(roomAutomationsProvider(widget.room.id));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: automationsAsync.when(
        data: (automations) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Automations',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showAutomationManager(automations),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                    child: const Text('Manage'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (automations.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1A1F3A),
                        const Color(0xFF0F1419),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Text(
                    'No automations yet',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              else
                Column(
                  children: automations
                      .map(
                        (automation) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildAutomationCard(
                            automation: automation,
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          );
        },
        loading: () => const Center(child: LottieLoading.medium()),
        error: (error, stackTrace) => _buildAutomationsError(error, stackTrace),
      ),
    );
  }

  /// Build a user-friendly error widget for automations loading failures
  Widget _buildAutomationsError(Object error, StackTrace? stackTrace) {
    // Log the error for debugging
    Logger.error('RoomDetailScreen: Failed to load automations: $error', error, stackTrace);
    
    // Parse error message to determine type
    final errorString = error.toString().toLowerCase();
    final isPermissionError = errorString.contains('permission-denied') || 
                              errorString.contains('permission denied');
    final isNetworkError = errorString.contains('network') || 
                          errorString.contains('connection') ||
                          errorString.contains('timeout');
    final isIndexError = errorString.contains('index');

    // Determine user-friendly message based on error type
    String title;
    String message;
    IconData icon;
    Color iconColor;

    if (isPermissionError) {
      title = 'Access Restricted';
      message = 'You don\'t have permission to view automations for this room. '
                'Please contact your administrator or check your account settings.';
      icon = Icons.lock_outline;
      iconColor = Colors.orange;
    } else if (isNetworkError) {
      title = 'Connection Error';
      message = 'Unable to load automations. Please check your internet connection and try again.';
      icon = Icons.wifi_off;
      iconColor = Colors.red;
    } else if (isIndexError) {
      title = 'Loading Automations';
      message = 'Database index is being created. Please wait a few minutes and try again.';
      icon = Icons.hourglass_empty;
      iconColor = Colors.blue;
    } else {
      title = 'Error Loading Automations';
      message = 'An unexpected error occurred while loading automations. Please try again.';
      icon = Icons.error_outline;
      iconColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1F3A),
            const Color(0xFF0F1419),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: iconColor.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: iconColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Error icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          
          // Error title
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          
          // Error message
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          
          // Retry button
          ElevatedButton.icon(
            onPressed: () {
              // Invalidate the provider to trigger a retry
              ref.invalidate(roomAutomationsProvider(widget.room.id));
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          
          // Show technical details in debug mode
          if (isPermissionError) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                // Show technical details in a dialog
                _showErrorDetailsDialog(error, stackTrace);
              },
              child: const Text(
                'Show Details',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Show error details dialog for debugging
  void _showErrorDetailsDialog(Object error, StackTrace? stackTrace) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text(
              'Error Details',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Error Message:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                error.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
              if (stackTrace != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Stack Trace:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  stackTrace.toString(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 10,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationCard({
    required Map<String, dynamic> automation,
  }) {
    final title = automation['name'] ?? 'Automation';
    final subtitle = automation['description'] ?? 'Scheduled action';
    final enabled = automation['enabled'] ?? true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1F3A),
            const Color(0xFF0F1419),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.schedule_rounded,
                color: Colors.blue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (value) =>
                _toggleAutomation(automation['id'] as String, value),
            activeThumbColor: Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildRoomSettings() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Room Settings',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingsTile(
            icon: Icons.edit_rounded,
            title: 'Edit Room',
            onTap: () {
              // ✅ FIXED: Use named route
              Navigator.pushNamed(
                context,
                Routes.editRoom,
                arguments: widget.room,
              );
            },
          ),
          _buildSettingsTile(
            icon: Icons.color_lens_rounded,
            title: 'Change Theme',
            onTap: _showThemeSheet,
          ),
          _buildSettingsTile(
            icon: Icons.delete_outline_rounded,
            title: 'Delete Room',
            color: Colors.red,
            onTap: () => _handleMenuAction('delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1F3A),
            const Color(0xFF0F1419),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: color ?? Colors.white70),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: color ?? Colors.white,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: Colors.white70,
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1F3A),
            const Color(0xFF0F1419),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Error Loading Devices',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action) {
    if (action == 'delete') {
      _showDeleteDialog();
    }
  }

  void _navigateToAddDevice() {
    Navigator.pushNamed(context, Routes.deviceScan);
  }

  Future<void> _toggleDevice(DeviceModel device, bool enabled) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await ref
        .read(deviceControllerProvider(user.uid).notifier)
        .toggleDevice(device, enabled);
  }

  void _showAutomationManager(List<Map<String, dynamic>> automations) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Automations',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ...automations.map(
              (automation) => ListTile(
                title: Text(
                  automation['name'] ?? 'Automation',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  automation['description'] ?? '',
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: Switch(
                  value: automation['enabled'] ?? true,
                  onChanged: (value) =>
                      _toggleAutomation(automation['id'] as String, value),
                  activeThumbColor: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                // Show add automation screen
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) return;

                final devicesAsync =
                    ref.read(roomDevicesProvider(widget.room.id));
                final devices = devicesAsync.maybeWhen(
                  data: (list) => list,
                  orElse: () => <DeviceModel>[],
                );

                if (devices.isEmpty) {
                  AppNotifications.showSnackBar(
                    context,
                    message: 'No devices in this room. Add devices first.',
                    type: AppNotificationType.warning,
                  );
                  return;
                }

                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddScheduledAutomationScreen(
                      roomId: widget.room.id,
                      devices: devices,
                    ),
                  ),
                );

                if (result == true) {
                  // Refresh automations
                  ref.invalidate(roomAutomationsProvider(widget.room.id));
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Scheduled Automation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAutomation(String automationId, bool enabled) async {
    // Get automation details for logging
    try {
      final automations = await FirebaseService().getUserAutomations(FirebaseAuth.instance.currentUser!.uid).first;
      final automation = automations.firstWhere((a) => a['id'] == automationId, orElse: () => {});
      
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: enabled ? 'Automation ENABLED' : 'Automation DISABLED',
        category: 'automation',
        details: 'Automation "${automation['name'] ?? automationId}" in room "${widget.room.name}" ${enabled ? "enabled" : "disabled"}',
        metadata: {
          'automationId': automationId,
          'automationName': automation['name'] ?? 'Unknown',
          'automationDescription': automation['description'] ?? '',
          'roomId': widget.room.id,
          'roomName': widget.room.name,
          'previousState': !enabled,
          'newState': enabled,
          'actionType': 'automation_toggle',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
    } catch (e) {
      Logger.warning('Failed to log automation toggle: $e');
    }
    
    await FirebaseService().toggleAutomation(automationId, enabled);
  }

  void _showThemeSheet() {
    final themes = ['living_room', 'kitchen', 'bedroom', 'bathroom', 'office'];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Room Theme',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          ...themes.map(
            (theme) => ListTile(
              leading: Icon(
                _getRoomIcon(theme),
                color: _getRoomColor(theme),
              ),
              title: Text(
                theme.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await FirebaseService()
                      .updateRoom(user.uid, widget.room.id, {'icon': theme});
                }
                if (!mounted) return;
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    AppNotifications.showDialog(
      context,
      title: 'Delete Room?',
      message:
          'Are you sure you want to delete ${widget.room.name}? This action cannot be undone.',
      type: AppNotificationType.error,
      primaryLabel: 'Delete',
      onPrimaryPressed: () => _deleteRoom(),
      secondaryLabel: 'Cancel',
      onSecondaryPressed: () async {},
    );
  }

  Future<void> _toggleAllDevices(bool enabled) async {
    Logger.info(
        'RoomDetailScreen: Toggling all devices to ${enabled ? "on" : "off"}');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Logger.warning('RoomDetailScreen: No user found');
      return;
    }

    // Log the action with detailed information
    final loggingService = LoggingService();
    final bleService = ref.read(bluetoothServiceProvider);
    final fanSpeedPercent = enabled ? _fanSpeed.round() : 0;
    final brightnessPercent = enabled ? _masterBrightness.round() : 0;
    final fanSpeedRaw = enabled ? ((_fanSpeed / 100) * 255).round() : 0;
    final brightnessRaw = enabled ? ((_masterBrightness / 100) * 255).round() : 0;
    
    await loggingService.logAction(
      action: 'Master Controller ${enabled ? "ON" : "OFF"}',
      category: 'device_control',
      details:
          'Master controller for room "${widget.room.name}" turned ${enabled ? "ON" : "OFF"}. Fan: $fanSpeedPercent% (raw: $fanSpeedRaw), Brightness: $brightnessPercent% (raw: $brightnessRaw)',
      level: LogLevel.info,
      metadata: {
        'roomId': widget.room.id,
        'roomName': widget.room.name,
        'roomIcon': widget.room.icon,
        'deviceCount': widget.room.deviceIds.length,
        'fanSpeed': fanSpeedPercent,
        'fanSpeedRaw': fanSpeedRaw,
        'brightness': brightnessPercent,
        'brightnessRaw': brightnessRaw,
        'previousState': !enabled,
        'newState': enabled,
        'bleConnected': bleService.isConnected,
        'actionType': 'master_controller_toggle',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    if (bleService.isConnected) {
      Logger.debug('RoomDetailScreen: BLE connected, sending commands');
      try {
        if (enabled) {
          // Use current values or default to 50%
          final fanValue =
              _fanSpeed > 0 ? ((_fanSpeed / 100) * 255).round() : 128;
          final ledValue = _masterBrightness > 0
              ? ((_masterBrightness / 100) * 255).round()
              : 128;

          await bleService.setFanSpeed(fanValue).timeout(
                const Duration(seconds: 5),
                onTimeout: () => false,
              );
          await bleService.setLEDBrightness(ledValue).timeout(
                const Duration(seconds: 5),
                onTimeout: () => false,
              );
        } else {
          // Turn off when disabling
          await bleService.setFanSpeed(0).timeout(
                const Duration(seconds: 5),
                onTimeout: () => false,
              );
          await bleService.setLEDBrightness(0).timeout(
                const Duration(seconds: 5),
                onTimeout: () => false,
              );
        }
      } catch (e) {
        Logger.error('RoomDetailScreen: Error toggling devices: $e');
      }
    }

    await FirebaseService()
        .toggleAllRoomDevices(user.uid, widget.room.id, enabled);
    if (!mounted) return;
    AppNotifications.showSnackBar(
      context,
      message: enabled
          ? 'All devices turned on (Fan: ${_fanSpeed.round()}%, Brightness: ${_masterBrightness.round()}%)'
          : 'All devices turned off',
      type: AppNotificationType.success,
    );
  }

  Future<void> _deleteRoom() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseService().deleteRoom(user.uid, widget.room.id);
    if (!mounted) return;
    AppNotifications.showSnackBar(
      context,
      message: '${widget.room.name} deleted',
      type: AppNotificationType.success,
    );
    Navigator.pop(context);
  }

  Future<void> _handleFanSpeedChange(int percent) async {
    final previousSpeed = _fanSpeed.round();
    
    // If master control is off, force to 0
    if (!_allDevicesOn) {
      setState(() {
        _fanSpeed = 0;
        _updateAnimations();
      });
      
      // Log the blocked action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: 'Fan Speed Change Blocked',
        category: 'device_control',
        details: 'Fan speed change to $percent% blocked because master controller is OFF in room "${widget.room.name}"',
        metadata: {
          'roomId': widget.room.id,
          'roomName': widget.room.name,
          'requestedSpeed': percent,
          'actualSpeed': 0,
          'previousSpeed': previousSpeed,
          'masterControllerState': false,
          'actionType': 'fan_speed_change_blocked',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
      return;
    }

    final bleService = ref.read(bluetoothServiceProvider);
    if (!bleService.isConnected) {
      // Save state even if not connected (for when connection is restored)
      final stateService = ApplianceStateService();
      final currentState = await stateService.loadApplianceState();
      await stateService.saveApplianceState(
        fanSpeed: ((percent / 100) * 255).round(),
        ledBrightness: currentState?['ledBrightness'] ?? 0,
        securityEnabled: currentState?['securityEnabled'] ?? false,
      );

      // Log the action (saved but not sent to device)
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: 'Fan Speed Changed (Offline)',
        category: 'device_control',
        details: 'Fan speed changed to $percent% in room "${widget.room.name}" (saved locally, device not connected)',
        metadata: {
          'roomId': widget.room.id,
          'roomName': widget.room.name,
          'previousSpeed': previousSpeed,
          'newSpeed': percent,
          'rawValue': ((percent / 100) * 255).round(),
          'bleConnected': false,
          'actionType': 'fan_speed_change_offline',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );

      // Only show notification once, not repeatedly
      if (mounted && !_notificationShown) {
        _notificationShown = true;
        AppNotifications.showSnackBar(
          context,
          message: 'Connect to your SmartSync hub to control the fan.',
          type: AppNotificationType.warning,
        );
        // Reset flag after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          _notificationShown = false;
        });
      }
      return;
    }

    try {
      final speed = ((percent / 100) * 255).round();
      final success = await bleService.setFanSpeed(speed).timeout(
            const Duration(seconds: 5),
            onTimeout: () => false,
          );

      // Log the action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: success ? 'Fan Speed Changed' : 'Fan Speed Change Failed',
        category: 'device_control',
        details: success 
            ? 'Fan speed changed from $previousSpeed% to $percent% in room "${widget.room.name}"'
            : 'Failed to change fan speed to $percent% in room "${widget.room.name}"',
        metadata: {
          'roomId': widget.room.id,
          'roomName': widget.room.name,
          'previousSpeed': previousSpeed,
          'newSpeed': percent,
          'rawValue': speed,
          'bleConnected': true,
          'success': success,
          'actionType': 'fan_speed_change',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: success ? LogLevel.info : LogLevel.warning,
      );

      if (!mounted) return;

      AppNotifications.showSnackBar(
        context,
        message: success
            ? 'Fan speed set to $percent%'
            : 'Failed to update fan speed. Please check your connection.',
        type: success ? AppNotificationType.success : AppNotificationType.error,
      );
    } catch (e) {
      // Log the error
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: 'Fan Speed Change Error',
        category: 'device_control',
        details: 'Error changing fan speed to $percent% in room "${widget.room.name}": ${e.toString()}',
        metadata: {
          'roomId': widget.room.id,
          'roomName': widget.room.name,
          'requestedSpeed': percent,
          'error': e.toString(),
          'actionType': 'fan_speed_change_error',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.error,
      );
      
      if (!mounted) return;
      AppNotifications.showSnackBar(
        context,
        message: 'Failed to update fan speed: ${e.toString()}',
        type: AppNotificationType.error,
      );
    }
  }

  Future<void> _handleLightBrightnessChange(int percent) async {
    final previousBrightness = _masterBrightness.round();
    
    // If master control is off, force to 0
    if (!_allDevicesOn) {
      setState(() {
        _masterBrightness = 0;
        _updateAnimations();
      });
      
      // Log the blocked action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: 'Light Brightness Change Blocked',
        category: 'device_control',
        details: 'Light brightness change to $percent% blocked because master controller is OFF in room "${widget.room.name}"',
        metadata: {
          'roomId': widget.room.id,
          'roomName': widget.room.name,
          'requestedBrightness': percent,
          'actualBrightness': 0,
          'previousBrightness': previousBrightness,
          'masterControllerState': false,
          'actionType': 'brightness_change_blocked',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
      return;
    }

    final bleService = ref.read(bluetoothServiceProvider);
    if (!bleService.isConnected) {
      // Save state even if not connected (for when connection is restored)
      final stateService = ApplianceStateService();
      final currentState = await stateService.loadApplianceState();
      await stateService.saveApplianceState(
        fanSpeed: currentState?['fanSpeed'] ?? 0,
        ledBrightness: ((percent / 100) * 255).round(),
        securityEnabled: currentState?['securityEnabled'] ?? false,
      );
      
      // Log the action (saved but not sent to device)
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: 'Light Brightness Changed (Offline)',
        category: 'device_control',
        details: 'Light brightness changed to $percent% in room "${widget.room.name}" (saved locally, device not connected)',
        metadata: {
          'roomId': widget.room.id,
          'roomName': widget.room.name,
          'previousBrightness': previousBrightness,
          'newBrightness': percent,
          'rawValue': ((percent / 100) * 255).round(),
          'bleConnected': false,
          'actionType': 'brightness_change_offline',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );

      // Only show notification once, not repeatedly
      if (mounted && !_notificationShown) {
        _notificationShown = true;
        AppNotifications.showSnackBar(
          context,
          message: 'Connect to your SmartSync hub to control the light.',
          type: AppNotificationType.warning,
        );
        // Reset flag after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          _notificationShown = false;
        });
      }
      return;
    }

    try {
      final brightness = ((percent / 100) * 255).round();
      final success = await bleService.setLEDBrightness(brightness).timeout(
            const Duration(seconds: 5),
            onTimeout: () => false,
          );

      // Log the action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: success ? 'Light Brightness Changed' : 'Light Brightness Change Failed',
        category: 'device_control',
        details: success 
            ? 'Light brightness changed from $previousBrightness% to $percent% in room "${widget.room.name}"'
            : 'Failed to change light brightness to $percent% in room "${widget.room.name}"',
        metadata: {
          'roomId': widget.room.id,
          'roomName': widget.room.name,
          'previousBrightness': previousBrightness,
          'newBrightness': percent,
          'rawValue': brightness,
          'bleConnected': true,
          'success': success,
          'actionType': 'brightness_change',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: success ? LogLevel.info : LogLevel.warning,
      );

      if (!mounted) return;

      AppNotifications.showSnackBar(
        context,
        message: success
            ? 'Light brightness set to $percent%'
            : 'Failed to update light brightness. Please check your connection.',
        type: success ? AppNotificationType.success : AppNotificationType.error,
      );
    } catch (e) {
      // Log the error
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: 'Light Brightness Change Error',
        category: 'device_control',
        details: 'Error changing light brightness to $percent% in room "${widget.room.name}": ${e.toString()}',
        metadata: {
          'roomId': widget.room.id,
          'roomName': widget.room.name,
          'requestedBrightness': percent,
          'error': e.toString(),
          'actionType': 'brightness_change_error',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.error,
      );
      
      if (!mounted) return;
      AppNotifications.showSnackBar(
        context,
        message: 'Failed to update light brightness: ${e.toString()}',
        type: AppNotificationType.error,
      );
    }
  }

  Future<void> _uploadRoomImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ImagePicker picker = ImagePicker();

    // Show options: Camera or Gallery
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        title: const Text(
          'Select Image Source',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title:
                  const Text('Camera', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title:
                  const Text('Gallery', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 85, // Compress image to reduce upload size
        maxWidth: 1920, // Limit image size
        maxHeight: 1080,
      );
      if (image == null) return;

      if (!mounted) return;
      AppNotifications.showSnackBar(
        context,
        message: 'Uploading image...',
        type: AppNotificationType.info,
      );

      // Upload to Firebase Storage and update room
      final firebaseService = FirebaseService();
      final imageFile = File(image.path);
      
      // Verify file exists before uploading
      if (!await imageFile.exists()) {
        throw Exception('Selected image file no longer exists');
      }

      final imageUrl = await firebaseService.uploadRoomImage(
        userId: user.uid,
        roomId: widget.room.id,
        imageFile: imageFile,
      );

      if (!mounted) return;

      // Update room with new image URL
      await firebaseService.updateRoom(user.uid, widget.room.id, {
        'imageUrl': imageUrl,
      });

      if (!mounted) return;
      AppNotifications.showSnackBar(
        context,
        message: 'Room image updated successfully!',
        type: AppNotificationType.success,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      // Extract the actual error message from the exception
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      AppNotifications.showSnackBar(
        context,
        message: errorMessage,
        type: AppNotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;
      AppNotifications.showSnackBar(
        context,
        message: 'Failed to upload image: ${e.toString()}',
        type: AppNotificationType.error,
      );
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

  Color _getRoomColor(String iconName) {
    switch (iconName) {
      case 'living_room':
        return const Color(0xFF00BFA5);
      case 'kitchen':
        return const Color(0xFFFF6B6B);
      case 'bedroom':
        return const Color(0xFF7C4DFF);
      case 'bathroom':
        return const Color(0xFF4ECDC4);
      case 'office':
        return const Color(0xFFFFA726);
      case 'garage':
        return const Color(0xFF78909C);
      case 'garden':
        return const Color(0xFF66BB6A);
      default:
        return const Color(0xFF00BFA5);
    }
  }
}
