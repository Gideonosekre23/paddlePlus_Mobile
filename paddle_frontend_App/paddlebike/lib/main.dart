import 'package:flutter/material.dart';
import 'package:reactive_theme/reactive_theme.dart';
import 'package:paddlebike/themes/app_themes.dart';
import 'package:paddlebike/constants/splash_screen.dart';
import 'package:paddlebike/Apiendpoints/apiservices/user_session_manager.dart';

// ✅ Global navigator key for notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final userSession = UserSessionManager();
  userSession.initObserver();
  userSession.initializeNotificationHandler();

  final thememode = await ReactiveMode.getSavedThemeMode();
  runApp(MyApp(savedThemeMode: thememode));
}

class MyApp extends StatelessWidget {
  final ThemeMode? savedThemeMode;

  const MyApp({super.key, this.savedThemeMode});

  @override
  Widget build(BuildContext context) {
    return ReactiveThemer(
      savedThemeMode: savedThemeMode,
      builder: (reactiveMode) => MaterialApp(
        title: 'PaddlePlus',
        debugShowCheckedModeBanner: false,
        themeMode: reactiveMode,
        theme: AppThemes.lightTheme,
        darkTheme: AppThemes.darkTheme,
        // ✅ Use global navigator key
        navigatorKey: navigatorKey,
        home: const AppContextProvider(),
      ),
    );
  }
}

class AppContextProvider extends StatefulWidget {
  const AppContextProvider({super.key});

  @override
  State<AppContextProvider> createState() => _AppContextProviderState();
}

class _AppContextProviderState extends State<AppContextProvider> {
  @override
  void initState() {
    super.initState();
    // Set context using the global navigator key
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        UserSessionManager().setAppContext(navigatorKey.currentContext!);
        print("📱 App context set using global navigator key!");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Splash_screen();
  }
}
