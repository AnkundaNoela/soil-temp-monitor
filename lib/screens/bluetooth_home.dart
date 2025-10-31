// lib/screens/bluetooth_home.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/sidebar_menu.dart';
import '../services/bluetooth_manager.dart';
import '../widgets/chatbot_widget.dart';

class BluetoothHome extends StatefulWidget {
  const BluetoothHome({super.key});

  @override
  State<BluetoothHome> createState() => _BluetoothHomeState();
}

class _BluetoothHomeState extends State<BluetoothHome> {
  // Use the singleton BluetoothManager instead of managing connection locally
  final BluetoothManager _bluetoothManager = BluetoothManager();

  bool isScanning = false;
  final List<ScanResult> scanResults = [];

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<String>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
    _subscribeToManagerUpdates();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _statusSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  void _subscribeToManagerUpdates() {
    // Listen to the manager's connection status
    _statusSubscription = _bluetoothManager.connectionStatusStream.listen((
        status,
        ) {
      if (mounted) {
        setState(() {
          // The manager will update its own state
        });
      }
    });
  }

  Future<void> _initBluetooth() async {
    await _checkPermissions();

    // Check if already connected via the manager
    if (_bluetoothManager.isConnected) {
      // Already connected, no need to scan
      setState(() {});
      return;
    }

    // If not connected, start scanning
    _startScan();
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  void _startScan() {
    // Don't scan if already connected
    if (_bluetoothManager.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Already connected to a device")),
        );
      }
      return;
    }

    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();

    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    try {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        final Map<String, ScanResult> unique = {};
        for (var r in results) {
          unique[r.device.remoteId.str] = r;
        }
        setState(() {
          scanResults
            ..clear()
            ..addAll(unique.values);
        });
      });

      _isScanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
        setState(() {
          isScanning = scanning;
        });
      });
    } catch (e) {
      debugPrint("Start scan error: $e");
      setState(() {
        isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() => isScanning = false);

      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Connecting...")));
      }

      // Connect to device - REMOVE autoConnect but KEEP license
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
        license: License.free, // <-- License MUST be kept
      );

      // Update the manager's state and notify streams
      _bluetoothManager.connectedDevice = device;
      _bluetoothManager.isConnected = true;
      _bluetoothManager.connectionStatus =
      "Connected to ${device.platformName}";
      _bluetoothManager.updateStatus(
        "Connected to ${device.platformName}",
        isConn: true,
      );

      // Discover services and set up characteristics
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() ==
            BluetoothManager.SERVICE_UUID.toLowerCase()) {
          for (BluetoothCharacteristic characteristic
          in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() ==
                BluetoothManager.CHARACTERISTIC_UUID_TX.toLowerCase()) {
              _bluetoothManager.txCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              _bluetoothManager.notificationSubscription = characteristic
                  .onValueReceived
                  .listen((value) {
                _bluetoothManager.handleTemperatureUpdate(value);
              });
            }
            if (characteristic.uuid.toString().toLowerCase() ==
                BluetoothManager.CHARACTERISTIC_UUID_RX.toLowerCase()) {
              _bluetoothManager.rxCharacteristic = characteristic;
            }
          }
        }
      }

      // Listen to connection state for reconnection
      _bluetoothManager.connectionStateSubscription = device.connectionState
          .listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _bluetoothManager.isConnected = false;
          _bluetoothManager.connectionStatus = "Disconnected";
        } else if (state == BluetoothConnectionState.connected) {
          _bluetoothManager.isConnected = true;
          _bluetoothManager.connectionStatus = "Connected";
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connected to ${device.platformName}")),
        );
        setState(() {});
      }
    } catch (e) {
      debugPrint("Connect error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Connection failed: $e")));
      }
      _startScan();
    }
  }

  Future<void> _disconnectDevice() async {
    try {
      await _bluetoothManager.disconnect();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Disconnected successfully")),
        );
        setState(() {});
      }

      _startScan();
    } catch (e) {
      debugPrint("Disconnect error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error disconnecting: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SidebarMenu(),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: const Text("Bluetooth Connection"),
        backgroundColor: Colors.green,
        actions: [
          if (!_bluetoothManager.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: isScanning ? null : _startScan,
            ),
        ],
      ),
      floatingActionButton: const ChatbotFAB(),
      body: _bluetoothManager.isConnected
          ? _buildConnectedView()
          : _buildScanResults(),
    );
  }

  Widget _buildConnectedView() {
    final device = _bluetoothManager.connectedDevice;
    if (device == null) {
      return const Center(child: Text("No device connected"));
    }

    return Center(
      child: Card(
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 5,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bluetooth_connected,
                color: Colors.blue,
                size: 60,
              ),
              const SizedBox(height: 16),
              Text(
                device.platformName.isNotEmpty
                    ? device.platformName
                    : device.remoteId.str,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text("ID: ${device.remoteId.str}"),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _bluetoothManager.connectionStatus,
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.link_off),
                label: const Text("Disconnect"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: _disconnectDevice,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanResults() {
    return Column(
      children: [
        if (isScanning)
          const LinearProgressIndicator(
            minHeight: 4,
            backgroundColor: Colors.grey,
          ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            isScanning ? "Scanning for devices..." : "Available devices",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          child: scanResults.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bluetooth_searching,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  isScanning ? "Searching..." : "No devices found",
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Make sure your ESP32 is powered on",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 24),
                if (!isScanning)
                  ElevatedButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Scan Again"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          )
              : ListView.builder(
            itemCount: scanResults.length,
            itemBuilder: (context, index) {
              final result = scanResults[index];
              final deviceName = result.device.platformName.isNotEmpty
                  ? result.device.platformName
                  : "Unknown Device";
              final isESP32 = deviceName.contains("ESP32");

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                elevation: isESP32 ? 4 : 2,
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isESP32
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.bluetooth,
                      color: isESP32 ? Colors.green : Colors.blue,
                    ),
                  ),
                  title: Text(
                    deviceName,
                    style: TextStyle(
                      fontWeight: isESP32
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.device.remoteId.str,
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (result.rssi != 0)
                        Text(
                          "Signal: ${result.rssi} dBm",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                  trailing: ElevatedButton(
                    onPressed: () => _connectToDevice(result.device),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isESP32
                          ? Colors.green
                          : Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Connect"),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}