import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../providers/sensor_provider.dart';
import '../../providers/device_provider.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../../core/widgets/lottie_motion_indicator.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _securityToggleInProgress = false;
  bool _alarmTriggerInProgress = false;
  bool _motionDetection = true;
  bool _alertNotifications = true;
  bool _autoArmSchedule = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login')),
      );
    }

    final sensorData = ref.watch(sensorStreamProvider);
    final bleConnection = ref.watch(bleConnectionProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: const Text(
          'Security Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSecurityStatusCard(sensorData, bleConnection),
            const SizedBox(height: 24),
            _buildSensorCards(sensorData),
            const SizedBox(height: 24),
            _buildAlarmControls(),
            const SizedBox(height: 24),
            _buildSecuritySettings(),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityStatusCard(
    AsyncValue sensorData,
    AsyncValue<bool> bleConnection,
  ) {
    final bool? connectionValue = bleConnection.asData?.value;
    final bool isConnected = connectionValue ?? false;

    return sensorData.when(
      data: (reading) {
        final bool isArmed = reading?.securityEnabled ?? false;

        return Container(
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
                color: (isArmed ? Colors.green : Colors.orange)
                    .withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(
                isArmed ? Icons.shield_rounded : Icons.shield_outlined,
                size: 64,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              Text(
                isArmed ? 'SYSTEM ARMED' : 'SYSTEM DISARMED',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isArmed
                    ? 'Your security protocols are active'
                    : 'Security automations are paused',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Switch.adaptive(
                value: isArmed,
                onChanged: (!isConnected || _securityToggleInProgress)
                    ? null
                    : _handleSecurityToggle,
              ),
            ],
          ),
        );
      },
      loading: () => _buildLoadingCard(),
      error: (_, __) => _buildErrorCard(),
    );
  }

  Widget _buildAlarmControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.red.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.emergency_rounded,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Alarm',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Trigger immediate alert',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
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
              onPressed: _alarmTriggerInProgress ? null : _handleTriggerAlarm,
              icon: _alarmTriggerInProgress
                  ? const LottieLoading.small()
                  : const Icon(Icons.warning_rounded),
              label: Text(
                _alarmTriggerInProgress ? 'Triggering...' : 'Trigger Alarm',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecuritySettings() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Security Settings',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          _buildSettingTile(
            icon: Icons.motion_photos_on_rounded,
            title: 'Motion Detection',
            subtitle: 'Alert on unusual activity',
            value: _motionDetection,
            onChanged: (value) {
              setState(() => _motionDetection = value);
              AppNotifications.showSnackBar(
                context,
                message: 'Motion detection ${value ? 'enabled' : 'disabled'}',
                type: AppNotificationType.success,
              );
            },
          ),
          const Divider(color: Colors.white24, height: 32),
          _buildSettingTile(
            icon: Icons.notifications_active_rounded,
            title: 'Alert Notifications',
            subtitle: 'Receive security alerts',
            value: _alertNotifications,
            onChanged: (value) {
              setState(() => _alertNotifications = value);
              AppNotifications.showSnackBar(
                context,
                message: 'Alert notifications ${value ? 'enabled' : 'disabled'}',
                type: AppNotificationType.success,
              );
            },
          ),
          const Divider(color: Colors.white24, height: 32),
          _buildSettingTile(
            icon: Icons.access_time_rounded,
            title: 'Auto-Arm Schedule',
            subtitle: 'Automatically arm at night',
            value: _autoArmSchedule,
            onChanged: (value) {
              setState(() => _autoArmSchedule = value);
              AppNotifications.showSnackBar(
                context,
                message: 'Auto-arm schedule ${value ? 'enabled' : 'disabled'}',
                type: AppNotificationType.success,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.blue, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
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
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.blue,
        ),
      ],
    );
  }

  Widget _buildSensorCards(AsyncValue sensorData) {
    return sensorData.when(
      data: (reading) {
        final motionDetected = reading?.motionDetected ?? false;
        final lastMotion = reading?.timestamp ?? DateTime.now();
        final distance = reading?.distance ?? 0.0;
        final proximityStatus = distance < 50 
            ? 'Very Close' 
            : distance < 150 
                ? 'Close' 
                : 'Far';

        return Column(
          children: [
            // Motion Detection Card
            Container(
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
                border: Border.all(
                  color: motionDetected 
                      ? Colors.orange.withOpacity(0.5) 
                      : Colors.white.withOpacity(0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: motionDetected 
                        ? Colors.orange.withOpacity(0.3) 
                        : Colors.black.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: motionDetected 
                          ? Colors.orange.withOpacity(0.2) 
                          : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: LottieMotionIndicator(
                      motionDetected: motionDetected,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          motionDetected ? 'Motion Detected' : 'No Motion',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: motionDetected ? Colors.orange : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Last detected: ${_formatTime(lastMotion)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: motionDetected ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                      boxShadow: motionDetected ? [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ] : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Proximity Sensor Card
            Container(
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
                border: Border.all(
                  color: Colors.cyan.withOpacity(0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyan.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.social_distance_rounded,
                      color: Colors.cyan,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Proximity: $proximityStatus',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Distance: ${distance.toStringAsFixed(0)} cm',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F3A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: LottieLoading.medium(),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F3A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: LottieLoading.medium(),
            ),
          ),
        ],
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 48),
              SizedBox(height: 12),
              Text(
                'Unable to load sensor data',
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: LottieLoading.medium(),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: const Column(
        children: [
          Icon(Icons.error_outline, color: Colors.red, size: 48),
          SizedBox(height: 12),
          Text(
            'Unable to load security status',
            style: TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
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

  Future<void> _handleTriggerAlarm() async {
    setState(() => _alarmTriggerInProgress = true);

    final bleService = ref.read(bluetoothServiceProvider);
    if (!bleService.isConnected) {
      AppNotifications.showSnackBar(
        context,
        message: 'Hub is offline. Alarm notification sent to caregivers.',
        type: AppNotificationType.warning,
      );
      setState(() => _alarmTriggerInProgress = false);
      return;
    }

    final success = await bleService.triggerSecurityAlarm(durationMs: 5000);
    setState(() => _alarmTriggerInProgress = false);

    if (!mounted) return;

    AppNotifications.showSnackBar(
      context,
      message: success
          ? 'Alarm triggered successfully!'
          : 'Failed to trigger alarm.',
      type: success ? AppNotificationType.success : AppNotificationType.error,
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }
}

final bleConnectionProvider = StreamProvider<bool>((ref) {
  final bluetoothService = ref.watch(bluetoothServiceProvider);
  return bluetoothService.connectionStream;
});

