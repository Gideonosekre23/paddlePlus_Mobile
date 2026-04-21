import 'package:flutter/material.dart';

class AppThemes {
  // App Colors
  static const primaryColor = Color.fromARGB(255, 118, 172, 198);
  static const secondaryColor = Color.fromARGB(255, 76, 146, 120);

  // Light Theme
  static final lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primarySwatch: MaterialColor(primaryColor.value, <int, Color>{
      50: primaryColor.withValues(alpha: 0.1),
      100: primaryColor.withValues(alpha: 0.2),
      200: primaryColor.withValues(alpha: 0.3),
      300: primaryColor.withValues(alpha: 0.4),
      400: primaryColor.withValues(alpha: 0.5),
      500: primaryColor,
      600: primaryColor.withValues(alpha: 0.7),
      700: primaryColor.withValues(alpha: 0.8),
      800: primaryColor.withValues(alpha: 0.9),
      900: primaryColor,
    }),
    primaryColor: primaryColor,
    scaffoldBackgroundColor: const Color.fromARGB(255, 233, 225, 225),
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 2,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: secondaryColor,
      indicatorColor: primaryColor.withValues(alpha: 0.3),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    ),
  );

  // Dark Theme
  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primarySwatch: MaterialColor(primaryColor.value, <int, Color>{
      50: const Color.fromARGB(255, 10, 29, 38).withValues(alpha: 0.1),
      100: const Color.fromARGB(255, 18, 41, 53).withValues(alpha: 0.2),
      200: const Color.fromARGB(255, 9, 32, 44).withValues(alpha: 0.3),
      300: primaryColor.withValues(alpha: 0.4),
      400: primaryColor.withValues(alpha: 0.5),
      500: primaryColor,
      600: primaryColor.withValues(alpha: 0.7),
      700: primaryColor.withValues(alpha: 0.8),
      800: primaryColor.withValues(alpha: 0.9),
      900: primaryColor,
    }),
    primaryColor: primaryColor,
    scaffoldBackgroundColor: const Color.fromARGB(255, 93, 71, 71),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color.fromARGB(255, 43, 74, 68),
      foregroundColor: Colors.white,
      elevation: 2,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E1E),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color.fromARGB(255, 43, 74, 68),
      indicatorColor: primaryColor.withValues(alpha: 0.3),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    ),
  );
}
