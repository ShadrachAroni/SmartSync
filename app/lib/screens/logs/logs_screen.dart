import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/logging_service.dart';
import '../../services/adaptive_auto_service.dart';
import '../../services/firebase_service.dart';
import '../../models/log_entry.dart';
import '../../core/utils/logger.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../../core/widgets/lottie_error_indicator.dart';

final loggingServiceProvider = Provider((ref) => LoggingService());

final userLogsProvider = StreamProvider<List<LogEntry>>((ref) async* {
  final service = ref.watch(loggingServiceProvider);
  Logger.debug('LogsScreen: Starting to fetch user logs');

  // Emit local logs immediately
  final localLogs = service.getLocalLogs();
  Logger.debug(
      'LogsScreen: Emitting ${localLogs.length} local logs immediately');
  yield localLogs;

  // Then try to get Firestore logs with timeout
  try {
    Logger.debug('LogsScreen: Attempting to get logs from Firestore...');
    yield* service.getUserLogs(limit: 200).timeout(
      const Duration(seconds: 10),
      onTimeout: (sink) {
        Logger.warning(
            'LogsScreen: Timeout fetching logs from Firestore, keeping local logs');
        sink.add(localLogs);
        sink.close();
      },
    ).handleError((error, stackTrace) {
      Logger.error('LogsScreen: Error fetching logs: $error');
      Logger.error('LogsScreen: Stack trace: $stackTrace');
      // Don't rethrow, just return local logs
    });
  } catch (e) {
    Logger.error('LogsScreen: Exception fetching logs: $e');
    // Return local logs on exception
    yield localLogs;
  }
});

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  String? _selectedCategory;
  LogLevel? _selectedLevel;

  @override
  Widget build(BuildContext context) {
    Logger.debug('LogsScreen: Building screen');
    final logsAsync = ref.watch(userLogsProvider);

    Logger.debug('LogsScreen: logsAsync state: ${logsAsync.runtimeType}');
    logsAsync.when(
      data: (logs) => Logger.debug('LogsScreen: Received ${logs.length} logs'),
      loading: () => Logger.debug('LogsScreen: Loading logs...'),
      error: (error, stack) => Logger.error('LogsScreen: Error: $error'),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        title: const Text(
          'Activity Logs',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white70),
            onPressed: _showFilterDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            color: const Color(0xFF1A1F3A),
            onSelected: (value) {
              if (value == 'clear_all') {
                _showClearAllDialog(context, ref);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.white70, size: 20),
                    SizedBox(width: 8),
                    Text('Clear All Logs', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: logsAsync.when(
        data: (logs) {
          Logger.debug('LogsScreen: Displaying ${logs.length} logs');
          if (logs.isEmpty) {
            Logger.debug('LogsScreen: No logs to display');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 80,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No logs yet',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            );
          }

          final filteredLogs = logs.where((log) {
            if (_selectedCategory != null &&
                log.category != _selectedCategory) {
              return false;
            }
            if (_selectedLevel != null && log.level != _selectedLevel) {
              return false;
            }
            return true;
          }).toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(userLogsProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredLogs.length,
              itemBuilder: (context, index) {
                return _LogEntryCard(
                  log: filteredLogs[index],
                  onRevertChange: (changeId, details) {
                    ref.invalidate(userLogsProvider);
                  },
                );
              },
            ),
          );
        },
        loading: () {
          Logger.debug('LogsScreen: Showing loading indicator');
          return const Center(
            child: LottieLoading(
              size: 80,
              message: 'Loading logs...',
              showMessage: true,
            ),
          );
        },
        error: (error, _) {
          Logger.error('LogsScreen: Error state: $error');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const LottieErrorIndicator(size: 80),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Logs',
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      ref.invalidate(userLogsProvider);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        title: const Text(
          'Filter Logs',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                labelStyle: TextStyle(color: Colors.white70),
              ),
              dropdownColor: const Color(0xFF1A1F3A),
              style: const TextStyle(color: Colors.white),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('All Categories')),
                const DropdownMenuItem(
                    value: 'auth', child: Text('Authentication')),
                const DropdownMenuItem(value: 'device', child: Text('Devices')),
                const DropdownMenuItem(value: 'room', child: Text('Rooms')),
                const DropdownMenuItem(
                    value: 'settings', child: Text('Settings')),
                const DropdownMenuItem(
                    value: 'security', child: Text('Security')),
              ],
              onChanged: (value) {
                setState(() => _selectedCategory = value);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<LogLevel?>(
              initialValue: _selectedLevel,
              decoration: const InputDecoration(
                labelText: 'Level',
                labelStyle: TextStyle(color: Colors.white70),
              ),
              dropdownColor: const Color(0xFF1A1F3A),
              style: const TextStyle(color: Colors.white),
              items: [
                const DropdownMenuItem(value: null, child: Text('All Levels')),
                const DropdownMenuItem(
                    value: LogLevel.debug, child: Text('Debug')),
                const DropdownMenuItem(
                    value: LogLevel.info, child: Text('Info')),
                const DropdownMenuItem(
                    value: LogLevel.warning, child: Text('Warning')),
                const DropdownMenuItem(
                    value: LogLevel.error, child: Text('Error')),
              ],
              onChanged: (value) {
                setState(() => _selectedLevel = value);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedCategory = null;
                _selectedLevel = null;
              });
              Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showClearAllDialog(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear All Logs',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to delete all activity logs? This action cannot be undone.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final firebaseService = FirebaseService();
                final deletedCount = await firebaseService.clearAllActivityLogs(user.uid);
                // Also clear local logs
                final loggingService = ref.read(loggingServiceProvider);
                loggingService.clearLocalLogs();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Deleted $deletedCount log(s)'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                ref.invalidate(userLogsProvider);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({
    required this.log,
    required this.onRevertChange,
  });

  final LogEntry log;
  final void Function(String changeId, String details) onRevertChange;

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return Colors.red;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.debug:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'auth':
        return Icons.lock_outline;
      case 'device':
        return Icons.devices;
      case 'room':
        return Icons.meeting_room;
      case 'settings':
        return Icons.settings;
      case 'security':
        return Icons.security;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final levelColor = _getLevelColor(log.level);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
        border: Border.all(color: levelColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: levelColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: levelColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getCategoryIcon(log.category),
                  color: levelColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.action,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: levelColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            log.level.name.toUpperCase(),
                            style: TextStyle(
                              color: levelColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          log.category,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                _formatTime(log.timestamp),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (log.details.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              log.details,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
          // Show revert button for automation changes
          if (log.category == 'automation' &&
              log.metadata['revertable'] == true) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _handleRevertChange(
                context,
                log.metadata['changeId'] as String? ?? '',
                log.details,
                onRevertChange,
              ),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Revert Change'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _handleRevertChange(
    BuildContext context,
    String changeId,
    String details,
    void Function(String, String) onRevertChange,
  ) {
    if (changeId.isEmpty) {
      AppNotifications.showSnackBar(
        context,
        message: 'Cannot revert: Invalid change ID',
        type: AppNotificationType.error,
      );
      return;
    }

    AppNotifications.showDialog(
      context,
      title: 'Revert Automation Change',
      message: 'Do you want to revert this change?\n\n$details',
      type: AppNotificationType.warning,
      primaryLabel: 'Revert',
      onPrimaryPressed: () async {
        final autoService = AdaptiveAutoService();
        final success = await autoService.revertChange(changeId);

        if (success) {
          AppNotifications.showSnackBar(
            context,
            message: 'Change reverted successfully',
            type: AppNotificationType.success,
          );
          // Refresh logs
          onRevertChange(changeId, details);
        } else {
          AppNotifications.showSnackBar(
            context,
            message: 'Failed to revert change',
            type: AppNotificationType.error,
          );
        }
      },
      secondaryLabel: 'Cancel',
      onSecondaryPressed: () async {},
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return DateFormat('MMM dd, HH:mm').format(timestamp);
    }
  }
}
