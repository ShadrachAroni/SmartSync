// app/lib/screens/home/home_screen.dart - COMPLETELY RESTRUCTURED

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../providers/auth_provider.dart';
import '../../services/firebase_service.dart';
import '../../models/sensor_data.dart';
import '../widgets/energy_card.dart';
import '../devices/device_scan_screen.dart';
import '../auth/login_screen.dart';
import '../rooms/rooms_screen.dart';
import '../../core/constants/routes.dart';
import '../../providers/device_provider.dart';
import '../../providers/sensor_provider.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/utils/logger.dart';
import '../../core/widgets/live_time_widget.dart';
import '../../core/utils/time_utils.dart';

// ==================== PROVIDERS ====================

final bleConnectionProvider = StreamProvider<bool>((ref) {
  final bluetoothService = ref.watch(bluetoothServiceProvider);
  return bluetoothService.connectionStream;
});

final energyConsumptionProvider =
    FutureProvider.family<double, String>((ref, userId) async {
  final firebaseService = ref.watch(firebaseServiceProvider);
  try {
    return await firebaseService
        .getTodayEnergyConsumption(userId)
        .timeout(const Duration(seconds: 10), onTimeout: () => 0.0);
  } catch (e) {
    return 0.0;
  }
});

// ==================== HOME SCREEN ====================

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: _getCurrentScreen(context),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _getCurrentScreen(BuildContext context) {
    switch (_currentIndex) {
      case 0:
        return const HomeTab();
      case 1:
        return RoomsScreen();
      case 2:
        return const DeviceScanScreen();
      case 3:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushNamed(Routes.analytics);
          setState(() => _currentIndex = 0);
        });
        return const HomeTab();
      default:
        return const HomeTab();
    }
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
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
              _buildNavItem(Icons.home_rounded, 'Home', 0, context),
              _buildNavItem(Icons.meeting_room_rounded, 'Rooms', 1, context),
              _buildNavItem(Icons.add_circle_rounded, 'Add', 2, context,
                  isCenter: true),
              _buildNavItem(Icons.bar_chart_rounded, 'Stats', 3, context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    String label,
    int index,
    BuildContext context, {
    bool isCenter = false,
  }) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        if (index == 3) {
          Navigator.of(context).pushNamed(Routes.analytics);
        } else {
          setState(() => _currentIndex = index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.blue : Colors.white60,
              size: isCenter ? 32 : 24,
            ),
            if (!isCenter) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.blue : Colors.white60,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== HOME TAB ====================

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  bool _securityToggleInProgress = false;
  bool _allAppliancesOn = false;

  @override
  void initState() {
    super.initState();
    // Initialize from sensor data if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sensorData = ref.read(sensorStreamProvider);
      sensorData.whenData((data) {
        if (data != null && mounted) {
          setState(() {
            _allAppliancesOn = (data.fanSpeed > 0 || data.ledBrightness > 0);
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      Logger.warning('HomeTab: User is null');
      return const Center(child: Text('Please login'));
    }

    Logger.debug('HomeTab: Building with user ${user.uid}');
    final currentUserAsync = ref.watch(currentUserProvider);
    final bleConnection = ref.watch(bleConnectionProvider);
    final sensorData = ref.watch(sensorStreamProvider);
    
    Logger.debug('HomeTab: currentUserAsync state: ${currentUserAsync.runtimeType}');
    Logger.debug('HomeTab: bleConnection state: ${bleConnection.runtimeType}');
    Logger.debug('HomeTab: sensorData state: ${sensorData.runtimeType}');
    
    sensorData.when(
      data: (data) => Logger.debug('HomeTab: sensorData has data: ${data != null}'),
      loading: () => Logger.debug('HomeTab: sensorData is loading'),
      error: (error, stack) => Logger.error('HomeTab: sensorData error: $error'),
    );

    // Sync appliance state from sensor data
    sensorData.whenData((data) {
      if (data != null && mounted) {
        final allOn = (data.fanSpeed > 0 || data.ledBrightness > 0);
        if (allOn != _allAppliancesOn) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _allAppliancesOn = allOn;
              });
            }
          });
        }
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildAppBar(currentUserAsync, bleConnection),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBLEBanner(bleConnection),
                    const SizedBox(height: 20),
                    _buildSecurityCard(sensorData, bleConnection),
                    const SizedBox(height: 20),
                    _buildEnergyCard(user.uid),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Environmental Status'),
                    const SizedBox(height: 16),
                    _buildSensorGrid(sensorData),
                    const SizedBox(height: 24),
                    _buildGlobalControlCard(bleConnection),
                    const SizedBox(height: 24),
                    _buildSOSButton(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== APP BAR ====================

  Widget _buildAppBar(
    AsyncValue currentUserAsync,
    AsyncValue<bool> bleConnection,
  ) {
    return SliverAppBar(
      expandedHeight: 140,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF1A1F3A),
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1A1F3A),
                const Color(0xFF0F1419),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
          child: currentUserAsync.when(
            data: (userData) => Row(
              children: [
                _buildAvatar(userData?.profileImageUrl, userData?.name ?? 'U'),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildWelcomeText(userData?.name ?? 'User'),
                ),
                _buildBLEIndicator(bleConnection),
                const SizedBox(width: 8),
                _buildNotificationButton(),
                const SizedBox(width: 8),
                _buildMenuButton(),
              ],
            ),
            loading: () {
              Logger.debug('HomeScreen: Loading user data...');
              // Show loading with timeout indicator
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
            error: (error, stackTrace) {
              Logger.error('HomeScreen: Error loading user data: $error');
              Logger.error('HomeScreen: Stack trace: $stackTrace');
              // Show error state with retry option
              return Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade300, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Error loading user',
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? imageUrl, String name) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.blue, Colors.cyan],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: imageUrl != null
          ? ClipOval(
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Text(
                      name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
            )
          : Center(
              child: Text(
                name.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }

  Widget _buildWelcomeText(String name) {
    final displayName = name.isNotEmpty ? name : 'User';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Welcome back,',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white70,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          displayName,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        // Live time display
        LiveTimeWidget(
          showSeconds: false,
          showDayNight: true,
          textStyle: TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildBLEIndicator(AsyncValue<bool> bleConnection) {
    return bleConnection.when(
      data: (isConnected) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isConnected
              ? Colors.green.withOpacity(0.2)
              : Colors.red.withOpacity(0.2),
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
    );
  }

  Widget _buildNotificationButton() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(
          Icons.notifications_outlined,
          color: Colors.white,
          size: 22,
        ),
        onPressed: () {
          Navigator.of(context).pushNamed(Routes.alerts);
        },
      ),
    );
  }

  Widget _buildMenuButton() {
    return PopupMenuButton<String>(
      icon: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.more_vert,
          color: Colors.white,
          size: 22,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      offset: const Offset(0, 55),
      elevation: 8,
      color: const Color(0xFF1A1F3A),
      itemBuilder: (context) => [
        _buildMenuItem(
            'settings', Icons.settings_outlined, 'Settings', Colors.white),
        _buildMenuItem(
            'security', Icons.security_rounded, 'Security', Colors.white),
        const PopupMenuDivider(),
        _buildMenuItem(
            'logout', Icons.logout_rounded, 'Logout', Colors.red.shade400),
      ],
      onSelected: _handleMenuAction,
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  void _handleMenuAction(String value) {
    switch (value) {
      case 'settings':
        Navigator.of(context).pushNamed(Routes.settings);
        break;
      case 'security':
        Navigator.of(context).pushNamed(Routes.security);
        break;
      case 'logout':
        _showLogoutDialog();
        break;
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.logout_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            const Text('Logout', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Are you sure you want to logout from SmartSync?',
          style: TextStyle(fontSize: 16, height: 1.5, color: Colors.white70),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                final bleService = ref.read(bluetoothServiceProvider);
                await bleService.disconnect().timeout(
                  const Duration(seconds: 5),
                  onTimeout: () {
                    // Ignore timeout, continue with logout
                  },
                );
                await FirebaseAuth.instance.signOut();

                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
              } catch (e) {
                // Even if logout fails, try to navigate away
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Logout', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  // ==================== BLE BANNER ====================

  Widget _buildBLEBanner(AsyncValue<bool> bleConnection) {
    return bleConnection.when(
      data: (isConnected) => !isConnected
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.withOpacity(0.2),
                    Colors.orange.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bluetooth_disabled,
                    color: Colors.orange,
                    size: 24,
                  ),
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
                            color: Colors.orange,
                          ),
                        ),
                        Text(
                          'Connect to your SmartSync device',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade300,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed(Routes.deviceScan);
                    },
                    child: Text(
                      'Connect',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // ==================== SECURITY CARD ====================

  Widget _buildSecurityCard(
    AsyncValue<SensorData?> sensorData,
    AsyncValue<bool> bleConnection,
  ) {
    final bool? connectionValue = bleConnection.asData?.value;
    final bool isConnected = connectionValue ?? false;

    return sensorData.when(
      data: (reading) {
        // Only show as armed if connected AND reading indicates it's armed
        // If not connected, default to false (disarmed)
        final bool isArmed = isConnected && (reading?.securityEnabled ?? false);

        return GestureDetector(
          onTap: () => Navigator.of(context).pushNamed(Routes.security),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isArmed
                    ? [Colors.green.shade700, Colors.green.shade900]
                    : [Colors.orange.shade700, Colors.orange.shade900],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color:
                      (isArmed ? Colors.green : Colors.orange).withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isArmed ? Icons.shield_rounded : Icons.shield_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Security System',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isArmed
                                ? 'Your safety protocols are active.'
                                : 'Security automations paused.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: isArmed,
                      onChanged: (!isConnected || _securityToggleInProgress)
                          ? null
                          : (value) {
                            Logger.info('Security toggle: ${value ? "arming" : "disarming"}');
                            _handleSecurityToggle(value);
                          },
                      activeColor: Colors.white,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.bluetooth, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      isConnected ? 'Device Connected' : 'Disconnected',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_securityToggleInProgress)
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F3A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: const Text(
          'Unable to load security status',
          style: TextStyle(color: Colors.red),
        ),
      ),
    );
  }

  Future<void> _handleSecurityToggle(bool enabled) async {
    final bleService = ref.read(bluetoothServiceProvider);

    if (!bleService.isConnected) {
      AppNotifications.showSnackBar(
        context,
        message: 'Connect to your SmartSync hub before changing security.',
        type: AppNotificationType.warning,
      );
      return;
    }

    setState(() => _securityToggleInProgress = true);
    final success = await bleService.setSecurityEnabled(enabled);
    if (!mounted) return;
    setState(() => _securityToggleInProgress = false);

    AppNotifications.showSnackBar(
      context,
      message: success
          ? 'Security ${enabled ? 'armed' : 'disarmed'} successfully.'
          : 'Unable to update security status.',
      type: success ? AppNotificationType.success : AppNotificationType.error,
    );
  }

  // ==================== GLOBAL CONTROL CARD ====================

  Widget _buildGlobalControlCard(AsyncValue<bool> bleConnection) {
    final bool? connectionValue = bleConnection.asData?.value;
    final bool isConnected = connectionValue ?? false;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade700.withOpacity(0.3),
            Colors.purple.shade700.withOpacity(0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.power_settings_new_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Global Control',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Switch all appliances on/off at once',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!isConnected)
                  ? null
                  : () => _handleGlobalToggle(!_allAppliancesOn),
              icon: Icon(
                _allAppliancesOn ? Icons.power_off_rounded : Icons.power_settings_new_rounded,
                size: 20,
              ),
              label: Text(
                _allAppliancesOn ? 'Turn Off All Appliances' : 'Turn On All Appliances',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _allAppliancesOn ? Colors.red.shade600 : Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
          if (!isConnected) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.white.withOpacity(0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Connect to your SmartSync hub to use this feature',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleGlobalToggle(bool turnOn) async {
    final bleService = ref.read(bluetoothServiceProvider);
    if (!bleService.isConnected) {
      AppNotifications.showSnackBar(
        context,
        message: 'Connect to your SmartSync hub first.',
        type: AppNotificationType.warning,
      );
      return;
    }

    try {
      if (turnOn) {
        // Turn on all devices to 50%
        await bleService.setFanSpeed(128).timeout(const Duration(seconds: 5));
        await bleService.setLEDBrightness(128).timeout(const Duration(seconds: 5));
        await bleService.setSecurityEnabled(true).timeout(const Duration(seconds: 5));

        if (mounted) {
          AppNotifications.showSnackBar(
            context,
            message: 'All appliances turned on.',
            type: AppNotificationType.success,
          );
        }
      } else {
        // Turn off all devices
        await bleService.setFanSpeed(0).timeout(const Duration(seconds: 5));
        await bleService.setLEDBrightness(0).timeout(const Duration(seconds: 5));
        await bleService.setSecurityEnabled(false).timeout(const Duration(seconds: 5));

        if (mounted) {
          AppNotifications.showSnackBar(
            context,
            message: 'All appliances turned off.',
            type: AppNotificationType.success,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppNotifications.showSnackBar(
          context,
          message: 'Failed to ${turnOn ? 'turn on' : 'turn off'} appliances: ${e.toString()}',
          type: AppNotificationType.error,
        );
      }
    }
  }

  // ==================== SECTION HEADER ====================

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  // ==================== ENERGY CARD ====================

  Widget _buildEnergyCard(String userId) {
    Logger.debug('HomeTab: Building energy card for user $userId');
    final energyAsync = ref.watch(energyConsumptionProvider(userId));
    return energyAsync.when(
      data: (consumption) {
        Logger.debug('HomeTab: Energy consumption loaded: $consumption');
        return EnergyCard(
          consumption: consumption,
          status:
              consumption > 0 ? 'System performing well' : 'No data available',
        );
      },
      loading: () {
        Logger.debug('HomeTab: Energy consumption loading...');
        return const EnergyCard(consumption: 0, status: 'Loading...');
      },
      error: (error, _) {
        Logger.error('HomeTab: Energy consumption error: $error');
        return const EnergyCard(
          consumption: 0,
          status: 'Unable to load energy data',
        );
      },
    );
  }

  // ==================== SENSOR GRID ====================

  Widget _buildSensorGrid(AsyncValue<SensorData?> sensorDataAsync) {
    Logger.debug('HomeTab: Building sensor grid');
    return sensorDataAsync.when(
      data: (sensorData) {
        Logger.debug('HomeTab: Sensor data received: ${sensorData != null}');
        if (sensorData == null) {
          Logger.warning('HomeTab: Sensor data is null, showing default grid');
          return _buildDefaultSensorGrid();
        }

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.1,
          children: [
            _buildAnimatedSensorCard(
              icon: Icons.thermostat_rounded,
              title: 'Temperature',
              value: sensorData.temperatureDisplay,
              subtitle: _getTemperatureStatus(sensorData.temperature),
              color: const Color(0xFFFF6B6B),
            ),
            _buildAnimatedSensorCard(
              icon: Icons.directions_walk_rounded,
              title: 'Motion',
              value: sensorData.motionDetected ? 'Detected' : 'No Motion',
              subtitle: _getMotionTime(sensorData.timestamp),
              color: const Color(0xFFFFE66D),
            ),
            _buildAnimatedSensorCard(
              icon: Icons.social_distance_rounded,
              title: 'Proximity',
              value: sensorData.distanceDisplay,
              subtitle: _getProximityStatus(sensorData.distance),
              color: const Color(0xFFA8E6CF),
            ),
          ],
        );
      },
      loading: () {
        Logger.debug('HomeTab: Sensor grid loading...');
        return _buildDefaultSensorGrid();
      },
      error: (error, stack) {
        Logger.error('HomeTab: Sensor grid error: $error');
        return _buildDefaultSensorGrid();
      },
    );
  }

  Widget _buildAnimatedSensorCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, animValue, child) {
        return Transform.scale(
          scale: animValue,
          child: Opacity(
            opacity: animValue,
            child: Container(
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
                border: Border.all(color: color.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 32, color: color),
                    const SizedBox(height: 10),
                    Flexible(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Flexible(
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
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

  Widget _buildDefaultSensorGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.2,
      children: [
        _buildAnimatedSensorCard(
          icon: Icons.thermostat_rounded,
          title: 'Temperature',
          value: '--°C',
          subtitle: 'No data',
          color: const Color(0xFFFF6B6B),
        ),
        _buildAnimatedSensorCard(
          icon: Icons.directions_walk_rounded,
          title: 'Motion',
          value: 'No data',
          subtitle: 'Connect device',
          color: const Color(0xFFFFE66D),
        ),
        _buildAnimatedSensorCard(
          icon: Icons.social_distance_rounded,
          title: 'Proximity',
          value: '-- cm',
          subtitle: 'No data',
          color: const Color(0xFFA8E6CF),
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


  // ==================== SOS BUTTON ====================

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
        backgroundColor: const Color(0xFF1A1F3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.emergency,
                color: Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Emergency Alert',
                style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will notify all your caregivers immediately.\n\nDo you need emergency assistance?',
          style: TextStyle(fontSize: 16, height: 1.5, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
            ),
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
                await _triggerSecurityAlarm();

                if (mounted) {
                  AppNotifications.showSnackBar(
                    context,
                    message: 'Emergency alert sent to caregivers!',
                    type: AppNotificationType.success,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Send Alert', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Future<bool> _triggerSecurityAlarm({int durationMs = 5000}) async {
    final bleService = ref.read(bluetoothServiceProvider);
    if (!bleService.isConnected) {
      AppNotifications.showSnackBar(
        context,
        message: 'SOS sent, but hub is offline so alarm was not triggered.',
        type: AppNotificationType.warning,
      );
      return false;
    }

    final success =
        await bleService.triggerSecurityAlarm(durationMs: durationMs);
    if (!success && mounted) {
      AppNotifications.showSnackBar(
        context,
        message: 'Hub did not acknowledge the SOS alarm.',
        type: AppNotificationType.error,
      );
    }
    return success;
  }
}
