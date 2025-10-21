import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:soil_temp_monitor/widgets/sidebar_menu.dart';

class BluetoothHome extends StatefulWidget {
  const BluetoothHome({super.key});

  @override
  State<BluetoothHome> createState() => _BluetoothHomeState();
}

class _BluetoothHomeState extends State<BluetoothHome> {
  BluetoothDevice? connectedDevice;
  bool isScanning = false;
  final List<ScanResult> scanResults = [];

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _initBluetooth() async {
    await _checkPermissions();
    await _checkAlreadyConnectedDevice();
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> _checkAlreadyConnectedDevice() async {
    try {
      final connectedDevices = await FlutterBluePlus.connectedDevices;
      if (connectedDevices.isNotEmpty) {
        setState(() {
          connectedDevice = connectedDevices.first;
        });
      } else {
        _startScan();
      }
    } catch (e) {
      debugPrint("Error checking connected devices: $e");
      _startScan();
    }
  }

  void _startScan() {
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();

    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    try {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

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

      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      setState(() => connectedDevice = device);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connected to ${device.platformName}")),
        );
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
      await connectedDevice?.disconnect();
      setState(() {
        connectedDevice = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Disconnected successfully")),
        );
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
      drawer: const SidebarMenu(), // Include your sidebar
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // Open the sidebar drawer
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: const Text("Bluetooth Connection"),
        backgroundColor: Colors.green,
        actions: [
          if (connectedDevice == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: isScanning ? null : _startScan,
            ),
        ],
      ),
      body: connectedDevice != null
          ? _buildConnectedView()
          : _buildScanResults(),
    );
  }

  Widget _buildConnectedView() {
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
                connectedDevice!.platformName.isNotEmpty
                    ? connectedDevice!.platformName
                    : connectedDevice!.remoteId.str,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text("ID: ${connectedDevice!.remoteId.str}"),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.link_off),
                label: const Text("Disconnect"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
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
        Expanded(
          child: scanResults.isEmpty
              ? const Center(child: Text("No devices found"))
              : ListView.builder(
                  itemCount: scanResults.length,
                  itemBuilder: (context, index) {
                    final result = scanResults[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.bluetooth,
                          color: Colors.blue,
                        ),
                        title: Text(
                          result.device.platformName.isNotEmpty
                              ? result.device.platformName
                              : "Unknown Device",
                        ),
                        subtitle: Text(result.device.remoteId.str),
                        trailing: ElevatedButton(
                          onPressed: () => _connectToDevice(result.device),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
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
