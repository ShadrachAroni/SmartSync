import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/constants/routes.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../../services/logging_service.dart';
import '../../services/test_data_generator.dart';
import '../../services/debug_service.dart';
import '../../services/ml_service.dart';
import '../../models/log_entry.dart';
import '../../screens/analytics/analytics_screen.dart';
import 'notifications_settings.dart';
import 'privacy_settings.dart';
import 'about_screen.dart';
import 'caregiver_screen.dart';
import 'hub_management_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final user = ref.watch(authStateProvider).value;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSectionHeader('Account'),
          _buildNavTile(
            context,
            icon: Icons.lock_reset_outlined,
            title: 'Reset Password',
            subtitle: 'Send password reset email',
            onTap: () => _showResetPasswordDialog(context, ref),
          ),
          const SizedBox(height: 12),
          _buildNavTile(
            context,
            icon: Icons.lock_outline,
            title: 'Change Password',
            subtitle: 'Update your current password',
            onTap: () => _showChangePasswordDialog(context, ref),
          ),
          const SizedBox(height: 12),
          _buildNavTile(
            context,
            icon: Icons.description_outlined,
            title: 'Activity Logs',
            subtitle: 'View all app actions and events',
            onTap: () => Navigator.pushNamed(context, Routes.logs),
          ),
          const SizedBox(height: 12),
          _buildNavTile(
            context,
            icon: Icons.delete_forever_outlined,
            title: 'Delete Account',
            subtitle: 'Permanently remove your SmartSync data',
            onTap: () => _showDeleteAccountDialog(context, ref),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Notifications'),
          _buildSwitchTile(
            icon: Icons.notifications_outlined,
            title: 'Push Notifications',
            subtitle: 'Critical alerts and reminders',
            value: settings.notificationsEnabled,
            onChanged: user == null
                ? null
                : (value) => ref
                    .read(settingsControllerProvider.notifier)
                    .toggleNotifications(user.uid, value),
          ),
          const SizedBox(height: 12),
          _buildSwitchTile(
            icon: Icons.family_restroom,
            title: 'Caregiver Alerts',
            subtitle: 'Share emergencies with caregivers',
            value: settings.caregiverAlerts,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .toggleCaregiverAlerts(value),
          ),
          const SizedBox(height: 12),
          _buildNavTile(
            context,
            icon: Icons.people_outlined,
            title: 'Manage Caregivers',
            subtitle: 'Add and manage your caregivers',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CaregiverScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _buildNavTile(
            context,
            icon: Icons.notifications_active_outlined,
            title: 'Notification Preferences',
            subtitle: 'Customize alert types',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen()),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Hubs & Rooms'),
          _buildNavTile(
            context,
            icon: Icons.router_outlined,
            title: 'Hub Management',
            subtitle: 'Manage hubs, assign to rooms, set primary hub',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const HubManagementScreen()),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Automation'),
          _buildSwitchTile(
            icon: Icons.auto_awesome,
            title: 'Adaptive Auto Mode',
            subtitle: 'Let AI adjust fan and lights',
            value: settings.autoMode,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .setAutoMode(value),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Legal'),
          _buildNavTile(
            context,
            icon: Icons.lock_outline,
            title: 'Privacy & Security',
            subtitle: 'Policies and permissions',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _buildNavTile(
            context,
            icon: Icons.info_outline,
            title: 'About SmartSync',
            subtitle: 'Version, licenses, feedback',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Developer'),
          _buildNavTile(
            context,
            icon: Icons.science_outlined,
            title: 'Generate Test Data',
            subtitle: 'Create sample sensor data for testing',
            onTap: () => _showGenerateTestDataDialog(context, ref),
          ),
          const SizedBox(height: 12),
          _buildNavTile(
            context,
            icon: Icons.delete_sweep_outlined,
            title: 'Reset Test Data',
            subtitle: 'Delete all generated test data',
            onTap: () => _showResetTestDataDialog(context, ref),
          ),
          const SizedBox(height: 12),
          _buildNavTile(
            context,
            icon: Icons.bug_report_outlined,
            title: 'Debug Sensor Data',
            subtitle: 'Diagnose why data might not be appearing',
            onTap: () => _showDebugDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showGenerateTestDataDialog(BuildContext context, WidgetRef ref) {
    final timeUnitController = TextEditingController(text: '7');
    bool useDays = true;
    bool isLoading = false;
    bool generateForAllDevices = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1F3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Generate Test Data',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLoading)
                  const Text(
                    'Generating test sensor data... This may take a moment.',
                    style: TextStyle(color: Colors.white70),
                  )
                else ...[
                  const Text(
                    'Generate realistic sensor data for testing analytics and ML features.',
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Flexible(
                        flex: 2,
                        child: TextField(
                          controller: timeUnitController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Amount',
                            labelStyle: const TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                          ),
                          child: ToggleButtons(
                            isSelected: [useDays, !useDays],
                            onPressed: (index) {
                              setState(() => useDays = index == 0);
                            },
                            borderRadius: BorderRadius.circular(12),
                            selectedColor: Colors.white,
                            color: Colors.white70,
                            fillColor: Colors.blue.withOpacity(0.3),
                            constraints: const BoxConstraints(
                              minHeight: 48,
                              minWidth: 0,
                            ),
                            children: const [
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text('Days', style: TextStyle(fontSize: 13)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text('Hours', style: TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    useDays
                        ? 'Recommended: 7-30 days for better ML predictions and analytics'
                        : 'Minimum: 24 hours for predictions | Recommended: 168 hours (7 days)',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: generateForAllDevices,
                        onChanged: (value) {
                          setState(() => generateForAllDevices = value ?? false);
                        },
                        activeColor: Colors.blue,
                      ),
                      Expanded(
                        child: Text(
                          'Generate for all devices',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (generateForAllDevices)
                    Padding(
                      padding: const EdgeInsets.only(left: 40, top: 4),
                      child: Text(
                        'Creates data for each device in your account',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      timeUnitController.dispose();
                      Navigator.pop(context);
                    },
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final value = int.tryParse(timeUnitController.text.trim());
                      if (value == null || value <= 0) {
                        AppNotifications.showSnackBar(
                          context,
                          message: 'Please enter a valid number greater than 0',
                          type: AppNotificationType.warning,
                        );
                        return;
                      }

                      if (useDays && value > 365) {
                        AppNotifications.showSnackBar(
                          context,
                          message: 'Maximum 365 days allowed',
                          type: AppNotificationType.warning,
                        );
                        return;
                      }

                      if (!useDays && value > 8760) {
                        AppNotifications.showSnackBar(
                          context,
                          message: 'Maximum 8760 hours (365 days) allowed',
                          type: AppNotificationType.warning,
                        );
                        return;
                      }

                      setState(() => isLoading = true);
                      try {
                        final generator = TestDataGenerator();
                        if (useDays) {
                          await generator.generateTestData(
                            days: value,
                            generateForAllDevices: generateForAllDevices,
                          );
                        } else {
                          await generator.generateTestData(
                            hours: value,
                            generateForAllDevices: generateForAllDevices,
                          );
                        }
                        
                        // Wait a moment for Firestore to propagate the new data
                        await Future.delayed(const Duration(seconds: 2));
                        
                        // Invalidate analytics providers to refresh the UI
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          // Invalidate all analytics providers
                          // StreamProviders should auto-update, but this forces a refresh
                          ref.invalidate(sensorHistoryProvider);
                          ref.invalidate(dailyAnalyticsProvider);
                          ref.invalidate(analyticsInsightsProvider);
                          ref.invalidate(previousPeriodInsightsProvider);
                          ref.invalidate(schedulePredictionsProvider);
                        }
                        MLService().clearPredictionCache();
                        
                        if (context.mounted) {
                          timeUnitController.dispose();
                          Navigator.pop(context);
                          AppNotifications.showSnackBar(
                            context,
                            message: '✅ Test data generated successfully! Analytics will update shortly.',
                            type: AppNotificationType.success,
                          );
                        }
                      } catch (e) {
                        setState(() => isLoading = false);
                        if (context.mounted) {
                          AppNotifications.showSnackBar(
                            context,
                            message: 'Failed to generate test data: ${e.toString()}',
                            type: AppNotificationType.error,
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: LottieLoading.small(),
                    )
                  : const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetTestDataDialog(BuildContext context, WidgetRef ref) {
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1F3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Reset Test Data',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            isLoading
                ? 'Deleting all test sensor data... This may take a moment.'
                : 'This will permanently delete ALL generated test sensor data. This action cannot be undone. Continue?',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      setState(() => isLoading = true);
                      try {
                        final generator = TestDataGenerator();
                        final deletedCount = await generator.clearTestData();
                        
                        // Wait a moment for Firestore to propagate the deletion
                        await Future.delayed(const Duration(seconds: 1));
                        
                        // Invalidate analytics providers to refresh the UI
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          ref.invalidate(sensorHistoryProvider);
                          ref.invalidate(dailyAnalyticsProvider);
                          ref.invalidate(analyticsInsightsProvider);
                          ref.invalidate(previousPeriodInsightsProvider);
                          ref.invalidate(schedulePredictionsProvider);
                        }
                        MLService().clearPredictionCache();
                        
                        if (context.mounted) {
                          Navigator.pop(context);
                          AppNotifications.showSnackBar(
                            context,
                            message: deletedCount > 0
                                ? '✅ Deleted $deletedCount test data entries. Analytics will update shortly.'
                                : 'ℹ️ No test data found to delete.',
                            type: deletedCount > 0
                                ? AppNotificationType.success
                                : AppNotificationType.info,
                          );
                        }
                      } catch (e) {
                        setState(() => isLoading = false);
                        if (context.mounted) {
                          AppNotifications.showSnackBar(
                            context,
                            message: 'Failed to delete test data: ${e.toString()}',
                            type: AppNotificationType.error,
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: LottieLoading.small(),
                    )
                  : const Text('Delete All'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildNavTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.blue, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
        trailing:
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white70),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.blue, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
        trailing: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.blue,
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    final rootContext = context;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      AppNotifications.showSnackBar(
        rootContext,
        message: 'Please log in again to manage your account.',
        type: AppNotificationType.error,
      );
      return;
    }

    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscurePassword = true;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1F3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Delete Account',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This action permanently deletes your SmartSync account, automation profiles, and history. This cannot be undone.',
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Confirm your password',
                    labelStyle: const TextStyle(color: Colors.white70),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() => obscurePassword = !obscurePassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmController,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Type DELETE to confirm',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      passwordController.dispose();
                      confirmController.dispose();
                      Navigator.pop(dialogContext);
                    },
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (confirmController.text.trim().toUpperCase() !=
                          'DELETE') {
                        AppNotifications.showSnackBar(
                          rootContext,
                          message:
                              'Please type DELETE to confirm account removal.',
                          type: AppNotificationType.warning,
                        );
                        return;
                      }

                      if (passwordController.text.isEmpty) {
                        AppNotifications.showSnackBar(
                          rootContext,
                          message:
                              'Password is required to delete your account.',
                          type: AppNotificationType.error,
                        );
                        return;
                      }

                      setState(() => isLoading = true);

                      try {
                        await ref.read(authServiceProvider).deleteAccount(
                              passwordController.text.trim(),
                            );

                        if (!dialogContext.mounted) return;
                        passwordController.dispose();
                        confirmController.dispose();
                        Navigator.pop(dialogContext);

                        if (!rootContext.mounted) return;
                        AppNotifications.showSnackBar(
                          rootContext,
                          message: 'Account deleted successfully.',
                          type: AppNotificationType.success,
                        );
                        Navigator.of(rootContext, rootNavigator: true)
                            .pushNamedAndRemoveUntil(
                          Routes.login,
                          (route) => false,
                        );
                      } on FirebaseAuthException catch (e) {
                        setState(() => isLoading = false);
                        AppNotifications.showSnackBar(
                          rootContext,
                          message: e.message ?? 'Failed to delete account.',
                          type: AppNotificationType.error,
                        );
                      } catch (_) {
                        setState(() => isLoading = false);
                        AppNotifications.showSnackBar(
                          rootContext,
                          message: 'Unexpected error. Please try again.',
                          type: AppNotificationType.error,
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: isLoading
                  ? const LottieLoading.small()
                  : const Text('Delete Account'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetPasswordDialog(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) {
      AppNotifications.showSnackBar(
        context,
        message: 'No email address found. Please log in again.',
        type: AppNotificationType.error,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Reset Password',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'A password reset email will be sent to:\n${user!.email}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseAuth.instance
                    .sendPasswordResetEmail(
                  email: user.email!,
                )
                    .timeout(
                  const Duration(seconds: 10),
                  onTimeout: () {
                    throw Exception(
                        'Request timed out. Please check your connection.');
                  },
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  AppNotifications.showSnackBar(
                    context,
                    message: 'Password reset email sent! Check your inbox.',
                    type: AppNotificationType.success,
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  AppNotifications.showSnackBar(
                    context,
                    message:
                        'Failed to send reset email: ${e.toString().replaceAll('Exception: ', '')}',
                    type: AppNotificationType.error,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: const Text('Send Email'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      AppNotifications.showSnackBar(
        context,
        message: 'Please log in to change your password.',
        type: AppNotificationType.error,
      );
      return;
    }

    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureOldPassword = true;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1F3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Change Password',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldPasswordController,
                  obscureText: obscureOldPassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    labelStyle: const TextStyle(color: Colors.white70),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureOldPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(
                            () => obscureOldPassword = !obscureOldPassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPasswordController,
                  obscureText: obscureNewPassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    labelStyle: const TextStyle(color: Colors.white70),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureNewPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(
                            () => obscureNewPassword = !obscureNewPassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirmPassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    labelStyle: const TextStyle(color: Colors.white70),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() =>
                            obscureConfirmPassword = !obscureConfirmPassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      oldPasswordController.dispose();
                      newPasswordController.dispose();
                      confirmPasswordController.dispose();
                      Navigator.pop(context);
                    },
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (newPasswordController.text.length < 6) {
                        AppNotifications.showSnackBar(
                          context,
                          message: 'New password must be at least 6 characters',
                          type: AppNotificationType.error,
                        );
                        return;
                      }

                      if (newPasswordController.text !=
                          confirmPasswordController.text) {
                        AppNotifications.showSnackBar(
                          context,
                          message: 'New passwords do not match',
                          type: AppNotificationType.error,
                        );
                        return;
                      }

                      setState(() => isLoading = true);

                      try {
                        // Re-authenticate user
                        final credential = EmailAuthProvider.credential(
                          email: user.email!,
                          password: oldPasswordController.text,
                        );
                        await user
                            .reauthenticateWithCredential(credential)
                            .timeout(
                              const Duration(seconds: 10),
                            );

                        // Update password
                        await user
                            .updatePassword(newPasswordController.text)
                            .timeout(
                              const Duration(seconds: 10),
                            );

                        // Log password change
                        final loggingService = LoggingService();
                        await loggingService.logAction(
                          action: 'Password changed',
                          category: 'auth',
                          details: 'User successfully changed their password',
                          level: LogLevel.info,
                        );

                        if (context.mounted) {
                          oldPasswordController.dispose();
                          newPasswordController.dispose();
                          confirmPasswordController.dispose();
                          Navigator.pop(context);
                          AppNotifications.showSnackBar(
                            context,
                            message: 'Password changed successfully!',
                            type: AppNotificationType.success,
                          );
                        }
                      } catch (e) {
                        setState(() => isLoading = false);
                        if (context.mounted) {
                          String errorMessage = 'Failed to change password';
                          if (e.toString().contains('wrong-password')) {
                            errorMessage = 'Current password is incorrect';
                          } else if (e.toString().contains('weak-password')) {
                            errorMessage = 'New password is too weak';
                          } else if (e.toString().contains('timeout')) {
                            errorMessage =
                                'Request timed out. Please check your connection.';
                          }
                          AppNotifications.showSnackBar(
                            context,
                            message: errorMessage,
                            type: AppNotificationType.error,
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: LottieLoading.small(),
                    )
                  : const Text('Change Password'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDebugDialog(BuildContext context, WidgetRef ref) {
    bool isLoading = false;
    String? debugResults;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1F3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Debug Sensor Data',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              'Running diagnostics...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (debugResults != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: SelectableText(
                        debugResults!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'This report shows why sensor data might not be appearing in analytics.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ]
                  else
                    const Text(
                      'Click "Run Diagnostics" to check why sensor data might not be appearing.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      Navigator.pop(context);
                    },
              child: const Text('Close', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      setState(() {
                        isLoading = true;
                        debugResults = null;
                      });

                      try {
                        final debugService = DebugService();
                        final results = await debugService.debugSensorData();
                        final formatted = debugService.formatDebugResults(results);

                        if (context.mounted) {
                          setState(() {
                            isLoading = false;
                            debugResults = formatted;
                          });
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setState(() {
                            isLoading = false;
                            debugResults = 'Error running diagnostics: $e';
                          });
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Run Diagnostics'),
            ),
          ],
        ),
      ),
    );
  }
}
