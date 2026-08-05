import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class ThemeProvider with ChangeNotifier {
  static const String _themeKey = 'theme_preference';

  ThemeMode _themeMode = ThemeMode.dark; // Default to dark theme
  final Color _accentColor = const Color(0xFFC0E000); // Yellowish Green
  final Color _backgroundBaseColor = const Color(0xFF0F1A12); // Very dark green/black

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  Color get backgroundBaseColor => _backgroundBaseColor;

  ThemeProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final themeIndex = prefs.getInt(_themeKey);
      if (themeIndex != null) {
        _themeMode = ThemeMode.values[themeIndex];
        notifyListeners();
      }
      // If no saved preference, keep default (dark)
    } catch (e) {
      debugPrint('Error loading theme settings: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeKey, mode.index);
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }

  ThemeData buildLightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _accentColor,
      brightness: Brightness.light,
      primary: _accentColor,
      surface: const Color(0xFFFFFFFF),
      onSurface: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFFF0F0F0),
    );

    return _buildTheme(colorScheme, Brightness.light);
  }

  ThemeData buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _accentColor,
      brightness: Brightness.dark,
      primary: _accentColor,
      surface: const Color(0xFF151B17),
      onSurface: const Color(0xFFFFFFFF),
      surfaceContainerHighest: const Color(0xFF1E2521),
    );

    return _buildTheme(colorScheme, Brightness.dark);
  }

  ThemeData _buildTheme(ColorScheme colorScheme, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: GoogleFonts.poppinsTextTheme(
        brightness == Brightness.light ? ThemeData.light().textTheme : ThemeData.dark().textTheme
      ).copyWith(
        bodyLarge: GoogleFonts.poppins(color: colorScheme.onSurface),
        bodyMedium: GoogleFonts.poppins(color: colorScheme.onSurface),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: GoogleFonts.poppins(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _accentColor,
        foregroundColor: Colors.black87,
      ),
    );
  }
}
