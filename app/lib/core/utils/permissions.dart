import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/storage_service.dart';
import '../widgets/app_notifications.dart';

typedef MountedCallback = bool Function();

/// Coordinates runtime permission prompts for the app.
class PermissionCoordinator {
  PermissionCoordinator._();

  static final PermissionCoordinator _instance = PermissionCoordinator._();
  factory PermissionCoordinator() => _instance;

  final StorageService _storage = StorageService();

  static const _firstRunKey = 'permissions.first_run_complete';
  static const _notificationConfiguredKey =
      'permissions.notification_configured';
  static const _locationConfiguredKey = 'permissions.location_configured';
  static const _notificationPrefKeys = [
    'health',
    'motion',
    'battery',
    'firmware',
  ];

  bool get _supportsRuntimePermissions =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Ensures notification + location permissions are requested in a controlled flow.
  Future<void> ensureInitialPermissionsFlow({
    required BuildContext context,
    required MountedCallback isMounted,
  }) async {
    if (!_supportsRuntimePermissions) {
      return;
    }

    await _storage.initialize();
    final firstRunComplete =
        _storage.getBool(_firstRunKey, defaultValue: false);

    if (!firstRunComplete) {
      await _enforceSafeDefaults();

      await _showPrimer(
        context,
        isMounted,
        title: 'Enable Notifications',
        message:
            'SmartSync sends caregiver alerts, device changes, and safety notices. '
            'You can turn notifications on later, but enabling them now keeps you informed.',
      );
      final notifGranted =
          await _requestNotificationPermission(context, isMounted);
      await _storage.saveBool(_notificationConfiguredKey, notifGranted);

      await _showPrimer(
        context,
        isMounted,
        title: 'Allow Location Access',
        message:
            'Location access helps SmartSync discover nearby hubs via Bluetooth '
            'and improves weather insights. We never store your location.',
      );
      final locationGranted =
          await _requestLocationPermission(context, isMounted);
      await _storage.saveBool(_locationConfiguredKey, locationGranted);

      await _storage.saveBool(_firstRunKey, true);
    } else {
      await _recheckLocationPermission(context, isMounted);
    }
  }

  Future<void> _recheckLocationPermission(
    BuildContext context,
    MountedCallback isMounted,
  ) async {
    final hasPermission = await _isLocationGranted();
    if (hasPermission) {
      await _storage.saveBool(_locationConfiguredKey, true);
      return;
    }

    if (!isMounted()) return;

    AppNotifications.showSnackBar(
      context,
      title: 'Location Needed',
      message: 'SmartSync needs location access to scan for nearby devices.',
      type: AppNotificationType.warning,
    );

    await _requestLocationPermission(
      context,
      isMounted,
      remindOnly: true,
    );
  }

  Future<void> _enforceSafeDefaults() async {
    await _storage.saveBool('settings.notifications', false);
    await _storage.saveBool('settings.caregiver', false);
    await _storage.saveBool('settings.auto_mode', false);

    for (final key in _notificationPrefKeys) {
      await _storage.saveBool('notifications.$key', false);
    }
  }

  Future<void> _showPrimer(
    BuildContext context,
    MountedCallback isMounted, {
    required String title,
    required String message,
  }) async {
    if (!isMounted()) return;

    await AppNotifications.showDialog(
      context,
      title: title,
      message: message,
      type: AppNotificationType.info,
      primaryLabel: 'Continue',
      barrierDismissible: false,
    );
  }

  Future<bool> _requestNotificationPermission(
    BuildContext context,
    MountedCallback isMounted,
  ) async {
    var status = await Permission.notification.status;

    if (status.isGranted || status.isLimited) {
      if (isMounted()) {
        AppNotifications.showSnackBar(
          context,
          message: 'Notifications are enabled.',
          type: AppNotificationType.success,
        );
      }
      return true;
    }

    status = await Permission.notification.request();

    if (status.isGranted || status.isLimited) {
      if (isMounted()) {
        AppNotifications.showSnackBar(
          context,
          message: 'Notifications enabled successfully.',
          type: AppNotificationType.success,
        );
      }
      return true;
    }

    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(
        context,
        isMounted,
        title: 'Notifications Disabled',
        message:
            'Please enable notifications in system settings to receive safety alerts.',
      );
    } else if (isMounted()) {
      AppNotifications.showSnackBar(
        context,
        message:
            'Notifications remain disabled. You can turn them on in Settings later.',
        type: AppNotificationType.warning,
      );
    }

    return false;
  }

  Future<bool> _requestLocationPermission(
    BuildContext context,
    MountedCallback isMounted, {
    bool remindOnly = false,
  }) async {
    var status = await Permission.location.status;

    if (status.isGranted || status.isLimited) {
      if (isMounted() && !remindOnly) {
        AppNotifications.showSnackBar(
          context,
          message: 'Location access is already enabled.',
          type: AppNotificationType.success,
        );
      }
      return true;
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      await _showSettingsDialog(
        context,
        isMounted,
        title: 'Location Disabled',
        message:
            'SmartSync cannot discover nearby devices without location access. '
            'Enable it from system settings.',
      );
      return false;
    }

    status = await Permission.location.request();

    if (status.isGranted || status.isLimited) {
      if (isMounted()) {
        AppNotifications.showSnackBar(
          context,
          message: 'Location permission granted.',
          type: AppNotificationType.success,
        );
      }
      return true;
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      await _showSettingsDialog(
        context,
        isMounted,
        title: 'Location Required',
        message:
            'Please enable location access in settings so SmartSync can connect to your devices.',
      );
    } else if (!remindOnly && isMounted()) {
      AppNotifications.showSnackBar(
        context,
        message:
            'Location access was denied. Some features will stay disabled.',
        type: AppNotificationType.warning,
      );
    }

    return false;
  }

  Future<void> _showSettingsDialog(
    BuildContext context,
    MountedCallback isMounted, {
    required String title,
    required String message,
  }) async {
    if (!isMounted()) return;

    await AppNotifications.showDialog(
      context,
      title: title,
      message: message,
      type: AppNotificationType.warning,
      primaryLabel: 'Open Settings',
      onPrimaryPressed: () async {
        await openAppSettings();
      },
      secondaryLabel: 'Not now',
    );
  }

  Future<bool> _isLocationGranted() async {
    final status = await Permission.location.status;
    return status.isGranted || status.isLimited;
  }
}
