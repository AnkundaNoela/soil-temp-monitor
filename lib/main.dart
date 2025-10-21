import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/bluetooth_home.dart';
import 'screens/soil_data_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const SoilTempAppShell());
}

class SoilTempAppShell extends StatefulWidget {
  const SoilTempAppShell({super.key});

  @override
  State<SoilTempAppShell> createState() => _SoilTempAppShellState();
}

class _SoilTempAppShellState extends State<SoilTempAppShell> {
  ThemeMode _themeMode = ThemeMode.light;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  // Load theme preference from SharedPreferences
  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDarkMode = prefs.getBool('darkMode') ?? false;
      setState(() {
        _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading theme preference: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Update theme mode
  void _updateThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
    _saveThemePreference(mode == ThemeMode.dark);
  }

  // Save theme preference to SharedPreferences
  Future<void> _saveThemePreference(bool isDarkMode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('darkMode', isDarkMode);
    } catch (e) {
      debugPrint('Error saving theme preference: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show splash screen while loading
    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.green.shade700, Colors.green.shade400],
              ),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.agriculture, size: 80, color: Colors.white),
                  SizedBox(height: 24),
                  Text(
                    'Soil Sensor',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Temperature Monitor',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  SizedBox(height: 40),
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ThemeProvider(
      themeMode: _themeMode,
      onThemeChanged: _updateThemeMode,
      child: Builder(
        builder: (context) {
          return MaterialApp(
            title: 'Soil Sensor Dashboard',
            debugShowCheckedModeBanner: false,

            // Theme Configuration
            theme: AppTheme.lightTheme.copyWith(
              textTheme: GoogleFonts.interTextTheme(
                AppTheme.lightTheme.textTheme,
              ),
            ),
            darkTheme: AppTheme.darkTheme.copyWith(
              textTheme: GoogleFonts.interTextTheme(
                AppTheme.darkTheme.textTheme,
              ),
            ),
            themeMode: ThemeProvider.of(context).themeMode,

            // Routes
            initialRoute: '/',
            routes: {
              '/': (context) => const DashboardScreen(),
              '/device': (context) => const BluetoothHome(),
              '/soil': (context) => const SoilDataScreen(),
              '/settings': (context) => const SettingsScreen(),
            },

            // Unknown Route Handler
            onUnknownRoute: (settings) {
              return MaterialPageRoute(
                builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('Page Not Found')),
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Page Not Found',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The page "${settings.name}" does not exist.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushNamedAndRemoveUntil(
                              context,
                              '/',
                              (route) => false,
                            );
                          },
                          icon: const Icon(Icons.home),
                          label: const Text('Go to Dashboard'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// Theme Provider for managing theme state across the app
class ThemeProvider extends InheritedWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeChanged;

  const ThemeProvider({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required super.child,
  });

  static ThemeProvider of(BuildContext context) {
    final ThemeProvider? result = context
        .dependOnInheritedWidgetOfExactType<ThemeProvider>();
    assert(result != null, 'No ThemeProvider found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(ThemeProvider oldWidget) {
    return themeMode != oldWidget.themeMode;
  }

  // Helper method to toggle theme
  void toggleTheme() {
    final newMode = themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    onThemeChanged(newMode);
  }

  // Helper method to check if dark mode is active
  bool get isDarkMode => themeMode == ThemeMode.dark;
}
