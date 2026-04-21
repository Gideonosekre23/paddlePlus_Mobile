import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:paddleapp/constants/button.dart';
import 'package:paddleapp/constants/tesxtfileds.dart';
import 'package:paddleapp/pages/login_page.dart';
import 'package:paddleapp/pages/register_page.dart';

import 'package:paddleapp/pages/stripe_page.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:location/location.dart';
import '../Apiendpoints/models/auth_models.dart';
import '../Apiendpoints/apiservices/auth_api_service.dart';

class Register2Page extends StatefulWidget {
  final String registrationToken;

  const Register2Page({super.key, required this.registrationToken});

  @override
  _Register2PageState createState() => _Register2PageState();
}

class _Register2PageState extends State<Register2Page> {
  final _phoneController = TextEditingController();
  final _cpnController = TextEditingController();
  final _addressController = TextEditingController();

  bool _loading = false;
  bool _isCleaningUp = false;

  bool _wsConnected = false;
  bool _verificationInProgress = false;
  String? _lastVerificationStatus;
  Timer? _connectionTimeoutTimer;

  File? _profileImageFile;
  final ImagePicker _picker = ImagePicker();
  late Location _location;
  bool _agreedToTerms = false;
  bool _agreedToLocationAccess = false;

  WebSocketChannel? _verificationWS;
  StreamSubscription? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _location = Location();
  }

  @override
  void dispose() {
    print("🗑️ Register2Page disposing...");

    _isCleaningUp = true;

    _disconnectVerificationWS();

    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;

    _phoneController.dispose();
    _cpnController.dispose();
    _addressController.dispose();

    Future.delayed(Duration(milliseconds: 100), () {
      print("✅ Register2Page cleanup completed");
    });

    super.dispose();
    print("✅ Register2Page disposed");
  }

  Future<bool> _requestCameraAndMicrophonePermissions() async {
    Map<ph.Permission, ph.PermissionStatus> statuses =
        await [ph.Permission.camera, ph.Permission.microphone].request();

    bool cameraGranted = statuses[ph.Permission.camera]?.isGranted ?? false;
    bool microphoneGranted =
        statuses[ph.Permission.microphone]?.isGranted ?? false;

    if (!mounted) return false;

    if (!cameraGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Camera permission is required for verification.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => ph.openAppSettings(),
          ),
        ),
      );
    }

    if (!microphoneGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Microphone permission is required for verification.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => ph.openAppSettings(),
          ),
        ),
      );
    }

    return cameraGranted && microphoneGranted;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 50,
      );
      if (pickedFile != null) {
        setState(() {
          _profileImageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Photo Library'),
                onTap: () {
                  _pickImage(ImageSource.gallery);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_camera),
                title: Text('Camera'),
                onTap: () {
                  _pickImage(ImageSource.camera);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startVerification() async {
    if (_loading) return;

    setState(() {
      _loading = true;
    });

    final cpn = _cpnController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();

    if (cpn.isEmpty || cpn.length != 13) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid CPN (must be 13 characters).'),
        ),
      );
      setState(() => _loading = false);
      return;
    }

    if (phone.isEmpty || address.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill all required fields.')),
      );
      setState(() => _loading = false);
      return;
    }

    if (!_agreedToTerms) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You must agree to the terms to register.')),
      );
      setState(() => _loading = false);
      return;
    }

    if (!_agreedToLocationAccess) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please allow location access to complete registration.',
          ),
        ),
      );
      setState(() => _loading = false);
      return;
    }

    bool cameraMicPermissionsGranted =
        await _requestCameraAndMicrophonePermissions();
    if (!cameraMicPermissionsGranted) {
      setState(() => _loading = false);
      return;
    }

    LocationData? locationData;
    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Location services are disabled. Please enable them to proceed.',
              ),
            ),
          );
          setState(() => _loading = false);
          return;
        }
      }

      PermissionStatus permissionStatus = await _location.hasPermission();
      if (permissionStatus == PermissionStatus.denied) {
        permissionStatus = await _location.requestPermission();
        if (permissionStatus != PermissionStatus.granted &&
            permissionStatus != PermissionStatus.grantedLimited) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Location permission denied. Please grant permission to proceed.',
              ),
            ),
          );
          setState(() => _loading = false);
          return;
        }
      }

      if (permissionStatus == PermissionStatus.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Location permission is permanently denied. Please enable it in app settings.',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => ph.openAppSettings(),
            ),
          ),
        );
        setState(() => _loading = false);
        return;
      }

      locationData = await _location.getLocation();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not get location: $e')));
      setState(() => _loading = false);
      return;
    }

    String? base64Image;
    if (_profileImageFile != null) {
      List<int> imageBytes = await _profileImageFile!.readAsBytes();
      base64Image = base64Encode(imageBytes);
    }

    try {
      final request = RegisterPhase2Request(
        token: widget.registrationToken,
        cpn: cpn,
        address: address,
        phoneNumber: phone,
        profilePicture: base64Image,
        latitude: locationData.latitude,
        longitude: locationData.longitude,
      );

      final response = await AuthApiService.registerPhase2(request);

      if (response.success && response.data != null) {
        _connectVerificationWS(response.data!.websocketUrl);

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => StripeVerificationWebViewPage(
                  initialUrl: response.data!.verificationUrl,
                ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.error ?? 'Failed to start verification'),
          ),
        );
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _loading = false);
    }
  }

  void _connectVerificationWS(String wsUrl) {
    print("🔌 Connecting to verification WebSocket: $wsUrl");

    // ✅ ADD: Validate URL format first
    if (!_isValidWebSocketUrl(wsUrl)) {
      print("❌ Invalid WebSocket URL format: $wsUrl");
      if (mounted) {
        setState(() {
          _loading = false;
          _verificationInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid verification URL received from server.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Clean up any existing connection
    _disconnectVerificationWS();

    if (mounted) {
      setState(() {
        _loading = true;
        _wsConnected = false;
        _verificationInProgress = true;
        _lastVerificationStatus = null;
      });
    }

    try {
      print("🌐 Attempting WebSocket connection...");
      print("📍 Full URL: $wsUrl");

      _verificationWS = WebSocketChannel.connect(Uri.parse(wsUrl));

      // ✅ REDUCE timeout to 15 seconds (30 is too long)
      _connectionTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (!_wsConnected && mounted) {
          print("⏰ WebSocket connection timeout after 15 seconds");
          _handleConnectionTimeout();
        }
      });

      _wsSubscription = _verificationWS!.stream.listen(
        (msg) {
          if (!mounted) return;

          // ✅ Mark connection as successful on first message
          if (!_wsConnected) {
            _connectionTimeoutTimer?.cancel();
            if (mounted) {
              setState(() {
                _wsConnected = true;
              });
            }
            print("✅ WebSocket connected successfully on first message");
          }

          // Handle the message
          try {
            final data = jsonDecode(msg);
            final String? messageType = data['type'] as String?;
            final String? status = data['status'] as String?;
            final String? message = data['message'] as String?;

            print("📨 WebSocket message: $messageType - $status");

            if (messageType == 'verification_complete') {
              _handleVerificationComplete(status, message);
            } else if (messageType == 'status_update') {
              _handleStatusUpdate(status, message);
            } else {
              print("❓ Unknown WS message type: $messageType");
            }
          } catch (e) {
            print('⚠️ WS parse error: $e. Message: $msg');
          }
        },
        onError: (error) {
          print('❌ WebSocket connection error: $error');
          _handleWebSocketError(error);
        },
        onDone: () {
          print('🔌 Verification WebSocket closed by server');
          _handleWebSocketClosed();
        },
        cancelOnError: true,
      );

      // ✅ ADD: Test connection after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        if (!_wsConnected && _verificationWS != null) {
          print("🧪 Testing WebSocket connection...");
          try {
            _verificationWS!.sink.add('{"type":"ping"}');
          } catch (e) {
            print("❌ WebSocket connection test failed: $e");
            _handleConnectionError(e);
          }
        }
      });
    } catch (e) {
      print("❌ Failed to create WebSocket connection: $e");
      _handleConnectionError(e);
    }
  }

  // ✅ ADD: URL validation
  bool _isValidWebSocketUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'ws' || uri.scheme == 'wss';
    } catch (e) {
      return false;
    }
  }

  void _handleVerificationComplete(String? status, String? message) {
    print("🎯 Verification complete: $status");

    // ✅ Prevent multiple calls
    if (!mounted || !_verificationInProgress) {
      print("⚠️ Widget not mounted or verification not in progress");
      return;
    }

    // ✅ IMMEDIATE cleanup
    _disconnectVerificationWS();

    // ✅ Update state ONCE
    setState(() {
      _verificationInProgress = false;
      _loading = false;
      _lastVerificationStatus = status;
    });

    // ✅ Close WebView (don't wait for it)
    Navigator.maybePop(context);

    // ✅ Single navigation based on status
    if (status == 'verified') {
      _handleVerificationSuccess();
    } else {
      _handleVerificationFailure(message);
    }
  }

  void _handleVerificationSuccess() {
    print("✅ Verification successful - navigating to login");
    if (!mounted) return;

    _disconnectVerificationWS();

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('✅ Verification successful! Please login.'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const login_page(),

            settings: const RouteSettings(name: '/login'),
          ),
          (route) => false,
        );
      }
    });
  }

  void _handleVerificationFailure(String? message) {
    print("❌ Verification failed: $message");

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Verification failed: ${message ?? 'Please try again.'}',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RegisterPage()),
          (route) => false,
        );
      }
    });
  }

  // ✅ Enhanced disconnect method
  void _disconnectVerificationWS() {
    if (_isCleaningUp) {
      print("🔄 Cleanup already in progress, skipping...");
      return;
    }
    _isCleaningUp = true;
    print("🔌 Disconnecting verification WebSocket");

    // Cancel timeout timer
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;

    // Cancel subscription first
    if (_wsSubscription != null) {
      _wsSubscription!.cancel();
      _wsSubscription = null;
      print("✅ WebSocket subscription cancelled");
    }

    // Close WebSocket with proper code
    if (_verificationWS != null) {
      try {
        _verificationWS!.sink.close(1000, 'Registration complete');
        print("✅ WebSocket closed with code 1000");
      } catch (e) {
        print("⚠️ Error closing WebSocket sink: $e");
      }
      _verificationWS = null;
    }

    // ✅ ADD: Force garbage collection hint
    Future.delayed(Duration(milliseconds: 100), () {
      // Small delay to ensure cleanup
    });

    // Update state only if widget is still mounted
    if (mounted) {
      setState(() {
        _wsConnected = false;
        _verificationInProgress = false;
      });
    }

    _isCleaningUp = false;
    print("✅ Verification WebSocket disconnected cleanly");
  }

  // ✅ Updated status update handler
  void _handleStatusUpdate(String? status, String? message) {
    print("📊 Status update: $status - $message");

    // ✅ Update state: Track status
    if (mounted) {
      setState(() {
        _lastVerificationStatus = status;
      });
    }

    // Show user-friendly status updates
    String userMessage = _getUserFriendlyStatusMessage(status, message);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userMessage),
          duration: Duration(seconds: 3),
          backgroundColor: _getStatusColor(status),
        ),
      );
    }

    // ✅ DON'T disconnect for status updates - keep listening
  }

  // ✅ Handle status updates

  // ✅ Handle WebSocket errors
  void _handleWebSocketError(dynamic error) {
    print("❌ WebSocket error: $error");

    // ✅ Update state: Error occurred
    if (mounted) {
      setState(() {
        _wsConnected = false;
        _loading = false;
        _verificationInProgress = false;
      });
    }

    // Close WebView
    Navigator.maybePop(context);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification connection error. Please try again.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );

      // ✅ Update loading state
      setState(() {
        _loading = false;
      });
    }

    _disconnectVerificationWS();
  }

  // ✅ Handle WebSocket closed unexpectedly
  void _handleWebSocketClosed() {
    // ✅ Update state: Connection closed
    if (mounted) {
      setState(() {
        _wsConnected = false;
      });
    }

    // Only show timeout message if verification was still in progress
    if (mounted && _verificationInProgress && _loading) {
      Navigator.maybePop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification process timed out or disconnected.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );

      // ✅ Update state: Stop loading
      setState(() {
        _loading = false;
        _verificationInProgress = false;
      });
    }

    // Ensure cleanup
    _verificationWS = null;
  }

  void _handleConnectionTimeout() {
    print("⏰ Connection timeout - WebSocket never connected");

    if (mounted) {
      setState(() {
        _wsConnected = false;
        _loading = false;
        _verificationInProgress = false;
      });
    }

    // Close WebView
    Navigator.maybePop(context);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Verification service unavailable. Please check your internet connection and try again.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              // Allow user to retry
              setState(() {
                _loading = false;
              });
            },
          ),
        ),
      );
    }

    _disconnectVerificationWS();
  }

  // ✅ Handle initial connection error
  void _handleConnectionError(dynamic error) {
    print("❌ Connection error: $error");

    // ✅ Update state: Failed to connect
    if (mounted) {
      setState(() {
        _wsConnected = false;
        _loading = false;
        _verificationInProgress = false;
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect for verification updates.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  // ✅ Get user-friendly status messages
  String _getUserFriendlyStatusMessage(String? status, String? message) {
    switch (status) {
      case 'requires_input':
        return 'Please complete the verification steps';
      case 'processing':
        return 'Processing your documents...';
      case 'verified':
        return 'Verification successful!';
      case 'requires_action':
        return 'Additional action required';
      default:
        return message ?? 'Verification status updated';
    }
  }

  // ✅ Get status-appropriate colors
  Color _getStatusColor(String? status) {
    switch (status) {
      case 'verified':
        return Colors.green;
      case 'processing':
        return Colors.blue;
      case 'requires_input':
      case 'requires_action':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Complete Your Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Picture Section
            Center(
              child: GestureDetector(
                onTap: () => _showImageSourceActionSheet(context),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[300],
                    backgroundImage:
                        _profileImageFile != null
                            ? FileImage(_profileImageFile!)
                            : null,
                    child:
                        _profileImageFile == null
                            ? Icon(
                              Icons.camera_alt,
                              color: Colors.grey[700],
                              size: 50,
                            )
                            : null,
                  ),
                ),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                _profileImageFile == null
                    ? 'Tap to add profile picture'
                    : 'Tap to change picture',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ),
            SizedBox(height: 24),

            // Form Fields
            TextFieldWidget(
              label: 'Company/Personal Number (CNP)',
              controller: _cpnController,
              hintText: 'Enter 13-digit CNP',
              icon: Icons.badge,
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 16),

            TextFieldWidget(
              label: 'Phone Number',
              controller: _phoneController,
              hintText: 'Enter phone number',
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
            ),
            SizedBox(height: 16),

            TextFieldWidget(
              label: 'Address',
              controller: _addressController,
              hintText: 'Enter full address',
              icon: Icons.home,
            ),
            SizedBox(height: 24),

            // Status Information Card (if verification in progress)
            if (_verificationInProgress || _lastVerificationStatus != null) ...[
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getStatusColor(
                    _lastVerificationStatus,
                  ).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getStatusColor(
                      _lastVerificationStatus,
                    ).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _verificationInProgress
                              ? Icons.hourglass_empty
                              : Icons.info,
                          color: _getStatusColor(_lastVerificationStatus),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Verification Status',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(_lastVerificationStatus),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      _verificationInProgress
                          ? 'Verification is in progress...'
                          : _getUserFriendlyStatusMessage(
                            _lastVerificationStatus,
                            null,
                          ),
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    if (_wsConnected) ...[
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Connected for real-time updates',
                            style: TextStyle(fontSize: 12, color: Colors.green),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 16),
            ],

            // Consent Checkboxes
            CheckboxListTile(
              title: Text(
                "I allow PaddlePlus to access my device's location for registration purposes.",
                style: TextStyle(fontSize: 14),
              ),
              value: _agreedToLocationAccess,
              onChanged: (newValue) {
                setState(() {
                  _agreedToLocationAccess = newValue ?? false;
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: Theme.of(context).primaryColor,
            ),

            CheckboxListTile(
              title: Text(
                "I agree to the terms and conditions to register.",
                style: TextStyle(fontSize: 14),
              ),
              value: _agreedToTerms,
              onChanged: (newValue) {
                setState(() {
                  _agreedToTerms = newValue ?? false;
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: Theme.of(context).primaryColor,
            ),
            SizedBox(height: 24),

            // Action Button
            _loading
                ? Column(
                  children: [
                    CircularProgressIndicator(
                      color: Theme.of(context).primaryColor,
                    ),
                    SizedBox(height: 16),
                    Text(
                      _verificationInProgress
                          ? 'Verification in progress...'
                          : 'Starting verification...',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                )
                : ButtonWidget(
                  text: 'Start Verification & Register',
                  onPressed: _startVerification,
                ),

            SizedBox(height: 20), // Bottom padding
          ],
        ),
      ),
    );
  }
}
