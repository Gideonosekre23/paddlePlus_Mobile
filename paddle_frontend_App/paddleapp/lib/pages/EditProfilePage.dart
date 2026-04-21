import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:paddleapp/constants/button.dart';
import 'package:paddleapp/constants/tesxtfileds.dart';
import 'package:paddleapp/Apiendpoints/apiservices/auth_api_service.dart';
import 'package:paddleapp/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddleapp/Apiendpoints/models/auth_models.dart';
import 'package:paddleapp/Apiendpoints/models/api_response.dart';
import 'package:paddleapp/Apiendpoints/apiservices/Image_utils.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController addressController = TextEditingController();

  // Session manager and services
  final UserSessionManager _sessionManager = UserSessionManager();
  final ImagePicker _imagePicker = ImagePicker();

  // State management
  bool _isLoading = false;
  String? _profileImagePath;
  String? _profileImageBase64;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    addressController.dispose();
    super.dispose();
  }

  // Load current user data from session
  void _loadUserData() {
    final user = _sessionManager.currentUser;
    print("🔍 Loading user data: $user");
    print("🖼️ Current profile picture URL: ${user?.profilePicture}");
    if (user != null) {
      setState(() {
        usernameController.text = user.username;
        emailController.text = user.email;
        phoneController.text = user.phoneNumber ?? '';
        addressController.text = user.address ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // Profile Picture Section
                  _buildProfilePictureSection(),
                  const SizedBox(height: 30),
                  const Text(
                    'EDIT PROFILE',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 25),
                  // Username field
                  TextFieldWidget(
                    label: 'Username',
                    hintText: 'Enter your username',
                    icon: Icons.person,
                    controller: usernameController,
                  ),
                  const SizedBox(height: 20),
                  // Email field
                  TextFieldWidget(
                    label: 'Email',
                    hintText: 'Enter your email',
                    icon: Icons.email,
                    controller: emailController,
                  ),
                  const SizedBox(height: 20),
                  // Phone field
                  TextFieldWidget(
                    label: 'Phone Number',
                    hintText: 'Enter your phone number',
                    icon: Icons.phone,
                    controller: phoneController,
                  ),
                  const SizedBox(height: 20),
                  // Address field
                  TextFieldWidget(
                    label: 'Address',
                    hintText: 'Enter your address',
                    icon: Icons.home,
                    controller: addressController,
                  ),
                  const SizedBox(height: 40),
                  // Save Changes button
                  _isLoading
                      ? const Column(
                        children: [
                          CircularProgressIndicator(
                            color: Color.fromARGB(255, 118, 172, 198),
                          ),
                          SizedBox(height: 10),
                          Text('Updating profile...'),
                        ],
                      )
                      : ButtonWidget(
                        text: "Save Changes",
                        onPressed: _saveProfile,
                      ),
                  const SizedBox(height: 20),
                  // Cancel button
                  ButtonWidget(
                    text: "Cancel",
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfilePictureSection() {
    print("🖼️ Building profile picture section:");
    print("  - Local path: $_profileImagePath");
    print(
      "  - Session manager profile: ${_sessionManager.currentUser?.profilePicture}",
    );

    final ImageProvider? imageProvider = _getProfileImageProvider();

    return Stack(
      children: [
        imageProvider != null
            ? CircleAvatar(
              radius: 60,
              backgroundColor: Colors.grey[400],
              backgroundImage: imageProvider,
              onBackgroundImageError: (exception, stackTrace) {
                print("Edit Profile Avatar Error: $exception");
              },
            )
            : CircleAvatar(
              radius: 60,
              backgroundColor: Colors.grey[400],
              child: const Icon(Icons.person, size: 60, color: Colors.white),
            ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _changeProfilePicture,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 118, 172, 198),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ✨ UPDATED: Helper method using ImageUtils for consistency
  ImageProvider? _getProfileImageProvider() {
    try {
      if (_profileImagePath != null && _profileImagePath!.isNotEmpty) {
        final file = File(_profileImagePath!);
        if (file.existsSync()) {
          print("🖼️ Using local file: $_profileImagePath");
          return FileImage(file);
        } else {
          print("🖼️ Local file doesn't exist, clearing path");
          _profileImagePath = null;
        }
      }

      final currentProfilePicture = _sessionManager.currentUser?.profilePicture;
      if (currentProfilePicture != null && currentProfilePicture.isNotEmpty) {
        print("🖼️ Using session profile picture: $currentProfilePicture");
        try {
          return ImageUtils.getProfileImageProvider(currentProfilePicture);
        } catch (e) {
          print("🖼️ Error getting profile image provider: $e");
          return null;
        }
      }

      print("🖼️ No profile image available");
      return null;
    } catch (e) {
      print("🖼️ Error in _getProfileImageProvider: $e");
      return null;
    }
  }

  Future<void> _saveProfile() async {
    // Validation
    String username = usernameController.text.trim();
    String email = emailController.text.trim();
    String phone = phoneController.text.trim();

    if (username.isEmpty) {
      _showErrorMessage("Please enter a username");
      return;
    }
    if (email.isEmpty) {
      _showErrorMessage("Please enter an email");
      return;
    }
    if (phone.isEmpty) {
      _showErrorMessage("Please enter a phone number");
      return;
    }
    if (!_isValidEmail(email)) {
      _showErrorMessage("Please enter a valid email");
      return;
    }
    if (!_isValidPhone(phone)) {
      _showErrorMessage("Please enter a valid phone number");
      return;
    }
    if (username.length < 3) {
      _showErrorMessage("Username must be at least 3 characters");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Prepare update request
      final address = addressController.text.trim();
      final updateRequest = UpdateProfileRequest(
        username: username,
        email: email,
        phoneNumber: phone,
        address: address.isEmpty ? null : address,
        profilePicture: _profileImageBase64,
      );

      print("🔄 Sending update request:");
      print("  - Username: $username");
      print("  - Email: $email");
      print("  - Phone: $phone");
      print("  - Has profile picture: ${_profileImageBase64 != null}");
      if (_profileImageBase64 != null) {
        print("  - Profile picture length: ${_profileImageBase64!.length}");
      }

      // Call API
      final ApiResponse<User> response = await AuthApiService.updateProfile(
        updateRequest,
      );

      print("📨 API Response:");
      print("  - Success: ${response.success}");
      print("  - Data: ${response.data}");
      print("  - Error: ${response.error}");

      if (response.success && response.data != null) {
        print(
          "✅ Before session update - Current user: ${_sessionManager.currentUser?.username}",
        );
        print(
          "✅ Before session update - Profile picture: ${_sessionManager.currentUser?.profilePicture}",
        );

        // Update session manager
        await _sessionManager.updateUser(response.data!);

        print(
          "✅ After session update - Current user: ${_sessionManager.currentUser?.username}",
        );
        print(
          "✅ After session update - Profile picture: ${_sessionManager.currentUser?.profilePicture}",
        );

        _showSuccessMessage("Profile updated successfully!");

        // Clear local image state since it's now saved
        setState(() {
          _profileImagePath = null;
          _profileImageBase64 = null;
        });

        // Go back after a delay
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pop(context);
          }
        });
      } else {
        _showErrorMessage(
          response.error ?? "Failed to update profile. Please try again.",
        );
      }
    } catch (e) {
      print("❌ Profile update error: $e");
      _showErrorMessage("An unexpected error occurred. Please try again.");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _changeProfilePicture() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Change Profile Picture',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt,
                    color: Color.fromARGB(255, 118, 172, 198),
                  ),
                  title: const Text('Take Photo'),
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library,
                    color: Color.fromARGB(255, 118, 172, 198),
                  ),
                  title: const Text('Choose from Gallery'),
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
                if (_profileImagePath != null ||
                    _sessionManager.currentUser?.profilePicture != null)
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text('Remove Photo'),
                    onTap: _removeProfilePicture,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context); // Close bottom sheet

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        print("📷 Image picked: ${image.path}");
        setState(() {
          _profileImagePath = image.path;
        });

        // Convert to base64 for API
        final bytes = await File(image.path).readAsBytes();
        setState(() {
          _profileImageBase64 = base64Encode(bytes);
        });

        print("📷 Base64 length: ${_profileImageBase64?.length}");
        _showSuccessMessage("Profile picture selected!");
      }
    } catch (e) {
      print("❌ Error selecting image: $e");
      _showErrorMessage("Error selecting image: ${e.toString()}");
    }
  }

  void _removeProfilePicture() {
    Navigator.pop(context);
    setState(() {
      _profileImagePath = null;
      _profileImageBase64 = null;
    });
    _showSuccessMessage("Profile picture removed!");
  }

  // Validation methods
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  bool _isValidPhone(String phone) {
    return RegExp(r'^\+?[\d\s\-\(\)]{10,}$').hasMatch(phone);
  }

  // Message display methods
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
}
