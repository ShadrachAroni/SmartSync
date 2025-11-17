import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../constants/colors.dart';

enum AppNotificationType { success, error, warning, info }

class AppNotifications {
  static final Map<AppNotificationType, _NotificationStyle> _styles = {
    AppNotificationType.success: _NotificationStyle(
      gradient: const [Color(0xFF34D399), Color(0xFF059669)],
      icon: Icons.check_circle_rounded,
      accent: const Color(0xFF10B981),
      animationAsset: 'assets/animations/success.json',
    ),
    AppNotificationType.error: _NotificationStyle(
      gradient: const [Color(0xFFF87171), Color(0xFFB91C1C)],
      icon: Icons.error_rounded,
      accent: const Color(0xFFEF4444),
      animationAsset: 'assets/animations/error.json',
    ),
    AppNotificationType.warning: _NotificationStyle(
      gradient: const [Color(0xFFFBBF24), Color(0xFFD97706)],
      icon: Icons.warning_amber_rounded,
      accent: const Color(0xFFF59E0B),
      animationAsset: 'assets/animations/loading.json',
    ),
    AppNotificationType.info: _NotificationStyle(
      gradient: const [AppColors.primary, AppColors.primaryDark],
      icon: Icons.info_rounded,
      accent: AppColors.primaryLight,
      animationAsset: 'assets/animations/loading.json',
    ),
  };

  static void showSnackBar(
    BuildContext context, {
    required String message,
    String? title,
    AppNotificationType type = AppNotificationType.info,
    Duration? duration,
  }) {
    final style = _styles[type]!;

    final snackBar = SnackBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: EdgeInsets.zero,
      duration: duration ??
          Duration(
            milliseconds: type == AppNotificationType.error ? 5200 : 3600,
          ),
      content: _NotificationCard(
        title: title,
        message: message,
        style: style,
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  static Future<void> showDialog(
    BuildContext context, {
    required String title,
    required String message,
    AppNotificationType type = AppNotificationType.info,
    String primaryLabel = 'OK',
    Future<void> Function()? onPrimaryPressed,
    String? secondaryLabel,
    Future<void> Function()? onSecondaryPressed,
    bool barrierDismissible = false,
  }) {
    final style = _styles[type]!;

    return showGeneralDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'SmartSyncDialog',
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(animation.value),
          child: Opacity(
            opacity: animation.value,
            child: _AlertCard(
              title: title,
              message: message,
              style: style,
              primaryLabel: primaryLabel,
              onPrimaryPressed: () async {
                Navigator.of(context).pop();
                if (onPrimaryPressed != null) {
                  await onPrimaryPressed();
                }
              },
              secondaryLabel: secondaryLabel,
              onSecondaryPressed: secondaryLabel == null
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      if (onSecondaryPressed != null) {
                        await onSecondaryPressed();
                      }
                    },
            ),
          ),
        );
      },
    );
  }
}

class _NotificationStyle {
  const _NotificationStyle({
    required this.gradient,
    required this.icon,
    required this.accent,
    required this.animationAsset,
  });

  final List<Color> gradient;
  final IconData icon;
  final Color accent;
  final String animationAsset;
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.style,
    required this.message,
    this.title,
  });

  final _NotificationStyle style;
  final String message;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: style.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: style.gradient.last.withOpacity(0.35),
            offset: const Offset(0, 12),
            blurRadius: 22,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              style.icon,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      height: 1.1,
                    ),
                  ),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.title,
    required this.message,
    required this.style,
    required this.primaryLabel,
    required this.onPrimaryPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  final String title;
  final String message;
  final _NotificationStyle style;
  final String primaryLabel;
  final Future<void> Function() onPrimaryPressed;
  final String? secondaryLabel;
  final Future<void> Function()? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                offset: const Offset(0, 25),
                blurRadius: 45,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 110,
                child: Lottie.asset(
                  style.animationAsset,
                  repeat: false,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (secondaryLabel != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onSecondaryPressed == null
                            ? null
                            : () async => onSecondaryPressed!(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: style.gradient.last,
                          side: BorderSide(color: style.gradient.last),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          secondaryLabel!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async => onPrimaryPressed(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: style.gradient.last,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        primaryLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

