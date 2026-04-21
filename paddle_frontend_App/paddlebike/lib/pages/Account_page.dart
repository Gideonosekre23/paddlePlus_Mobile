import 'package:flutter/material.dart';

import 'package:paddlebike/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddlebike/Apiendpoints/models/auth_models.dart';
import 'package:paddlebike/pages/Settings_page.dart';
import 'package:paddlebike/pages/login_page.dart';
import 'package:paddlebike/pages/Accountdetail_page.dart';
import 'package:paddlebike/Apiendpoints/apiservices/Image_utils.dart';

class Account_page extends StatefulWidget {
  final User? user;

  const Account_page({super.key, this.user});

  @override
  State<Account_page> createState() => _Account_pageState();
}

class _Account_pageState extends State<Account_page> {
  bool _isLoggingOut = false;

  final UserSessionManager _sessionManager = UserSessionManager();
  User? _currentUser;

  @override
  void initState() {
    super.initState();

    _currentUser = _sessionManager.currentUser ?? widget.user;

    _sessionManager.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    // ✅ Remove listener
    _sessionManager.removeListener(_onSessionChanged);
    super.dispose();
  }

  // ✅ ADD: Handle session changes
  void _onSessionChanged() {
    if (mounted && _sessionManager.currentUser != null) {
      setState(() {
        _currentUser = _sessionManager.currentUser;
      });
      print('🔄 Account page: User data updated from session manager');
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() {
      _isLoggingOut = true;
    });

    try {
      await _sessionManager.logout(notifyApi: true);

      print("✅ UserSessionManager logout completed");

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const login_page()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      print("❌ Logout error: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Use current user instead of widget.user
    final String username = _currentUser?.username ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          username,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ImageUtils.buildAvatar(
              profilePicture: _currentUser?.profilePicture,
              radius: 20,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    ImageUtils.buildAvatar(
                      profilePicture:
                          _currentUser?.profilePicture, // ✅ Use current user
                      radius: 50,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      username,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentUser?.email ?? 'No email', // ✅ Use current user
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.settings,
                  color: Color.fromARGB(255, 118, 172, 198),
                ),
                title: const Text(
                  "Settings",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const Settings_Page(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.person,
                  color: Color.fromARGB(255, 118, 172, 198),
                ),
                title: const Text(
                  "Account Details",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                onTap: () async {
                  // ✅ UPDATED: Navigate and refresh on return
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Accountdetail_page(
                        user: _currentUser!, // Pass current user
                      ),
                    ),
                  );

                  // ✅ Force refresh when returning
                  if (result == true && mounted) {
                    setState(() {
                      _currentUser =
                          _sessionManager.currentUser ?? _currentUser;
                    });
                    print(
                      '🔄 Returned from account details, refreshing user data',
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.payment,
                  color: Color.fromARGB(255, 118, 172, 198),
                ),
                title: const Text(
                  "Payment Methods",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pushNamed(context, '/payment-methods');
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.help,
                  color: Color.fromARGB(255, 118, 172, 198),
                ),
                title: const Text(
                  "Help & Support",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pushNamed(context, '/help');
                },
              ),
              const Divider(),
              ListTile(
                leading: _isLoggingOut
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                        ),
                      )
                    : const Icon(Icons.logout, color: Colors.red),
                title: Text(
                  _isLoggingOut ? "Logging out..." : "Logout",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
                onTap: _isLoggingOut ? null : _logout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
