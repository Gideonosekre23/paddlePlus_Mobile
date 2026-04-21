import 'package:flutter/material.dart';
import 'package:paddlebike/Apiendpoints/apiservices/auth_api_service.dart';
import 'package:paddlebike/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddlebike/Apiendpoints/models/api_response.dart';
import 'package:paddlebike/pages/register_page.dart';
import 'package:reactive_theme/reactive_theme.dart';
import 'package:paddlebike/pages/EditProfilePage.dart';

class Settings_Page extends StatefulWidget {
  const Settings_Page({super.key});

  @override
  State<Settings_Page> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<Settings_Page> {
  bool notificationsEnabled = true;
  String distanceUnit = 'Kilometers';

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
                        // Navigate to change password page
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
                      title: const Text("Payment Methods"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        // todo payment methods
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
                        // Navigate to help center
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.description),
                      title: const Text("Terms of Service"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        // Show terms of service
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip),
                      title: const Text("Privacy Policy"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        // Show privacy policy
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text("About"),
                      subtitle: const Text("Version 1.0.0"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        // Show about dialog
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
