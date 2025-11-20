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
import '../../core/utils/analytics_utils.dart';
import '../../core/utils/logger.dart';

// ==================== PROVIDERS ====================
final mlServiceProvider = Provider((ref) => MLService());
final sensorHistoryProvider =
    FutureProvider.autoDispose.family<List<SensorData>, Map<String, dynamic>>(
  (ref, params) async {
    final firebase = ref.watch(firebaseServiceProvider);
    Logger.debug('AnalyticsScreen: Loading sensor history for ${params['userId']}, days: ${params['days']}');
    try {
      final history = await firebase.getUserSensorHistory(
        params['userId'] as String,
        params['days'] as int,
      ).timeout(
        const Duration(seconds: 10), // Reduced timeout
        onTimeout: () {
          Logger.warning('AnalyticsScreen: Timeout loading sensor history');
          return <SensorData>[];
        },
      );
      Logger.debug('AnalyticsScreen: Sensor history loaded: ${history.length} records');
      return history;
    } catch (e) {
      Logger.error('AnalyticsScreen: Error loading sensor history: $e');
      return <SensorData>[];
    }
  },
);
final dailyAnalyticsProvider =
    FutureProvider.autoDispose.family<List<DailyAnalytics>, Map<String, dynamic>>(
  (ref, params) async {
    final firebase = ref.watch(firebaseServiceProvider);
    Logger.debug('AnalyticsScreen: Loading daily analytics for ${params['userId']}, days: ${params['days']}');
    try {
      final analytics = await firebase.getDailyAnalytics(
        params['userId'] as String,
        params['days'] as int,
      ).timeout(
        const Duration(seconds: 10), // Reduced timeout
        onTimeout: () {
          Logger.warning('AnalyticsScreen: Timeout loading daily analytics');
          return <DailyAnalytics>[];
        },
      );
      Logger.debug('AnalyticsScreen: Daily analytics loaded: ${analytics.length} records');
      return analytics;
    } catch (e) {
      Logger.error('AnalyticsScreen: Error loading daily analytics: $e');
      return <DailyAnalytics>[];
    }
  },
);

final analyticsTimeRangeProvider = StateProvider<int>((ref) => 7); // Days

final analyticsInsightsProvider =
    FutureProvider.autoDispose.family<AnalyticsInsights, Map<String, dynamic>>(
  (ref, params) async {
    final mlService = ref.watch(mlServiceProvider);
    final userId = params['userId'] as String;
    final days = params['days'] as int;
    Logger.debug('AnalyticsScreen: Loading insights for user $userId, days: $days');
    try {
      final insights = await mlService.getInsights(userId, days).timeout(
        const Duration(seconds: 15), // Reduced timeout
        onTimeout: () {
          Logger.warning('AnalyticsScreen: Timeout loading insights, returning default');
          // Return default insights instead of throwing
          return AnalyticsInsights(
            totalLogs: 0,
            avgTemperature: 22.0,
            avgHumidity: 50.0,
            motionEvents: 0,
            energyConsumption: 0.0,
            avgFanUsage: 0.0,
            avgLightUsage: 0.0,
            peakUsageHour: 12,
          );
        },
      );
      Logger.debug('AnalyticsScreen: Insights loaded successfully');
      return insights;
    } catch (e) {
      Logger.error('AnalyticsScreen: Error loading insights: $e');
      // Return default insights on error
      return AnalyticsInsights(
        totalLogs: 0,
        avgTemperature: 22.0,
        avgHumidity: 50.0,
        motionEvents: 0,
        energyConsumption: 0.0,
        avgFanUsage: 0.0,
        avgLightUsage: 0.0,
        peakUsageHour: 12,
      );
    }
  },
);

final schedulePredictionsProvider =
    FutureProvider.autoDispose.family<List<SchedulePrediction>, Map<String, String>>(
  (ref, params) async {
    final mlService = ref.watch(mlServiceProvider);
    Logger.debug('AnalyticsScreen: Loading schedule predictions for ${params['userId']}');
    try {
      final predictions = await mlService.predictSchedules(
          params['userId']!, params['deviceId'] ?? 'all').timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.warning('AnalyticsScreen: Timeout loading schedule predictions');
          return <SchedulePrediction>[];
        },
      );
      Logger.debug('AnalyticsScreen: Schedule predictions loaded: ${predictions.length} predictions');
      return predictions;
    } catch (e) {
      Logger.error('AnalyticsScreen: Error loading schedule predictions: $e');
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

    // Initialize ML Service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mlServiceProvider).initialize();
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
      Logger.warning('AnalyticsScreen: User is null');
      return const Scaffold(
        body: Center(child: Text('Please login to view analytics')),
      );
    }
    
    Logger.debug('AnalyticsScreen: Building for user ${user.uid}');

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverAppBar(user.uid),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(user.uid),
            _buildInsightsTab(user.uid),
            _buildPredictionsTab(user.uid),
          ],
        ),
      );
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
                        child: const Icon(
                          Icons.analytics_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Analytics',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
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
  Widget _buildOverviewTab(String userId) {
    Logger.debug('AnalyticsScreen: Building overview tab for user $userId');
    final timeRange = ref.watch(analyticsTimeRangeProvider);
    Logger.debug('AnalyticsScreen: Time range: $timeRange days');
    
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
    
    Logger.debug('AnalyticsScreen: insightsAsync state: ${insightsAsync.runtimeType}');
    Logger.debug('AnalyticsScreen: historyAsync state: ${historyAsync.runtimeType}');
    Logger.debug('AnalyticsScreen: dailyAnalyticsAsync state: ${dailyAnalyticsAsync.runtimeType}');

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
      },
      child: insightsAsync.when(
        data: (insights) {
          Logger.debug('AnalyticsScreen: Insights loaded successfully');
          return dailyAnalyticsAsync.when(
            data: (dailyData) {
              Logger.debug('AnalyticsScreen: Daily analytics loaded: ${dailyData.length} entries');
              return historyAsync.when(
                data: (history) {
                  Logger.debug('AnalyticsScreen: History loaded: ${history.length} entries');
                  final trendData = dailyData.isNotEmpty
                      ? _mapDailyAnalytics(dailyData)
                      : buildDailyTrends(history, timeRange);
                  final hourlyActivity = buildHourlyActivity(history);

              return Container(
                color: const Color(0xFF0A0E27),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCards(insights),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Environmental Trends'),
                      const SizedBox(height: 16),
                      _buildEnvironmentalChart(trendData),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Usage Patterns'),
                      const SizedBox(height: 16),
                      _buildUsageChart(hourlyActivity, insights.peakUsageHour),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Energy Breakdown'),
                      const SizedBox(height: 16),
                      _buildEnergyBreakdown(insights),
                    ],
                  ),
                ),
              );
                },
                loading: () {
                  Logger.debug('AnalyticsScreen: History loading...');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading sensor history...',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                },
                error: (error, stackTrace) {
                  Logger.error('AnalyticsScreen: History error: $error');
                  Logger.error('AnalyticsScreen: History stack trace: $stackTrace');
                  return _buildErrorState(
                    error.toString(),
                    onRetry: () {
                      Logger.debug('AnalyticsScreen: Retrying history load');
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
              Logger.debug('AnalyticsScreen: Daily analytics loading...');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading daily analytics...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              );
            },
            error: (error, stackTrace) {
              Logger.error('AnalyticsScreen: Daily analytics error: $error');
              Logger.error('AnalyticsScreen: Daily analytics stack trace: $stackTrace');
              return _buildErrorState(
                error.toString(),
                onRetry: () {
                  Logger.debug('AnalyticsScreen: Retrying daily analytics load');
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
          Logger.debug('AnalyticsScreen: Insights loading...');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading insights...',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  'This may take a few seconds',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          );
        },
        error: (error, stackTrace) {
          Logger.error('AnalyticsScreen: Insights error: $error');
          Logger.error('AnalyticsScreen: Stack trace: $stackTrace');
          return _buildErrorState(
            error.toString(),
            onRetry: () {
              Logger.debug('AnalyticsScreen: Retrying insights load');
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

  Widget _buildSummaryCards(AnalyticsInsights insights) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.thermostat_rounded,
                label: 'Avg Temperature',
                value: '${insights.avgTemperature.toStringAsFixed(1)}°C',
                color: const Color(0xFFFF6B6B),
                trend: _getTemperatureTrend(insights.avgTemperature),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.water_drop_rounded,
                label: 'Avg Humidity',
                value: '${insights.avgHumidity.toStringAsFixed(0)}%',
                color: const Color(0xFF4ECDC4),
                trend: _getHumidityTrend(insights.avgHumidity),
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
                value: insights.motionEvents.toString(),
                color: const Color(0xFFFFE66D),
                subtitle: 'Daily average',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.flash_on_rounded,
                label: 'Energy Used',
                value: '${insights.energyConsumption.toStringAsFixed(1)} kWh',
                color: const Color(0xFFA8E6CF),
                subtitle: 'This period',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
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

  Widget _buildEnvironmentalChart(List<DailyTrendPoint> trendData) {
    if (trendData.isEmpty) {
      return _buildNoDataCard(
        'We need at least one day of sensor logs to chart trends.',
      );
    }

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
          title: AxisTitle(text: 'Temperature (°C)', textStyle: TextStyle(color: Colors.white)),
          minimum: 15,
          maximum: 35,
          majorGridLines: const MajorGridLines(width: 1, color: Colors.white24, dashArray: [5, 5]),
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
  }

  Widget _buildUsageChart(
      List<HourlyActivityPoint> activityData, int peakUsageHour) {
    final hasActivity =
        activityData.any((point) => point.activityValue > 0.0);

    if (!hasActivity) {
      return _buildNoDataCard(
        'No motion activity was captured for this time range.',
      );
    }

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
                majorGridLines: const MajorGridLines(width: 0, color: Colors.white24),
                labelStyle: const TextStyle(color: Colors.white70),
              ),
              primaryYAxis: NumericAxis(
                title: AxisTitle(text: 'Activity Level', textStyle: TextStyle(color: Colors.white)),
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
  }

  Widget _buildEnergyBreakdown(AnalyticsInsights insights) {
    final totalUsage = insights.avgFanUsage + insights.avgLightUsage;
    final fanPercent =
        totalUsage > 0 ? (insights.avgFanUsage / totalUsage) : 0.5;
    final lightPercent =
        totalUsage > 0 ? (insights.avgLightUsage / totalUsage) : 0.5;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
          Divider(color: Colors.grey.shade200),
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

  Widget _buildUsageBar(
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

  Widget _buildNoDataCard(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insights_rounded,
              size: 36, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          Text(
            'Not enough data yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  List<DailyTrendPoint> _mapDailyAnalytics(List<DailyAnalytics> analytics) {
    return analytics
        .map(
          (entry) => DailyTrendPoint(
            label: DateFormat('MMM dd').format(entry.date),
            temperature: entry.avgTemperature,
            humidity: entry.avgHumidity,
          ),
        )
        .toList();
  }


  // ==================== INSIGHTS TAB ====================
  Widget _buildInsightsTab(String userId) {
    Logger.debug('AnalyticsScreen: Building insights tab for user $userId');
    final timeRange = ref.watch(analyticsTimeRangeProvider);
    final insightsAsync = ref.watch(analyticsInsightsProvider({
      'userId': userId,
      'days': timeRange,
    }));

    return insightsAsync.when(
      data: (insights) {
        Logger.debug('AnalyticsScreen: Insights data loaded');
        return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInsightCard(
              icon: Icons.lightbulb_rounded,
              title: 'Energy Saving Tip',
              description:
                  'Your fan usage is ${_getFanUsageLevel(insights.avgFanUsage)}. '
                  'Consider reducing speed by 20% during off-peak hours to save energy.',
              color: const Color(0xFFFFA726),
              actionLabel: 'Optimize',
              onTap: () {},
            ),
            const SizedBox(height: 16),
            _buildInsightCard(
              icon: Icons.thermostat_rounded,
              title: 'Temperature Pattern',
              description: 'Temperature peaks at ${insights.peakUsageHour}:00. '
                  'Schedule cooling to start 30 minutes earlier for optimal comfort.',
              color: const Color(0xFFFF6B6B),
              actionLabel: 'Create Schedule',
              onTap: () {},
            ),
            const SizedBox(height: 16),
            _buildInsightCard(
              icon: Icons.emoji_events_rounded,
              title: 'Efficiency Score',
              description:
                  'Your home is ${_getEfficiencyScore(insights)}% more efficient '
                  'than similar households. Great job!',
              color: const Color(0xFF66BB6A),
              actionLabel: 'View Details',
              onTap: () {},
            ),
            const SizedBox(height: 16),
            _buildInsightCard(
              icon: Icons.timeline_rounded,
              title: 'Usage Trend',
              description:
                  'Motion activity has ${_getMotionTrend(insights.motionEvents)} '
                  'compared to last week. Monitor for health changes.',
              color: const Color(0xFF7C4DFF),
              actionLabel: 'View History',
              onTap: () {},
            ),
          ],
        ),
      ),
      loading: () {
        Logger.debug('AnalyticsScreen: Insights tab loading...');
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading insights...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        );
      },
      error: (error, stackTrace) {
        Logger.error('AnalyticsScreen: Insights tab error: $error');
        Logger.error('AnalyticsScreen: Insights tab stack trace: $stackTrace');
        return _buildErrorState(
          error.toString(),
          onRetry: () {
            Logger.debug('AnalyticsScreen: Retrying insights tab load');
            ref.invalidate(analyticsInsightsProvider({
              'userId': userId,
              'days': timeRange,
            }));
          },
        );
      },
    );
  }

  Widget _buildInsightCard({
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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

  // ==================== PREDICTIONS TAB ====================
  Widget _buildPredictionsTab(String userId) {
    final predictionsAsync = ref.watch(schedulePredictionsProvider({
      'userId': userId,
      'deviceId': 'all',
    }));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(schedulePredictionsProvider);
      },
      child: predictionsAsync.when(
        data: (predictions) {
          if (predictions.isEmpty) {
            return _buildEmptyPredictions();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: predictions.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildPredictionCard(predictions[index]),
              );
            },
          );
        },
        loading: () {
          Logger.debug('AnalyticsScreen: Predictions loading...');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
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
          Logger.error('AnalyticsScreen: Predictions stack trace: $stackTrace');
          return _buildErrorState(
            error.toString(),
            onRetry: () {
              Logger.debug('AnalyticsScreen: Retrying predictions load');
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

  Widget _buildPredictionCard(SchedulePrediction prediction) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      prediction.deviceType == 'fan'
                          ? 'Fan Speed'
                          : 'Brightness',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${prediction.value}%',
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
              color: Colors.grey.shade700,
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
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      'Confidence: ${prediction.confidence.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _showCreateScheduleDialog(prediction),
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

  Widget _buildEmptyPredictions() {
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
              child: Icon(
                Icons.calendar_today_rounded,
                size: 64,
                color: const Color(0xFF00BFA5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Not Enough Data',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'We need at least 30 days of usage data\nto generate accurate predictions',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Keep using SmartSync to unlock predictions',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade900,
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

  // ==================== HELPER METHODS ====================
  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildErrorState(String error, {VoidCallback? onRetry}) {
    Logger.error('AnalyticsScreen: Displaying error state: $error');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
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
              onPressed: onRetry ?? () {
                Logger.debug('AnalyticsScreen: Retry button pressed');
                // Default retry - invalidate all analytics providers
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

  String _getTemperatureTrend(double temp) {
    if (temp > 24) return '+2.5°C';
    if (temp < 20) return '-1.8°C';
    return '+0.5°C';
  }

  String _getHumidityTrend(double humidity) {
    if (humidity > 60) return '+5%';
    if (humidity < 40) return '-3%';
    return '+1%';
  }

  String _getFanUsageLevel(double usage) {
    final percent = (usage / 255 * 100);
    if (percent > 70) return 'high';
    if (percent > 40) return 'moderate';
    return 'low';
  }

  int _getEfficiencyScore(AnalyticsInsights insights) {
    // Simple efficiency calculation
    final avgUsage = (insights.avgFanUsage + insights.avgLightUsage) / 2;
    final efficiency = ((255 - avgUsage) / 255 * 100).round();
    return efficiency.clamp(0, 100);
  }

  String _getMotionTrend(int events) {
    if (events > 100) return 'increased by 15%';
    if (events < 50) return 'decreased by 12%';
    return 'remained stable';
  }

  String _timeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showCreateScheduleDialog(SchedulePrediction prediction) {
    AppNotifications.showDialog(
      context,
      title: 'Create Schedule',
      message:
          'AI suggests scheduling ${prediction.deviceType} to ${prediction.value}% every ${prediction.dayName} at ${prediction.timeString}.'
          '\nDevice: ${prediction.deviceName ?? 'Select device on next step'}',
      type: AppNotificationType.info,
      primaryLabel: 'Create',
      onPrimaryPressed: () => _handlePredictionCreate(prediction),
      secondaryLabel: 'Cancel',
      onSecondaryPressed: () async {},
    );
  }

  Future<void> _handlePredictionCreate(
      SchedulePrediction prediction) async {
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
          ? _firstDeviceWhere(devices, (d) => d.id == prediction.deviceId)
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
            : await _promptDeviceSelection(matched);

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

      if (!mounted) return;
      AppNotifications.showSnackBar(
        context,
        message:
            'Schedule added for ${targetDevice.name}. Enable it from the schedules tab.',
        type: AppNotificationType.success,
      );
    } catch (e) {
      AppNotifications.showSnackBar(
        context,
        message: 'Failed to create schedule: $e',
        type: AppNotificationType.error,
      );
    }
  }

  Future<DeviceModel?> _promptDeviceSelection(
      List<DeviceModel> devices) async {
    return showModalBottomSheet<DeviceModel>(
      context: context,
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
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Device',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: Icon(device.icon, color: Colors.teal),
                        title: Text(device.name),
                        subtitle: Text(
                          device.roomId.isEmpty
                              ? 'Unassigned room'
                              : 'Room: ${device.roomId}',
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

  DeviceModel? _firstDeviceWhere(
      List<DeviceModel> devices, bool Function(DeviceModel) test) {
    for (final device in devices) {
      if (test(device)) return device;
    }
    return null;
  }
}

