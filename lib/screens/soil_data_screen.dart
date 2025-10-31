// lib/screens/soil_data_screen.dart
import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import '../services/bluetooth_manager.dart';
import '../models/temperature_reading.dart';
import 'dart:async';
import '../widgets/chatbot_widget.dart';
import 'package:fl_chart/fl_chart.dart';

class SoilDataScreen extends StatefulWidget {
  const SoilDataScreen({super.key});

  @override
  State<SoilDataScreen> createState() => _SoilDataScreenState();
}

class _SoilDataScreenState extends State<SoilDataScreen> {
  final BluetoothManager _bluetoothManager = BluetoothManager();
  double _currentTemperature = 0.0;
  String _connectionStatus = "Not Connected";
  List<TemperatureReading> _readings = [];

  StreamSubscription<double>? _tempSubscription;
  StreamSubscription<String>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _subscribeToUpdates();
  }

  @override
  void dispose() {
    _tempSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _initializeData() {
    setState(() {
      _currentTemperature = _bluetoothManager.currentTemp;
      _connectionStatus = _bluetoothManager.connectionStatus;
      _readings = _bluetoothManager.readings;
    });
    
    // DEBUG
    print('=== SOIL DATA SCREEN INIT ===');
    print('Total readings loaded: ${_readings.length}');
    if (_readings.isNotEmpty) {
      print('Date range: ${_readings.first.timestamp} to ${_readings.last.timestamp}');
    }
  }

  void _subscribeToUpdates() {
    _tempSubscription = _bluetoothManager.temperatureStream.listen((temp) {
      if (mounted) {
        setState(() {
          _currentTemperature = temp;
          _readings = _bluetoothManager.readings;
        });
      }
    });

    _statusSubscription =
        _bluetoothManager.connectionStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _connectionStatus = status;
        });
      }
    });
  }

  Map<String, dynamic> _getDailyStats(DateTime date) {
    // Normalize the date to start of day for comparison
    final targetDate = DateTime(date.year, date.month, date.day);
    
    final dayReadings = _readings.where((r) {
      final readingDate = DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
      return readingDate == targetDate;
    }).toList();

    print('Stats for ${date.day}/${date.month}/${date.year}: ${dayReadings.length} readings');

    if (dayReadings.isEmpty) {
      return {
        'temp': '-- °C',
        'humidity': '--',
        'readings': '0',
        'min': 0.0,
        'max': 0.0,
        'avg': 0.0,
      };
    }

    final temps = dayReadings.map((r) => r.temperature).toList();
    final avgTemp = temps.reduce((a, b) => a + b) / temps.length;
    final minTemp = temps.reduce((a, b) => a < b ? a : b);
    final maxTemp = temps.reduce((a, b) => a > b ? a : b);

    return {
      'temp': '${avgTemp.toStringAsFixed(1)}°C',
      'humidity': '68%', // Placeholder
      'readings': '${dayReadings.length}',
      'min': minTemp,
      'max': maxTemp,
      'avg': avgTemp,
    };
  }

  double _getTodayAverage() {
    final today = DateTime.now();
    final stats = _getDailyStats(today);
    return stats['avg'];
  }

  double _getWeekAverage() {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final weekReadings =
        _readings.where((r) => r.timestamp.isAfter(weekAgo)).toList();

    if (weekReadings.isEmpty) return 0.0;
    return weekReadings.map((r) => r.temperature).reduce((a, b) => a + b) /
        weekReadings.length;
  }

  double _getHighest() {
    if (_readings.isEmpty) return 0.0;
    return _readings.map((r) => r.temperature).reduce((a, b) => a > b ? a : b);
  }

  double _getLowest() {
    if (_readings.isEmpty) return 0.0;
    return _readings.map((r) => r.temperature).reduce((a, b) => a < b ? a : b);
  }

  List<FlSpot> _getChartData() {
    if (_readings.isEmpty) return [];
    
    // Get last 7 days
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    List<FlSpot> spots = [];
    
    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final stats = _getDailyStats(date);
      
      if (stats['avg'] > 0) {
        spots.add(FlSpot((6 - i).toDouble(), stats['avg']));
      }
    }

    return spots;
  }

  void _showDayDetail(DateTime date, Map<String, dynamic> stats) {
    final dayReadings = _bluetoothManager.getReadingsForDate(date);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${date.day}/${date.month}/${date.year}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(Icons.thermostat, 'Average', stats['temp']),
              const SizedBox(height: 8),
              _buildDetailRow(Icons.arrow_upward, 'Highest', 
                stats['max'] > 0 ? '${stats['max'].toStringAsFixed(1)}°C' : '--'),
              const SizedBox(height: 8),
              _buildDetailRow(Icons.arrow_downward, 'Lowest', 
                stats['min'] > 0 ? '${stats['min'].toStringAsFixed(1)}°C' : '--'),
              const SizedBox(height: 8),
              _buildDetailRow(Icons.bar_chart, 'Total Readings', stats['readings']),
              const SizedBox(height: 16),
              if (dayReadings.isNotEmpty) ...[
                const Divider(),
                const Text(
                  'Recent readings:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                ...dayReadings.take(5).map((reading) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${reading.timestamp.hour.toString().padLeft(2, '0')}:${reading.timestamp.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                      Text(
                        '${reading.temperature.toStringAsFixed(1)}°C',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAllHistory() {
    final datesWithData = _bluetoothManager.getDatesWithReadings();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'All History (${datesWithData.length} days)',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              if (datesWithData.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No historical data yet',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: datesWithData.length,
                    itemBuilder: (context, index) {
                      final date = datesWithData[index];
                      final stats = _getDailyStats(date);
                      final colors = [
                        Colors.green,
                        Colors.blue,
                        Colors.orange,
                        Colors.purple
                      ];
                      
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final daysDiff = today.difference(date).inDays;
                      
                      String label;
                      if (daysDiff == 0) {
                        label = "Today";
                      } else if (daysDiff == 1) {
                        label = "Yesterday";
                      } else {
                        label = "$daysDiff days ago";
                      }

                      return _buildDailyAverageCard(
                        date: label,
                        day: "${date.month}/${date.day}/${date.year}",
                        temp: stats['temp'],
                        humidity: stats['humidity'],
                        readings: stats['readings'],
                        color: colors[index % colors.length],
                        onTap: () => _showDayDetail(date, stats),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(value),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayAvg = _getTodayAverage();
    final weekAvg = _getWeekAverage();
    final highest = _getHighest();
    final lowest = _getLowest();

    return Scaffold(
      drawer: const SidebarMenu(),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('Soil Data & History'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          // Debug button to check data
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              final dates = _bluetoothManager.getDatesWithReadings();
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Debug Info'),
                  content: Text(
                    'Total readings: ${_readings.length}\n'
                    'Days with data: ${dates.length}\n'
                    'Current temp: $_currentTemperature°C\n'
                    'Status: $_connectionStatus'
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: const ChatbotFAB(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.shade700, Colors.green.shade50],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Live Temperature Card
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Current Temperature",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _currentTemperature > 0
                                  ? "${_currentTemperature.toStringAsFixed(2)}°C"
                                  : "-- °C",
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_readings.length} total readings',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  _bluetoothManager.isConnected
                                      ? Icons.bluetooth_connected
                                      : Icons.bluetooth_disabled,
                                  size: 16,
                                  color: _bluetoothManager.isConnected
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _connectionStatus,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _bluetoothManager.isConnected
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        title: "Today's Avg",
                        value: todayAvg > 0
                            ? "${todayAvg.toStringAsFixed(1)}°C"
                            : "-- °C",
                        icon: Icons.thermostat,
                        color: Colors.orange,
                        trend: "+1.2°",
                        trendUp: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildSummaryCard(
                        title: "Week Avg",
                        value: weekAvg > 0
                            ? "${weekAvg.toStringAsFixed(1)}°C"
                            : "-- °C",
                        icon: Icons.calendar_today,
                        color: Colors.blue,
                        trend: "-0.5°",
                        trendUp: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        title: "Highest",
                        value: highest > 0
                            ? "${highest.toStringAsFixed(1)}°C"
                            : "-- °C",
                        icon: Icons.trending_up,
                        color: Colors.red,
                        trend: "This week",
                        trendUp: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildSummaryCard(
                        title: "Lowest",
                        value: lowest > 0
                            ? "${lowest.toStringAsFixed(1)}°C"
                            : "-- °C",
                        icon: Icons.trending_down,
                        color: Colors.teal,
                        trend: "This week",
                        trendUp: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Chart Section
                const Text(
                  "Temperature History",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                _buildChartCard(),
                const SizedBox(height: 24),

                // Daily Averages
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Daily Averages",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showAllHistory,
                      icon: const Icon(Icons.calendar_month, size: 18),
                      label: const Text("View All"),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._buildDailyAveragesList(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Last 7 Days",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Row(
                children: [
                  _buildFilterChip("Day", true),
                  const SizedBox(width: 8),
                  _buildFilterChip("Week", false),
                  const SizedBox(width: 8),
                  _buildFilterChip("Month", false),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTemperatureChart(),
        ],
      ),
    );
  }

  Widget _buildTemperatureChart() {
    final chartData = _getChartData();

    if (chartData.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.bar_chart,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 8),
              Text(
                "No data available yet",
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 14,
                ),
              ),
              Text(
                "${_readings.length} readings recorded",
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 5,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.shade300,
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Day ${value.toInt()}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}°C',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: 6,
          minY: chartData.map((e) => e.y).reduce((a, b) => a < b ? a : b) - 5,
          maxY: chartData.map((e) => e.y).reduce((a, b) => a > b ? a : b) + 5,
          lineBarsData: [
            LineChartBarData(
              spots: chartData,
              isCurved: true,
              color: Colors.green,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: Colors.green,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.green.withOpacity(0.1),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.toStringAsFixed(1)}°C',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDailyAveragesList() {
    final colors = [Colors.green, Colors.blue, Colors.orange, Colors.purple];
    final labels = ["Today", "Yesterday", "2 days ago", "3 days ago"];

    return List.generate(4, (index) {
      final date = DateTime.now().subtract(Duration(days: index));
      final stats = _getDailyStats(date);

      return _buildDailyAverageCard(
        date: labels[index],
        day: "${date.month}/${date.day}/${date.year}",
        temp: stats['temp'],
        humidity: stats['humidity'],
        readings: stats['readings'],
        color: colors[index % colors.length],
        onTap: () => _showDayDetail(date, stats),
      );
    });
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String trend,
    required bool trendUp,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Icon(
                trendUp ? Icons.arrow_upward : Icons.arrow_downward,
                color: trendUp ? Colors.green : Colors.red,
                size: 16,
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
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            trend,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? Colors.green : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildDailyAverageCard({
    required String date,
    required String day,
    required String temp,
    required String humidity,
    required String readings,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 60,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        date,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "$readings readings",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    day,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.thermostat,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        temp,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.water_drop,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        humidity,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}