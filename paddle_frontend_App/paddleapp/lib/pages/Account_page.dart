import 'package:flutter/material.dart';
import 'package:paddleapp/Apiendpoints/apiservices/auth_api_service.dart';
import 'package:paddleapp/Apiendpoints/apiservices/token_storage_service.dart';
import 'package:paddleapp/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddleapp/Apiendpoints/models/auth_models.dart';
import 'package:paddleapp/pages/Settings_page.dart';
import 'package:paddleapp/pages/login_page.dart';
import 'package:paddleapp/pages/Accountdetail_page.dart';
import 'package:paddleapp/Apiendpoints/apiservices/Image_utils.dart';
import 'package:paddleapp/pages/payment_setup_page.dart';
import 'package:paddleapp/pages/notification_history_page.dart';

class Account_page extends StatefulWidget {
  final User user;

  const Account_page({super.key, required this.user});

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
    NotificationStore.instance.addListener(_onNotifChanged);
    _refreshUser();
  }

  void _onNotifChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshUser() async {
    final resp = await AuthApiService.getProfile();
    if (resp.success && resp.data != null && mounted) {
      await _sessionManager.updateUser(resp.data!);
    }
  }

  @override
  void dispose() {
    _sessionManager.removeListener(_onSessionChanged);
    NotificationStore.instance.removeListener(_onNotifChanged);
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

    final refreshToken = await TokenStorageService.getRefreshToken();
    bool logoutSuccess = false;

    if (refreshToken != null) {
      final response = await AuthApiService.logout(refreshToken);

      if (response.success) {
        print("Logout successful from API.");
        logoutSuccess = true;
      } else {
        print("Logout API call failed: ${response.error}");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response.error ??
                    'Logout failed on server. Logging out locally.',
              ),
            ),
          );
        }
      }
    } else {
      print("No refresh token found for logout. Proceeding with local logout.");
      logoutSuccess = true;
    }

    await TokenStorageService.clearTokens();
    print("Local tokens cleared.");

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const login_page()),
        (Route<dynamic> route) => false,
      );
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
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined, color: Colors.white),
                if (NotificationStore.instance.unreadCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        NotificationStore.instance.unreadCount > 9
                            ? '9+'
                            : '${NotificationStore.instance.unreadCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 9),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationHistoryPage()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ImageUtils.buildAvatar(
              profilePicture:
                  _currentUser?.profilePicture, // ✅ Use current user
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
                      builder:
                          (context) => Accountdetail_page(
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PaymentSetupPage(),
                    ),
                  );
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
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Help & Support'),
                      content: const Text(
                        'For support, please contact us at support@paddleplus.app\n\nCommon issues:\n• Bike not unlocking: Check the unlock code in the chat\n• Payment issues: Contact us with your trip ID\n• App problems: Restart the app and try again',
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
              ),
              const Divider(),
              ListTile(
                leading:
                    _isLoggingOut
                        ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.red,
                            ),
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
