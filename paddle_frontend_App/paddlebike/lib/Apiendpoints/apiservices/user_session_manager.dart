import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const List<int> _reconnectDelays = [2, 5, 10, 30, 60];

  // Stream controller for broadcasting WebSocket messages
  final StreamController<Map<String, dynamic>> _wsMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  // App context for notifications
  BuildContext? _appContext;

  // Singleton pattern
  static final UserSessionManager _instance = UserSessionManager._internal();
  factory UserSessionManager() => _instance;
  UserSessionManager._internal();

  void _log(String message) {
    if (kDebugMode) debugPrint('[SessionManager] $message');
  }

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
    _log("📱 UserSessionManager: App context set for notifications");
  }

  // --- Initialization and Lifecycle ---
  void initObserver() {
    WidgetsBinding.instance.addObserver(this);
    _log("UserSessionManager: WidgetsBindingObserver added.");
  }

  void initializeNotificationHandler() {
    _log("🔔 UserSessionManager: Notification handler ready");
  }

  @override
  void dispose() {
    _cancelReconnectTimer();
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
    _log("UserSessionManager: AppLifecycleState changed to $state");
    if (state == AppLifecycleState.resumed) {
      _attemptReconnectWebSockets();
    }
  }

  // --- Session Management ---
  Future<void> loadSession() async {
    _log("UserSessionManager: Loading session...");
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
          _log("UserSessionManager: Session is valid with backend.");
          _mainWsRelativePath = await UserStorageService.getMainWebSocketPath();
          _chatWsRelativePath = await UserStorageService.getChatWebSocketPath();
          _attemptReconnectWebSockets();
        } else {
          _log("UserSessionManager: Session invalid. Logging out.");
          await logout(notifyApi: false);
        }
      } catch (e) {
        _log("UserSessionManager: Error loading session: $e. Logging out.");
        await logout(notifyApi: false);
      }
    } else {
      _log("UserSessionManager: No stored session found.");
      _currentUser = null;
      _isAuthenticated = false;
      _isVerified = false;
    }
    notifyListeners();
  }

  Future<void> completeLogin(LoginResponse loginData) async {
    _log("UserSessionManager: Completing login...");
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
    _log(
      "UserSessionManager: Login completed. MainWS connected: $_isMainWSConnected",
    );
  }

  Future<void> logout({bool notifyApi = true}) async {
    _log("UserSessionManager: Logging out...");
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
    _log("UserSessionManager: Logout complete.");
  }

  // --- WebSocket Management ---
  Future<void> _connectWebSocketUsingRelativePath(
    String relativePath, {
    required bool isMainSocket,
  }) async {
    if (isMainSocket) {
      if (_isMainWSConnecting || _isMainWSConnected) {
        _log(
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
      String fullWsUrl;
      if (relativePath.startsWith('ws://') || relativePath.startsWith('wss://')) {
        fullWsUrl = relativePath;
      } else {
        String pathSegment = relativePath.startsWith('/')
            ? relativePath
            : '/$relativePath';
        fullWsUrl = '$wsScheme://$wsHostPort$pathSegment';
      }

      _log("Connecting to main WebSocket (isMain: $isMainSocket)");

      if (isMainSocket) {
        disconnectMainWebSocket();
        _mainWebSocket = WebSocketChannel.connect(Uri.parse(fullWsUrl));
        _mainWsSubscription = _mainWebSocket!.stream.listen(
          (msg) => _handleIncomingNotification(msg, isMainSocket: true),
          onDone: () {
            _log('Main WS disconnected (onDone)');
            _isMainWSConnected = false;
            _isMainWSConnecting = false;
            _mainWebSocket = null;
            _mainWsSubscription = null;
            notifyListeners();
            _scheduleReconnect();
          },
          onError: (err) {
            _log('Main WS error: $err');
            _isMainWSConnected = false;
            _isMainWSConnecting = false;
            _mainWebSocket = null;
            _mainWsSubscription = null;
            notifyListeners();
            _scheduleReconnect();
          },
          cancelOnError: false,
        );
        _isMainWSConnected = true;
        _isMainWSConnecting = false;
        _reconnectAttempts = 0;
        _cancelReconnectTimer();
        _log('Main WS connected successfully.');
      }

      notifyListeners();
    } catch (e) {
      _log("UserSessionManager: Error connecting WebSocket: $e");
      if (isMainSocket) {
        _isMainWSConnected = false;
        _isMainWSConnecting = false;
      }
      notifyListeners();
    }
  }

  void disconnectMainWebSocket() {
    _cancelReconnectTimer();
    _reconnectAttempts = 0;
    if (_mainWebSocket == null && _mainWsSubscription == null) return;

    _log("Disconnecting Main WebSocket...");
    _mainWsSubscription?.cancel();
    _mainWebSocket?.sink.close().catchError((e) {
      _log("UserSessionManager: Error closing main WebSocket: $e");
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
    _log("🔍 DEBUG: Incoming notification");
    _log("🔍 Current user: ${_currentUser?.username}");
    _log("🔍 Message data: $message");

    _log("UserSessionManager: Handling WS message: $message");
    try {
      final decodedMessage = jsonDecode(message as String);

      if (decodedMessage == null || decodedMessage is! Map<String, dynamic>) {
        _log("UserSessionManager: Invalid message format.");
        return;
      }

      final String? messageType = decodedMessage['type'] as String?;
      final dynamic messageData = decodedMessage['data'];

      if (messageType == 'notification' && messageData != null) {
        final String? targetOwnerUsername =
            messageData['target_owner_username'];
        final String? currentUsername = _currentUser?.username;

        _log("🔍 Target owner: $targetOwnerUsername");
        _log("🔍 Current user: $currentUsername");

        if (targetOwnerUsername != null &&
            targetOwnerUsername != currentUsername) {
          _log(
            "❌ NOTIFICATION MISMATCH! This notification is not for current user",
          );
          return; // Don't show notification
        }

        if (messageType == null) {
          _log("UserSessionManager: Message missing 'type' field.");
          return;
        }

        _log("UserSessionManager: Message type: $messageType");

        // 🚀 NEW: Handle EARNINGS UPDATES
        final String? notificationType =
            messageData['notification_type'] as String?;
        if (notificationType == 'earnings_updated') {
          _log("💰 UserSessionManager: EARNINGS UPDATE received!");
          _handleEarningsUpdate(messageData);
          return; // Don't process as regular notification
        }

        // Handle notification messages with GlobalNotificationOverlay
        if (messageType == 'notification' &&
            messageData != null &&
            _appContext != null) {
          // Handle RIDE REQUEST notifications
          final String? tempRequestId =
              messageData['temp_request_id'] as String?;
          final String? notifType =
              messageData['notification_type'] as String?;

          if (tempRequestId != null && notifType == 'ride_request') {
            _log("🔔 UserSessionManager: RIDE REQUEST - Showing card!");
            GlobalNotificationOverlay().showRideRequestCard(
              _appContext!,
              messageData,
            );
            return;
          }

          // Handle RIDE CANCELLATION notifications
          final String? action = messageData['action'] as String?;
          if (action == 'cancelled_by_rider') {
            _log("🔔 UserSessionManager: RIDE CANCELLED - Showing card!");
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
      _log("UserSessionManager: Error handling message: $e");
      _log("UserSessionManager: StackTrace: $stackTrace");
    }
  }

  Future<void> _handleEarningsUpdate(Map<String, dynamic> messageData) async {
    try {
      // Parse earnings — the WS message may send them as int or double.
      final rawEarnings = messageData['new_total_earnings'];
      final double? newTotalEarnings = rawEarnings is num ? rawEarnings.toDouble() : null;
      final rawTrip = messageData['trip_earnings'];
      final double? tripEarnings = rawTrip is num ? rawTrip.toDouble() : null;

      if (newTotalEarnings == null || _currentUser == null) {
        _log("Earnings update: missing data, ignoring");
        return;
      }

      // Sanity-check: earnings must not decrease or jump by more than $10,000
      final current = _currentUser!.total_earnings ?? 0.0;
      if (newTotalEarnings < 0 || newTotalEarnings - current > 10000) {
        _log("Earnings update rejected: suspicious value $newTotalEarnings (current $current)");
        // Verify from backend rather than applying the potentially spoofed value
        await _refreshEarningsFromBackend();
        return;
      }

      _log("Earnings update: $current → $newTotalEarnings (trip: +${tripEarnings?.toStringAsFixed(2) ?? '?'})");

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

      await updateUser(updatedUser);
    } catch (e) {
      _log("Error handling earnings update: $e");
    }
  }

  Future<void> _checkMissedRideRequests() async {
    if (_appContext == null) return;
    try {
      final response = await AuthApiService.getPendingRideRequests();
      if (response.success && response.data != null) {
        final List<dynamic> pending =
            response.data!['pending_requests'] as List<dynamic>? ?? [];
        for (final req in pending) {
          final data = req as Map<String, dynamic>;
          if (data['temp_request_id'] != null) {
            GlobalNotificationOverlay().showRideRequestCard(_appContext!, data);
          }
        }
      }
    } catch (e) {
      _log('_checkMissedRideRequests error: $e');
    }
  }

  Future<void> _refreshEarningsFromBackend() async {
    try {
      final response = await BaseApiService.get<Map<String, dynamic>>(
        '/owner/profile/',
        fromJson: (json) => json,
      );
      if (response.success && response.data != null && _currentUser != null) {
        final raw = response.data!['total_earnings'];
        final double? verified = raw is num ? raw.toDouble() : null;
        if (verified != null) {
          final updatedUser = User(
            id: _currentUser!.id,
            username: _currentUser!.username,
            email: _currentUser!.email,
            phoneNumber: _currentUser!.phoneNumber,
            profilePicture: _currentUser!.profilePicture,
            address: _currentUser!.address,
            verificationStatus: _currentUser!.verificationStatus,
            total_earnings: verified,
          );
          await updateUser(updatedUser);
          _log("Earnings verified from backend: $verified");
        }
      }
    } catch (e) {
      _log("Could not verify earnings from backend: $e");
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

      _log("Connecting to Verification WebSocket");
      _verificationWebSocket = WebSocketChannel.connect(Uri.parse(fullWsUrl));
      _verificationWsSubscription = _verificationWebSocket!.stream.listen(
        (msg) => _handleStripeVerificationMessage(msg),
        onDone: () {
          _log('UserSessionManager: Verification WS disconnected.');
          _verificationWebSocket = null;
          _verificationWsSubscription = null;
        },
        onError: (err) {
          _log('UserSessionManager: Verification WS error: $err');
          _verificationWebSocket = null;
          _verificationWsSubscription = null;
        },
        cancelOnError: true,
      );
    } catch (e) {
      _log("UserSessionManager: Error connecting Verification WebSocket: $e");
      _verificationWebSocket = null;
      _verificationWsSubscription = null;
    }
  }

  void _handleStripeVerificationMessage(dynamic message) {
    _log("UserSessionManager: Stripe Verification Message: $message");
    try {
      final decodedMessage = jsonDecode(message as String);
      final verificationMsg = VerificationCompleteMessage.fromJson(
        decodedMessage,
      );

      if (verificationMsg.type == 'verification_complete') {
        if (verificationMsg.status == 'verified' &&
            verificationMsg.user != null) {
          _log("UserSessionManager: Stripe verification successful.");
          _handleStripeVerificationSuccess(verificationMsg.user!);
        } else {
          _log(
            "UserSessionManager: Stripe verification failed: ${verificationMsg.message}",
          );
        }
        disconnectVerificationWebSocket();
      } else if (verificationMsg.type == 'status_update') {
        _log(
          "UserSessionManager: Verification status: ${verificationMsg.status} - ${verificationMsg.message}",
        );
      } else {
        _log(
          "UserSessionManager: Unknown verification message type: ${verificationMsg.type}",
        );
      }
    } catch (e) {
      _log("UserSessionManager: Error decoding verification message: $e");
    }
  }

  Future<void> _handleStripeVerificationSuccess(
    VerifiedUserData verifiedUserData,
  ) async {
    _log("UserSessionManager: Updating session with verified user data...");

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
    _log("UserSessionManager: Verification success handling complete.");
  }

  void disconnectVerificationWebSocket() {
    if (_verificationWebSocket == null && _verificationWsSubscription == null) {
      return;
    }

    _log("UserSessionManager: Disconnecting Verification WebSocket...");
    _verificationWsSubscription?.cancel();
    _verificationWebSocket?.sink.close().catchError((e) {
      _log("UserSessionManager: Error closing verification WebSocket: $e");
    });
    _verificationWebSocket = null;
    _verificationWsSubscription = null;
  }

  void _scheduleReconnect() {
    if (!_isAuthenticated || _mainWsRelativePath == null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _log('Max reconnect attempts reached, giving up');
      _reconnectAttempts = 0;
      return;
    }
    final delayIndex = _reconnectAttempts.clamp(0, _reconnectDelays.length - 1);
    final delay = _reconnectDelays[delayIndex];
    _reconnectAttempts++;
    _log('Scheduling reconnect in ${delay}s (attempt $_reconnectAttempts)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _attemptReconnectWebSockets();
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // --- Reconnection Logic ---
  Future<void> _attemptReconnectWebSockets() async {
    _log("UserSessionManager: Attempting to reconnect WebSockets...");
    if (_isAuthenticated &&
        _mainWsRelativePath != null &&
        _mainWsRelativePath!.isNotEmpty) {
      if (!_isMainWSConnected && !_isMainWSConnecting) {
        _log("UserSessionManager: Reconnecting main WebSocket...");
        // Refresh JWT before reconnecting — stored path contains the old token
        await BaseApiService.refreshToken();
        final freshToken = await TokenStorageService.getAccessToken();
        if (freshToken != null) {
          _mainWsRelativePath = _injectTokenIntoWsUrl(_mainWsRelativePath!, freshToken);
          await UserStorageService.saveWebSocketPaths(_mainWsRelativePath!, _chatWsRelativePath);
        }
        await _connectWebSocketUsingRelativePath(
          _mainWsRelativePath!,
          isMainSocket: true,
        );
        // After reconnecting, surface any ride requests that arrived while offline
        _checkMissedRideRequests();
      } else {
        _log(
          "UserSessionManager: Main WebSocket already connected/connecting.",
        );
      }
    } else {
      _log(
        "UserSessionManager: Cannot reconnect - not authenticated or no path.",
      );
    }
  }

  String _injectTokenIntoWsUrl(String wsUrl, String freshToken) {
    try {
      final uri = Uri.parse(wsUrl);
      final updated = uri.replace(
        queryParameters: Map.from(uri.queryParameters)..['token'] = freshToken,
      );
      return updated.toString();
    } catch (_) {
      return wsUrl;
    }
  }

  // --- Token Management ---
  Future<bool> refreshSessionTokens() async {
    _log("UserSessionManager: Refreshing session tokens...");
    final success = await BaseApiService.refreshToken();
    if (success) {
      _log("UserSessionManager: Token refresh successful.");
      _isAuthenticated = true;
      notifyListeners();
      return true;
    } else {
      _log("UserSessionManager: Token refresh failed. Logging out.");
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
    _log("UserSessionManager: Updating user data...");
    _currentUser = newUserData;
    _isVerified = _currentUser?.verificationStatus == 'verified';
    await UserStorageService.saveUserJson(jsonEncode(_currentUser!.toJson()));

    if (newAccessToken != null && newRefreshToken != null) {
      await TokenStorageService.saveTokens(newAccessToken, newRefreshToken);
      _log("UserSessionManager: New tokens saved.");
    }
    notifyListeners();
  }

  // --- Public Utility Methods ---
  Future<bool> attemptReconnectMainWebSocket() async {
    _log("UserSessionManager: Public reconnect request...");
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
    _log(
      "UserSessionManager: Cannot reconnect - not authenticated or no path.",
    );
    return false;
  }
}
