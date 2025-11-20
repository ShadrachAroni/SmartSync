import 'package:intl/intl.dart';

/// Utility class for time and day/night detection
class TimeUtils {
  /// Get current time as formatted string
  static String getCurrentTime() {
    return DateFormat('HH:mm:ss').format(DateTime.now());
  }

  /// Get current date and time as formatted string
  static String getCurrentDateTime() {
    return DateFormat('MMM dd, yyyy HH:mm:ss').format(DateTime.now());
  }

  /// Check if current time is night (between 8 PM and 6 AM)
  static bool isNight() {
    final hour = DateTime.now().hour;
    return hour >= 20 || hour < 6;
  }

  /// Check if current time is day (between 6 AM and 8 PM)
  static bool isDay() {
    return !isNight();
  }

  /// Get time of day label (Morning, Afternoon, Evening, Night)
  static String getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Afternoon';
    } else if (hour >= 17 && hour < 20) {
      return 'Evening';
    } else {
      return 'Night';
    }
  }

  /// Get sun/moon icon based on time
  static String getTimeIcon() {
    return isNight() ? '🌙' : '☀️';
  }

  /// Format time for display (12-hour format)
  static String formatTime12Hour(DateTime time) {
    return DateFormat('h:mm a').format(time);
  }

  /// Format time for display (24-hour format)
  static String formatTime24Hour(DateTime time) {
    return DateFormat('HH:mm').format(time);
  }

  /// Get time until next hour
  static Duration getTimeUntilNextHour() {
    final now = DateTime.now();
    final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
    return nextHour.difference(now);
  }

  /// Check if a time is in the past
  static bool isTimeInPast(int hour, int minute) {
    final now = DateTime.now();
    final scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);
    return scheduledTime.isBefore(now);
  }

  /// Get next occurrence of a scheduled time
  static DateTime getNextScheduledTime(int hour, int minute) {
    final now = DateTime.now();
    var scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);
    
    // If time is in the past, schedule for tomorrow
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }
    
    return scheduledTime;
  }
}

