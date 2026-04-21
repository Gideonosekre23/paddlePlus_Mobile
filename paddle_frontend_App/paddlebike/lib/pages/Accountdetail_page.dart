import 'package:flutter/material.dart';
import 'package:paddlebike/Apiendpoints/models/auth_models.dart';
import 'package:paddlebike/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddlebike/pages/EditProfilePage.dart';
import 'package:paddlebike/Apiendpoints/apiservices/Image_utils.dart';

class Accountdetail_page extends StatefulWidget {
  final User user;

  const Accountdetail_page({super.key, required this.user});

  @override
  State<Accountdetail_page> createState() => _Accountdetail_pageState();
}

class _Accountdetail_pageState extends State<Accountdetail_page> {
  // ✅ ADD: SessionManager and current user tracking
  final UserSessionManager _sessionManager = UserSessionManager();
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    // ✅ Initialize with current user from session manager
    _currentUser = _sessionManager.currentUser ?? widget.user;

    // ✅ Listen to session manager changes
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
      print('🔄 Account details: User data updated from session manager');
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Use current user instead of widget.user
    final String username = _currentUser?.username ?? 'Unknown';
    final String displayName = _currentUser?.username ?? 'Unknown';
    final String email = _currentUser?.email ?? 'No email';
    final String phone = _currentUser?.phoneNumber ?? "Not provided";

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Account Details',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () =>
              Navigator.pop(context, true), // ✅ Return true to trigger refresh
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header
            Center(
              child: Column(
                children: [
                  ImageUtils.buildAvatar(
                    profilePicture:
                        _currentUser?.profilePicture, // ✅ Use current user
                    radius: 60,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@$username',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: ${_currentUser?.verificationStatus ?? 'Unknown'}', // ✅ Use current user
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Personal Information Section
            const Text(
              'Personal Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 118, 172, 198),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildInfoRow('Username', username),
                    const Divider(),
                    _buildInfoRow('Email', email),
                    const Divider(),
                    _buildInfoRow('Phone', phone),
                    if (_currentUser?.address != null &&
                        _currentUser!.address!.isNotEmpty) ...[
                      const Divider(),
                      _buildInfoRow('Address', _currentUser!.address!),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            Center(
              child: ElevatedButton.icon(
                icon: Icon(Icons.edit),
                label: Text("Edit Profile"),
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const EditProfilePage(), // Remove user parameter if it doesn't exist
                    ),
                  );

                  // ✅ Force refresh when returning from edit page
                  if (result == true && mounted) {
                    setState(() {
                      _currentUser =
                          _sessionManager.currentUser ?? _currentUser;
                    });
                    print('🔄 Returned from edit page, forcing rebuild');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 118, 172, 198),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
      ],
    );
  }
}
