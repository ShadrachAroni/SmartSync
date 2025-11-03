import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../services/ml_service.dart';

// ==================== PROVIDERS ====================
final mlServiceProvider = Provider((ref) => MLService());

final analyticsInsightsProvider =
    FutureProvider.family<AnalyticsInsights, String>(
  (ref, userId) async {
    final mlService = ref.watch(mlServiceProvider);
    return await mlService.getInsights(userId, 30); // Last 30 days
  },
);

final schedulePredictionsProvider =
    FutureProvider.family<List<SchedulePrediction>, Map<String, String>>(
  (ref, params) async {
    final mlService = ref.watch(mlServiceProvider);
    return await mlService.predictSchedules(
        params['userId']!, params['deviceId']!);
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
      return const Scaffold(
        body: Center(child: Text('Please login')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Analytics & Insights'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF00BFA5),
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: const Color(0xFF00BFA5),
          tabs: const [
            Tab(icon: Icon(Icons.insights_rounded), text: 'Insights'),
            Tab(icon: Icon(Icons.schedule_rounded), text: 'Predictions'),
            Tab(icon: Icon(Icons.warning_rounded), text: 'Anomalies'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInsightsTab(user.uid),
          _buildPredictionsTab(user.uid),
          _buildAnomaliesTab(user.uid),
        ],
      ),
    );
  }

  // ==================== INSIGHTS TAB ====================
  Widget _buildInsightsTab(String userId) {
    final insightsAsync = ref.watch(analyticsInsightsProvider(userId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(analyticsInsightsProvider(userId));
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

              // Temperature Trend Chart
              _buildSectionTitle('Temperature Trend'),
              const SizedBox(height: 16),
              _buildTemperatureChart(userId),
              const SizedBox(height: 24),

              // Activity Heatmap
              _buildSectionTitle('Activity Patterns'),
              const SizedBox(height: 16),
              _buildActivityHeatmap(insights),
              const SizedBox(height: 24),

              // Energy Usage
              _buildSectionTitle('Energy Consumption'),
              const SizedBox(height: 16),
              _buildEnergyChart(insights),
            ],
          ),
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
          ),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text('Error loading analytics',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(analyticsInsightsProvider(userId));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
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
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                icon: Icons.water_drop_rounded,
                label: 'Avg Humidity',
                value: '${insights.avgHumidity.toStringAsFixed(0)}%',
                color: const Color(0xFF4ECDC4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.directions_walk_rounded,
                label: 'Motion Events',
                value: insights.motionEvents.toString(),
                color: const Color(0xFFFFE66D),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                icon: Icons.flash_on_rounded,
                label: 'Energy Used',
                value: '${insights.energyConsumption.toStringAsFixed(1)} kWh',
                color: const Color(0xFFA8E6CF),
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
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
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
        ],
      ),
    );
  }

  Widget _buildTemperatureChart(String userId) {
    // Fetch last 7 days of temperature data
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
      child: SfCartesianChart(
        primaryXAxis: CategoryAxis(),
        primaryYAxis: NumericAxis(
          title: AxisTitle(text: 'Temperature (°C)'),
          minimum: 15,
          maximum: 35,
        ),
        series: <CartesianSeries>[
          LineSeries<Map<String, dynamic>, String>(
            dataSource: _generateMockTemperatureData(),
            xValueMapper: (data, _) => data['day'],
            yValueMapper: (data, _) => data['temp'],
            color: const Color(0xFFFF6B6B),
            width: 3,
            markerSettings: const MarkerSettings(isVisible: true),
          ),
        ],
        tooltipBehavior: TooltipBehavior(enable: true),
      ),
    );
  }

  Widget _buildActivityHeatmap(AnalyticsInsights insights) {
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
          Text(
            'Peak Activity Hour: ${insights.peakUsageHour}:00',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00BFA5).withOpacity(0.2),
                  const Color(0xFF00BFA5),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'Heatmap visualization\n(Coming soon)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnergyChart(AnalyticsInsights insights) {
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
          const Text(
            'Device Usage Breakdown',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 24),
          _buildUsageBar(
              'Fan', insights.avgFanUsage / 255.0, const Color(0xFF4ECDC4)),
          const SizedBox(height: 16),
          _buildUsageBar('Lights', insights.avgLightUsage / 255.0,
              const Color(0xFFFFE66D)),
        ],
      ),
    );
  }

  Widget _buildUsageBar(String label, double percentage, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            Text(
              '${(percentage * 100).toStringAsFixed(0)}%',
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

  // ==================== PREDICTIONS TAB ====================
  Widget _buildPredictionsTab(String userId) {
    // Note: Need deviceId, using placeholder for now
    final predictionsAsync = ref.watch(schedulePredictionsProvider({
      'userId': userId,
      'deviceId': 'device_1',
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
              return _buildPredictionCard(predictions[index]);
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
          ),
        ),
        error: (error, _) => Center(
          child: Text('Error: $error'),
        ),
      ),
    );
  }

  Widget _buildPredictionCard(SchedulePrediction prediction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    prediction.deviceType == 'fan'
                        ? Icons.air_rounded
                        : Icons.lightbulb_rounded,
                    color: const Color(0xFF00BFA5),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${prediction.dayName} at ${prediction.timeString}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        prediction.deviceType == 'fan'
                            ? 'Fan Speed'
                            : 'Brightness',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
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
          const SizedBox(height: 12),
          Text(
            prediction.reason,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
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
              ElevatedButton(
                onPressed: () {
                  _showCreateScheduleDialog(prediction);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BFA5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            Icon(Icons.calendar_today_rounded,
                size: 80, color: Colors.grey.shade300),
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
        ref.invalidate(anomalyReportProvider(userId));
      },
      child: anomalyAsync.when(
        data: (report) {
          if (report == null || !report.hasAnomalies) {
            return _buildNoAnomalies();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: report.anomalies.length,
            itemBuilder: (context, index) {
              return _buildAnomalyCard(report.anomalies[index]);
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
          ),
        ),
        error: (error, _) => Center(
          child: Text('Error: $error'),
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
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: severityColor.withOpacity(0.3)),
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
                  color: severityColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(severityIcon, color: severityColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anomaly.type.toString().split('.').last.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: severityColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      anomaly.message,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Detected ${_timeAgo(anomaly.timestamp)}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
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
            Icon(Icons.check_circle_rounded,
                size: 80, color: Colors.green.shade300),
            const SizedBox(height: 24),
            const Text(
              'All Clear!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No unusual activity detected in the last 24 hours',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HELPERS ====================
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  List<Map<String, dynamic>> _generateMockTemperatureData() {
    return [
      {'day': 'Mon', 'temp': 23.5},
      {'day': 'Tue', 'temp': 24.2},
      {'day': 'Wed', 'temp': 25.1},
      {'day': 'Thu', 'temp': 24.8},
      {'day': 'Fri', 'temp': 23.9},
      {'day': 'Sat', 'temp': 24.5},
      {'day': 'Sun', 'temp': 25.0},
    ];
  }

  String _timeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showCreateScheduleDialog(SchedulePrediction prediction) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Create Schedule'),
        content: Text(
          'Create a schedule for ${prediction.dayName} at ${prediction.timeString}?',
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
                const SnackBar(content: Text('Schedule created successfully!')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
              foregroundColor: Colors.white,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
