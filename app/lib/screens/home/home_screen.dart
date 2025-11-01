// app/lib/screens/home/home_screen.dart - COMPLETE VERSION
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../services/firebase_service.dart';
import '../../services/bluetooth_service.dart';
import '../../models/device_model.dart';
import '../../models/room_model.dart';
import '../../models/sensor_data.dart';
import '../widgets/energy_card.dart';
import '../widgets/device_card.dart';
import '../widgets/sensor_card.dart';
import '../widgets/room_card.dart';
import '../rooms/rooms_screen.dart';
import '../devices/device_scan_screen.dart';
import '../analytics/analytics_screen.dart';
import '../auth/login_screen.dart';

// ==================== PROVIDERS ====================
final firebaseServiceProvider = Provider((ref) => FirebaseService());
final bluetoothServiceProvider = Provider((ref) => BluetoothService());

// Stream provider for user devices
final userDevicesProvider = StreamProvider.family<List<DeviceModel>, String>(
  (ref, userId) {
    final firebaseService = ref.watch(firebaseServiceProvider);
    return firebaseService.getUserDevices(userId);
  },
);

// Stream provider for user rooms
final userRoomsProvider = StreamProvider.family<List<RoomModel>, String>(
  (ref, userId) {
    final firebaseService = ref.watch(firebaseServiceProvider);
    return firebaseService.getUserRooms(userId);
  },
);

// Stream provider for sensor data
final sensorDataProvider = StreamProvider<SensorData?>((ref) {
  final bluetoothService = ref.watch(bluetoothServiceProvider);
  return bluetoothService.sensorDataStream;
});

// BLE connection state provider
final bleConnectionProvider = StreamProvider<bool>((ref) {
  final bluetoothService = ref.watch(bluetoothServiceProvider);
  return bluetoothService.connectionStream;
});

// Energy consumption provider
final energyConsumptionProvider = FutureProvider.family<double, String>(
  (ref, userId) async {
    final firebaseService = ref.watch(firebaseServiceProvider);
    return await firebaseService.getTodayEnergyConsumption(userId);
  },
);

// ==================== HOME SCREEN ====================
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
              _buildNavItem(Icons.add_circle_rounded, 'Add', 2, isCenter: true),
              _buildNavItem(Icons.bar_chart_rounded, 'Stats', 3),
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

// ==================== ENHANCED HOME TAB ====================
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
    final bleConnection = ref.watch(bleConnectionProvider);
    final sensorData = ref.watch(sensorDataProvider);

    if (user == null) {
      return const Center(child: Text('Please login'));
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App Bar with BLE status
            _buildEnhancedAppBar(currentUserAsync, bleConnection),

            // Content
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // BLE Connection Status Banner
                    _buildBLEStatusBanner(bleConnection),
                    const SizedBox(height: 16),

                    // Energy Consumption Card (Real-time)
                    _buildEnergyCard(user.uid),
                    const SizedBox(height: 24),

                    // Environmental Sensors (Real-time from BLE)
                    _buildSectionHeader('Environmental Status'),
                    const SizedBox(height: 16),
                    _buildSensorGrid(sensorData),
                    const SizedBox(height: 24),

                    // Quick Device Controls (Real-time from Firebase)
                    _buildSectionHeader('Quick Controls'),
                    const SizedBox(height: 16),
                    _buildDeviceGrid(user.uid),
                    const SizedBox(height: 24),

                    // Emergency SOS Button
                    _buildSOSButton(),
                    const SizedBox(height: 24),

                    // Rooms Preview (Real-time from Firebase)
                    _buildSectionHeader('My Rooms', showSeeAll: true),
                    const SizedBox(height: 16),
                    _buildRoomsList(user.uid),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedAppBar(
      AsyncValue currentUserAsync, AsyncValue<bool> bleConnection) {
    return SliverAppBar(
      expandedHeight: 140,
      floating: false,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
          child: currentUserAsync.when(
            data: (userData) => Row(
              children: [
                // User Avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00BFA5), Color(0xFF00897B)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00BFA5).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      userData?.name.substring(0, 1).toUpperCase() ?? 'U',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Welcome Text
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
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userData?.name.split(' ').first ?? 'User',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // BLE Connection Indicator
                bleConnection.when(
                  data: (isConnected) => Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.bluetooth_rounded,
                      color: isConnected ? Colors.green : Colors.red,
                      size: 20,
                    ),
                  ),
                  loading: () => const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const SizedBox(),
                ),
                const SizedBox(width: 8),

                // Notification Bell
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.notifications_outlined,
                        color: Colors.grey.shade700, size: 22),
                    onPressed: () {
                      // Navigate to notifications
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Menu with Logout
                PopupMenuButton<String>(
                  icon: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.more_vert,
                        color: Colors.grey.shade700, size: 22),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  offset: const Offset(0, 55),
                  elevation: 8,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'profile',
                      child: Row(
                        children: [
                          Icon(Icons.person_outline,
                              color: Colors.grey.shade700, size: 20),
                          const SizedBox(width: 12),
                          const Text('Profile'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'settings',
                      child: Row(
                        children: [
                          Icon(Icons.settings_outlined,
                              color: Colors.grey.shade700, size: 20),
                          const SizedBox(width: 12),
                          const Text('Settings'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout_rounded,
                              color: Colors.red.shade600, size: 20),
                          const SizedBox(width: 12),
                          Text('Logout',
                              style: TextStyle(color: Colors.red.shade600)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: _handleMenuAction,
                ),
              ],
            ),
            loading: () => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
              ),
            ),
            error: (_, __) => const SizedBox(),
          ),
        ),
      ),
    );
  }

  void _handleMenuAction(String value) {
    switch (value) {
      case 'profile':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile - Coming Soon')),
        );
        break;
      case 'settings':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings - Coming Soon')),
        );
        break;
      case 'logout':
        _showLogoutDialog();
        break;
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.logout_rounded,
                  color: Colors.red.shade600, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Logout'),
          ],
        ),
        content: const Text(
          'Are you sure you want to logout from SmartSync?',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () async {
              final bleService = ref.read(bluetoothServiceProvider);
              await bleService.disconnect();
              await FirebaseAuth.instance.signOut();

              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Logout', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildBLEStatusBanner(AsyncValue<bool> bleConnection) {
    return bleConnection.when(
      data: (isConnected) => !isConnected
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.bluetooth_disabled,
                      color: Colors.orange.shade700, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device Disconnected',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        Text(
                          'Connect to your SmartSync device',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      // Navigate to device scan
                    },
                    child: Text('Connect',
                        style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildSectionHeader(String title, {bool showSeeAll = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        if (showSeeAll)
          TextButton(
            onPressed: () {},
            child: const Text(
              'See all',
              style: TextStyle(
                color: Color(0xFF00BFA5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEnergyCard(String userId) {
    final energyAsync = ref.watch(energyConsumptionProvider(userId));

    return energyAsync.when(
      data: (consumption) => EnergyCard(
        consumption: consumption,
        status: 'System performing well',
      ),
      loading: () => const EnergyCard(
        consumption: 0,
        status: 'Loading...',
      ),
      error: (_, __) => const EnergyCard(
        consumption: 0,
        status: 'Error loading data',
      ),
    );
  }

  Widget _buildSensorGrid(AsyncValue<SensorData?> sensorDataAsync) {
    return sensorDataAsync.when(
      data: (sensorData) {
        if (sensorData == null) {
          return _buildDefaultSensorGrid();
        }

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.4,
          children: [
            SensorCard(
              icon: Icons.thermostat_rounded,
              title: 'Temperature',
              value: sensorData.temperatureDisplay,
              subtitle: _getTemperatureStatus(sensorData.temperature),
              color: const Color(0xFFFF6B6B),
              onTap: () {},
            ),
            SensorCard(
              icon: Icons.water_drop_rounded,
              title: 'Humidity',
              value: sensorData.humidityDisplay,
              subtitle: _getHumidityStatus(sensorData.humidity),
              color: const Color(0xFF4ECDC4),
              onTap: () {},
            ),
            SensorCard(
              icon: Icons.directions_walk_rounded,
              title: 'Motion',
              value: sensorData.motionDetected ? 'Detected' : 'No Motion',
              subtitle: _getMotionTime(sensorData.timestamp),
              color: const Color(0xFFFFE66D),
              onTap: () {},
            ),
            SensorCard(
              icon: Icons.social_distance_rounded,
              title: 'Proximity',
              value: sensorData.distanceDisplay,
              subtitle: _getProximityStatus(sensorData.distance),
              color: const Color(0xFFA8E6CF),
              onTap: () {},
            ),
          ],
        );
      },
      loading: () => _buildDefaultSensorGrid(),
      error: (_, __) => _buildDefaultSensorGrid(),
    );
  }

  Widget _buildDefaultSensorGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.4,
      children: [
        SensorCard(
          icon: Icons.thermostat_rounded,
          title: 'Temperature',
          value: '--°C',
          subtitle: 'No data',
          color: const Color(0xFFFF6B6B),
          onTap: () {},
        ),
        SensorCard(
          icon: Icons.water_drop_rounded,
          title: 'Humidity',
          value: '--%',
          subtitle: 'No data',
          color: const Color(0xFF4ECDC4),
          onTap: () {},
        ),
        SensorCard(
          icon: Icons.directions_walk_rounded,
          title: 'Motion',
          value: 'No data',
          subtitle: 'Connect device',
          color: const Color(0xFFFFE66D),
          onTap: () {},
        ),
        SensorCard(
          icon: Icons.social_distance_rounded,
          title: 'Proximity',
          value: '-- cm',
          subtitle: 'No data',
          color: const Color(0xFFA8E6CF),
          onTap: () {},
        ),
      ],
    );
  }

  String _getTemperatureStatus(double temp) {
    if (temp < 18) return 'Cold';
    if (temp < 24) return 'Comfortable';
    if (temp < 28) return 'Warm';
    return 'Hot';
  }

  String _getHumidityStatus(double humidity) {
    if (humidity < 30) return 'Dry';
    if (humidity < 60) return 'Normal';
    return 'Humid';
  }

  String _getMotionTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours}h ago';
  }

  String _getProximityStatus(double distance) {
    if (distance < 50) return 'Very Close';
    if (distance < 150) return 'Close';
    return 'Far';
  }

  Widget _buildDeviceGrid(String userId) {
    final devicesAsync = ref.watch(userDevicesProvider(userId));

    return devicesAsync.when(
      data: (devices) {
        if (devices.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.devices_other,
                      size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No devices yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Add Device'),
                  ),
                ],
              ),
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.1,
          ),
          itemCount: devices.length > 4 ? 4 : devices.length,
          itemBuilder: (context, index) {
            return DeviceCard(device: devices[index]);
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
        ),
      ),
      error: (error, _) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Error loading devices',
          style: TextStyle(color: Colors.red.shade900),
        ),
      ),
    );
  }

  Widget _buildSOSButton() {
    return Container(
      width: double.infinity,
      height: 70,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade600, Colors.red.shade800],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade600.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleSOSPress,
          borderRadius: BorderRadius.circular(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emergency,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'EMERGENCY HELP',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSOSPress() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.emergency, color: Colors.red.shade600, size: 28),
            ),
            const SizedBox(width: 12),
            const Text('Emergency Alert'),
          ],
        ),
        content: const Text(
          'This will notify all your caregivers immediately.\n\nDo you need emergency assistance?',
          style: TextStyle(fontSize: 16, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                await FirebaseFirestore.instance.collection('alerts').add({
                  'userId': user.uid,
                  'type': 'SOS',
                  'severity': 'critical',
                  'timestamp': FieldValue.serverTimestamp(),
                  'message': 'Emergency assistance requested',
                });
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                            child: Text('Emergency alert sent to caregivers!')),
                      ],
                    ),
                    backgroundColor: Colors.green.shade600,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Send Alert', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsList(String userId) {
    final roomsAsync = ref.watch(userRoomsProvider(userId));

    return roomsAsync.when(
      data: (rooms) {
        if (rooms.isEmpty) {
          return Container(
            height: 120,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.meeting_room_rounded,
                      size: 32, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'No rooms created yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              return Padding(
                padding:
                    EdgeInsets.only(right: index < rooms.length - 1 ? 16 : 0),
                child: RoomCard(room: rooms[index]),
              );
            },
          ),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
        ),
      ),
      error: (error, _) => Container(
        height: 120,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'Error loading rooms',
            style: TextStyle(color: Colors.red.shade900),
          ),
        ),
      ),
    );
  }
}
