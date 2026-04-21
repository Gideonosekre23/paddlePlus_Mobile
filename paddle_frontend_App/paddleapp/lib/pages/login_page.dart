import 'package:flutter/material.dart';
import 'package:paddleapp/constants/button.dart';
import 'package:paddleapp/constants/buttonimage.dart';
import 'package:paddleapp/constants/tesxtfileds.dart';
import 'package:paddleapp/pages/register_page.dart';
import 'package:paddleapp/constants/Navbar.dart';
import 'package:paddleapp/Apiendpoints/apiservices/auth_api_service.dart';
import 'package:paddleapp/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddleapp/Apiendpoints/models/auth_models.dart';
import 'package:paddleapp/Apiendpoints/models/api_response.dart';
import 'package:google_sign_in/google_sign_in.dart';

final GoogleSignIn _googleSignIn = GoogleSignIn();

class login_page extends StatefulWidget {
  const login_page({super.key});

  @override
  State<login_page> createState() => _login_pageState();
}

class _login_pageState extends State<login_page> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  // Get the singleton instance of UserSessionManager
  final UserSessionManager _sessionManager = UserSessionManager();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: SafeArea(
          child: Column(
            children: [
              // Branded gradient header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF5B9BB5), Color(0xFF76ACC6), Color(0xFF9DCCE0)],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.pedal_bike_rounded, size: 56, color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'PaddlePlus',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your ride, your way',
                      style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.85)),
                    ),
                  ],
                ),
              ),
              Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 28),
                  const Text(
                    'SIGN IN',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 25),

                  // Email Field
                  TextFieldWidget(
                    label: 'Email',
                    hintText: 'Enter your email',
                    icon: Icons.email,
                    controller: emailController,
                  ),

                  const SizedBox(height: 25),

                  // Password Field with Visibility Toggle
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Password',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          hintText: 'Enter your password',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color.fromARGB(255, 118, 172, 198),
                              width: 2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ],
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Forgot Password'),
                              content: const Text(
                                'Password reset is coming soon. Please contact support if you need immediate assistance.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('Forgot Password?'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 25),

                  // Login Button with Loading State
                  _isLoading
                      ? Column(
                        children: [
                          const CircularProgressIndicator(
                            color: Color.fromARGB(255, 118, 172, 198),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Signing in and connecting...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      )
                      : ButtonWidget(text: "Sign In", onPressed: signInUser),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?"),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RegisterPage(),
                            ),
                          );
                        },
                        child: const Text("Sign Up"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 50),

                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Text("Or Sign In With")],
                  ),

                  const SizedBox(height: 30),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ButtonImage(
                        imagePath: "assets/images/apple.png",
                        onPressed: () => externalLogin('apple'),
                        width: 30,
                        height: 30,
                      ),
                      const SizedBox(width: 20),
                      ButtonImage(
                        imagePath: 'assets/images/google.png',
                        onPressed: () => externalLogin('google'),
                        width: 30,
                        height: 30,
                      ),
                    ],
                  ),

                  const SizedBox(height: 50),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> signInUser() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    if (email.isEmpty) {
      _showErrorMessage("Please enter your email");
      return;
    }
    if (password.isEmpty) {
      _showErrorMessage("Please enter your password");
      return;
    }
    if (!_isValidEmail(email)) {
      _showErrorMessage("Please enter a valid email");
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final loginRequest = LoginRequest(email: email, password: password);
      debugPrint('🔄 Attempting login for: $email');
      final ApiResponse<LoginResponse> response = await AuthApiService.login(
        loginRequest,
      );

      if (response.success && response.data != null) {
        debugPrint('✅ Login API successful');
        await _sessionManager.completeLogin(response.data!);
        debugPrint('✅ Login process completed by UserSessionManager');

        if (_sessionManager.isVerified) {
          _showSuccessMessage(
            "Login successful! ${_sessionManager.isMainWSConnected ? 'Connected to notifications.' : 'Notification service connecting...'}",
          );
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => Navbar(user: response.data!.user),
              ),
              (route) => false,
            );
          }
        } else {
          _showWarningMessage(
            "Login successful, but account verification is pending. Please complete verification.",
          );
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => Navbar(user: response.data!.user),
              ),
              (route) => false,
            );
          }
        }
      } else {
        _showErrorMessage(response.error ?? "Login failed. Please try again.");
      }
    } catch (e) {
      _showErrorMessage("An unexpected error occurred. Please try again.");
      debugPrint('❌ Login error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // This method remains a placeholder for social login
  Future<void> externalLogin(String provider) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      if (provider == 'google') {
        await _handleGoogleSignIn();
      } else {
        _showInfoMessage("$provider login coming soon!");
      }
    } catch (e) {
      _showErrorMessage("Social login failed. Please try again.");
      debugPrint(' Social login error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      // Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in
        return;
      }

      // Get authentication details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null) {
        throw Exception('Failed to get Google ID token');
      }

      // Send to your backend
      await _loginWithSocialToken('google', googleAuth.idToken!);
    } catch (e) {
      debugPrint('Google Sign In Error: $e');
      rethrow;
    }
  }

  Future<void> _loginWithSocialToken(String provider, String token) async {
    try {
      // Create social login request
      final socialLoginRequest = {
        'provider': provider,
        'provider_token': token,
      };

      debugPrint('🔄 Attempting social login with $provider');
      debugPrint('🔍 Request payload: $socialLoginRequest'); // ✅ Add this

      final ApiResponse<LoginResponse> response =
          await AuthApiService.socialLogin(socialLoginRequest);

      debugPrint('🔍 Response success: ${response.success}'); // ✅ Add this
      debugPrint('🔍 Response data: ${response.data}'); // ✅ Add this
      debugPrint('🔍 Response error: ${response.error}'); // ✅ Add this

      if (response.success && response.data != null) {
        debugPrint('✅ Social login successful');
        await _sessionManager.completeLogin(response.data!);
        _showSuccessMessage("Welcome! Signed in with Google.");

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => Navbar(user: response.data!.user),
            ),
            (route) => false,
          );
        }
      } else {
        debugPrint(
          '❌ Social login failed - showing response error',
        ); // ✅ Add this
        _showErrorMessage(response.error ?? "Social login failed.");
      }
    } catch (e) {
      debugPrint('❌ Social login exception: $e'); // ✅ Improved logging
      _showErrorMessage(
        "An error occurred during social login: $e",
      ); // ✅ Show actual error
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showWarningMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showInfoMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
}
