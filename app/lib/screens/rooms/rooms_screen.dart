// app/lib/screens/rooms/rooms_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/room_model.dart';
import '../../models/device_model.dart';
import '../../services/firebase_service.dart';
import '../../providers/device_provider.dart';
import 'add_room_screen.dart';
import '../../core/constants/routes.dart';

// Provider for rooms
final roomsProvider = StreamProvider.autoDispose<List<RoomModel>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);

  try {
    final firebaseService = FirebaseService();
    return firebaseService.getUserRooms(user.uid).timeout(
      const Duration(seconds: 30),
      onTimeout: (sink) {
        sink.addError('Request timed out. Please check your connection.');
      },
    ).handleError((error) {
      // Return empty list on error instead of crashing
      return <RoomModel>[];
    });
  } catch (e) {
    return Stream.value(<RoomModel>[]);
  }
});

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  String _selectedFilter = 'All';
  final List<String> _filters = [
    'All',
    'Living Room',
    'Kitchen',
    'Bedroom',
    'Bathroom'
  ];

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomsProvider);
    final user = FirebaseAuth.instance.currentUser;
    final devicesAsync = user == null
        ? const AsyncValue<List<DeviceModel>>.data([])
        : ref.watch(deviceControllerProvider(user.uid));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        title: const Text(
          'My Rooms',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white70),
            onPressed: () {
              final rooms = ref.read(roomsProvider).maybeWhen(
                    data: (rooms) => rooms,
                    orElse: () => <RoomModel>[],
                  );
              showSearch<RoomModel?>(
                context: context,
                delegate: RoomSearchDelegate(rooms),
              ).then((room) {
                if (room != null) {
                  Navigator.pushNamed(
                    context,
                    Routes.roomDetail,
                    arguments: room,
                  );
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Color(0xFF00BFA5)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddRoomScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Room Type Filters
            _buildFilterChips(),

            // Rooms Grid
            Expanded(
              child: roomsAsync.when(
                data: (rooms) {
                  if (rooms.isEmpty) {
                    return _buildEmptyState();
                  }

                  final filteredRooms = _selectedFilter == 'All'
                      ? rooms
                      : rooms.where((r) => r.name == _selectedFilter).toList();

                  if (filteredRooms.isEmpty) {
                    return _buildNoResultsState();
                  }

                  final devices = devicesAsync.maybeWhen(
                    data: (list) => list,
                    orElse: () => <DeviceModel>[],
                  );
                  return _buildRoomsGrid(filteredRooms, devices);
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                error: (error, stackTrace) {
                  // Handle errors gracefully with timeout
                  final errorMessage = error.toString().contains('timeout')
                      ? 'Connection timed out. Please check your internet and try again.'
                      : error.toString();
                  return _buildErrorState(errorMessage);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 60,
      color: const Color(0xFF1A1F3A),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              label: Text(
                filter,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedFilter = filter;
                });
              },
              backgroundColor: Colors.white.withOpacity(0.1),
              selectedColor: Colors.blue,
              checkmarkColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 0,
              pressElevation: 0,
            ),
          );
        },
      ),
    );
  }

  Widget _buildRoomsGrid(List<RoomModel> rooms, List<DeviceModel> devices) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        return _buildRoomCard(rooms[index], devices);
      },
    );
  }

  Widget _buildRoomCard(RoomModel room, List<DeviceModel> devices) {
    final activeCount =
        devices.where((d) => d.roomId == room.id && d.isOn).length;
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          Routes.roomDetail,
          arguments: room,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Room Image/Icon
            Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _getRoomColor(room.icon).withOpacity(0.7),
                    _getRoomColor(room.icon),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Stack(
                children: [
                  // Background pattern
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.1,
                      child: Icon(
                        _getRoomIcon(room.icon),
                        size: 100,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  // Room icon
                  Center(
                    child: Icon(
                      _getRoomIcon(room.icon),
                      size: 50,
                      color: Colors.white,
                    ),
                  ),

                  // Device count badge
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${room.deviceIds.length} devices',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Room info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.power_settings_new_rounded,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$activeCount active',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: const Color(0xFF00BFA5).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.meeting_room_rounded,
                size: 80,
                color: const Color(0xFF00BFA5),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'No Rooms Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create your first room to start\norganizing your smart devices',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddRoomScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Room'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFA5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No $_selectedFilter rooms',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try selecting a different filter',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Error Loading Rooms',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
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

class RoomSearchDelegate extends SearchDelegate<RoomModel?> {
  RoomSearchDelegate(this.rooms);

  final List<RoomModel> rooms;

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = _filterRooms();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final room = results[index];
        return ListTile(
          leading:
              Icon(Icons.meeting_room_rounded, color: const Color(0xFF00BFA5)),
          title: Text(room.name),
          onTap: () => close(context, room),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = _filterRooms();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final room = results[index];
        return ListTile(
          title: Text(room.name),
          onTap: () => close(context, room),
        );
      },
    );
  }

  List<RoomModel> _filterRooms() {
    if (query.isEmpty) return rooms;
    final lower = query.toLowerCase();
    return rooms
        .where((room) => room.name.toLowerCase().contains(lower))
        .toList();
  }
}
