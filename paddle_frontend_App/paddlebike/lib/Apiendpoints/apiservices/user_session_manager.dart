import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/auth_models.dart';
import 'user_storage_services.dart';
import 'token_storage_service.dart';
import 'auth_api_service.dart';
import 'base_api_service.dart';
import 'Ride_notification.dart';

class UserSessionManager extends ChangeNotifier with WidgetsBindingObserver {
  User? _currentUser;
  bool _isAuthenticated = false;
  bool _isVerified = false;

  String? _mainWsRelativePath;
  String? _chatWsRelativePath;

  WebSocketChannel? _mainWebSocket;
  WebSocketChannel? _verificationWebSocket;
  StreamSubscription? _mainWsSubscription;
  StreamSubscription? _verificationWsSubscription;

  bool _isMainWSConnected = false;
  bool _isMainWSConnecting = false;

  // Stream controller for broadcasting WebSocket messages
  final StreamController<Map<String, dynamic>> _wsMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  // App context for notifications
  BuildContext? _appContext;

  // Singleton pattern
  static final UserSessionManager _instance = UserSessionManager._internal();
  factory UserSessionManager() => _instance;
  UserSessionManager._internal();

  // --- Getters ---
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isVerified => _isVerified;
  bool get isMainWSConnected => _isMainWSConnected;
  bool get isMainWSConnecting => _isMainWSConnecting;
  Stream<Map<String, dynamic>> get wsMessageStream =>
      _wsMessageController.stream;

  // --- App Context Management ---
  void setAppContext(BuildContext context) {
    _appContext = context;
    print("📱 UserSessionManager: App context set for notifications");
  }

  // --- Initialization and Lifecycle ---
  void initObserver() {
    WidgetsBinding.instance.addObserver(this);
    print("UserSessionManager: WidgetsBindingObserver added.");
  }

  void initializeNotificationHandler() {
    print("🔔 UserSessionManager: Notification handler ready");
  }

  @override
  void dispose() {
    print("UserSessionManager: dispose() called.");
    WidgetsBinding.instance.removeObserver(this);
    disconnectMainWebSocket();
    disconnectVerificationWebSocket();

    if (!_wsMessageController.isClosed) {
      _wsMessageController.close();
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print("UserSessionManager: AppLifecycleState changed to $state");
    if (state == AppLifecycleState.resumed) {
      _attemptReconnectWebSockets();
    }
  }

  // --- Session Management ---
  Future<void> loadSession() async {
    print("UserSessionManager: Loading session...");
    final accessToken = await TokenStorageService.getAccessToken();
    final refreshToken = await TokenStorageService.getRefreshToken();
    final userJson = await UserStorageService.getUserJson();

    if (accessToken != null && refreshToken != null && userJson != null) {
      try {
        _currentUser = User.fromJson(jsonDecode(userJson));
        _isAuthenticated = true;
        _isVerified = _currentUser?.verificationStatus == 'verified';

        final validSession = await AuthApiService.isAuthenticated();
        if (validSession) {
          print("UserSessionManager: Session is valid with backend.");
          _mainWsRelativePath = await UserStorageService.getMainWebSocketPath();
          _chatWsRelativePath = await UserStorageService.getChatWebSocketPath();
          _attemptReconnectWebSockets();
        } else {
          print("UserSessionManager: Session invalid. Logging out.");
          await logout(notifyApi: false);
        }
      } catch (e) {
        print("UserSessionManager: Error loading session: $e. Logging out.");
        await logout(notifyApi: false);
      }
    } else {
      print("UserSessionManager: No stored session found.");
      _currentUser = null;
      _isAuthenticated = false;
      _isVerified = false;
    }
    notifyListeners();
  }

  Future<void> completeLogin(LoginResponse loginData) async {
    print("UserSessionManager: Completing login...");
    await TokenStorageService.saveTokens(
      loginData.accessToken,
      loginData.refreshToken,
    );
    _currentUser = loginData.user;
    await UserStorageService.saveUserJson(jsonEncode(_currentUser!.toJson()));

    _isAuthenticated = true;
    _isVerified = _currentUser?.verificationStatus == 'verified';

    _mainWsRelativePath = loginData.wsUrl;
    _chatWsRelativePath = loginData.chatWsUrl;

    if (_mainWsRelativePath != null) {
      await UserStorageService.saveWebSocketPaths(
        _mainWsRelativePath!,
        _chatWsRelativePath,
      );
      await _connectWebSocketUsingRelativePath(
        _mainWsRelativePath!,
        isMainSocket: true,
      );
    }

    notifyListeners();
    print(
      "UserSessionManager: Login completed. MainWS connected: $_isMainWSConnected",
    );
  }

  Future<void> logout({bool notifyApi = true}) async {
    print("UserSessionManager: Logging out...");
    if (notifyApi && _isAuthenticated) {
      final refreshTokenVal = await TokenStorageService.getRefreshToken();
      if (refreshTokenVal != null) {
        await AuthApiService.logout(refreshTokenVal);
      }
    }
    await TokenStorageService.clearTokens();
    await UserStorageService.clearAllUserData();

    disconnectMainWebSocket();
    disconnectVerificationWebSocket();

    _mainWsRelativePath = null;
    _chatWsRelativePath = null;
    _currentUser = null;
    _isAuthenticated = false;
    _isVerified = false;

    notifyListeners();
    print("UserSessionManager: Logout complete.");
  }

  // --- WebSocket Management ---
  Future<void> _connectWebSocketUsingRelativePath(
    String relativePath, {
    required bool isMainSocket,
  }) async {
    if (isMainSocket) {
      if (_isMainWSConnecting || _isMainWSConnected) {
        print(
          "UserSessionManager: Main WebSocket already connecting/connected.",
        );
        return;
      }
      _isMainWSConnecting = true;
      notifyListeners();
    }

    try {
      String httpBaseUrl = BaseApiService.baseUrl;
      Uri parsedHttpBaseUrl = Uri.parse(httpBaseUrl);
      String wsScheme = parsedHttpBaseUrl.scheme == 'https' ? 'wss' : 'ws';
      String wsHostPort = parsedHttpBaseUrl.host;
      if (parsedHttpBaseUrl.hasPort &&
          parsedHttpBaseUrl.port != 80 &&
          parsedHttpBaseUrl.port != 443) {
        wsHostPort += ':${parsedHttpBaseUrl.port}';
      }
      String pathSegment = relativePath.startsWith('/')
          ? relativePath
          : '/$relativePath';
      String fullWsUrl = '$wsScheme://$wsHostPort$pathSegment';

      print("UserSessionManager: Connecting to WebSocket: $fullWsUrl");

      if (isMainSocket) {
        disconnectMainWebSocket();
        _mainWebSocket = WebSocketChannel.connect(Uri.parse(fullWsUrl));
        _mainWsSubscription = _mainWebSocket!.stream.listen(
          (msg) => _handleIncomingNotification(msg, isMainSocket: true),
          onDone: () {
            print('UserSessionManager: Main WS disconnected.');
            _isMainWSConnected = false;
            _isMainWSConnecting = false;
            _mainWebSocket = null;
            _mainWsSubscription = null;
            notifyListeners();
          },
          onError: (err) {
            print('UserSessionManager: Main WS error: $err');
            _isMainWSConnected = false;
            _isMainWSConnecting = false;
            _mainWebSocket = null;
            _mainWsSubscription = null;
            notifyListeners();
          },
          cancelOnError: false,
        );
        _isMainWSConnected = true;
        _isMainWSConnecting = false;
        print('UserSessionManager: Main WS connected successfully.');
      }

      notifyListeners();
    } catch (e) {
      print("UserSessionManager: Error connecting WebSocket: $e");
      if (isMainSocket) {
        _isMainWSConnected = false;
        _isMainWSConnecting = false;
      }
      notifyListeners();
    }
  }

  void disconnectMainWebSocket() {
    if (_mainWebSocket == null && _mainWsSubscription == null) return;

    print("UserSessionManager: Disconnecting Main WebSocket...");
    _mainWsSubscription?.cancel();
    _mainWebSocket?.sink.close().catchError((e) {
      print("UserSessionManager: Error closing main WebSocket: $e");
    });
    _mainWebSocket = null;
    _mainWsSubscription = null;

    if (_isMainWSConnected || _isMainWSConnecting) {
      _isMainWSConnected = false;
      _isMainWSConnecting = false;
      notifyListeners();
    }
  }

  // --- Message Handling ---
  // --- Message Handling ---
  void _handleIncomingNotification(
    dynamic message, {
    required bool isMainSocket,
  }) {
    print("🔍 DEBUG: Incoming notification");
    print("🔍 Current user: ${_currentUser?.username}");
    print("🔍 Message data: $message");

    print("UserSessionManager: Handling WS message: $message");
    try {
      final decodedMessage = jsonDecode(message as String);

      if (decodedMessage == null || decodedMessage is! Map<String, dynamic>) {
        print("UserSessionManager: Invalid message format.");
        return;
      }

      final String? messageType = decodedMessage['type'] as String?;
      final dynamic messageData = decodedMessage['data'];

      if (messageType == 'notification' && messageData != null) {
        final String? targetOwnerUsername =
            messageData['target_owner_username'];
        final String? currentUsername = _currentUser?.username;

        print("🔍 Target owner: $targetOwnerUsername");
        print("🔍 Current user: $currentUsername");

        if (targetOwnerUsername != null &&
            targetOwnerUsername != currentUsername) {
          print(
            "❌ NOTIFICATION MISMATCH! This notification is not for current user",
          );
          return; // Don't show notification
        }

        if (messageType == null) {
          print("UserSessionManager: Message missing 'type' field.");
          return;
        }

        print("UserSessionManager: Message type: $messageType");

        // 🚀 NEW: Handle EARNINGS UPDATES
        final String? notificationType =
            messageData['notification_type'] as String?;
        if (notificationType == 'earnings_updated') {
          print("💰 UserSessionManager: EARNINGS UPDATE received!");
          _handleEarningsUpdate(messageData);
          return; // Don't process as regular notification
        }

        // Handle notification messages with GlobalNotificationOverlay
        if (messageType == 'notification' &&
            messageData != null &&
            _appContext != null) {
          // Handle RIDE REQUEST notifications
          final bool paymentCompleted =
              messageData['payment_completed'] as bool? ?? false;
          final String? tempRequestId =
              messageData['temp_request_id'] as String?;

          if (paymentCompleted && tempRequestId != null) {
            print("🔔 UserSessionManager: RIDE REQUEST - Showing card!");
            GlobalNotificationOverlay().showRideRequestCard(
              _appContext!,
              messageData,
            );
            return;
          }

          // Handle RIDE CANCELLATION notifications
          final String? action = messageData['action'] as String?;
          if (action == 'cancelled_by_rider') {
            print("🔔 UserSessionManager: RIDE CANCELLED - Showing card!");
            GlobalNotificationOverlay().showRideCancelledCard(
              _appContext!,
              messageData,
            );
            return;
          }
        }

        // Broadcast to stream for other listeners
        if (!_wsMessageController.isClosed) {
          _wsMessageController.add(decodedMessage);
        }
      }
    } catch (e, stackTrace) {
      print("UserSessionManager: Error handling message: $e");
      print("UserSessionManager: StackTrace: $stackTrace");
    }
  }

  // 🚀 NEW: Add this method
  Future<void> _handleEarningsUpdate(Map<String, dynamic> messageData) async {
    try {
      final double? newTotalEarnings =
          messageData['new_total_earnings'] as double?;
      final double? tripEarnings = messageData['trip_earnings'] as double?;

      if (newTotalEarnings != null && _currentUser != null) {
        print(
          "💰 Updating earnings: ${_currentUser!.total_earnings} → $newTotalEarnings",
        );
        print(
          "💰 Trip earnings: +€${tripEarnings?.toStringAsFixed(2) ?? '0.00'}",
        );

        // Create updated user with new earnings
        final updatedUser = User(
          id: _currentUser!.id,
          username: _currentUser!.username,
          email: _currentUser!.email,
          phoneNumber: _currentUser!.phoneNumber,
          profilePicture: _currentUser!.profilePicture,
          address: _currentUser!.address,
          verificationStatus: _currentUser!.verificationStatus,
          total_earnings: newTotalEarnings,
        );

        // Update session and save to storage
        await updateUser(updatedUser);

        print("✅ UserSessionManager: Earnings updated successfully!");
      } else {
        print("❌ UserSessionManager: Invalid earnings data received");
      }
    } catch (e) {
      print("❌ UserSessionManager: Error handling earnings update: $e");
    }
  }

  // --- Verification WebSocket ---
  void connectVerificationWebSocket(String verificationWsUrl) {
    disconnectVerificationWebSocket();

    try {
      String httpBaseUrl = BaseApiService.baseUrl;
      Uri parsedHttpBaseUrl = Uri.parse(httpBaseUrl);
      String wsScheme = parsedHttpBaseUrl.scheme == 'https' ? 'wss' : 'ws';
      String wsHostPort = parsedHttpBaseUrl.host;
      if (parsedHttpBaseUrl.hasPort &&
          parsedHttpBaseUrl.port != 80 &&
          parsedHttpBaseUrl.port != 443) {
        wsHostPort += ':${parsedHttpBaseUrl.port}';
      }

      String fullWsUrl;
      if (verificationWsUrl.startsWith('ws://') ||
          verificationWsUrl.startsWith('wss://')) {
        fullWsUrl = verificationWsUrl;
      } else {
        String pathSegment = verificationWsUrl.startsWith('/')
            ? verificationWsUrl
            : '/$verificationWsUrl';
        fullWsUrl = '$wsScheme://$wsHostPort$pathSegment';
      }

      print(
        "UserSessionManager: Connecting to Verification WebSocket: $fullWsUrl",
      );
      _verificationWebSocket = WebSocketChannel.connect(Uri.parse(fullWsUrl));
      _verificationWsSubscription = _verificationWebSocket!.stream.listen(
        (msg) => _handleStripeVerificationMessage(msg),
        onDone: () {
          print('UserSessionManager: Verification WS disconnected.');
          _verificationWebSocket = null;
          _verificationWsSubscription = null;
        },
        onError: (err) {
          print('UserSessionManager: Verification WS error: $err');
          _verificationWebSocket = null;
          _verificationWsSubscription = null;
        },
        cancelOnError: true,
      );
    } catch (e) {
      print("UserSessionManager: Error connecting Verification WebSocket: $e");
      _verificationWebSocket = null;
      _verificationWsSubscription = null;
    }
  }

  void _handleStripeVerificationMessage(dynamic message) {
    print("UserSessionManager: Stripe Verification Message: $message");
    try {
      final decodedMessage = jsonDecode(message as String);
      final verificationMsg = VerificationCompleteMessage.fromJson(
        decodedMessage,
      );

      if (verificationMsg.type == 'verification_complete') {
        if (verificationMsg.status == 'verified' &&
            verificationMsg.user != null) {
          print("UserSessionManager: Stripe verification successful.");
          _handleStripeVerificationSuccess(verificationMsg.user!);
        } else {
          print(
            "UserSessionManager: Stripe verification failed: ${verificationMsg.message}",
          );
        }
        disconnectVerificationWebSocket();
      } else if (verificationMsg.type == 'status_update') {
        print(
          "UserSessionManager: Verification status: ${verificationMsg.status} - ${verificationMsg.message}",
        );
      } else {
        print(
          "UserSessionManager: Unknown verification message type: ${verificationMsg.type}",
        );
      }
    } catch (e) {
      print("UserSessionManager: Error decoding verification message: $e");
    }
  }

  Future<void> _handleStripeVerificationSuccess(
    VerifiedUserData verifiedUserData,
  ) async {
    print("UserSessionManager: Updating session with verified user data...");

    await TokenStorageService.saveTokens(
      verifiedUserData.accessToken,
      verifiedUserData.refreshToken,
    );

    _currentUser = User(
      id: verifiedUserData.id,
      username: verifiedUserData.username,
      email: verifiedUserData.email,
      phoneNumber: verifiedUserData.phoneNumber,
      profilePicture: verifiedUserData.profilePicture,
      address: verifiedUserData.address,
      verificationStatus: verifiedUserData.verificationStatus,
      total_earnings: verifiedUserData.total_earnings,
    );

    await UserStorageService.saveUserJson(jsonEncode(_currentUser!.toJson()));

    _isAuthenticated = true;
    _isVerified = true;

    // Reconnect WebSocket if new URL provided
    if (verifiedUserData.wsUrl != null && verifiedUserData.wsUrl!.isNotEmpty) {
      _mainWsRelativePath = verifiedUserData.wsUrl;
      _chatWsRelativePath = verifiedUserData.chatWsUrl;

      await UserStorageService.saveWebSocketPaths(
        _mainWsRelativePath!,
        _chatWsRelativePath,
      );

      disconnectMainWebSocket();
      await _connectWebSocketUsingRelativePath(
        _mainWsRelativePath!,
        isMainSocket: true,
      );
    }

    notifyListeners();
    print("UserSessionManager: Verification success handling complete.");
  }

  void disconnectVerificationWebSocket() {
    if (_verificationWebSocket == null && _verificationWsSubscription == null) {
      return;
    }

    print("UserSessionManager: Disconnecting Verification WebSocket...");
    _verificationWsSubscription?.cancel();
    _verificationWebSocket?.sink.close().catchError((e) {
      print("UserSessionManager: Error closing verification WebSocket: $e");
    });
    _verificationWebSocket = null;
    _verificationWsSubscription = null;
  }

  // --- Reconnection Logic ---
  Future<void> _attemptReconnectWebSockets() async {
    print("UserSessionManager: Attempting to reconnect WebSockets...");
    if (_isAuthenticated &&
        _mainWsRelativePath != null &&
        _mainWsRelativePath!.isNotEmpty) {
      if (!_isMainWSConnected && !_isMainWSConnecting) {
        print("UserSessionManager: Reconnecting main WebSocket...");
        await _connectWebSocketUsingRelativePath(
          _mainWsRelativePath!,
          isMainSocket: true,
        );
      } else {
        print(
          "UserSessionManager: Main WebSocket already connected/connecting.",
        );
      }
    } else {
      print(
        "UserSessionManager: Cannot reconnect - not authenticated or no path.",
      );
    }
  }

  // --- Token Management ---
  Future<bool> refreshSessionTokens() async {
    print("UserSessionManager: Refreshing session tokens...");
    final success = await BaseApiService.refreshToken();
    if (success) {
      print("UserSessionManager: Token refresh successful.");
      _isAuthenticated = true;
      notifyListeners();
      return true;
    } else {
      print("UserSessionManager: Token refresh failed. Logging out.");
      await logout(notifyApi: false);
      return false;
    }
  }

  Future<bool> handleApiUnauthorized() async {
    return await refreshSessionTokens();
  }

  // --- User Profile Updates ---
  Future<void> updateUser(
    User newUserData, {
    String? newAccessToken,
    String? newRefreshToken,
  }) async {
    print("UserSessionManager: Updating user data...");
    _currentUser = newUserData;
    _isVerified = _currentUser?.verificationStatus == 'verified';
    await UserStorageService.saveUserJson(jsonEncode(_currentUser!.toJson()));

    if (newAccessToken != null && newRefreshToken != null) {
      await TokenStorageService.saveTokens(newAccessToken, newRefreshToken);
      print("UserSessionManager: New tokens saved.");
    }
    notifyListeners();
  }

  // --- Public Utility Methods ---
  Future<bool> attemptReconnectMainWebSocket() async {
    print("UserSessionManager: Public reconnect request...");
    if (_isAuthenticated &&
        _mainWsRelativePath != null &&
        _mainWsRelativePath!.isNotEmpty) {
      if (!_isMainWSConnected && !_isMainWSConnecting) {
        await _connectWebSocketUsingRelativePath(
          _mainWsRelativePath!,
          isMainSocket: true,
        );
        return _isMainWSConnected;
      }
      return _isMainWSConnected;
    }
    print(
      "UserSessionManager: Cannot reconnect - not authenticated or no path.",
    );
    return false;
  }
}
