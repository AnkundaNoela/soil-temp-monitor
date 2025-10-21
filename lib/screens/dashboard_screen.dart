import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/sidebar_menu.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // BLE Configuration - Match your Arduino code
  static const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String CHARACTERISTIC_UUID_TX =
      "beb5483e-36e1-4688-b7f5-ea07361b26a9";
  static const String CHARACTERISTIC_UUID_RX =
      "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  // BLE Objects
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? txCharacteristic;
  BluetoothCharacteristic? rxCharacteristic;
  StreamSubscription<List<int>>? notificationSubscription;

  // Temperature data
  double currentTemp = 0.00;
  List<TemperatureReading> readings = [];
  String selectedChartType = 'line';
  int selectedTimeRange = 7;
  bool isConnected = false;
  bool isScanning = false;
  String connectionStatus = "Not Connected";

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
    _loadHistoricalData();
  }

  @override
  void dispose() {
    notificationSubscription?.cancel();
    super.dispose();
  }

  // ============================================
  // BLUETOOTH INITIALIZATION
  // ============================================
  Future<void> _initializeBluetooth() async {
    // Request permissions
    if (Platform.isAndroid) {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.location.request();
    }

    // Check if Bluetooth is available
    try {
      final isAvailable = await FlutterBluePlus.isSupported;
      if (!isAvailable) {
        _showError("Bluetooth not available on this device");
        return;
      }

      // Check if Bluetooth is on
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _showError("Please turn on Bluetooth");
        return;
      }

      // Auto-connect to ESP32
      await _scanAndConnect();
    } catch (e) {
      _showError("Bluetooth initialization failed: $e");
    }
  }

  // ============================================
  // SCAN AND CONNECT TO ESP32
  // ============================================
  Future<void> _scanAndConnect() async {
    setState(() {
      isScanning = true;
      connectionStatus = "Scanning...";
    });

    try {
      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Listen for devices
      var subscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult result in results) {
          // Look for ESP32_Soil_Sensor_BLE device
          if (result.device.platformName.contains("ESP32_Soil_Sensor_BLE") ||
              result.advertisementData.serviceUuids.any(
                (uuid) =>
                    uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase(),
              )) {
            // Stop scanning
            await FlutterBluePlus.stopScan();

            // Connect to device
            await _connectToDevice(result.device);
            break;
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 10));
      subscription.cancel();

      if (!isConnected) {
        setState(() {
          connectionStatus = "ESP32 not found";
          isScanning = false;
        });
        _showError("ESP32 sensor not found. Make sure it's powered on.");
      }
    } catch (e) {
      setState(() {
        isScanning = false;
        connectionStatus = "Scan failed";
      });
      _showError("Scan failed: $e");
    }
  }

  // ============================================
  // CONNECT TO ESP32 DEVICE
  // ============================================
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        connectionStatus = "Connecting...";
      });

      // Connect to device
      await device.connect(
        timeout: const Duration(seconds: 15),
        license: License.free, // ← Required parameter
      );

      setState(() {
        connectedDevice = device;
        isConnected = true;
        connectionStatus = "Connected";
        isScanning = false;
      });

      // Discover services
      List<BluetoothService> services = await device.discoverServices();

      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() ==
            SERVICE_UUID.toLowerCase()) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            // TX Characteristic (receives temperature from ESP32)
            if (characteristic.uuid.toString().toLowerCase() ==
                CHARACTERISTIC_UUID_TX.toLowerCase()) {
              txCharacteristic = characteristic;

              // Enable notifications
              await characteristic.setNotifyValue(true);

              // Listen for temperature updates
              notificationSubscription = characteristic.onValueReceived.listen((
                value,
              ) {
                _handleTemperatureUpdate(value);
              });

              print("✅ Subscribed to temperature notifications");
            }

            // RX Characteristic (sends commands to ESP32)
            if (characteristic.uuid.toString().toLowerCase() ==
                CHARACTERISTIC_UUID_RX.toLowerCase()) {
              rxCharacteristic = characteristic;
              print("✅ Found RX characteristic for commands");
            }
          }
        }
      }

      _showSuccess("Connected to ESP32 Sensor!");
    } catch (e) {
      setState(() {
        isConnected = false;
        connectionStatus = "Connection failed";
        isScanning = false;
      });
      _showError("Connection failed: $e");
    }
  }

  // ============================================
  // HANDLE TEMPERATURE UPDATES FROM ESP32
  // ============================================
  void _handleTemperatureUpdate(List<int> value) {
    try {
      // Convert bytes to string
      String tempString = utf8.decode(value);

      // Parse temperature (format: "24.5 °C")
      String numericPart = tempString.replaceAll(RegExp(r'[^0-9.]'), '');
      double temperature = double.parse(numericPart);

      setState(() {
        currentTemp = temperature;
        readings.add(
          TemperatureReading(
            timestamp: DateTime.now(),
            temperature: temperature,
          ),
        );

        // Keep last 500 readings
        if (readings.length > 500) {
          readings.removeAt(0);
        }
      });

      // Save to database
      _saveReadingToDatabase(temperature);

      print("🌡️ Temperature received: $temperature°C");
    } catch (e) {
      print("Error parsing temperature: $e");
    }
  }

  // ============================================
  // SEND COMMANDS TO ESP32
  // ============================================
  Future<void> _sendCommand(String command) async {
    if (rxCharacteristic == null || !isConnected) {
      _showError("Not connected to ESP32");
      return;
    }

    try {
      await rxCharacteristic!.write(utf8.encode(command));
      print("📤 Sent command: $command");
      _showSuccess("Command sent: $command");
    } catch (e) {
      _showError("Failed to send command: $e");
    }
  }

  // ============================================
  // DATABASE OPERATIONS
  // ============================================
  Future<void> _saveReadingToDatabase(double temperature) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedReadings =
          prefs.getStringList('temperature_readings') ?? [];

      final reading = jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'temperature': temperature,
      });

      savedReadings.add(reading);

      // Keep only last 1000 readings to save space
      if (savedReadings.length > 1000) {
        savedReadings = savedReadings.sublist(savedReadings.length - 1000);
      }

      await prefs.setStringList('temperature_readings', savedReadings);
    } catch (e) {
      print('Error saving to database: $e');
    }
  }

  Future<void> _loadHistoricalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedReadings =
          prefs.getStringList('temperature_readings') ?? [];

      setState(() {
        readings = savedReadings.map((str) {
          final data = jsonDecode(str);
          return TemperatureReading(
            timestamp: DateTime.parse(data['timestamp']),
            temperature: data['temperature'].toDouble(),
          );
        }).toList();

        if (readings.isNotEmpty) {
          currentTemp = readings.last.temperature;
        }
      });

      print('✅ Loaded ${readings.length} historical readings');
    } catch (e) {
      print('Error loading historical data: $e');
    }
  }

  // ============================================
  // QUICK ACTIONS
  // ============================================
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
                  setState(() {
                    readings.add(
                      TemperatureReading(
                        timestamp: DateTime.now(),
                        temperature: temp,
                      ),
                    );
                    currentTemp = temp;
                  });
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
        builder: (context) => HistoryScreen(readings: readings),
      ),
    );
  }

  Future<void> _exportData() async {
    if (readings.isEmpty) {
      _showError('No data to export');
      return;
    }

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
🌡️ Current: ${currentTemp.toStringAsFixed(2)}°C
📅 ${DateTime.now().toString().split('.')[0]}

📈 Last 24 Hours:
   • Average: ${avg24h.toStringAsFixed(1)}°C
   • Highest: ${max24h.toStringAsFixed(1)}°C
   • Lowest: ${min24h.toStringAsFixed(1)}°C
   • Readings: $readingCount

━━━━━━━━━━━━━━━━━━━━━━━━━━
ESP32 Temperature Monitor
''';

    await Share.share(summary, subject: 'Temperature Reading');
  }

  // ============================================
  // STATISTICS CALCULATIONS
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
  // UI HELPERS
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
  // BUILD UI
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
              if (!isConnected) {
                _scanAndConnect();
              }
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
                _buildCurrentTempCard(),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 48, color: Colors.black26),
            const SizedBox(height: 8),
            const Text(
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
          Icon(Icons.chevron_right, color: Colors.black26),
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
  // BUZZER CONTROL DIALOG
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
class TemperatureReading {
  final DateTime timestamp;
  final double temperature;

  TemperatureReading({required this.timestamp, required this.temperature});

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'temperature': temperature,
  };

  factory TemperatureReading.fromJson(Map<String, dynamic> json) =>
      TemperatureReading(
        timestamp: DateTime.parse(json['timestamp']),
        temperature: json['temperature'].toDouble(),
      );
}

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
                    trailing: Icon(Icons.chevron_right, color: Colors.black26),
                  ),
                );
              },
            ),
    );
  }
}