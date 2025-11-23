// app/lib/screens/home/home_screen.dart - COMPLETELY RESTRUCTURED

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';

import '../../providers/auth_provider.dart';
import '../../models/sensor_data.dart';
import '../widgets/energy_card.dart';
import '../devices/device_scan_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../rooms/rooms_screen.dart';
import '../../core/constants/routes.dart';
import '../../providers/device_provider.dart';
import '../../providers/sensor_provider.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../../core/utils/logger.dart';
import '../../core/widgets/weather_time_widget.dart';
import '../../core/widgets/error_boundary.dart';
import '../../services/appliance_state_service.dart';
import '../../services/ml_service.dart';
import '../../models/ml_prediction.dart';

// ==================== PROVIDERS ====================

final mlServiceProvider = Provider((ref) => MLService());

final bleConnectionProvider = StreamProvider<bool>((ref) {
  final bluetoothService = ref.watch(bluetoothServiceProvider);
  return bluetoothService.connectionStream;
});

final energyConsumptionProvider =
    StreamProvider.family<double, String>((ref, userId) {
  final mlService = ref.watch(mlServiceProvider);
  // Use real-time stream for energy consumption updates
  // Use 7 days for better accuracy (home screen shows overall consumption)
  return mlService.watchInsights(userId, 7)
      .map((insights) => insights.energyConsumption)
      .handleError((error, stackTrace) {
    Logger.error('Energy consumption stream error: $error', error, stackTrace);
    // Return default value to keep stream alive
    return 0.0;
  });
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
        return ErrorBoundary(
          key: const ValueKey('HomeTab_0'),
          context: 'HomeTab',
          child: const HomeTab(),
        );
      case 1:
        return ErrorBoundary(
          key: const ValueKey('RoomsScreen_1'),
          context: 'RoomsScreen',
          child: RoomsScreen(),
        );
      case 2:
        return ErrorBoundary(
          key: const ValueKey('DeviceScanScreen_2'),
          context: 'DeviceScanScreen',
          child: const DeviceScanScreen(),
        );
      case 3:
        // Navigate to analytics without blocking
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            try {
              await Navigator.of(context).pushNamed(Routes.analytics);
            } catch (e) {
              Logger.error('HomeScreen: Navigation error', e);
            }
            if (mounted) {
              setState(() => _currentIndex = 0);
            }
          }
        });
        return ErrorBoundary(
          key: const ValueKey('HomeTab_3'),
          context: 'HomeTab',
          child: const HomeTab(),
        );
      default:
        return ErrorBoundary(
          key: const ValueKey('HomeTab_default'),
          context: 'HomeTab',
          child: const HomeTab(),
        );
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
              _buildNavItem(Icons.home, 'Home', 0, context),
              _buildNavItem('assets/icons/room.png', 'Rooms', 1, context),
              _buildNavItem('assets/icons/plus.png', 'Add', 2, context,
                  isCenter: true),
              _buildNavItem(Icons.bar_chart, 'Stats', 3, context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    dynamic icon, // Can be String (iconPath) or IconData
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
            icon is IconData
                ? Icon(
                    icon,
                    size: isCenter ? 32 : 24,
                    color: isSelected ? Colors.blue : Colors.white60,
                  )
                : Image.asset(
                    icon as String,
                    width: isCenter ? 32 : 24,
                    height: isCenter ? 32 : 24,
                    color: isSelected ? Colors.blue : Colors.white60,
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
      return const Center(child: Text('Please login'));
    }

    // Use read for providers that don't need to trigger rebuilds
    final currentUserAsync = ref.watch(currentUserProvider);
    final bleConnection = ref.read(bleConnectionProvider);
    final sensorData = ref.watch(sensorStreamProvider);

    // Use listen for side effects instead of whenData in build
    ref.listen<AsyncValue<SensorData?>>(
      sensorStreamProvider,
      (previous, next) {
        next.whenData((data) {
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
        next.whenOrNull(
          error: (error, stack) =>
              Logger.error('HomeTab: sensorData error: $error'),
        );
      },
    );

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
                    const WeatherTimeWidget(),
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
              crossAxisAlignment: CrossAxisAlignment.center,
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
              // Show a fallback with user info from Firebase Auth while loading
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                // Show basic info while loading detailed data
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildAvatar(
                        null,
                        user.displayName ??
                            user.email?.substring(0, 1).toUpperCase() ??
                            'U'),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildWelcomeText(user.displayName ??
                          user.email?.split('@')[0] ??
                          'User'),
                    ),
                    _buildBLEIndicator(bleConnection),
                    const SizedBox(width: 8),
                    _buildNotificationButton(),
                    const SizedBox(width: 8),
                    _buildMenuButton(),
                  ],
                );
              }
              // If no user, show loading
              return const Center(
                child: LottieLoading(
                  size: 50,
                  message: 'Loading...',
                  showMessage: true,
                ),
              );
            },
            error: (error, stackTrace) {
              Logger.error('HomeScreen: Error loading user data: $error');
              Logger.error('HomeScreen: Stack trace: $stackTrace');
              // Show error state with retry option
              return Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.red.shade300, size: 20),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Welcome back,',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white70,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          displayName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
      loading: () => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.bluetooth_disabled_rounded,
          color: Colors.grey,
          size: 20,
        ),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.bluetooth_disabled_rounded,
          color: Colors.red,
          size: 20,
        ),
      ),
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
        icon: Image.asset(
          'assets/icons/notification.png',
          width: 22,
          height: 22,
          color: Colors.white,
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
                    MaterialPageRoute(
                        builder: (context) => const OnboardingScreen()),
                    (route) => false,
                  );
                }
              } catch (e) {
                // Even if logout fails, try to navigate away
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (context) => const OnboardingScreen()),
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
  // Note: _buildSecurityCard and _handleSecurityToggle methods removed as they were unused

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
                _allAppliancesOn
                    ? Icons.power_off_rounded
                    : Icons.power_settings_new_rounded,
                size: 20,
              ),
              label: Text(
                _allAppliancesOn
                    ? 'Turn Off All Appliances'
                    : 'Turn On All Appliances',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _allAppliancesOn
                    ? Colors.red.shade600
                    : Colors.green.shade600,
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
      // Save state even if not connected
      final stateService = ApplianceStateService();
      await stateService.saveApplianceState(
        fanSpeed: turnOn ? 128 : 0,
        ledBrightness: turnOn ? 128 : 0,
        securityEnabled: turnOn,
      );

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
        await bleService
            .setLEDBrightness(128)
            .timeout(const Duration(seconds: 5));
        await bleService
            .setSecurityEnabled(true)
            .timeout(const Duration(seconds: 5));

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
        await bleService
            .setLEDBrightness(0)
            .timeout(const Duration(seconds: 5));
        await bleService
            .setSecurityEnabled(false)
            .timeout(const Duration(seconds: 5));

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
          message:
              'Failed to ${turnOn ? 'turn on' : 'turn off'} appliances: ${e.toString()}',
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
    final energyAsync = ref.watch(energyConsumptionProvider(userId));
    return energyAsync.when(
      data: (consumption) {
        return EnergyCard(
          consumption: consumption,
          status:
              consumption > 0 ? 'System performing well' : 'No data available',
        );
      },
      loading: () {
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
          childAspectRatio: 1.1,
          children: [
            _buildAnimatedSensorCard(
              animationPath: 'assets/animations/temperature.json',
              title: 'Temperature',
              value: sensorData.temperatureDisplay,
              subtitle: _getTemperatureStatus(sensorData.temperature),
              color: const Color(0xFFFF6B6B),
            ),
            _buildAnimatedSensorCard(
              animationPath: 'assets/animations/humidity.json',
              title: 'Humidity',
              value: sensorData.humidityDisplay,
              subtitle: _getHumidityStatus(sensorData.humidity),
              color: const Color(0xFF4ECDC4),
            ),
            _buildMotionSensorCard(
              motionDetected: sensorData.motionDetected,
              title: 'Motion',
              value: sensorData.motionDetected ? 'Detected' : 'No Motion',
              subtitle: _getMotionTime(sensorData.timestamp),
              color: const Color(0xFFFFE66D),
            ),
            _buildAnimatedSensorCard(
              animationPath: 'assets/animations/distance.json',
              title: 'Proximity',
              value: sensorData.distanceDisplay,
              subtitle: _getProximityStatus(sensorData.distance),
              color: const Color(0xFFA8E6CF),
            ),
          ],
        );
      },
      loading: () {
        return _buildDefaultSensorGrid();
      },
      error: (error, stack) {
        Logger.error('HomeTab: Sensor grid error: $error');
        return _buildDefaultSensorGrid();
      },
    );
  }

  Widget _buildAnimatedSensorCard({
    required String animationPath,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Lottie.asset(
                        animationPath,
                        fit: BoxFit.contain,
                        repeat: true,
                      ),
                    ),
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

  Widget _buildMotionSensorCard({
    required bool motionDetected,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Lottie.asset(
                        'assets/animations/motion.json',
                        fit: BoxFit.contain,
                        repeat: true,
                      ),
                    ),
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
      childAspectRatio: 1.1,
      children: [
        _buildAnimatedSensorCard(
          animationPath: 'assets/animations/temperature.json',
          title: 'Temperature',
          value: '--°C',
          subtitle: 'No data',
          color: const Color(0xFFFF6B6B),
        ),
        _buildAnimatedSensorCard(
          animationPath: 'assets/animations/humidity.json',
          title: 'Humidity',
          value: '--%',
          subtitle: 'No data',
          color: const Color(0xFF4ECDC4),
        ),
        _buildMotionSensorCard(
          motionDetected: false,
          title: 'Motion',
          value: 'No data',
          subtitle: 'Connect device',
          color: const Color(0xFFFFE66D),
        ),
        _buildAnimatedSensorCard(
          animationPath: 'assets/animations/distance.json',
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

  String _getHumidityStatus(double humidity) {
    if (humidity < 30) return 'Dry';
    if (humidity < 50) return 'Comfortable';
    if (humidity < 70) return 'Moderate';
    return 'Humid';
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
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Lottie.asset(
                    'assets/animations/emergency.json',
                    fit: BoxFit.contain,
                    repeat: true,
                  ),
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
