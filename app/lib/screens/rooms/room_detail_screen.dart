// app/lib/screens/rooms/room_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
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
  late AnimationController _fanAnimationController;
  late AnimationController _bulbAnimationController;

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

        if ((_fanSpeed != fanSpeedPercent ||
            _masterBrightness != brightnessPercent ||
            _allDevicesOn != allOn)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _fanSpeed = fanSpeedPercent;
                _masterBrightness = brightnessPercent;
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
      body: CustomScrollView(
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
                      TextButton.icon(
                        onPressed: _navigateToAddDevice,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Device List
                devicesAsync.when(
                  data: (devices) {
                    if (devices.isEmpty) {
                      return _buildEmptyDevices();
                    }
                    return _buildDevicesList(devices);
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
                  Text(
                    '${widget.room.deviceIds.length} devices connected',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
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
    final user = FirebaseAuth.instance.currentUser;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Active Devices
          Expanded(
            child: devicesAsync.when(
              data: (devices) {
                final activeCount = devices.where((d) => d.isOn).length;
                return _buildStatCard(
                  icon: Icons.power_settings_new_rounded,
                  label: 'Active',
                  value: '$activeCount',
                  color: const Color(0xFF00BFA5),
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
  }) {
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
                        // When turning off, set to 0
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
                    return Transform.rotate(
                      angle: _fanAnimationController.value * 2 * 3.14159,
                      child: Image.asset(
                        'assets/fan.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                        color: _fanSpeed > 0
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
                            color: _fanSpeed > 0
                                ? Colors.blue
                                    .withOpacity(0.8 + (_fanSpeed / 100 * 0.2))
                                : Colors.white70,
                          );
                        },
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
                            '${_fanSpeed.round()}%',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _fanSpeed,
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
                    return Container(
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
                            '${_masterBrightness.round()}%',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _masterBrightness,
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
          // Device icon
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

          // Device info
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

          // Device control
          Switch(
            value: device.isOn,
            onChanged: (value) => _toggleDevice(device, value),
            activeThumbColor: Colors.blue,
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
            'Add devices to control them from here',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _navigateToAddDevice,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Device'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
        error: (error, _) => Text('Failed to load automations: $error'),
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

    // Log the action
    final loggingService = LoggingService();
    await loggingService.logAction(
      action: 'Master Controller ${enabled ? "ON" : "OFF"}',
      category: 'device_control',
      details:
          'Master controller for ${widget.room.name} turned ${enabled ? "on" : "off"}',
      level: LogLevel.info,
      metadata: {
        'roomId': widget.room.id,
        'roomName': widget.room.name,
        'fanSpeed': enabled ? _fanSpeed.round() : 0,
        'brightness': enabled ? _masterBrightness.round() : 0,
      },
    );

    final bleService = ref.read(bluetoothServiceProvider);
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
    // If master control is off, force to 0
    if (!_allDevicesOn) {
      setState(() {
        _fanSpeed = 0;
        _updateAnimations();
      });
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

      if (!mounted) return;

      AppNotifications.showSnackBar(
        context,
        message: success
            ? 'Fan speed set to $percent%'
            : 'Failed to update fan speed. Please check your connection.',
        type: success ? AppNotificationType.success : AppNotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;
      AppNotifications.showSnackBar(
        context,
        message: 'Failed to update fan speed: ${e.toString()}',
        type: AppNotificationType.error,
      );
    }
  }

  Future<void> _handleLightBrightnessChange(int percent) async {
    // If master control is off, force to 0
    if (!_allDevicesOn) {
      setState(() {
        _masterBrightness = 0;
        _updateAnimations();
      });
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

      if (!mounted) return;

      AppNotifications.showSnackBar(
        context,
        message: success
            ? 'Light brightness set to $percent%'
            : 'Failed to update light brightness. Please check your connection.',
        type: success ? AppNotificationType.success : AppNotificationType.error,
      );
    } catch (e) {
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
