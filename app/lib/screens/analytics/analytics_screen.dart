// app/lib/screens/analytics/enhanced_analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../../services/ml_service.dart';
import '../../services/firebase_service.dart';

// ==================== PROVIDERS ====================
final mlServiceProvider = Provider((ref) => MLService());
final firebaseServiceProvider = Provider((ref) => FirebaseService());

final analyticsTimeRangeProvider = StateProvider<int>((ref) => 7); // Days

final analyticsInsightsProvider =
    FutureProvider.family<AnalyticsInsights, Map<String, dynamic>>(
  (ref, params) async {
    final mlService = ref.watch(mlServiceProvider);
    final userId = params['userId'] as String;
    final days = params['days'] as int;
    return await mlService.getInsights(userId, days);
  },
);

final schedulePredictionsProvider =
    FutureProvider.family<List<SchedulePrediction>, Map<String, String>>(
  (ref, params) async {
    final mlService = ref.watch(mlServiceProvider);
    return await mlService.predictSchedules(
        params['userId']!, params['deviceId'] ?? 'all');
  },
);

final anomalyReportProvider = FutureProvider.family<AnomalyReport?, String>(
  (ref, userId) async {
    final mlService = ref.watch(mlServiceProvider);
    return await mlService.detectAnomalies(userId, const Duration(hours: 24));
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
    _tabController = TabController(length: 4, vsync: this);

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
      return const Scaffold(
        body: Center(child: Text('Please login to view analytics')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
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
            _buildAnomaliesTab(user.uid),
          ],
        ),
      ),
    );
  }

  // ==================== APP BAR ====================
  Widget _buildSliverAppBar(String userId) {
    final timeRange = ref.watch(analyticsTimeRangeProvider);

    return SliverAppBar(
      expandedHeight: 180,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF00BFA5),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF00BFA5),
                const Color(0xFF00897B),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
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
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Insights'),
          Tab(text: 'Predictions'),
          Tab(text: 'Anomalies'),
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
    final timeRange = ref.watch(analyticsTimeRangeProvider);
    final insightsAsync = ref.watch(analyticsInsightsProvider({
      'userId': userId,
      'days': timeRange,
    }));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(analyticsInsightsProvider);
      },
      child: insightsAsync.when(
        data: (insights) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Cards
              _buildSummaryCards(insights),
              const SizedBox(height: 24),

              // Environmental Trends
              _buildSectionHeader('Environmental Trends'),
              const SizedBox(height: 16),
              _buildEnvironmentalChart(insights, userId, timeRange),
              const SizedBox(height: 24),

              // Usage Patterns
              _buildSectionHeader('Usage Patterns'),
              const SizedBox(height: 16),
              _buildUsageChart(insights),
              const SizedBox(height: 24),

              // Energy Breakdown
              _buildSectionHeader('Energy Breakdown'),
              const SizedBox(height: 16),
              _buildEnergyBreakdown(insights),
            ],
          ),
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
          ),
        ),
        error: (error, _) => _buildErrorState(error.toString()),
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
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
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

  Widget _buildEnvironmentalChart(
      AnalyticsInsights insights, String userId, int days) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(16),
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
      child: SfCartesianChart(
        title: ChartTitle(
          text: 'Temperature & Humidity Trends',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        legend: Legend(
          isVisible: true,
          position: LegendPosition.bottom,
        ),
        primaryXAxis: CategoryAxis(
          majorGridLines: const MajorGridLines(width: 0),
        ),
        primaryYAxis: NumericAxis(
          title: AxisTitle(text: 'Temperature (°C)'),
          minimum: 15,
          maximum: 35,
        ),
        axes: <ChartAxis>[
          NumericAxis(
            name: 'yAxis',
            opposedPosition: true,
            title: AxisTitle(text: 'Humidity (%)'),
            minimum: 0,
            maximum: 100,
          ),
        ],
        series: <CartesianSeries>[
          LineSeries<Map<String, dynamic>, String>(
            name: 'Temperature',
            dataSource: _generateTrendData(days),
            xValueMapper: (data, _) => data['day'],
            yValueMapper: (data, _) => data['temp'],
            color: const Color(0xFFFF6B6B),
            width: 3,
            markerSettings: const MarkerSettings(isVisible: true),
          ),
          LineSeries<Map<String, dynamic>, String>(
            name: 'Humidity',
            dataSource: _generateTrendData(days),
            xValueMapper: (data, _) => data['day'],
            yValueMapper: (data, _) => data['humidity'],
            yAxisName: 'yAxis',
            color: const Color(0xFF4ECDC4),
            width: 3,
            markerSettings: const MarkerSettings(isVisible: true),
          ),
        ],
        tooltipBehavior: TooltipBehavior(enable: true),
      ),
    );
  }

  Widget _buildUsageChart(AnalyticsInsights insights) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Peak Activity Hour',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BFA5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${insights.peakUsageHour}:00',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00BFA5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(
                majorGridLines: const MajorGridLines(width: 0),
              ),
              primaryYAxis: NumericAxis(
                title: AxisTitle(text: 'Activity Level'),
                majorGridLines: const MajorGridLines(
                  width: 1,
                  dashArray: [5, 5],
                ),
              ),
              series: <CartesianSeries>[
                ColumnSeries<Map<String, dynamic>, String>(
                  dataSource: _generateHourlyActivity(insights.peakUsageHour),
                  xValueMapper: (data, _) => data['hour'],
                  yValueMapper: (data, _) => data['activity'],
                  color: const Color(0xFF00BFA5),
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
                  color: Colors.black87,
                ),
              ),
              Text(
                '${insights.energyConsumption.toStringAsFixed(2)} kWh',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00BFA5),
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
                color: Colors.black87,
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
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  // ==================== INSIGHTS TAB ====================
  Widget _buildInsightsTab(String userId) {
    final timeRange = ref.watch(analyticsTimeRangeProvider);
    final insightsAsync = ref.watch(analyticsInsightsProvider({
      'userId': userId,
      'days': timeRange,
    }));

    return insightsAsync.when(
      data: (insights) => SingleChildScrollView(
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
      loading: () => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
        ),
      ),
      error: (error, _) => _buildErrorState(error.toString()),
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
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
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
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
          ),
        ),
        error: (error, _) => _buildErrorState(error.toString()),
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

  // ==================== ANOMALIES TAB ====================
  Widget _buildAnomaliesTab(String userId) {
    final anomalyAsync = ref.watch(anomalyReportProvider(userId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(anomalyReportProvider);
      },
      child: anomalyAsync.when(
        data: (report) {
          if (report == null || !report.hasAnomalies) {
            return _buildNoAnomalies();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: report.anomalies.length + 1, // +1 for summary card
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildAnomalySummaryCard(report),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildAnomalyCard(report.anomalies[index - 1]),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
          ),
        ),
        error: (error, _) => _buildErrorState(error.toString()),
      ),
    );
  }

  Widget _buildAnomalySummaryCard(AnomalyReport report) {
    final criticalCount =
        report.anomalies.where((a) => a.severity == 'high').length;
    final mediumCount =
        report.anomalies.where((a) => a.severity == 'medium').length;
    final lowCount = report.anomalies.where((a) => a.severity == 'low').length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: report.hasCritical
              ? [Colors.red.shade400, Colors.red.shade600]
              : [const Color(0xFF00BFA5), const Color(0xFF00897B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (report.hasCritical ? Colors.red : const Color(0xFF00BFA5))
                .withOpacity(0.3),
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
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  report.hasCritical
                      ? Icons.warning_rounded
                      : Icons.info_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.hasCritical
                          ? 'Action Required'
                          : 'Anomalies Detected',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Last 24 hours',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (criticalCount > 0) ...[
                _buildSeverityBadge('Critical', criticalCount, Colors.white),
                const SizedBox(width: 8),
              ],
              if (mediumCount > 0) ...[
                _buildSeverityBadge('Medium', mediumCount, Colors.white70),
                const SizedBox(width: 8),
              ],
              if (lowCount > 0)
                _buildSeverityBadge('Low', lowCount, Colors.white60),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityBadge(String label, int count, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildAnomalyCard(Anomaly anomaly) {
    Color severityColor;
    IconData severityIcon;

    switch (anomaly.severity) {
      case 'high':
        severityColor = Colors.red;
        severityIcon = Icons.error_rounded;
        break;
      case 'medium':
        severityColor = Colors.orange;
        severityIcon = Icons.warning_rounded;
        break;
      default:
        severityColor = Colors.blue;
        severityIcon = Icons.info_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: severityColor.withOpacity(0.3), width: 2),
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
                  color: severityColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(severityIcon, color: severityColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anomaly.type.toString().split('.').last.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: severityColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      anomaly.message,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.access_time_rounded,
                  size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                'Detected ${_timeAgo(anomaly.timestamp)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics_rounded,
                        size: 12, color: severityColor),
                    const SizedBox(width: 4),
                    Text(
                      '${(anomaly.confidence * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: severityColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (anomaly.severity == 'high') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _handleAnomalyAction(anomaly),
                icon: const Icon(Icons.phone_rounded, size: 18),
                label: const Text('Contact Caregiver'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: severityColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoAnomalies() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                size: 64,
                color: Colors.green.shade500,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'All Clear!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No unusual activity detected\nin the last 24 hours',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'AI monitors activity patterns 24/7 to detect anomalies',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                        height: 1.4,
                      ),
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
        color: Colors.black87,
      ),
    );
  }

  Widget _buildErrorState(String error) {
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
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                ref.invalidate(analyticsInsightsProvider);
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

  List<Map<String, dynamic>> _generateTrendData(int days) {
    final data = <Map<String, dynamic>>[];
    for (int i = days - 1; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i));
      data.add({
        'day': DateFormat('MMM dd').format(date),
        'temp': 22.0 + (i % 5) * 0.8,
        'humidity': 50.0 + (i % 7) * 2.5,
      });
    }
    return data;
  }

  List<Map<String, dynamic>> _generateHourlyActivity(int peakHour) {
    final data = <Map<String, dynamic>>[];
    for (int i = 0; i < 24; i++) {
      final activity = i == peakHour
          ? 100
          : (50 + (24 - (i - peakHour).abs()) * 2).toDouble();
      data.add({
        'hour': i.toString().padLeft(2, '0'),
        'activity': activity,
      });
    }
    return data;
  }

  void _showCreateScheduleDialog(SchedulePrediction prediction) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.schedule_rounded, color: Color(0xFF00BFA5)),
            SizedBox(width: 12),
            Text('Create Schedule'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI suggests scheduling ${prediction.deviceType} to ${prediction.value}% '
              'every ${prediction.dayName} at ${prediction.timeString}.',
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Based on your usage patterns',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Schedule created successfully!'),
                  backgroundColor: Color(0xFF00BFA5),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _handleAnomalyAction(Anomaly anomaly) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.phone_rounded, color: Colors.red.shade600),
            const SizedBox(width: 12),
            const Text('Contact Caregiver'),
          ],
        ),
        content: const Text(
          'This will send an alert to all registered caregivers.\n\n'
          'Do you want to proceed?',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Alert sent to caregivers'),
                  backgroundColor: Colors.red.shade600,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Send Alert'),
          ),
        ],
      ),
    );
  }
}
