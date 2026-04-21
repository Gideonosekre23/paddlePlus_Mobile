import 'package:flutter/material.dart';
import 'package:paddleapp/constants/button.dart';
import 'package:paddleapp/constants/buttonimage.dart';
import 'package:paddleapp/constants/tesxtfileds.dart';
import 'package:paddleapp/pages/login_page.dart';
import 'package:paddleapp/pages/register2_page.dart';
import '../Apiendpoints/apiservices/auth_api_service.dart';
import '../Apiendpoints/models/auth_models.dart';
import 'package:google_sign_in/google_sign_in.dart';

final GoogleSignIn _googleSignIn = GoogleSignIn();

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordObscured = true; // State for password field
  bool _isConfirmPasswordObscured = true; // State for confirm password field

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose(); // Dispose new controller
    super.dispose();
  }

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // Basic validation
    if (email.isEmpty ||
        username.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please fill all fields')));
      return;
    }

    // Password match validation
    if (password != confirmPassword) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Passwords do not match')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final request = RegisterPhase1Request(
        email: email,
        username: username,
        password: password,
      );

      final response = await AuthApiService.registerPhase1(request);

      // Check if the widget is still mounted before using context or setting state.
      if (!mounted) return;

      if (response.success && response.data != null) {
        // Navigate to Register2Page with token
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => Register2Page(registrationToken: response.data!.token),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.error ?? 'Registration failed')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _registerWithSocialToken(String provider, String token) async {
    try {
      final socialRequest = {'provider': provider, 'provider_token': token};

      final response = await AuthApiService.socialRegister(socialRequest);

      if (!mounted) return;

      if (response.success && response.data != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => Register2Page(registrationToken: response.data!.token),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.error ?? 'Registration failed')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Social registration failed: $e')));
    }
  }

  void _socialSignUp(String provider) {
    if (!mounted) return;

    if (provider == 'google') {
      _handleGoogleSignUp();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$provider sign up coming soon!')));
    }
  }

  Future<void> _handleGoogleSignUp() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null) {
        throw Exception('Failed to get Google ID token');
      }

      await _registerWithSocialToken('google', googleAuth.idToken!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Google sign up failed: $e')));
    }
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
                      'Create your account',
                      style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.85)),
                    ),
                  ],
                ),
              ),
              Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
              children: [
                const SizedBox(height: 20),
                const Text(
                  'CREATE ACCOUNT',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 25),
                // Username
                TextFieldWidget(
                  label: 'Username',
                  hintText: 'Choose a username',
                  icon: Icons.person,
                  controller: _usernameController,
                ),
                const SizedBox(height: 20),
                // Email
                TextFieldWidget(
                  label: 'Email',
                  hintText: 'Enter your email',
                  icon: Icons.email,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                // Password
                TextFieldWidget(
                  label: 'Password',
                  hintText: 'Enter your password',
                  icon: Icons.lock_outline,
                  controller: _passwordController,
                  obscureText: _isPasswordObscured,
                  suffixIcon: IconButton(
                    // This is the Widget passed to suffixIcon
                    icon: Icon(
                      _isPasswordObscured
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordObscured = !_isPasswordObscured;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 20),
                // Confirm Password
                TextFieldWidget(
                  label: 'Confirm Password',
                  hintText: 'Re-enter your password',
                  icon: Icons.lock,
                  controller: _confirmPasswordController,
                  obscureText: _isConfirmPasswordObscured,
                  suffixIcon: IconButton(
                    // This is the Widget passed to suffixIcon
                    icon: Icon(
                      _isConfirmPasswordObscured
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmPasswordObscured =
                            !_isConfirmPasswordObscured;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 30),
                // Register button
                _isLoading
                    ? const CircularProgressIndicator()
                    : ButtonWidget(text: 'Sign Up', onPressed: _register),
                const SizedBox(height: 20),
                // Sign in link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account?'),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          // Use pushReplacement if you don't want to go back to register
                          context,
                          MaterialPageRoute(builder: (_) => const login_page()),
                        );
                      },
                      child: const Text('Sign In'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Divider
                Row(
                  children: const [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text('Or Sign Up With'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                // Social buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ButtonImage(
                      imagePath: "assets/images/apple.png",
                      onPressed: () => _socialSignUp('apple'),
                      width: 30,
                      height: 30,
                    ),
                    const SizedBox(width: 20),
                    ButtonImage(
                      imagePath: 'assets/images/google.png',
                      onPressed: () => _socialSignUp('google'),
                      width: 30,
                      height: 30,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
  );
  }
}
