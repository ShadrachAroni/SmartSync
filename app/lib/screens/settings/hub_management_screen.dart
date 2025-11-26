import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/device_model.dart';
import '../../models/room_model.dart';
import '../../services/firebase_service.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../../core/utils/logger.dart';
import '../../services/bluetooth_service.dart';

class HubManagementScreen extends ConsumerStatefulWidget {
  const HubManagementScreen({super.key});

  @override
  ConsumerState<HubManagementScreen> createState() =>
      _HubManagementScreenState();
}

class _HubManagementScreenState extends ConsumerState<HubManagementScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLoading = true;
  List<DeviceModel> _hubs = [];
  List<RoomModel> _rooms = [];
  String? _primaryHubId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Load all hubs
      final devices = await _firebaseService.fetchUserDevices(user.uid);
      _hubs = devices.where((d) => d.isHub).toList();

      // Load all rooms
      _rooms = await _firebaseService.getUserRooms(user.uid).first;

      // Get primary hub
      _primaryHubId = await _firebaseService.getPrimaryHub(user.uid);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      Logger.error('HubManagementScreen: Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        AppNotifications.showSnackBar(
          context,
          message: 'Failed to load hub data: ${e.toString()}',
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _setPrimaryHub(String hubId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _firebaseService.setPrimaryHub(user.uid, hubId);
      _primaryHubId = hubId;

      if (mounted) {
        setState(() {});
        
        // Update ESP32 LCD display if connected
        try {
          final bluetoothService = BluetoothService();
          if (bluetoothService.isConnected && 
              bluetoothService.connectedDeviceId == hubId) {
            await bluetoothService.updateHubConfiguration();
          }
        } catch (e) {
          Logger.warning('Failed to update hub configuration on ESP32: $e');
        }
        
        AppNotifications.showSnackBar(
          context,
          message: 'Primary hub updated successfully',
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      Logger.error('HubManagementScreen: Error setting primary hub: $e');
      if (mounted) {
        AppNotifications.showSnackBar(
          context,
          message: 'Failed to set primary hub: ${e.toString()}',
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _reassignHub(String hubId, String? currentRoomId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Show dialog to select new room
    final selectedRoomId = await showDialog<String>(
      context: context,
      builder: (context) => _RoomSelectionDialog(
        rooms: _rooms,
        currentRoomId: currentRoomId,
        hubId: hubId,
      ),
    );

    if (selectedRoomId == null || selectedRoomId == currentRoomId) {
      return; // User cancelled or selected same room
    }

    try {
      // Check if selected room already has a hub
      final selectedRoom = _rooms.firstWhere((r) => r.id == selectedRoomId);
      if (selectedRoom.hubId != null &&
          selectedRoom.hubId!.isNotEmpty &&
          selectedRoom.hubId != hubId) {
        AppNotifications.showSnackBar(
          context,
          message:
              'Room "${selectedRoom.name}" already has a hub assigned. Each room can only have one hub.',
          type: AppNotificationType.error,
        );
        return;
      }

      // Remove hub from current room if it exists
      if (currentRoomId != null && currentRoomId.isNotEmpty) {
        await _firebaseService.updateRoom(user.uid, currentRoomId, {
          'hubId': FieldValue.delete(),
          'isPrimaryHub': false,
        });
      }

      // Assign hub to new room
      await _firebaseService.updateRoom(user.uid, selectedRoomId, {
        'hubId': hubId,
      });

      // Update hub device's roomId
      await _firebaseService.updateDevice(hubId, {
        'roomId': selectedRoomId,
      });

      // Also update virtual devices (fan and light)
      final fanDeviceId = '${hubId}_fan';
      final lightDeviceId = '${hubId}_light';
      await _firebaseService.updateDevice(fanDeviceId, {
        'roomId': selectedRoomId,
      });
      await _firebaseService.updateDevice(lightDeviceId, {
        'roomId': selectedRoomId,
      });

      // Reload data
      await _loadData();

      // Update ESP32 LCD display if connected
      try {
        final bluetoothService = BluetoothService();
        if (bluetoothService.isConnected && 
            bluetoothService.connectedDeviceId == hubId) {
          await bluetoothService.updateHubConfiguration();
        }
      } catch (e) {
        Logger.warning('Failed to update hub configuration on ESP32: $e');
      }

      if (mounted) {
        AppNotifications.showSnackBar(
          context,
          message: 'Hub reassigned to ${selectedRoom.name} successfully',
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      Logger.error('HubManagementScreen: Error reassigning hub: $e');
      if (mounted) {
        AppNotifications.showSnackBar(
          context,
          message: 'Failed to reassign hub: ${e.toString()}',
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _removeHubFromRoom(String hubId, String roomId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        title: const Text(
          'Remove Hub from Room?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will remove the hub from its current room. The hub and its appliances will still exist but won\'t be assigned to any room.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Remove hub from room
      await _firebaseService.updateRoom(user.uid, roomId, {
        'hubId': FieldValue.delete(),
        'isPrimaryHub': false,
      });

      // Update hub device's roomId
      await _firebaseService.updateDevice(hubId, {
        'roomId': '',
      });

      // Also update virtual devices
      final fanDeviceId = '${hubId}_fan';
      final lightDeviceId = '${hubId}_light';
      await _firebaseService.updateDevice(fanDeviceId, {
        'roomId': '',
      });
      await _firebaseService.updateDevice(lightDeviceId, {
        'roomId': '',
      });

      // Reload data
      await _loadData();

      if (mounted) {
        AppNotifications.showSnackBar(
          context,
          message: 'Hub removed from room successfully',
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      Logger.error('HubManagementScreen: Error removing hub: $e');
      if (mounted) {
        AppNotifications.showSnackBar(
          context,
          message: 'Failed to remove hub: ${e.toString()}',
          type: AppNotificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E27),
        appBar: AppBar(
          title: const Text(
            'Hub Management',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF1A1F3A),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(child: LottieLoading.medium()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: const Text(
          'Hub Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A1F3A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _hubs.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildSectionHeader('Primary Hub'),
                  if (_primaryHubId != null) ...[
                    _buildPrimaryHubCard(),
                    const SizedBox(height: 24),
                  ],
                  _buildSectionHeader('All Hubs'),
                  ..._hubs.map((hub) => _buildHubCard(hub)),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.router_outlined,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Hubs Registered',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect to an ESP32 hub to register it',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00BFA5),
        ),
      ),
    );
  }

  Widget _buildPrimaryHubCard() {
    final primaryHub = _hubs.firstWhere(
      (h) => h.id == _primaryHubId,
      orElse: () => _hubs.first,
    );
    final room = _rooms.firstWhere(
      (r) => r.hubId == primaryHub.id,
      orElse: () => RoomModel(id: '', name: 'No Room', icon: 'home'),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00BFA5).withOpacity(0.2),
            const Color(0xFF00BFA5).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00BFA5).withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BFA5).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.star,
                  color: Color(0xFF00BFA5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryHub.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Primary Hub • ${room.name}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHubCard(DeviceModel hub) {
    final room = _rooms.firstWhere(
      (r) => r.hubId == hub.id,
      orElse: () => RoomModel(id: '', name: 'No Room Assigned', icon: 'home'),
    );
    final isPrimary = hub.id == _primaryHubId;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrimary
              ? const Color(0xFF00BFA5).withOpacity(0.5)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BFA5).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.router,
                  color: Color(0xFF00BFA5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            hub.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (isPrimary)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00BFA5).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  size: 14,
                                  color: Color(0xFF00BFA5),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Primary',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF00BFA5),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      room.name,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hub.id,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (!isPrimary)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _setPrimaryHub(hub.id),
                    icon: const Icon(Icons.star_outline, size: 18),
                    label: const Text('Set as Primary'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00BFA5),
                      side: const BorderSide(color: Color(0xFF00BFA5)),
                    ),
                  ),
                ),
              if (!isPrimary && room.id.isNotEmpty) const SizedBox(width: 8),
              if (room.id.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reassignHub(hub.id, room.id),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Reassign'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                    ),
                  ),
                ),
              if (room.id.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _removeHubFromRoom(hub.id, room.id),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  tooltip: 'Remove from room',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RoomSelectionDialog extends StatelessWidget {
  final List<RoomModel> rooms;
  final String? currentRoomId;
  final String hubId;

  const _RoomSelectionDialog({
    required this.rooms,
    required this.currentRoomId,
    required this.hubId,
  });

  @override
  Widget build(BuildContext context) {
    // Filter out rooms that already have a different hub
    final availableRooms = rooms.where((room) {
      return room.hubId == null ||
          room.hubId!.isEmpty ||
          room.hubId == hubId;
    }).toList();

    return Dialog(
      backgroundColor: const Color(0xFF1A1F3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Room',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: availableRooms.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No available rooms. All rooms already have hubs assigned.',
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: availableRooms.length,
                      itemBuilder: (context, index) {
                        final room = availableRooms[index];
                        final isCurrent = room.id == currentRoomId;
                        return ListTile(
                          leading: Icon(
                            Icons.room,
                            color: isCurrent
                                ? const Color(0xFF00BFA5)
                                : Colors.white70,
                          ),
                          title: Text(
                            room.name,
                            style: TextStyle(
                              color: isCurrent
                                  ? const Color(0xFF00BFA5)
                                  : Colors.white,
                              fontWeight:
                                  isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: isCurrent
                              ? const Text(
                                  'Current room',
                                  style: TextStyle(color: Color(0xFF00BFA5)),
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(room.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

