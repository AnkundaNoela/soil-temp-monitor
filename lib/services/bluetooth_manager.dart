// lib/services/bluetooth_manager.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/temperature_reading.dart';

class BluetoothManager {
  // --- SINGLETON SETUP ---
  static final BluetoothManager _instance = BluetoothManager._internal();
  factory BluetoothManager() => _instance;
  BluetoothManager._internal();

  // --- BLE Configuration (Centralized - Must Match Dashboard) ---
  static const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String CHARACTERISTIC_UUID_TX =
      "beb5483e-36e1-4688-b7f5-ea07361b26a9";
  static const String CHARACTERISTIC_UUID_RX =
      "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  // --- STATE (Persistent) ---
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? txCharacteristic;
  BluetoothCharacteristic? rxCharacteristic;
  StreamSubscription<List<int>>? notificationSubscription;
  StreamSubscription<BluetoothConnectionState>? connectionStateSubscription;

  double currentTemp = 0.00;
  List<TemperatureReading> readings = [];
  bool isInitialized = false;
  bool isConnected = false;
  bool isScanning = false;
  String connectionStatus = "Not Connected";

  // --- STREAMS for UI Updates ---
  final _connectionStatusController = StreamController<String>.broadcast();
  Stream<String> get connectionStatusStream =>
      _connectionStatusController.stream;

  final _temperatureController = StreamController<double>.broadcast();
  Stream<double> get temperatureStream => _temperatureController.stream;

  // --- INITIALIZATION ---
  Future<void> initialize() async {
    if (isInitialized) {
      if (isConnected) return;
      return;
    }

    isInitialized = true;
    await _loadHistoricalData();
    
    // DEBUG: Print loaded data
    print('=== LOADED DATA DEBUG ===');
    print('Total readings: ${readings.length}');
    if (readings.isNotEmpty) {
      print('First reading: ${readings.first.timestamp} - ${readings.first.temperature}°C');
      print('Last reading: ${readings.last.timestamp} - ${readings.last.temperature}°C');
      
      // Group by date for debugging
      Map<String, int> dailyCounts = {};
      for (var reading in readings) {
        String dateKey = '${reading.timestamp.year}-${reading.timestamp.month}-${reading.timestamp.day}';
        dailyCounts[dateKey] = (dailyCounts[dateKey] ?? 0) + 1;
      }
      print('Readings per day:');
      dailyCounts.forEach((date, count) {
        print('  $date: $count readings');
      });
    }
    print('========================');
  }

  // --- STATUS UPDATES ---
  void updateStatus(
    String status, {
    bool isConn = false,
    bool isScan = false,
  }) {
    connectionStatus = status;
    isConnected = isConn;
    isScanning = isScan;
    _connectionStatusController.add(status);
  }

  void _updateTemp(double temp) {
    currentTemp = temp;
    _temperatureController.add(temp);
  }

  // Handle disconnection and attempt reconnection
  Future<void> handleDisconnection() async {
    isConnected = false;
    txCharacteristic = null;
    rxCharacteristic = null;

    await Future.delayed(const Duration(seconds: 2));

    if (connectedDevice != null) {
      try {
        await connectedDevice!.connect(
          timeout: const Duration(seconds: 15),
          license: License.free,
        );

        List<BluetoothService> services = await connectedDevice!.discoverServices();
        for (BluetoothService service in services) {
          if (service.uuid.toString().toLowerCase() ==
              SERVICE_UUID.toLowerCase()) {
            for (BluetoothCharacteristic characteristic
                in service.characteristics) {
              if (characteristic.uuid.toString().toLowerCase() ==
                  CHARACTERISTIC_UUID_TX.toLowerCase()) {
                txCharacteristic = characteristic;
                await characteristic.setNotifyValue(true);
                notificationSubscription = characteristic.onValueReceived
                    .listen((value) {
                      _handleTemperatureUpdate(value);
                    });
              }
              if (characteristic.uuid.toString().toLowerCase() ==
                  CHARACTERISTIC_UUID_RX.toLowerCase()) {
                rxCharacteristic = characteristic;
              }
            }
          }
        }

        updateStatus("Reconnected", isConn: true);
      } catch (e) {
        updateStatus("Reconnection failed - Please reconnect manually", isConn: false);
      }
    }
  }

  // PUBLIC METHOD - Exposed for manual input from DashboardScreen
  void handleTemperatureUpdate(List<int> value) {
    _handleTemperatureUpdate(value);
  }

  // PRIVATE METHOD - Internal temperature handling
  void _handleTemperatureUpdate(List<int> value) {
    try {
      String tempString = utf8.decode(value);
      String numericPart = tempString.replaceAll(RegExp(r'[^0-9.]'), '');
      double temperature = double.parse(numericPart);

      _updateTemp(temperature);

      // Use local time consistently
      final timestamp = DateTime.now();
      readings.add(
        TemperatureReading(timestamp: timestamp, temperature: temperature),
      );
      
      if (readings.length > 500) {
        readings.removeAt(0);
      }

      _saveReadingToDatabase(temperature, timestamp);
      
      // DEBUG: Print saved reading
      print('Saved reading: $timestamp - $temperature°C');
    } catch (e) {
      print("Error parsing temperature: $e");
    }
  }

  // --- COMMAND/DB LOGIC ---
  Future<void> sendCommand(String command) async {
    if (rxCharacteristic == null || !isConnected) {
      return;
    }
    try {
      await rxCharacteristic!.write(utf8.encode(command));
    } catch (e) {
      print("Error sending command: $e");
    }
  }

  Future<void> _saveReadingToDatabase(double temperature, DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedReadings =
          prefs.getStringList('temperature_readings') ?? [];

      final reading = jsonEncode({
        'timestamp': timestamp.toIso8601String(),
        'temperature': temperature,
      });

      savedReadings.add(reading);
      if (savedReadings.length > 1000) {
        savedReadings = savedReadings.sublist(savedReadings.length - 1000);
      }

      await prefs.setStringList('temperature_readings', savedReadings);
      
      // Verify save
      final verify = prefs.getStringList('temperature_readings');
      print('Verified save: ${verify?.length ?? 0} total readings in storage');
    } catch (e) {
      print('Error saving to database: $e');
    }
  }

  Future<void> _loadHistoricalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedReadings =
          prefs.getStringList('temperature_readings') ?? [];

      print('Loading ${savedReadings.length} readings from storage...');

      readings = savedReadings.map((str) {
        final data = jsonDecode(str);
        return TemperatureReading(
          timestamp: DateTime.parse(data['timestamp']),
          temperature: data['temperature'].toDouble(),
        );
      }).toList();

      // Sort by timestamp (oldest to newest)
      readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (readings.isNotEmpty) {
        currentTemp = readings.last.temperature;
        _temperatureController.add(currentTemp);
      }
    } catch (e) {
      print('Error loading historical data: $e');
    }
  }

  // PUBLIC METHOD - Get readings for a specific date
  List<TemperatureReading> getReadingsForDate(DateTime date) {
    return readings.where((r) {
      return r.timestamp.year == date.year &&
             r.timestamp.month == date.month &&
             r.timestamp.day == date.day;
    }).toList();
  }

  // PUBLIC METHOD - Get all unique dates with readings
  List<DateTime> getDatesWithReadings() {
    Set<String> uniqueDates = {};
    List<DateTime> dates = [];
    
    for (var reading in readings) {
      String dateKey = '${reading.timestamp.year}-${reading.timestamp.month}-${reading.timestamp.day}';
      if (!uniqueDates.contains(dateKey)) {
        uniqueDates.add(dateKey);
        dates.add(DateTime(
          reading.timestamp.year,
          reading.timestamp.month,
          reading.timestamp.day,
        ));
      }
    }
    
    dates.sort((a, b) => b.compareTo(a)); // Newest first
    return dates;
  }

  // PUBLIC METHOD - Clear all readings
  Future<void> clearReadings() async {
    readings.clear();
    currentTemp = 0.0;
    _updateTemp(0.0);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('temperature_readings');
      print('Cleared all readings from storage');
    } catch (e) {
      print('Error clearing readings: $e');
    }
  }

  // Disconnect device
  Future<void> disconnect() async {
    try {
      await notificationSubscription?.cancel();
      await connectionStateSubscription?.cancel();
      if (connectedDevice != null) {
        await connectedDevice!.disconnect();
      }
      updateStatus("Disconnected", isConn: false);
      connectedDevice = null;
      txCharacteristic = null;
      rxCharacteristic = null;
    } catch (e) {
      print('Error disconnecting: $e');
    }
  }

  // Dispose streams
  void dispose() {
    _connectionStatusController.close();
    _temperatureController.close();
  }
}