import 'package:flutter/material.dart';
import 'package:reactive_theme/reactive_theme.dart';
import 'package:paddleapp/themes/app_themes.dart';
import 'package:paddleapp/constants/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Get the saved thememode
  final thememode = await ReactiveMode.getSavedThemeMode();

  runApp(MyApp(savedThemeMode: thememode));
}

class MyApp extends StatelessWidget {
  final ThemeMode? savedThemeMode;

  const MyApp({super.key, this.savedThemeMode});

  @override
  Widget build(BuildContext context) {
    return ReactiveThemer(
      // loads the saved thememode. If null then ThemeMode.system is used
      savedThemeMode: savedThemeMode,
      builder:
          (reactiveMode) => MaterialApp(
            title: 'PaddlePlus',
            debugShowCheckedModeBanner: false,
            // Pass the reactiveMode to the themeMode parameter
            themeMode: reactiveMode,
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            home: const Splash_screen(),
          ),
    );
  }
}
