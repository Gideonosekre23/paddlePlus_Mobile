import 'package:flutter/material.dart';
import 'package:paddleapp/Apiendpoints/apiservices/auth_api_service.dart';
import 'package:paddleapp/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddleapp/Apiendpoints/models/api_response.dart';
import 'package:paddleapp/pages/register_page.dart';
import 'package:reactive_theme/reactive_theme.dart';
import 'package:paddleapp/pages/EditProfilePage.dart';
import 'package:paddleapp/pages/payment_setup_page.dart';
import 'package:paddleapp/pages/change_password_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings_Page extends StatefulWidget {
  const Settings_Page({super.key});

  @override
  State<Settings_Page> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<Settings_Page> {
  bool notificationsEnabled = true;
  String distanceUnit = 'Kilometers';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      distanceUnit = prefs.getString('distance_unit') ?? 'Kilometers';
    });
  }

  Future<void> _saveNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
  }

  Future<void> _saveDistanceUnit(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('distance_unit', value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Account Settings Section
              Text(
                "Account Settings",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: const Text("Edit Profile"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const EditProfilePage(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock),
                      title: const Text("Change Password"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChangePasswordPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // App Settings Section
              Text(
                "App Settings",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text("Push Notifications"),
                      subtitle: const Text(
                        "Receive alerts about rides and promotions",
                      ),
                      value: notificationsEnabled,
                      onChanged: (value) {
                        setState(() {
                          notificationsEnabled = value;
                        });
                        _saveNotifications(value);
                      },
                    ),
                    const Divider(height: 1),

                    // Simple Theme Toggle using ReactiveSwitch
                    ListTile(
                      leading: Icon(
                        ReactiveMode.isDarkMode(context)
                            ? Icons.dark_mode
                            : Icons.light_mode,
                      ),
                      title: const Text("Dark Mode"),
                      subtitle: Text(
                        ReactiveMode.isDarkMode(context)
                            ? "Dark theme enabled"
                            : "Light theme enabled",
                      ),
                      trailing: ReactiveSwitch(
                        darkmodeIcon: const Icon(Icons.dark_mode),
                        lightModeIcon: const Icon(Icons.light_mode),
                        activeCol: Theme.of(context).primaryColor,
                        inactiveIconColor: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              const SizedBox(height: 24),

              // Manual Theme Selection
              const SizedBox(height: 24),

              // Preferences Section
              Text(
                "Preferences",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text("Distance Unit"),
                      subtitle: Text(distanceUnit),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _showDistanceUnitPicker(context);
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.payment),
                      title: const Text("Payment Methods"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PaymentSetupPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Support & Legal Section
              Text(
                "Support & Legal",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: const Text("Help Center"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Help Center'),
                            content: const SingleChildScrollView(
                              child: Text(
                                'Need help? Here\'s how to reach us:\n\n'
                                '📧 Email: support@paddleplus.app\n\n'
                                'Common issues:\n'
                                '• Bike not unlocking: Check the unlock code in the chat\n'
                                '• Payment issues: Contact us with your trip ID\n'
                                '• App problems: Restart the app and try again\n'
                                '• Forgot password: Use the "Forgot Password" link on the login screen\n\n'
                                'Our team responds within 24 hours.',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.description),
                      title: const Text("Terms of Service"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Terms of Service'),
                            content: const SingleChildScrollView(
                              child: Text(
                                'PaddlePlus Terms of Service\n\n'
                                '1. Acceptance of Terms\n'
                                'By using PaddlePlus, you agree to these terms.\n\n'
                                '2. Use of Service\n'
                                'You must be 18+ with a valid ID and payment method to rent bikes.\n\n'
                                '3. Payments\n'
                                'Your card is charged at the end of each trip based on actual distance and time.\n\n'
                                '4. Safety\n'
                                'You agree to follow all local traffic laws and wear appropriate safety gear.\n\n'
                                '5. Liability\n'
                                'PaddlePlus is not liable for accidents or damages during a rental.\n\n'
                                '6. Account\n'
                                'Keep your login credentials secure. You are responsible for all activity on your account.\n\n'
                                'For the full terms, contact support@paddleplus.app.',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip),
                      title: const Text("Privacy Policy"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Privacy Policy'),
                            content: const SingleChildScrollView(
                              child: Text(
                                'PaddlePlus Privacy Policy\n\n'
                                '1. Data We Collect\n'
                                'We collect your name, email, phone number, location, and payment information to operate the service.\n\n'
                                '2. How We Use It\n'
                                'Your data is used to process rides, handle payments, and improve the app. We never sell your data.\n\n'
                                '3. Location\n'
                                'Location data is used during active rides only and is not stored long-term.\n\n'
                                '4. Payments\n'
                                'Payment information is stored securely by Stripe. PaddlePlus never stores your raw card details.\n\n'
                                '5. Your Rights\n'
                                'You can request deletion of your account and data at any time from Account Settings.\n\n'
                                'For questions, contact support@paddleplus.app.',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text("About"),
                      subtitle: const Text("Version 1.0.0"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'PaddlePlus',
                          applicationVersion: '1.0.0',
                          applicationIcon: const Icon(
                            Icons.directions_bike,
                            size: 48,
                            color: Color(0xFF76ACC6),
                          ),
                          applicationLegalese: '© 2025 PaddlePlus. All rights reserved.',
                          children: const [
                            SizedBox(height: 12),
                            Text(
                              'PaddlePlus connects riders with bike owners for convenient, affordable bike sharing.',
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Danger Zone
              const Text(
                "Danger Zone",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    "Delete Account",
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    _showDeleteAccountConfirmation(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Manual theme selector using custom logic

  // Custom method to change theme (you might need to implement this based on the actual package API)

  void _showDistanceUnitPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Distance Unit',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Kilometers'),
                  selected: distanceUnit == 'Kilometers',
                  onTap: () {
                    setState(() {
                      distanceUnit = 'Kilometers';
                    });
                    _saveDistanceUnit('Kilometers');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Miles'),
                  selected: distanceUnit == 'Miles',
                  onTap: () {
                    setState(() {
                      distanceUnit = 'Miles';
                    });
                    _saveDistanceUnit('Miles');
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteAccountConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
            'Are you sure you want to delete your account? This action cannot be undone and will permanently remove all your data.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // ✅ REPLACE THIS SECTION - Implement actual account deletion
                Navigator.of(context).pop(); // Close dialog first
                await _deleteAccount(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    // Save context reference
    final navigator = Navigator.of(context);
    final scaffold = ScaffoldMessenger.of(context);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Color.fromARGB(255, 118, 172, 198),
              ),
              SizedBox(height: 16),
              Text('Deleting account...'),
            ],
          ),
        );
      },
    );

    try {
      print('🗑️ Starting account deletion...');

      final UserSessionManager sessionManager = UserSessionManager();
      final ApiResponse<void> response = await AuthApiService.deleteProfile();

      print(
        '📨 Delete response: Success=${response.success}, StatusCode=${response.statusCode}',
      );

      // Close loading dialog
      navigator.pop();

      // ✅ Check for success OR 204 status code
      if (response.success || response.statusCode == 204) {
        print('✅ Account deletion successful! Moving to register page...');

        // Show success message
        scaffold.showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 16),
                Text('Account deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );

        // Clear session
        await sessionManager.logout(notifyApi: false);

        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RegisterPage()),
          (route) => false,
        );
      } else {
        print('❌ Account deletion failed: ${response.error}');
        scaffold.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 16),
                Text(response.error ?? 'Failed to delete account'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Exception during account deletion: $e');

      try {
        navigator.pop(); // Close loading dialog
      } catch (_) {}

      try {
        scaffold.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 16),
                Text('Error: ${e.toString()}'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (_) {}
    }
  }
}
