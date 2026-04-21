import 'package:animated_splash_screen/animated_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:paddleapp/Apiendpoints/apiservices/base_api_service.dart';
import 'package:paddleapp/pages/login_page.dart';
import 'package:paddleapp/constants/navbar.dart';
import 'package:paddleapp/Apiendpoints/apiservices/token_storage_service.dart';
import 'package:paddleapp/Apiendpoints/models/auth_models.dart';
import 'package:paddleapp/Apiendpoints/apiservices/user_session_manager.dart';

class Splash_screen extends StatefulWidget {
  const Splash_screen({super.key});

  @override
  State<Splash_screen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<Splash_screen>
    with TickerProviderStateMixin {
  late AnimationController _lottieController;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _lottieController.dispose();
    super.dispose();
  }

  Future<bool> _validateAndRefreshTokensIfNeeded() async {
    print("Splash_screen: Validating tokens...");
    String? accessToken = await TokenStorageService.getAccessToken();

    if (accessToken == null) {
      print("Splash_screen: No access token found.");
      UserSessionManager().logout();
      return false;
    }

    try {
      bool isTokenExpired = JwtDecoder.isExpired(accessToken);

      if (isTokenExpired) {
        print("Splash_screen: Access token is expired. Attempting refresh...");
        bool refreshedSuccessfully = await BaseApiService.refreshToken();
        if (refreshedSuccessfully) {
          print("Splash_screen: Token refresh successful.");
          String? newAccessToken = await TokenStorageService.getAccessToken();
          if (newAccessToken != null && !JwtDecoder.isExpired(newAccessToken)) {
            print("Splash_screen: New access token is valid.");
            return true;
          } else {
            print(
              "Splash_screen: New access token is null or still expired after refresh.",
            );
            await TokenStorageService.clearTokens();
            UserSessionManager().logout();
            return false;
          }
        } else {
          print("Splash_screen: Token refresh failed. Clearing tokens.");
          await TokenStorageService.clearTokens();
          UserSessionManager().logout();
          return false;
        }
      } else {
        print("Splash_screen: Access token is valid (not expired).");
        return true; // Authenticated
      }
    } catch (e) {
      print(
        "Splash_screen: Error decoding or validating token: $e. Clearing tokens.",
      );
      await TokenStorageService.clearTokens();
      UserSessionManager().logout();
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSplashScreen.withScreenFunction(
      splash: Center(
        child: Lottie.asset(
          'assets/animations/Animation1.json',
          controller: _lottieController,
          width: 200,
          height: 200,
          fit: BoxFit.contain,
          onLoaded: (composition) {
            _lottieController
              ..duration = composition.duration
              ..repeat();
          },
        ),
      ),
      screenFunction: () async {
        print(
          "Splash_screen (screenFunction): Starting authentication check...",
        );
        bool tokensAreValid = await _validateAndRefreshTokensIfNeeded();

        if (tokensAreValid) {
          User? currentUser = UserSessionManager().currentUser;

          if (currentUser != null) {
            print(
              "Splash_screen (screenFunction): Tokens valid and user in session. Returning Navbar with user: ${currentUser.username}.",
            );

            return Navbar(user: currentUser);
          } else {
            print(
              "Splash_screen (screenFunction): Tokens valid, but no user in session. Returning LoginPage.",
            );

            return const login_page();
          }
        } else {
          print(
            "Splash_screen (screenFunction): Tokens invalid or not found. Returning LoginPage.",
          );
          return const login_page();
        }
      },
      duration: 0,
      splashIconSize: 250,
      backgroundColor: const Color.fromARGB(210, 9, 255, 116),
      splashTransition: SplashTransition.fadeTransition,
    );
  }
}
