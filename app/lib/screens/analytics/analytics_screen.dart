// app/lib/screens/analytics/enhanced_analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../../services/ml_service.dart';
import '../../services/firebase_service.dart';
import '../../models/ml_prediction.dart';
import '../../models/sensor_data.dart';
import '../../models/daily_analytics.dart';
import '../../models/device_model.dart';
import '../../models/schedule_model.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_error_indicator.dart';
import 'package:lottie/lottie.dart';
import '../../core/utils/analytics_utils.dart';
import '../../core/utils/logger.dart';
import '../../core/widgets/error_boundary.dart';

// ==================== PROVIDERS ====================
final mlServiceProvider = Provider((ref) => MLService());
final sensorHistoryProvider =
    FutureProvider.autoDispose.family<List<SensorData>, Map<String, dynamic>>(
  (ref, params) async {
    final userId = params['userId'] as String;
    final days = params['days'] as int;
    
    Logger.info('📊 sensorHistoryProvider: Starting load for user $userId, $days days');
    final stopwatch = Stopwatch()..start();
    
    try {
      final firebase = ref.watch(firebaseServiceProvider);
      Logger.info('📊 sensorHistoryProvider: Firebase service obtained');
      
      final history = await firebase
          .getUserSensorHistory(userId, days)
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.warning('📊 sensorHistoryProvider: Timeout after 10s');
          return <SensorData>[];
        },
      );
      
      stopwatch.stop();
      Logger.success('📊 sensorHistoryProvider: Loaded ${history.length} records in ${stopwatch.elapsedMilliseconds}ms');
      return history;
    } catch (e, stackTrace) {
      stopwatch.stop();
      Logger.error(
        '📊 sensorHistoryProvider: Error loading sensor history (took ${stopwatch.elapsedMilliseconds}ms)',
        e,
        stackTrace,
      );
      return <SensorData>[];
    }
  },
);

final dailyAnalyticsProvider = FutureProvider.autoDispose
    .family<List<DailyAnalytics>, Map<String, dynamic>>(
  (ref, params) async {
    final userId = params['userId'] as String;
    final days = params['days'] as int;
    
    Logger.info('📊 dailyAnalyticsProvider: Starting load for user $userId, $days days');
    final stopwatch = Stopwatch()..start();
    
    try {
      final firebase = ref.watch(firebaseServiceProvider);
      Logger.info('📊 dailyAnalyticsProvider: Firebase service obtained');
      
      final analytics = await firebase
          .getDailyAnalytics(userId, days)
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.warning('📊 dailyAnalyticsProvider: Timeout after 10s');
          return <DailyAnalytics>[];
        },
      );
      
      stopwatch.stop();
      Logger.success('📊 dailyAnalyticsProvider: Loaded ${analytics.length} records in ${stopwatch.elapsedMilliseconds}ms');
      return analytics;
    } catch (e, stackTrace) {
      stopwatch.stop();
      Logger.error(
        '📊 dailyAnalyticsProvider: Error loading daily analytics (took ${stopwatch.elapsedMilliseconds}ms)',
        e,
        stackTrace,
      );
      return <DailyAnalytics>[];
    }
  },
);

final analyticsTimeRangeProvider = StateProvider<int>((ref) => 7); // Days

final analyticsInsightsProvider =
    FutureProvider.autoDispose.family<AnalyticsInsights, Map<String, dynamic>>(
  (ref, params) async {
    final userId = params['userId'] as String;
    final days = params['days'] as int;
    
    Logger.info('📊 analyticsInsightsProvider: Starting load for user $userId, $days days');
    final stopwatch = Stopwatch()..start();
    
    try {
      final mlService = ref.watch(mlServiceProvider);
      Logger.info('📊 analyticsInsightsProvider: ML service obtained');
      
      final insights = await mlService.getInsights(userId, days).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          Logger.warning('📊 analyticsInsightsProvider: Timeout after 15s');
          return AnalyticsInsights(
            totalLogs: 0,
            avgTemperature: 0.0,
            avgHumidity: 0.0,
            motionEvents: 0,
            energyConsumption: 0.0,
            avgFanUsage: 0.0,
            avgLightUsage: 0.0,
            peakUsageHour: 0,
          );
        },
      );
      
      stopwatch.stop();
      Logger.success('📊 analyticsInsightsProvider: Loaded insights (${insights.totalLogs} logs) in ${stopwatch.elapsedMilliseconds}ms');
      return insights;
    } catch (e, stackTrace) {
      stopwatch.stop();
      Logger.error(
        '📊 analyticsInsightsProvider: Error loading insights (took ${stopwatch.elapsedMilliseconds}ms)',
        e,
        stackTrace,
      );
      return AnalyticsInsights(
        totalLogs: 0,
        avgTemperature: 0.0,
        avgHumidity: 0.0,
        motionEvents: 0,
        energyConsumption: 0.0,
        avgFanUsage: 0.0,
        avgLightUsage: 0.0,
        peakUsageHour: 0,
      );
    }
  },
);

final schedulePredictionsProvider = FutureProvider.autoDispose
    .family<List<SchedulePrediction>, Map<String, String>>(
  (ref, params) async {
    final userId = params['userId']!;
    final deviceId = params['deviceId'] ?? 'all';
    
    Logger.info('📊 schedulePredictionsProvider: Starting load for user $userId, device $deviceId');
    final stopwatch = Stopwatch()..start();
    
    final mlService = ref.watch(mlServiceProvider);

    // Ensure ML Service is initialized before making predictions
    try {
      Logger.info('📊 schedulePredictionsProvider: Initializing ML service...');
      await mlService.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          Logger.warning('📊 schedulePredictionsProvider: ML service init timeout');
        },
      );
      Logger.info('📊 schedulePredictionsProvider: ML service initialized');
    } catch (e, stackTrace) {
      Logger.warning('📊 schedulePredictionsProvider: ML Service initialization failed: $e');
      Logger.error('📊 schedulePredictionsProvider: Init error details', e, stackTrace);
    }

    try {
      Logger.info('📊 schedulePredictionsProvider: Calling predictSchedules...');
      final predictions = await mlService
          .predictSchedules(userId, deviceId)
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          Logger.warning('📊 schedulePredictionsProvider: predictSchedules timeout after 15s');
          return <SchedulePrediction>[];
        },
      );
      
      stopwatch.stop();
      Logger.success('📊 schedulePredictionsProvider: Loaded ${predictions.length} predictions in ${stopwatch.elapsedMilliseconds}ms');
      return predictions;
    } catch (e, stackTrace) {
      stopwatch.stop();
      Logger.error(
        '📊 schedulePredictionsProvider: Error loading schedule predictions (took ${stopwatch.elapsedMilliseconds}ms)',
        e,
        stackTrace,
      );
      return <SchedulePrediction>[];
    }
  },
);

// ==================== ANALYTICS SCREEN ====================
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Initialize ML Service early (don't await to avoid blocking UI)
    // This ensures models are loaded before predictions are requested
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(mlServiceProvider).initialize().catchError((e) {
          Logger.error('Failed to initialize ML Service: $e');
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view analytics')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverAppBar(user.uid),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            ErrorBoundary(
              context: 'OverviewTab',
              child: _OverviewTab(userId: user.uid),
            ),
            ErrorBoundary(
              context: 'InsightsTab',
              child: _InsightsTab(userId: user.uid, tabController: _tabController),
            ),
            ErrorBoundary(
              context: 'PredictionsTab',
              child: _PredictionsTab(userId: user.uid),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== APP BAR ====================
  Widget _buildSliverAppBar(String userId) {
    final timeRange = ref.watch(analyticsTimeRangeProvider);

    return SliverAppBar(
      expandedHeight: 140,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF00BFA5),
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
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Lottie.asset(
                            'assets/animations/data-analysis.json',
                            fit: BoxFit.contain,
                            repeat: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Analytics',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'AI-Powered Insights',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<int>(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.date_range_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        itemBuilder: (context) => [
                          _buildTimeRangeItem('Last 7 Days', 7, timeRange),
                          _buildTimeRangeItem('Last 14 Days', 14, timeRange),
                          _buildTimeRangeItem('Last 30 Days', 30, timeRange),
                          _buildTimeRangeItem('Last 90 Days', 90, timeRange),
                        ],
                        onSelected: (days) {
                          ref.read(analyticsTimeRangeProvider.notifier).state =
                              days;
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottom: TabBar(
        controller: _tabController,
        labelColor: Colors.blue,
        unselectedLabelColor: Colors.white60,
        indicatorColor: Colors.blue,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Insights'),
          Tab(text: 'Predictions'),
        ],
      ),
    );
  }

  PopupMenuItem<int> _buildTimeRangeItem(
      String label, int days, int currentDays) {
    return PopupMenuItem<int>(
      value: days,
      child: Row(
        children: [
          Icon(
            days == currentDays
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: days == currentDays ? const Color(0xFF00BFA5) : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  // ==================== OVERVIEW TAB ====================
  // Moved to _OverviewTab widget class below
}

// ==================== TAB WIDGETS (Isolated to prevent rebuild loops) ====================

class _OverviewTab extends ConsumerWidget {
  final String userId;

  const _OverviewTab({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeRange = ref.watch(analyticsTimeRangeProvider);

    final insightsAsync = ref.watch(analyticsInsightsProvider({
      'userId': userId,
      'days': timeRange,
    }));
    final historyAsync = ref.watch(sensorHistoryProvider({
      'userId': userId,
      'days': timeRange,
    }));
    final dailyAnalyticsAsync = ref.watch(dailyAnalyticsProvider({
      'userId': userId,
      'days': timeRange,
    }));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(analyticsInsightsProvider({
          'userId': userId,
          'days': timeRange,
        }));
        ref.invalidate(sensorHistoryProvider({
          'userId': userId,
          'days': timeRange,
        }));
        ref.invalidate(dailyAnalyticsProvider({
          'userId': userId,
          'days': timeRange,
        }));
      },
      child: insightsAsync.when(
        data: (insights) {
          if (insights.totalLogs == 0) {
            return _AnalyticsTabHelpers.buildEmptyState(
                'No sensor data available yet. Start using your devices to see analytics.');
          }
          return dailyAnalyticsAsync.when(
            data: (dailyData) {
              return historyAsync.when(
                data: (history) {
                  Logger.info('📊 OverviewTab: Processing ${history.length} history records');
                  final trendData = Logger.safeExecute(
                    'mapDailyAnalytics/buildDailyTrends',
                    () => dailyData.isNotEmpty
                        ? _AnalyticsTabHelpers.mapDailyAnalytics(dailyData)
                        : buildDailyTrends(history, timeRange),
                    defaultValue: <DailyTrendPoint>[],
                  )!;
                  
                  final hourlyActivity = Logger.safeExecute(
                    'buildHourlyActivity',
                    () => buildHourlyActivity(history),
                    defaultValue: <HourlyActivityPoint>[],
                  )!;
                  
                  Logger.info('📊 OverviewTab: Processed ${trendData.length} trend points, ${hourlyActivity.length} hourly points');

                  return Container(
                    color: const Color(0xFF0A0E27),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AnalyticsTabHelpers.buildSummaryCards(insights),
                          const SizedBox(height: 24),
                          _AnalyticsTabHelpers.buildSectionHeader(
                              'Environmental Trends'),
                          const SizedBox(height: 16),
                          _AnalyticsTabHelpers.buildEnvironmentalChart(
                              trendData),
                          const SizedBox(height: 24),
                          _AnalyticsTabHelpers.buildSectionHeader(
                              'Usage Patterns'),
                          const SizedBox(height: 16),
                          _AnalyticsTabHelpers.buildUsageChart(
                              hourlyActivity, insights.peakUsageHour),
                          const SizedBox(height: 24),
                          _AnalyticsTabHelpers.buildSectionHeader(
                              'Energy Breakdown'),
                          const SizedBox(height: 16),
                          _AnalyticsTabHelpers.buildEnergyBreakdown(insights),
                        ],
                      ),
                    ),
                  );
                },
                loading: () {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: Lottie.asset(
                            'assets/animations/data-analysis.json',
                            fit: BoxFit.contain,
                            repeat: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Loading sensor history...',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                },
                error: (error, stackTrace) {
                  Logger.error('AnalyticsScreen: History error: $error');
                  return _AnalyticsTabHelpers.buildErrorState(
                    ref,
                    error.toString(),
                    onRetry: () {
                      ref.invalidate(sensorHistoryProvider({
                        'userId': userId,
                        'days': timeRange,
                      }));
                    },
                  );
                },
              );
            },
            loading: () {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: Lottie.asset(
                        'assets/animations/data-analysis.json',
                        fit: BoxFit.contain,
                        repeat: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Loading daily analytics...',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              );
            },
            error: (error, stackTrace) {
              Logger.error('AnalyticsScreen: Daily analytics error: $error');
              return _AnalyticsTabHelpers.buildErrorState(
                ref,
                error.toString(),
                onRetry: () {
                  ref.invalidate(dailyAnalyticsProvider({
                    'userId': userId,
                    'days': timeRange,
                  }));
                },
              );
            },
          );
        },
        loading: () {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Lottie.asset(
                    'assets/animations/data-analysis.json',
                    fit: BoxFit.contain,
                    repeat: true,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Loading insights...\nThis may take a few seconds',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          );
        },
        error: (error, stackTrace) {
          Logger.error('AnalyticsScreen: Insights error: $error');
          return _AnalyticsTabHelpers.buildErrorState(
            ref,
            error.toString(),
            onRetry: () {
              ref.invalidate(analyticsInsightsProvider({
                'userId': userId,
                'days': timeRange,
              }));
            },
          );
        },
      ),
    );
  }
}

// ==================== TAB WIDGETS (Isolated to prevent rebuild loops) ====================

class _InsightsTab extends ConsumerWidget {
  final String userId;
  final TabController tabController;

  const _InsightsTab({
    required this.userId,
    required this.tabController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeRange = ref.watch(analyticsTimeRangeProvider);
    final insightsAsync = ref.watch(analyticsInsightsProvider({
      'userId': userId,
      'days': timeRange,
    }));

    return insightsAsync.when(
      data: (insights) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AnalyticsTabHelpers.buildInsightCard(
                icon: Icons.lightbulb_rounded,
                title: 'Energy Saving Tip',
                description: insights.totalLogs > 0
                    ? 'Your fan usage is ${_AnalyticsTabHelpers.getFanUsageLevel(insights.avgFanUsage)}. '
                        'Check ML predictions to optimize schedules and save energy.'
                    : 'Start using your devices to get personalized energy-saving recommendations.',
                color: const Color(0xFFFFA726),
                actionLabel: 'View Predictions',
                onTap: () => tabController.animateTo(2),
              ),
              const SizedBox(height: 16),
              _AnalyticsTabHelpers.buildInsightCard(
                icon: Icons.thermostat_rounded,
                title: 'Temperature Pattern',
                description: insights.peakUsageHour > 0
                    ? 'Temperature peaks at ${insights.peakUsageHour}:00. '
                        'Schedule cooling to start 30 minutes earlier for optimal comfort.'
                    : 'Temperature data shows consistent patterns. '
                        'Use ML predictions to optimize your schedule.',
                color: const Color(0xFFFF6B6B),
                actionLabel: 'View Predictions',
                onTap: () => tabController.animateTo(2),
              ),
              const SizedBox(height: 16),
              _AnalyticsTabHelpers.buildInsightCard(
                icon: Icons.emoji_events_rounded,
                title: 'Efficiency Score',
                description:
                    'Your home is ${_AnalyticsTabHelpers.getEfficiencyScore(insights)}% more efficient '
                    'than similar households. Great job!',
                color: const Color(0xFF66BB6A),
                actionLabel: 'View Details',
                onTap: () {},
              ),
              const SizedBox(height: 16),
              _AnalyticsTabHelpers.buildInsightCard(
                icon: Icons.timeline_rounded,
                title: 'Usage Trend',
                description:
                    'Motion activity has ${_AnalyticsTabHelpers.getMotionTrend(insights.motionEvents)} '
                    'compared to last week. Monitor for health changes.',
                color: const Color(0xFF7C4DFF),
                actionLabel: 'View History',
                onTap: () {},
              ),
            ],
          ),
        );
      },
      loading: () {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: Lottie.asset(
                  'assets/animations/data-analysis.json',
                  fit: BoxFit.contain,
                  repeat: true,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Loading insights...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        );
      },
      error: (error, stackTrace) {
        Logger.error('AnalyticsScreen: Insights tab error: $error');
        return _AnalyticsTabHelpers.buildErrorState(
          ref,
          error.toString(),
          onRetry: () {
            ref.invalidate(analyticsInsightsProvider({
              'userId': userId,
              'days': timeRange,
            }));
          },
        );
      },
    );
  }
}

class _PredictionsTab extends ConsumerWidget {
  final String userId;

  const _PredictionsTab({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predictionsAsync = ref.watch(schedulePredictionsProvider({
      'userId': userId,
      'deviceId': 'all',
    }));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(schedulePredictionsProvider({
          'userId': userId,
          'deviceId': 'all',
        }));
      },
      child: predictionsAsync.when(
        data: (predictions) {
          if (predictions.isEmpty) {
            return _AnalyticsTabHelpers.buildEmptyPredictions();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: predictions.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _AnalyticsTabHelpers.buildPredictionCard(
                  context,
                  ref,
                  predictions[index],
                ),
              );
            },
          );
        },
        loading: () {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: Lottie.asset(
                    'assets/animations/data-analysis.json',
                    fit: BoxFit.contain,
                    repeat: true,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading predictions...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        },
        error: (error, stackTrace) {
          Logger.error('AnalyticsScreen: Predictions error: $error');
          return _AnalyticsTabHelpers.buildErrorState(
            ref,
            error.toString(),
            onRetry: () {
              ref.invalidate(schedulePredictionsProvider({
                'userId': userId,
                'deviceId': 'all',
              }));
            },
          );
        },
      ),
    );
  }
}

// ==================== HELPER CLASS FOR TAB WIDGETS ====================
class _AnalyticsTabHelpers {
  static List<DailyTrendPoint> mapDailyAnalytics(
      List<DailyAnalytics> analytics) {
    return Logger.safeExecute(
      'mapDailyAnalytics',
      () {
        if (analytics.isEmpty) {
          Logger.info('mapDailyAnalytics: Empty analytics, returning empty list');
          return <DailyTrendPoint>[];
        }
        
        return analytics
            .map(
              (entry) {
                try {
                  return DailyTrendPoint(
                    label: DateFormat('MMM dd').format(entry.date),
                    temperature: entry.avgTemperature,
                    humidity: entry.avgHumidity,
                  );
                } catch (e, stackTrace) {
                  Logger.error('mapDailyAnalytics: Error processing entry', e, stackTrace);
                  return DailyTrendPoint(
                    label: DateFormat('MMM dd').format(entry.date),
                    temperature: 0.0,
                    humidity: 0.0,
                  );
                }
              },
            )
            .toList();
      },
      defaultValue: <DailyTrendPoint>[],
    )!;
  }

  static String getFanUsageLevel(double usage) {
    final percent = (usage / 255 * 100);
    if (percent > 70) return 'high';
    if (percent > 40) return 'moderate';
    return 'low';
  }

  static int getEfficiencyScore(AnalyticsInsights insights) {
    final avgUsage = (insights.avgFanUsage + insights.avgLightUsage) / 2;
    final efficiency = ((255 - avgUsage) / 255 * 100).round();
    return efficiency.clamp(0, 100);
  }

  static String getMotionTrend(int events) {
    if (events > 100) return 'increased by 15%';
    if (events < 50) return 'decreased by 12%';
    return 'remained stable';
  }

  static Widget buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: Lottie.asset(
                'assets/animations/settings-warning-error.json',
                fit: BoxFit.contain,
                repeat: true,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Data Available',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildErrorState(WidgetRef ref, String error,
      {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const LottieErrorIndicator(size: 80),
            const SizedBox(height: 16),
            const Text(
              'Error Loading Analytics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.length > 100 ? '${error.substring(0, 100)}...' : error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry ??
                  () {
                    ref.invalidate(analyticsInsightsProvider);
                    ref.invalidate(sensorHistoryProvider);
                    ref.invalidate(dailyAnalyticsProvider);
                    ref.invalidate(schedulePredictionsProvider);
                  },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFA5),
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  static Widget buildSummaryCards(AnalyticsInsights insights) {
    final hasData = insights.totalLogs > 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.thermostat_rounded,
                label: 'Avg Temperature',
                value: hasData && insights.avgTemperature > 0
                    ? '${insights.avgTemperature.toStringAsFixed(1)}°C'
                    : 'N/A',
                color: const Color(0xFFFF6B6B),
                trend: hasData && insights.avgTemperature > 0
                    ? _getTemperatureTrend(insights.avgTemperature)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.water_drop_rounded,
                label: 'Avg Humidity',
                value: hasData && insights.avgHumidity > 0
                    ? '${insights.avgHumidity.toStringAsFixed(0)}%'
                    : 'N/A',
                color: const Color(0xFF4ECDC4),
                trend: hasData && insights.avgHumidity > 0
                    ? _getHumidityTrend(insights.avgHumidity)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.directions_walk_rounded,
                label: 'Motion Events',
                value: hasData ? insights.motionEvents.toString() : 'N/A',
                color: const Color(0xFFFFE66D),
                subtitle: 'Daily average',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.flash_on_rounded,
                label: 'Energy Used',
                value: hasData && insights.energyConsumption > 0
                    ? '${insights.energyConsumption.toStringAsFixed(1)} kWh'
                    : 'N/A',
                color: const Color(0xFFA8E6CF),
                subtitle: 'This period',
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? trend,
    String? subtitle,
  }) {
    return Container(
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
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
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
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              if (trend != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: trend.startsWith('+')
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    trend,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: trend.startsWith('+')
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _getTemperatureTrend(double temp) {
    if (temp > 24) return '+2.5°C';
    if (temp < 20) return '-1.8°C';
    return '+0.5°C';
  }

  static String _getHumidityTrend(double humidity) {
    if (humidity > 60) return '+5%';
    if (humidity < 40) return '-3%';
    return '+1%';
  }

  static Widget _buildNoDataCard(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insights_rounded,
              size: 36, color: Colors.white.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(
            'Not enough data yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildUsageBar(
      String label, double percentage, Color color, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 12,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  static Widget buildEnvironmentalChart(List<DailyTrendPoint> trendData) {
    return Logger.safeExecute(
      'buildEnvironmentalChart',
      () {
        if (trendData.isEmpty) {
          Logger.info('buildEnvironmentalChart: Empty trend data');
          return _buildNoDataCard(
            'We need at least one day of sensor logs to chart trends.',
          );
        }

        Logger.info('buildEnvironmentalChart: Building chart with ${trendData.length} points');
        return Container(
      height: 280,
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
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SfCartesianChart(
        title: ChartTitle(
          text: 'Temperature Trends',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        legend: Legend(
          isVisible: true,
          position: LegendPosition.bottom,
        ),
        primaryXAxis: CategoryAxis(
          majorGridLines: const MajorGridLines(width: 0, color: Colors.white24),
          labelStyle: const TextStyle(color: Colors.white70),
        ),
        primaryYAxis: NumericAxis(
          title: AxisTitle(
              text: 'Temperature (°C)',
              textStyle: TextStyle(color: Colors.white)),
          minimum: 15,
          maximum: 35,
          majorGridLines: const MajorGridLines(
              width: 1, color: Colors.white24, dashArray: [5, 5]),
          labelStyle: const TextStyle(color: Colors.white70),
        ),
        series: <CartesianSeries>[
          LineSeries<DailyTrendPoint, String>(
            name: 'Temperature',
            dataSource: trendData,
            xValueMapper: (data, _) => data.label,
            yValueMapper: (data, _) => data.temperature,
            color: const Color(0xFFFF6B6B),
            width: 3,
            markerSettings: const MarkerSettings(isVisible: true),
          ),
        ],
        tooltipBehavior: TooltipBehavior(enable: true),
      ),
    );
      },
      defaultValue: _buildNoDataCard('Error building chart. Please try again.'),
    )!;
  }

  static Widget buildUsageChart(
      List<HourlyActivityPoint> activityData, int peakUsageHour) {
    return Logger.safeExecute(
      'buildUsageChart',
      () {
        final hasActivity = activityData.any((point) => point.activityValue > 0.0);

        if (!hasActivity) {
          Logger.info('buildUsageChart: No activity data');
          return _buildNoDataCard(
            'No motion activity was captured for this time range.',
          );
        }

        Logger.info('buildUsageChart: Building chart with ${activityData.length} points');
        return Container(
      height: 250,
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
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Peak Activity Hour',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${peakUsageHour.toString().padLeft(2, '0')}:00',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(
                majorGridLines:
                    const MajorGridLines(width: 0, color: Colors.white24),
                labelStyle: const TextStyle(color: Colors.white70),
              ),
              primaryYAxis: NumericAxis(
                title: AxisTitle(
                    text: 'Activity Level',
                    textStyle: TextStyle(color: Colors.white)),
                majorGridLines: const MajorGridLines(
                  width: 1,
                  dashArray: [5, 5],
                  color: Colors.white24,
                ),
                labelStyle: const TextStyle(color: Colors.white70),
              ),
              series: <CartesianSeries>[
                ColumnSeries<HourlyActivityPoint, String>(
                  dataSource: activityData,
                  xValueMapper: (data, _) => data.hourLabel,
                  yValueMapper: (data, _) => data.activityValue,
                  color: Colors.blue,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
      },
      defaultValue: _buildNoDataCard('Error building usage chart. Please try again.'),
    )!;
  }

  static Widget buildEnergyBreakdown(AnalyticsInsights insights) {
    final totalUsage = insights.avgFanUsage + insights.avgLightUsage;
    final fanPercent =
        totalUsage > 0 ? (insights.avgFanUsage / totalUsage) : 0.5;
    final lightPercent =
        totalUsage > 0 ? (insights.avgLightUsage / totalUsage) : 0.5;

    return Container(
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildUsageBar(
            'Fan Usage',
            fanPercent,
            const Color(0xFF4ECDC4),
            '${(insights.avgFanUsage / 255 * 100).toStringAsFixed(0)}%',
          ),
          const SizedBox(height: 20),
          _buildUsageBar(
            'Light Usage',
            lightPercent,
            const Color(0xFFFFE66D),
            '${(insights.avgLightUsage / 255 * 100).toStringAsFixed(0)}%',
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Energy',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Text(
                '${insights.energyConsumption.toStringAsFixed(2)} kWh',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget buildInsightCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Container(
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
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
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget buildPredictionCard(
      BuildContext context, WidgetRef ref, SchedulePrediction prediction) {
    return Container(
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BFA5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  prediction.deviceType == 'fan'
                      ? Icons.air_rounded
                      : Icons.lightbulb_rounded,
                  color: const Color(0xFF00BFA5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${prediction.dayName} at ${prediction.timeString}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      prediction.deviceType == 'fan'
                          ? 'Fan Speed'
                          : 'Brightness',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${((prediction.value / 255) * 100).round()}%',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00BFA5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            prediction.reason,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.analytics_rounded,
                        size: 16, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      'Confidence: ${prediction.confidence.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () =>
                    _showCreateScheduleDialog(context, ref, prediction),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BFA5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  elevation: 0,
                ),
                child: const Text('Create Schedule'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget buildEmptyPredictions() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: const Color(0xFF00BFA5).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_today_rounded,
                size: 64,
                color: Color(0xFF00BFA5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Not Enough Data',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'We need at least 30 days of usage data\nto generate accurate predictions',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade300, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Keep using SmartSync to unlock predictions',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade300,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showCreateScheduleDialog(
      BuildContext context, WidgetRef ref, SchedulePrediction prediction) {
    AppNotifications.showDialog(
      context,
      title: 'Create Schedule',
      message:
          'AI suggests scheduling ${prediction.deviceType} to ${((prediction.value / 255) * 100).round()}% every ${prediction.dayName} at ${prediction.timeString}.'
          '\nDevice: ${prediction.deviceName ?? 'Select device on next step'}',
      type: AppNotificationType.info,
      primaryLabel: 'Create',
      onPrimaryPressed: () => _handlePredictionCreate(context, ref, prediction),
      secondaryLabel: 'Cancel',
      onSecondaryPressed: () async {},
    );
  }

  static Future<void> _handlePredictionCreate(BuildContext context,
      WidgetRef ref, SchedulePrediction prediction) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppNotifications.showSnackBar(
        context,
        message: 'Please login to manage schedules.',
        type: AppNotificationType.warning,
      );
      return;
    }

    try {
      final firebase = ref.read(firebaseServiceProvider);
      final devices = await firebase.fetchUserDevices(user.uid);

      if (devices.isEmpty) {
        AppNotifications.showSnackBar(
          context,
          message: 'No devices found. Add a device to accept AI schedules.',
          type: AppNotificationType.error,
        );
        return;
      }

      DeviceModel? targetDevice = prediction.deviceId != null
          ? devices.firstWhere(
              (d) => d.id == prediction.deviceId,
              orElse: () => devices.first,
            )
          : null;

      if (targetDevice == null) {
        final matched = devices
            .where((device) => device.type.name == prediction.deviceType)
            .toList();

        if (matched.isEmpty) {
          AppNotifications.showSnackBar(
            context,
            message:
                'No ${prediction.deviceType} devices found. Add one to accept AI schedules.',
            type: AppNotificationType.error,
          );
          return;
        }

        targetDevice = matched.length == 1
            ? matched.first
            : await _promptDeviceSelection(context, matched);

        if (targetDevice == null) {
          return;
        }
      }

      final schedule = ScheduleModel(
        id: '',
        userId: user.uid,
        deviceId: targetDevice.id,
        roomId: targetDevice.roomId,
        hour: prediction.hour,
        minute: prediction.minute,
        fanSpeed: prediction.deviceType == 'fan' ? prediction.value : 0,
        brightness: prediction.deviceType == 'light' ? prediction.value : 0,
        enabled: false,
        repeatDaily: true,
        daysOfWeek: [prediction.dayOfWeek],
        source: 'ai',
        createdAt: DateTime.now(),
      );

      await firebase.addSchedule(user.uid, schedule);

      if (context.mounted) {
        AppNotifications.showSnackBar(
          context,
          message:
              'Schedule added for ${targetDevice.name}. Enable it from the schedules tab.',
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      AppNotifications.showSnackBar(
        context,
        message: 'Failed to create schedule: $e',
        type: AppNotificationType.error,
      );
    }
  }

  static Future<DeviceModel?> _promptDeviceSelection(
      BuildContext context, List<DeviceModel> devices) async {
    return showModalBottomSheet<DeviceModel>(
      context: context,
      backgroundColor: const Color(0xFF1A1F3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Device',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1, color: Colors.white.withOpacity(0.1)),
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: Icon(device.icon, color: Colors.teal),
                        title: Text(device.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          device.roomId.isEmpty
                              ? 'Unassigned room'
                              : 'Room: ${device.roomId}',
                          style: TextStyle(color: Colors.white70),
                        ),
                        onTap: () => Navigator.of(context).pop(device),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
