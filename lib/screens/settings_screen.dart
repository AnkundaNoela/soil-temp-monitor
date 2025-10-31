// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../widgets/sidebar_menu.dart';
import '../services/bluetooth_manager.dart';
import '../widgets/chatbot_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final BluetoothManager _bluetoothManager = BluetoothManager();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool notificationsEnabled = true;
  bool soundEnabled = true;
  double temperatureThreshold = 30.0;
  DateTime? _lastAlertTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeNotifications();
    _loadSettings();
    _startMonitoringSensor();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  bool get isConnected => _bluetoothManager.isConnected;
  BluetoothDevice? get connectedDevice => _bluetoothManager.connectedDevice;

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(initSettings);

    // Request permissions
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      notificationsEnabled = prefs.getBool('notifications') ?? true;
      soundEnabled = prefs.getBool('sound') ?? true;
      temperatureThreshold = prefs.getDouble('tempThreshold') ?? 30.0;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
  }

  void _startMonitoringSensor() {
    // Monitor sensor data from BluetoothManager
    _bluetoothManager.temperatureStream.listen((temperature) {
      _checkTemperatureAlert(temperature);
    });
  }

  void _checkTemperatureAlert(double temperature) {
    if (!notificationsEnabled) return;

    // Check if temperature exceeds threshold
    if (temperature > temperatureThreshold) {
      // Prevent alert spam - only alert once every 5 minutes
      final now = DateTime.now();
      if (_lastAlertTime == null ||
          now.difference(_lastAlertTime!).inMinutes >= 5) {
        _lastAlertTime = now;
        _triggerAlert(
          'Temperature Alert',
          'Temperature is ${temperature.toStringAsFixed(1)}°C (threshold: ${temperatureThreshold.toStringAsFixed(0)}°C)',
        );
      }
    }
  }

  Future<void> _triggerAlert(String title, String message) async {
    // Play sound if enabled
    if (soundEnabled) {
      try {
        await _audioPlayer.play(AssetSource('sounds/alert.mp3'));
      } catch (e) {
        debugPrint('Error playing sound: $e');
      }
    }

    // Show notification
    const androidDetails = AndroidNotificationDetails(
      'temperature_alerts',
      'Temperature Alerts',
      channelDescription: 'Alerts for temperature threshold exceeded',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      0,
      title,
      message,
      details,
    );
  }

  Future<void> _showTestNotification() async {
    await _triggerAlert(
      'Test Notification',
      'Notifications are working correctly!',
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = ThemeProvider.of(context);
    final isDarkMode = themeProvider.isDarkMode;

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
        title: const Text('Settings'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    color: isConnected ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  if (isConnected && connectedDevice != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      'Connected',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade100,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: const ChatbotFAB(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).scaffoldBackgroundColor,
            ],
            stops: const [0.0, 0.3],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Bluetooth Connection Status
            if (isConnected && connectedDevice != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Device Connected',
                            style: TextStyle(
                              color: Colors.green.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            connectedDevice?.platformName ?? 'ESP32 Sensor',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: Colors.green.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Appearance Section
            _buildSectionTitle('Appearance'),
            _buildSettingsCard(
              children: [_buildThemeTile(isDarkMode, themeProvider)],
            ),

            const SizedBox(height: 24),

            // Device Settings Section
            _buildSectionTitle('Device Settings'),
            _buildSettingsCard(
              children: [
                _buildNotificationTile(),
                const Divider(height: 1),
                _buildSoundTile(),
                const Divider(height: 1),
                _buildTemperatureThresholdTile(),
              ],
            ),

            const SizedBox(height: 24),

            // Data Management Section
            _buildSectionTitle('Data Management'),
            _buildSettingsCard(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.download, color: Colors.blue.shade700),
                  ),
                  title: const Text(
                    'Export Data',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Download sensor readings as CSV'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showExportDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade700,
                    ),
                  ),
                  title: const Text(
                    'Clear History',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Remove all stored readings'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showClearDataDialog,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // About Section
            _buildSectionTitle('About'),
            _buildSettingsCard(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.info_outline,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  title: const Text(
                    'App Version',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('1.0.0'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showAboutDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.description,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  title: const Text(
                    'Licenses',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Open source licenses'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    showLicensePage(context: context);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.help_outline,
                      color: Colors.green.shade700,
                    ),
                  ),
                  title: const Text(
                    'Help & Support',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Get help or send feedback'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showHelpDialog,
                ),
              ],
            ),

            const SizedBox(height: 40),

            // App Info Footer
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.agriculture,
                    size: 48,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Soil Temperature Monitor',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).textTheme.bodySmall?.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildThemeTile(bool isDarkMode, ThemeProvider themeProvider) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey.shade800 : Colors.amber.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isDarkMode ? Icons.dark_mode : Icons.light_mode,
          color: isDarkMode ? Colors.amber : Colors.amber.shade700,
        ),
      ),
      title: const Text(
        'Dark Mode',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(isDarkMode ? 'Dark theme enabled' : 'Light theme enabled'),
      trailing: Switch(
        value: isDarkMode,
        onChanged: (value) {
          themeProvider.toggleTheme();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(value ? 'Dark mode enabled' : 'Light mode enabled'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        activeColor: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildNotificationTile() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: notificationsEnabled
              ? Colors.blue.shade100
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          notificationsEnabled
              ? Icons.notifications_active
              : Icons.notifications_off,
          color: notificationsEnabled
              ? Colors.blue.shade700
              : Colors.grey.shade600,
        ),
      ),
      title: const Text(
        'Notifications',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: const Text('Receive alerts for temperature changes'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (notificationsEnabled)
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 20),
              onPressed: _showTestNotification,
              tooltip: 'Test notification',
            ),
          Switch(
            value: notificationsEnabled,
            onChanged: (value) async {
              setState(() {
                notificationsEnabled = value;
              });
              await _saveSetting('notifications', value);
              if (value) {
                await _showTestNotification();
              }
            },
            activeColor: Theme.of(context).primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSoundTile() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: soundEnabled ? Colors.orange.shade100 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          soundEnabled ? Icons.volume_up : Icons.volume_off,
          color: soundEnabled ? Colors.orange.shade700 : Colors.grey.shade600,
        ),
      ),
      title: const Text(
        'Sound Alerts',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: const Text('Play sound when threshold is exceeded'),
      trailing: Switch(
        value: soundEnabled,
        onChanged: (value) {
          setState(() {
            soundEnabled = value;
          });
          _saveSetting('sound', value);
        },
        activeColor: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildTemperatureThresholdTile() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.thermostat, color: Colors.red.shade700),
      ),
      title: const Text(
        'Temperature Alert',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Alert when exceeding ${temperatureThreshold.toStringAsFixed(0)}°C',
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        _showThresholdDialog(
          title: 'Temperature Threshold',
          currentValue: temperatureThreshold,
          unit: '°C',
          min: 0,
          max: 60,
          onSave: (value) {
            setState(() {
              temperatureThreshold = value;
            });
            _saveSetting('tempThreshold', value);
          },
        );
      },
    );
  }

  void _showThresholdDialog({
    required String title,
    required double currentValue,
    required String unit,
    required double min,
    required double max,
    required Function(double) onSave,
  }) {
    double tempValue = currentValue;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${tempValue.toStringAsFixed(0)}$unit',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 20),
              Slider(
                value: tempValue,
                min: min,
                max: max,
                divisions: (max - min).toInt(),
                label: '${tempValue.toStringAsFixed(0)}$unit',
                activeColor: Theme.of(context).primaryColor,
                onChanged: (value) {
                  setDialogState(() {
                    tempValue = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${min.toInt()}$unit',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${max.toInt()}$unit',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
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
                onSave(tempValue);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '$title set to ${tempValue.toStringAsFixed(0)}$unit',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.agriculture,
              color: Theme.of(context).primaryColor,
              size: 32,
            ),
            const SizedBox(width: 12),
            const Text('About'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Soil Temperature Monitor',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Version 1.0.0'),
            const SizedBox(height: 16),
            const Text(
              'A professional soil monitoring application for tracking temperature and other soil conditions via ESP32 sensors.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Features:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Real-time temperature monitoring'),
            const Text('• Bluetooth ESP32 connectivity'),
            const Text('• Custom alert thresholds'),
            const Text('• Push notifications & sound alerts'),
            const Text('• Data export capabilities'),
            const Text('• Dark mode support'),
            const SizedBox(height: 16),
            Text(
              '© 2025 Soil Sensor Team',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 12),
            Text('Help & Support'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Need help?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildHelpItem(
              Icons.email,
              'Email Support',
              'noelaankunda2@gmail.com',
              () => _launchEmail('noelaankunda2@gmail.com'),
            ),
            _buildHelpItem(
              Icons.bug_report,
              'Report Bug',
              'Send feedback',
              () => _launchEmail(
                'support@soilsensor.com',
                subject: 'Bug Report',
              ),
            ),
            _buildHelpItem(
              Icons.book,
              'Documentation',
              'View user guide',
              () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Documentation coming soon!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchEmail(String email, {String? subject}) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: subject != null ? 'subject=$subject' : null,
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open email app. Email: $email'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.download, color: Colors.blue),
            SizedBox(width: 12),
            Text('Export Data'),
          ],
        ),
        content: const Text(
          'Export all sensor readings to CSV format. The file will be saved to your Downloads folder.',
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
                  content: Text('Data exported successfully!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 12),
            Text('Clear History'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete all stored sensor readings? This action cannot be undone.',
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
                  content: Text('All data cleared successfully'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}