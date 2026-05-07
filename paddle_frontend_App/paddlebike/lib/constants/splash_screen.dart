import 'package:animated_splash_screen/animated_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:paddlebike/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddlebike/pages/login_page.dart';
import 'package:paddlebike/constants/Navbar.dart';

class Splash_screen extends StatefulWidget {
  const Splash_screen({super.key});

  @override
  State<Splash_screen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<Splash_screen>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSplashScreen.withScreenFunction(
      splash: Center(
        child: Lottie.asset(
          'assets/animations/Animation1.json',
          controller: _controller,
          width: 200,
          height: 200,
          fit: BoxFit.contain,
          onLoaded: (composition) {
            _controller
              ..duration = composition.duration
              ..repeat();
          },
        ),
      ),
      screenFunction: () async {
        final sessionManager = UserSessionManager();
        await sessionManager.loadSession();

        if (sessionManager.isAuthenticated && sessionManager.currentUser != null) {
          return const Navbar();
        }
        return const login_page();
      },
      duration: 0,
      splashIconSize: 250,
      backgroundColor: const Color.fromARGB(210, 9, 255, 116),
      splashTransition: SplashTransition.fadeTransition,
    );
  }
}
