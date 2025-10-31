import 'package:flutter/material.dart';
import 'package:soil_temp_monitor/services/insights_dashboard.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/sidebar_menu.dart';
import 'package:intl/intl.dart';
import '../models/temperature_reading.dart';
import '../widgets/chatbot_widget.dart';

// NEW SERVICE IMPORTS
import '../services/alerts_service.dart';
import '../services/soil_health_service.dart';
import '../services/weather_service.dart';
import '../services/bluetooth_manager.dart'; // <--- IMPORTANT: Singleton Manager


// The next classes (DashboardScreen, _DashboardScreenState) are now decoupled
// from the direct BLE hardware management.

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // --- PERSISTENT STATE MANAGER INSTANCE ---
  // Access the single instance of the BluetoothManager
  final BluetoothManager _bleManager = BluetoothManager();

  // --- LOCAL STATE VARIABLES (MIRRORED FROM MANAGER) ---
  double currentTemp = 0.00;
  List<TemperatureReading> readings = [];
  String selectedChartType = 'line';
  int selectedTimeRange = 7;
  // BLE status is now pulled from manager's streams/state
  bool isConnected = false;
  bool isScanning = false;
  String connectionStatus = "Not Connected";

  // INSIGHTS STATE VARIABLES
  double ambientTemp = 0.0;
  double tempTrend = 0.0;
  double soilHealthScore = 0.0;
  String? alertMessage;
  List<ForecastDay> forecastDays = [];

  // SERVICES
  final AlertsService _alertsService = AlertsService();
  final SoilHealthService _healthService = SoilHealthService();
  final WeatherService _weatherService = WeatherService();

  // Stream Subscriptions to update UI when manager state changes
  StreamSubscription? _statusSubscription;
  StreamSubscription? _tempSubscription;

  @override
  void initState() {
    super.initState();

    // 1. Initial State Load
    // Load the current data/status immediately from the manager's state
    readings = _bleManager.readings.cast<TemperatureReading>();
    currentTemp = _bleManager.currentTemp;
    connectionStatus = _bleManager.connectionStatus;
    isConnected = _bleManager.isConnected;
    isScanning = _bleManager.isScanning;

    // 2. Initial Setup/Scan (Only triggered by the manager if it hasn't run yet)
    // This is the call that ensures scan ONLY happens on app launch
    _bleManager.initialize();

    // 3. Subscribe to Manager's Streams for persistent UI updates
    _statusSubscription = _bleManager.connectionStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          connectionStatus = status;
          isConnected = _bleManager.isConnected;
          isScanning = _bleManager.isScanning;
        });
      }
    });

    _tempSubscription = _bleManager.temperatureStream.listen((temp) {
      if (mounted) {
        setState(() {
          currentTemp = temp;
          readings = _bleManager.readings
              .cast<TemperatureReading>(); // Get the updated full list
        });
        _updateInsights(); // Recalculate insights on new temperature data
      }
    });

    // 4. Initial Load of Insights (including Weather API call)
    _updateInsights();
  }

  @override
  void dispose() {
    // ONLY cancel subscriptions! DO NOT dispose of the manager.
    _statusSubscription?.cancel();
    _tempSubscription?.cancel();
    super.dispose();
  }

  // ============================================
  // INSIGHTS & CALCULATION LOGIC
  // ============================================

  // Helper to calculate the temperature trend over the last hour
  double _calculateTemperatureTrend() {
    if (readings.length < 2) return 0.0;

    // Find a reading from approximately 1 hour ago
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    final readingsOneHour = readings
        .where((r) => r.timestamp.isAfter(oneHourAgo))
        .toList();

    if (readingsOneHour.length < 2) return 0.0;

    final oldReading = readingsOneHour.first;
    final newReading = readingsOneHour.last;

    // Time difference in hours
    final timeDifferenceHours =
        newReading.timestamp.difference(oldReading.timestamp).inMinutes / 60.0;

    if (timeDifferenceHours < 0.1) return 0.0; // Prevent division by near-zero

    // Calculate trend per day (°C/day)
    final tempDiff = newReading.temperature - oldReading.temperature;
    final trendPerDay = (tempDiff / timeDifferenceHours) * 24.0;

    return trendPerDay;
  }

  Future<void> _updateInsights() async {
    if (readings.isEmpty) return;

    // 1. Calculate Trend (for Alerts and Crop Recommendations)
    final trend = _calculateTemperatureTrend();

    // 2. Calculate Health Score (using last 24 hours of readings)
    final recentTemps = readings
        .where(
          (r) => r.timestamp.isAfter(
        DateTime.now().subtract(const Duration(hours: 24)),
      ),
    )
        .map((r) => r.temperature)
        .toList();
    final healthScore = _healthService.calculateHealthScore(recentTemps);

    // 3. Fetch Weather Data (Makerere University, Uganda)
    const double lat = 0.31361;
    const double lon = 32.58111;

    final forecast = await _weatherService.getForecast(
      lat,
      lon,
    ); // Fetch 3-day forecast (with hourly data)
    final temp = await _weatherService.getAmbientTemperature(
      lat,
      lon,
    ); // Fetch current ambient temp

    // 4. Check Alerts & Predictions
    final alert = _alertsService.checkTemperatureAlerts(
      currentTemp,
      temp ?? ambientTemp,
    );
    final message = alert ?? _alertsService.predictTrend(trend);

    if (mounted) {
      // Only call setState if the widget is still mounted
      setState(() {
        tempTrend = trend;
        soilHealthScore = healthScore;
        ambientTemp = temp ?? ambientTemp;
        alertMessage = message;
        forecastDays = forecast; // Update state with full forecast data
      });
    }
  }

  // ============================================
  // BLUETOOTH/DB/COMMAND LOGIC (REPLACED WITH MANAGER CALLS)
  // ============================================

  // Trigger the Singleton's scan method

  // Trigger the Singleton's command method
  Future<void> _sendCommand(String command) async {
    await _bleManager.sendCommand(command);
    if (!_bleManager.isConnected) {
      _showError("Not connected to ESP32");
    } else {
      _showSuccess("Command sent: $command");
    }
  }

  // Used for manual input, calls the manager's public method
  void _addManualReading() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Add Manual Reading'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Temperature (°C)',
              hintText: '25.5',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final temp = double.tryParse(controller.text);
                if (temp != null) {
                  // CORRECTED: Call the now-public method 'handleTemperatureUpdate'
                  _bleManager.handleTemperatureUpdate(
                    utf8.encode(temp.toStringAsFixed(2) + " °C"),
                  );
                  Navigator.pop(context);
                  _showSuccess('Reading added successfully');
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _viewHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoryScreen(
          readings: _bleManager.readings,
        ), // Use manager's persistent list
      ),
    );
  }

  Future<void> _exportData() async {
    if (readings.isEmpty) {
      _showError('No data to export');
      return;
    }
    // ... (rest of export logic remains the same, using local 'readings' which is mirrored) ...
    try {
      List<List<dynamic>> csvData = [
        ['Date', 'Time', 'Temperature (°C)'],
      ];

      for (var reading in readings) {
        csvData.add([
          reading.timestamp.toLocal().toString().split(' ')[0],
          reading.timestamp.toLocal().toString().split(' ')[1].substring(0, 8),
          reading.temperature.toStringAsFixed(2),
        ]);
      }

      String csv = const ListToCsvConverter().convert(csvData);
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .split('.')[0]
          .replaceAll(':', '-');
      final file = File('${directory.path}/temperature_export_$timestamp.csv');
      await file.writeAsString(csv);

      final result = await Share.shareXFiles([
        XFile(file.path),
      ], subject: 'Temperature Sensor Data - ${readings.length} readings');

      if (result.status == ShareResultStatus.success) {
        _showSuccess('Exported ${readings.length} readings successfully');
      }
    } catch (e) {
      _showError('Export failed: ${e.toString()}');
    }
  }

  Future<void> _shareCurrentReading() async {
    if (readings.isEmpty) {
      _showError('No readings available to share');
      return;
    }
    // ... (rest of share logic remains the same) ...
    final avg24h = _calculateAverage(24);
    final min24h = _calculateMin(24);
    final max24h = _calculateMax(24);
    final readingCount = readings
        .where(
          (r) => r.timestamp.isAfter(
        DateTime.now().subtract(const Duration(hours: 24)),
      ),
    )
        .length;

    final summary =
    '''
📊 Temperature Sensor Report
━━━━━━━━━━━━━━━━━━━━━━━━━━
🌡️ Current Soil Temp: ${currentTemp.toStringAsFixed(2)}°C
☀️ Current Ambient Temp: ${ambientTemp.toStringAsFixed(1)}°C
🌱 Soil Health Score: ${soilHealthScore.toStringAsFixed(0)}/100
📅 ${DateTime.now().toString().split('.')[0]}

📈 Last 24 Hours:
   • Average: ${avg24h.toStringAsFixed(1)}°C
   • Highest: ${max24h.toStringAsFixed(1)}°C
   • Lowest: ${min24h.toStringAsFixed(1)}°C
   • Readings: $readingCount

━━━━━━━━━━━━━━━━━━━━━━━━━━
${alertMessage ?? "All systems nominal."}
''';

    await Share.share(summary, subject: 'Temperature Reading');
  }

  // ============================================
  // STATISTICS CALCULATIONS (Unchanged)
  // ============================================
  double _calculateAverage(int hours) {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final recentReadings = readings
        .where((r) => r.timestamp.isAfter(cutoff))
        .toList();
    if (recentReadings.isEmpty) return 0;
    return recentReadings.map((r) => r.temperature).reduce((a, b) => a + b) /
        recentReadings.length;
  }

  double _calculateMin(int hours) {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final recentReadings = readings
        .where((r) => r.timestamp.isAfter(cutoff))
        .toList();
    if (recentReadings.isEmpty) return 0;
    return recentReadings
        .map((r) => r.temperature)
        .reduce((a, b) => a < b ? a : b);
  }

  double _calculateMax(int hours) {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final recentReadings = readings
        .where((r) => r.timestamp.isAfter(cutoff))
        .toList();
    if (recentReadings.isEmpty) return 0;
    return recentReadings
        .map((r) => r.temperature)
        .reduce((a, b) => a > b ? a : b);
  }

  // ============================================
  // UI HELPERS (Unchanged)
  // ============================================
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    }
  }

  // ============================================
  // BUILD UI (MODIFIED: Replaced individual cards with FullWeatherCard)
  // ============================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SidebarMenu(),
      appBar: AppBar(
        title: const Text("Temperature Monitor"),
        elevation: 0,
        backgroundColor: Colors.green.shade700,
        actions: [
          IconButton(
            icon: Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
            ),
            onPressed: () {
              // Navigate to Bluetooth connection screen
              Navigator.pushNamed(context, '/bluetooth');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              _showBuzzerControlDialog();
            },
          ),
        ],
      ),
      floatingActionButton: const ChatbotFAB(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.green.shade700, Colors.green.shade50],
            stops: const [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConnectionCard(),
                const SizedBox(height: 20),

                _buildFullWeatherCard(),
                const SizedBox(height: 20),

                _buildStatisticsCards(),
                const SizedBox(height: 24),
                _buildGraphCard(),
                const SizedBox(height: 24),
                _buildQuickActions(),
                const SizedBox(height: 24),
                _buildRecentReadings(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // WIDGETS (Rely on local state, which is mirrored from the Manager)
  // ============================================

  Widget _buildFullWeatherCard() {
    if (forecastDays.isEmpty || readings.isEmpty) {
      // Fallback if data is missing
      return Column(
        children: [
          _buildCurrentTempCard(),
          const SizedBox(height: 20),
          _buildAlertsCard(),
          const SizedBox(height: 20),
        ],
      );
    }

    final currentDay = forecastDays.first;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCurrentSummary(currentDay.maxTempC, currentDay.minTempC),
          const SizedBox(height: 16),

          _buildHourlyForecast(currentDay.hourlyForecast),
          const SizedBox(height: 16),

          _buildDailyForecastList(),
          const SizedBox(height: 16),

          _buildCombinedInsightBar(ambientTemp),
        ],
      ),
    );
  }

  Widget _buildCurrentSummary(double maxTemp, double minTemp) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.black87, size: 18),
                const SizedBox(width: 4),
                const Text(
                  "Kampala",
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${ambientTemp.toStringAsFixed(0)}",
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 80,
                fontWeight: FontWeight.w300,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Text(
                "°",
                style: TextStyle(
                  color: Colors.black.withOpacity(0.7),
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 15),
                Text(
                  "${maxTemp.toStringAsFixed(0)}° / ${minTemp.toStringAsFixed(0)}°",
                  style: const TextStyle(color: Colors.black87, fontSize: 18),
                ),
                Text(
                  forecastDays.first.condition,
                  style: const TextStyle(color: Colors.black87, fontSize: 18),
                ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Icon(
                DateTime.now().hour > 6 && DateTime.now().hour < 18
                    ? Icons.wb_sunny
                    : Icons.nightlight_round,
                color: Colors.orange.shade600,
                size: 40,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHourlyForecast(List<ForecastHour> hourlyForecast) {
    final nowHour = DateTime.now().hour;
    final startIndex = hourlyForecast.indexWhere((h) => h.time.hour >= nowHour);

    final startingIndex = startIndex != -1 ? startIndex : 0;

    final nextHours = hourlyForecast.sublist(startingIndex).take(7).toList();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: nextHours.length,
        itemBuilder: (context, index) {
          final hour = nextHours[index];
          String timeText = hour.time.hour == nowHour
              ? "Now"
              : DateFormat('ha').format(hour.time).toLowerCase();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(
                  timeText,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Image.network(
                  hour.iconUrl,
                  width: 30,
                  height: 30,
                  errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.cloud, color: Colors.green, size: 30),
                ),
                const SizedBox(height: 4),
                Text(
                  "${hour.tempC.toStringAsFixed(0)}°",
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.water_drop_outlined,
                      color: Colors.blueGrey,
                      size: 10,
                    ),
                    Text(
                      "${hour.chanceOfRain.toStringAsFixed(0)}%",
                      style: const TextStyle(
                        color: Colors.blueGrey,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDailyForecastList() {
    final dailyForecast = forecastDays.take(3).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.green.shade50,
      ),
      child: Column(
        children: dailyForecast.map((day) {
          String dayName = day.date.day == DateTime.now().day
              ? "Today"
              : day.date.day == DateTime.now().add(const Duration(days: 1)).day
              ? "Tomorrow"
              : DateFormat('EEEE').format(day.date);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    dayName,
                    style: const TextStyle(color: Colors.black87, fontSize: 16),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.network(
                        day.iconUrl,
                        width: 25,
                        height: 25,
                        errorBuilder: (context, error, stackTrace) =>
                        const Icon(
                          Icons.cloud,
                          color: Colors.green,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        day.condition.split(' ').first,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    "${day.maxTempC.toStringAsFixed(0)}° / ${day.minTempC.toStringAsFixed(0)}°",
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.black87, fontSize: 16),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCombinedInsightBar(double currentAmbientTemp) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade700,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Soil Health: ${soilHealthScore.toStringAsFixed(0)}/100",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Ambient: ${currentAmbientTemp.toStringAsFixed(1)}°C | Soil: ${currentTemp.toStringAsFixed(1)}°C",
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: readings.isEmpty
                ? null
                : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => InsightsDashboard(
                    soilTemp: currentTemp,
                    tempTrend: tempTrend,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.psychology_outlined, size: 18),
            label: const Text("AI Insights", style: TextStyle(fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade500,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alertMessage?.startsWith('⚠') == true
            ? Colors.red.shade50
            : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alertMessage?.startsWith('⚠') == true
              ? Colors.red.shade300
              : Colors.green.shade300,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            alertMessage?.startsWith('⚠') == true
                ? Icons.warning_amber
                : Icons.notifications_active,
            color: alertMessage?.startsWith('⚠') == true
                ? Colors.red.shade700
                : Colors.green.shade700,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              alertMessage ?? "No alerts. Soil temperature stable.",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTempCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.thermostat,
              size: 32,
              color: Colors.orange.shade700,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Current Temperature",
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  currentTemp > 0
                      ? "${currentTemp.toStringAsFixed(2)}°C"
                      : "-- °C",
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          if (isConnected)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 8, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? Colors.green.shade300 : Colors.orange.shade300,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.check_circle : Icons.warning,
            color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connectionStatus,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isConnected
                        ? Colors.green.shade900
                        : Colors.orange.shade900,
                  ),
                ),
                if (!isConnected)
                  const Text(
                    "Tap Bluetooth icon to connect",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
          ),
          if (isScanning)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: "24h Average",
            value: readings.isEmpty
                ? "--"
                : "${_calculateAverage(24).toStringAsFixed(1)}°C",
            icon: Icons.trending_neutral,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: "24h High",
            value: readings.isEmpty
                ? "--"
                : "${_calculateMax(24).toStringAsFixed(1)}°C",
            icon: Icons.trending_up,
            color: Colors.red,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: "24h Low",
            value: readings.isEmpty
                ? "--"
                : "${_calculateMin(24).toStringAsFixed(1)}°C",
            icon: Icons.trending_down,
            color: Colors.teal,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
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
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGraphCard() {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Temperature Trend",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              PopupMenuButton<String>(
                icon: Row(
                  children: [
                    Text(
                      selectedChartType == 'line'
                          ? 'Line'
                          : selectedChartType == 'bar'
                          ? 'Bar'
                          : 'Area',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
                onSelected: (value) {
                  setState(() {
                    selectedChartType = value;
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'line', child: Text('Line Chart')),
                  const PopupMenuItem(value: 'bar', child: Text('Bar Chart')),
                  const PopupMenuItem(value: 'area', child: Text('Area Chart')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(height: 200, child: _buildChart()),
        ],
      ),
    );
  }

  Widget _buildChart() {
    if (readings.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 48, color: Colors.black26),
            SizedBox(height: 8),
            Text(
              "Waiting for sensor data...",
              style: TextStyle(color: Colors.black38),
            ),
          ],
        ),
      );
    }

    // Prepare data for Syncfusion chart
    List<ChartData> chartData = readings.asMap().entries.map((entry) {
      return ChartData(entry.key.toDouble(), entry.value.temperature);
    }).toList();

    if (selectedChartType == 'line') {
      return SfCartesianChart(
        primaryXAxis: NumericAxis(isVisible: false),
        primaryYAxis: NumericAxis(labelFormat: '{value}°C'),
        plotAreaBorderWidth: 0,
        series: <CartesianSeries>[
          LineSeries<ChartData, double>(
            dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.x,
            yValueMapper: (ChartData data, _) => data.y,
            color: Colors.green.shade600,
            width: 3,
            markerSettings: const MarkerSettings(isVisible: false),
          ),
        ],
        tooltipBehavior: TooltipBehavior(enable: true),
      );
    } else if (selectedChartType == 'area') {
      return SfCartesianChart(
        primaryXAxis: NumericAxis(isVisible: false),
        primaryYAxis: NumericAxis(labelFormat: '{value}°C'),
        plotAreaBorderWidth: 0,
        series: <CartesianSeries>[
          AreaSeries<ChartData, double>(
            dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.x,
            yValueMapper: (ChartData data, _) => data.y,
            color: Colors.green.shade600,
            opacity: 0.3,
            borderColor: Colors.green.shade600,
            borderWidth: 2,
          ),
        ],
        tooltipBehavior: TooltipBehavior(enable: true),
      );
    } else {
      // Bar chart
      return SfCartesianChart(
        primaryXAxis: NumericAxis(isVisible: false),
        primaryYAxis: NumericAxis(labelFormat: '{value}°C'),
        plotAreaBorderWidth: 0,
        series: <CartesianSeries>[
          ColumnSeries<ChartData, double>(
            dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.x,
            yValueMapper: (ChartData data, _) => data.y,
            color: Colors.green.shade600,
            width: 0.8,
          ),
        ],
        tooltipBehavior: TooltipBehavior(enable: true),
      );
    }
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Quick Actions",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildActionButton(
              icon: Icons.add_chart,
              label: "Add Data",
              color: Colors.green,
              onTap: _addManualReading,
            ),
            _buildActionButton(
              icon: Icons.history,
              label: "History",
              color: Colors.blue,
              onTap: _viewHistory,
            ),
            _buildActionButton(
              icon: Icons.download,
              label: "Export",
              color: Colors.orange,
              onTap: _exportData,
            ),
            _buildActionButton(
              icon: Icons.share,
              label: "Share",
              color: Colors.purple,
              onTap: _shareCurrentReading,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentReadings() {
    final recentReadings = readings.reversed.take(5).toList();

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Recent Readings",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              TextButton(
                onPressed: _viewHistory,
                child: const Text("View All"),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (recentReadings.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "No readings yet",
                  style: TextStyle(color: Colors.black38),
                ),
              ),
            )
          else
            ...recentReadings.map((reading) => _buildReadingItem(reading)),
        ],
      ),
    );
  }

  Widget _buildReadingItem(TemperatureReading reading) {
    final timeStr = _formatTime(reading.timestamp);
    final tempColor = reading.temperature > 25
        ? Colors.orange
        : reading.temperature < 18
        ? Colors.blue
        : Colors.green;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: tempColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  "${reading.temperature.toStringAsFixed(2)}°C",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.black26),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} min ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else {
      return '${diff.inDays} days ago';
    }
  }

  // ============================================
  // BUZZER CONTROL DIALOG (Unchanged)
  // ============================================
  void _showBuzzerControlDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buzzer Control'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Control the ESP32 buzzer'),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _sendCommand('BUZZER_ON');
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Turn ON'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _sendCommand('BUZZER_OFF');
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.volume_off),
                  label: const Text('Turn OFF'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ListToCsvConverter {
  const ListToCsvConverter();

  String convert(List<List<dynamic>> rows) {
    final buffer = StringBuffer();
    for (var row in rows) {
      buffer.writeln(row.map((e) => e.toString()).join(','));
    }
    return buffer.toString();
  }
}

// ============================================
// TEMPERATURE READING MODEL
// ============================================

// ============================================
// CHART DATA MODEL
// ============================================
class ChartData {
  final double x;
  final double y;

  ChartData(this.x, this.y);
}

// ============================================
// HISTORY SCREEN
// ============================================
class HistoryScreen extends StatelessWidget {
  final List<TemperatureReading> readings;

  const HistoryScreen({super.key, required this.readings});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Temperature History'),
        backgroundColor: Colors.green.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear History'),
                  content: const Text(
                    'Are you sure you want to clear all readings?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        // Clear readings from SharedPreferences
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('temperature_readings');

                        // NOTE: We need to tell the manager to clear its list too.
                        BluetoothManager().readings.clear();

                        Navigator.pop(context);
                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('History cleared successfully'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: readings.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.black26),
            SizedBox(height: 16),
            Text(
              'No readings yet',
              style: TextStyle(fontSize: 18, color: Colors.black38),
            ),
            SizedBox(height: 8),
            Text(
              'Connect your sensor to start collecting data',
              style: TextStyle(fontSize: 14, color: Colors.black38),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: readings.length,
        itemBuilder: (context, index) {
          final reading = readings.reversed.toList()[index];
          final tempColor = reading.temperature > 25
              ? Colors.orange
              : reading.temperature < 18
              ? Colors.blue
              : Colors.green;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tempColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.thermostat, color: tempColor),
              ),
              title: Text(
                '${reading.temperature.toStringAsFixed(2)}°C',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                reading.timestamp.toString().split('.')[0],
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.black26,
              ),
            ),
          );
        },
      ),
    );
  }
}