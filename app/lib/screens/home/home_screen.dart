import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/auth_provider.dart';
import '../../services/firebase_service.dart';
import '../../models/device_model.dart';
import '../../models/room_model.dart';
import '../widgets/energy_card.dart';
import '../widgets/device_card.dart';
import '../widgets/room_card.dart';
import '../rooms/rooms_screen.dart';
import '../devices/device_scan_screen.dart';
import '../analytics/analytics_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeTab(),
    RoomsScreen(),
    DeviceScanScreen(),
    AnalyticsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_rounded, 'Home', 0),
              _buildNavItem(Icons.meeting_room_rounded, 'Rooms', 1),
              _buildNavItem(Icons.add_circle_rounded, 'Devices', 2,
                  isCenter: true),
              _buildNavItem(Icons.bar_chart_rounded, 'Statistics', 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index,
      {bool isCenter = false}) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00BFA5).withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color:
                  isSelected ? const Color(0xFF00BFA5) : Colors.grey.shade400,
              size: isCenter ? 32 : 24,
            ),
            if (!isCenter) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? const Color(0xFF00BFA5)
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Home Tab
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final currentUserAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App Bar
            _buildAppBar(currentUserAsync),

            // Content
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Energy Consumption Card
                    const EnergyCard(
                      consumption: 672,
                      status: 'Our analytic is on performance',
                    ),
                    const SizedBox(height: 24),

                    // Quick Controls Section
                    const Text(
                      'Quick Controls',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Device Grid
                    _buildDeviceGrid(),
                    const SizedBox(height: 24),

                    // Rooms Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Rooms',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            // Navigate to rooms
                          },
                          child: const Text(
                            'See all',
                            style: TextStyle(
                              color: Color(0xFF00BFA5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Room Cards
                    _buildRoomsList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(AsyncValue currentUserAsync) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
          child: currentUserAsync.when(
            data: (user) => Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF00BFA5).withOpacity(0.1),
                  child: user?.profileImageUrl != null
                      ? ClipOval(
                          child: Image.network(
                            user!.profileImageUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Text(
                          user?.name.substring(0, 1).toUpperCase() ?? 'U',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00BFA5),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Welcome back,',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        user?.name.split(' ').first ?? 'User',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.notifications_outlined,
                      color: Colors.grey.shade700),
                  onPressed: () {
                    // Navigate to notifications
                  },
                ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox(),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceGrid() {
    // Sample devices - Replace with actual data from Firebase
    final devices = [
      DeviceModel(
        id: '1',
        name: 'Smart Lamp',
        type: DeviceType.light,
        roomId: 'living-room',
        isOn: true,
        value: 75,
        isOnline: true,
        lastSeen: DateTime.now(),
      ),
      DeviceModel(
        id: '2',
        name: 'Air Conditioner',
        type: DeviceType.airConditioner,
        roomId: 'living-room',
        isOn: false,
        value: 0,
        isOnline: true,
        lastSeen: DateTime.now(),
      ),
      DeviceModel(
        id: '3',
        name: 'Smart TV',
        type: DeviceType.tv,
        roomId: 'living-room',
        isOn: false,
        value: 0,
        isOnline: true,
        lastSeen: DateTime.now(),
      ),
      DeviceModel(
        id: '4',
        name: 'Vacuum Cleaner',
        type: DeviceType.vacuum,
        roomId: 'bedroom',
        isOn: false,
        value: 0,
        isOnline: true,
        lastSeen: DateTime.now(),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        return DeviceCard(device: devices[index]);
      },
    );
  }

  Widget _buildRoomsList() {
    // Sample rooms - Replace with actual data from Firebase
    final rooms = [
      RoomModel(
        id: '1',
        name: 'Living Room',
        icon: 'living_room',
        deviceIds: ['1', '2', '3'],
      ),
      RoomModel(
        id: '2',
        name: 'Kitchen',
        icon: 'kitchen',
        deviceIds: ['4'],
      ),
      RoomModel(
        id: '3',
        name: 'Bedroom',
        icon: 'bedroom',
        deviceIds: ['5', '6'],
      ),
    ];

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(right: index < rooms.length - 1 ? 16 : 0),
            child: RoomCard(room: rooms[index]),
          );
        },
      ),
    );
  }
}
