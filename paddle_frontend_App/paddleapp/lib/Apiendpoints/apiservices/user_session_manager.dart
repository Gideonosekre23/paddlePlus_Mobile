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

class UserSessionManager extends ChangeNotifier with WidgetsBindingObserver {
  User? _currentUser;
  bool _isAuthenticated = false;
  bool _isVerified = false;

  String? _mainWsRelativePath;
  String? _chatWsRelativePath;

  WebSocketChannel? _mainWebSocket;
  WebSocketChannel? _verificationWebSocket; // For Stripe verification flow
  StreamSubscription? _mainWsSubscription;
  StreamSubscription? _verificationWsSubscription;

  bool _isMainWSConnected = false;
  bool _isMainWSConnecting = false;
  bool _isReconnecting = false;
  Timer? _reconnectionTimer;
  int _reconnectionAttempts = 0;
  static const int _maxReconnectionAttempts = 5;
  static const List<int> _reconnectionDelays = [1, 2, 5, 10, 30];

  String? _sessionExpiredReason;

  final List<Map<String, dynamic>> _messageQueue = [];
  bool _isProcessingQueue = false;

  bool _isAppInForeground = true;
  DateTime? _lastBackgroundTime;

  // ✨ ADD: StreamController for broadcasting WebSocket messages
  final StreamController<Map<String, dynamic>> _wsMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

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
  String? get sessionExpiredReason => _sessionExpiredReason;

  Stream<Map<String, dynamic>> get wsMessageStream =>
      _wsMessageController.stream;

  bool get isReconnecting => _reconnectionTimer?.isActive ?? false;
  int get reconnectionAttempts => _reconnectionAttempts;
  List<Map<String, dynamic>> get queuedMessages =>
      List.unmodifiable(_messageQueue);

  String getConnectionStatus() {
    if (_isMainWSConnected) {
      return 'connected';
    } else if (_isMainWSConnecting || isReconnecting) {
      return 'connecting';
    } else if (_reconnectionAttempts >= _maxReconnectionAttempts) {
      return 'failed';
    } else {
      return 'disconnected';
    }
  }

  void initObserver() {
    WidgetsBinding.instance.addObserver(this);
    _log("UserSessionManager: WidgetsBindingObserver added.");
  }

  @override
  void dispose() {
    _log(" UserSessionManager disposing with enhanced cleanup");

    //  Enhanced cleanup
    _cancelReconnectionTimer();
    _messageQueue.clear();

    WidgetsBinding.instance.removeObserver(this);
    _log("UserSessionManager: WidgetsBindingObserver removed.");
    disconnectMainWebSocket();
    disconnectVerificationWebSocket();

    // Close stream controller safely
    if (!_wsMessageController.isClosed) {
      _wsMessageController.close();
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _log("UserSessionManager: AppLifecycleState changed to $state");

    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.paused:
        _handleAppPaused();
        break;
      case AppLifecycleState.inactive:
        // App is transitioning between foreground and background
        break;
      case AppLifecycleState.detached:
        _handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        // App is hidden (iOS specific)
        break;
    }
  }

  // ✅ ADD THESE NEW METHODS HERE:
  void _handleAppResumed() {
    _log("🔄 App resumed - checking WebSocket connection");
    _isAppInForeground = true;

    if (_lastBackgroundTime != null) {
      final backgroundDuration = DateTime.now().difference(
        _lastBackgroundTime!,
      );
      _log(
        "📱 App was in background for ${backgroundDuration.inSeconds} seconds",
      );

      if (backgroundDuration.inSeconds > 30) {
        _log("⏰ Background time exceeded 30s - forcing reconnection");
        _forceReconnection();
      } else {
        _quickConnectionCheck();
      }
    } else {
      _quickConnectionCheck();
    }

    _lastBackgroundTime = null;
  }

  void _handleAppPaused() {
    _log("⏸️ App paused - WebSocket will likely disconnect");
    _isAppInForeground = false;
    _lastBackgroundTime = DateTime.now();
    _cancelReconnectionTimer();
  }

  void _handleAppDetached() {
    _log("🔴 App detached - cleaning up connections");
    _cancelReconnectionTimer();
    disconnectMainWebSocket();
  }

  void _quickConnectionCheck() {
    if (!_isAuthenticated || _mainWsRelativePath == null) {
      _log("🔍 Quick check: Not authenticated or no WS path");
      return;
    }

    if (!_isMainWSConnected && !_isMainWSConnecting) {
      _log(
        "🔍 Quick check: WebSocket not connected - attempting reconnection",
      );
      _attemptReconnectionWithRetry();
    } else if (_isMainWSConnected) {
      _log("🔍 Quick check: WebSocket appears connected - sending ping");
      _sendPingMessage();
    }
  }

  void _forceReconnection() {
    _log("🔄 Forcing WebSocket reconnection");
    disconnectMainWebSocket();
    _resetReconnectionState();
    _attemptReconnectionWithRetry();
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
        // Temporarily assume authenticated to allow isAuthenticated call if needed by AuthApiService
        _isAuthenticated = true;
        _isVerified = _currentUser?.verificationStatus == 'verified';

        final validSession = await AuthApiService.isAuthenticated();
        if (validSession) {
          _log("UserSessionManager: Session is valid with backend.");
          _mainWsRelativePath = await UserStorageService.getMainWebSocketPath();
          _chatWsRelativePath = await UserStorageService.getChatWebSocketPath();
          _attemptReconnectWebSockets(); // Attempt to connect WS if paths exist
        } else {
          _log(
            "UserSessionManager: Session invalid or expired according to backend. Logging out.",
          );
          await logout(
            notifyApi: false,
          ); // Don't call API logout if session is already invalid
        }
      } catch (e) {
        _log(
          "UserSessionManager: Error loading session data: $e. Logging out.",
        );
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
    _sessionExpiredReason = null;
    await TokenStorageService.saveTokens(
      loginData.accessToken,
      loginData.refreshToken,
    );
    _currentUser = loginData.user;
    await UserStorageService.saveUserJson(jsonEncode(_currentUser!.toJson()));

    _isAuthenticated = true;
    _isVerified = _currentUser?.verificationStatus == 'verified';

    _mainWsRelativePath =
        loginData.wsUrl; // This is the relative path from backend
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
    } else {
      _log(
        "UserSessionManager: Warning - Main WebSocket URL from login is null.",
      );
    }

    notifyListeners();
    _log(
      "UserSessionManager: Login completed. MainWS connected: $_isMainWSConnected",
    );
  }

  Future<void> logout({bool notifyApi = true}) async {
    _log("UserSessionManager: Logging out (notifyApi: $notifyApi)...");
    if (notifyApi && _isAuthenticated) {
      final refreshTokenVal = await TokenStorageService.getRefreshToken();
      if (refreshTokenVal != null) {
        // Call backend logout endpoint
        // Pass the refreshToken string directly
        await AuthApiService.logout(refreshTokenVal);
      }
    }
    await TokenStorageService.clearTokens();
    await UserStorageService.clearAllUserData(); // Clears userJson and WS paths

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

  // --- Main Notification WebSocket ---

  Future<void> _connectWebSocketUsingRelativePath(
    String relativePath, {
    required bool isMainSocket,
  }) async {
    if (isMainSocket) {
      if (_isMainWSConnecting || _isMainWSConnected) {
        _log(
          "UserSessionManager: Main WebSocket already connecting or connected for $relativePath.",
        );
        return;
      }
      _isMainWSConnecting = true;
      notifyListeners();
    }
    // Add similar logic for chat WebSocket if you manage its connecting state separately

    try {
      String httpBaseUrl =
          BaseApiService.baseUrl; // Get base URL (e.g., http://10.0.2.2:8000)
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
        String pathSegment =
            relativePath.startsWith('/') ? relativePath : '/$relativePath';
        fullWsUrl = '$wsScheme://$wsHostPort$pathSegment';
      }

      _log("Attempting WS connect (isMain: $isMainSocket)");

      if (isMainSocket) {
        disconnectMainWebSocket(); // Ensure any old connection is closed
        _mainWebSocket = WebSocketChannel.connect(Uri.parse(fullWsUrl));
        _mainWsSubscription = _mainWebSocket!.stream.listen(
          (msg) {
            _handleIncomingNotification(msg, isMainSocket: true);
          },
          onDone: () {
            _log(
              'UserSessionManager: Main WS disconnected (onDone) from $fullWsUrl.',
            );
            _isMainWSConnected = false;
            _isMainWSConnecting = false;
            _mainWebSocket = null; // Important to nullify
            _mainWsSubscription = null; // Important to nullify
            notifyListeners();
            // Optionally attempt auto-reconnect here after a delay, or rely on app resume
          },
          onError: (err) {
            _log('UserSessionManager: Main WS error for $fullWsUrl: $err');
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
        _log(
          'UserSessionManager: Main WS connection initiated to $fullWsUrl.',
        );
      }

      notifyListeners();
    } catch (e) {
      _log(
        "UserSessionManager: Error establishing WebSocket connection for $relativePath: $e",
      );
      if (isMainSocket) {
        _isMainWSConnected = false;
        _isMainWSConnecting = false;
      }

      notifyListeners();
    }
  }

  void disconnectMainWebSocket() {
    if (_mainWebSocket == null && _mainWsSubscription == null) {
      return; // Already disconnected
    }
    _log("UserSessionManager: Disconnecting Main WebSocket...");
    _mainWsSubscription?.cancel();
    _mainWebSocket?.sink.close().catchError((e) {
      _log("UserSessionManager: Error closing main WebSocket sink: $e");
    });
    _mainWebSocket = null;
    _mainWsSubscription = null;
    if (_isMainWSConnected || _isMainWSConnecting) {
      _isMainWSConnected = false;
      _isMainWSConnecting = false;
      notifyListeners();
    }
  }

  void _handleIncomingNotification(
    dynamic message, {
    required bool isMainSocket,
  }) {
    _log("📨 Incoming message: $message");

    try {
      final decodedMessage = jsonDecode(message as String);

      if (decodedMessage == null || decodedMessage is! Map<String, dynamic>) {
        _log("❌ Invalid message format");
        return;
      }

      final String? messageType = decodedMessage['type'] as String?;

      if (messageType == null) {
        _log("❌ Message missing type field");
        return;
      }

      // Handle special message types
      switch (messageType) {
        case 'ping':
          _handlePingMessage(decodedMessage);
          break;
        case 'pong':
          _handlePongMessage(decodedMessage);
          break;
        case 'connection_ack':
          _log("✅ Connection acknowledged by server");
          _resetReconnectionState();
          break;
        default:
          // Regular message - broadcast to app
          if (!_wsMessageController.isClosed) {
            _wsMessageController.add(decodedMessage);
          }
          _log("✅ Message broadcasted: $messageType");
      }

      // Reset reconnection attempts on successful message
      if (_reconnectionAttempts > 0) {
        _log("📡 Connection stable - resetting reconnection attempts");
        _resetReconnectionState();
      }
    } catch (e, stackTrace) {
      _log("❌ Error handling message: $e");
      _log("📍 Stack trace: $stackTrace");
    }
  }

  void _handlePingMessage(Map<String, dynamic> message) {
    _log("🏓 Received ping - sending pong");
    if (_mainWebSocket != null) {
      try {
        _mainWebSocket!.sink.add(
          jsonEncode({
            'type': 'pong',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }),
        );
      } catch (e) {
        _log("❌ Failed to send pong: $e");
      }
    }
  }

  void _handlePongMessage(Map<String, dynamic> message) {
    _log("Received pong - connection alive");
  }

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
        String pathSegment =
            verificationWsUrl.startsWith('/')
                ? verificationWsUrl
                : '/$verificationWsUrl';
        fullWsUrl = '$wsScheme://$wsHostPort$pathSegment';
      }

      _log(
        "UserSessionManager: Connecting to Verification WebSocket: $fullWsUrl",
      );
      _verificationWebSocket = WebSocketChannel.connect(Uri.parse(fullWsUrl));
      _verificationWsSubscription = _verificationWebSocket!.stream.listen(
        (msg) {
          _handleStripeVerificationMessage(msg);
        },
        onDone: () {
          _log(
            'UserSessionManager: Verification WS disconnected (onDone) from $fullWsUrl.',
          );
          _verificationWebSocket = null;
          _verificationWsSubscription = null;
        },
        onError: (err) {
          _log(
            'UserSessionManager: Verification WS error for $fullWsUrl: $err',
          );
          _verificationWebSocket = null;
          _verificationWsSubscription = null;
        },
        cancelOnError: true,
      );
    } catch (e) {
      _log(
        "UserSessionManager: Error establishing Verification WebSocket connection: $e",
      );
      _verificationWebSocket = null;
      _verificationWsSubscription = null;
    }
  }

  void _handleStripeVerificationMessage(dynamic message) {
    _log("UserSessionManager: Stripe Verification WS Message: $message");
    try {
      final decodedMessage = jsonDecode(message as String);
      final verificationMsg = VerificationCompleteMessage.fromJson(
        decodedMessage,
      );

      if (verificationMsg.type == 'verification_complete') {
        if (verificationMsg.status == 'verified' &&
            verificationMsg.user != null) {
          _log(
            "UserSessionManager: Stripe verification successful via WebSocket.",
          );
          _handleStripeVerificationSuccess(verificationMsg.user!);
        } else {
          _log(
            "UserSessionManager: Stripe verification not successful via WebSocket. Status: ${verificationMsg.status}, Message: ${verificationMsg.message}",
          );
        }
        disconnectVerificationWebSocket();
      } else if (verificationMsg.type == 'status_update') {
        _log(
          "UserSessionManager: Stripe verification status update: ${verificationMsg.status} - ${verificationMsg.message}",
        );
      } else {
        _log(
          "UserSessionManager: Unknown message type from verification WebSocket: ${verificationMsg.type}",
        );
      }
    } catch (e) {
      _log(
        "UserSessionManager: Error decoding Stripe verification message: $e",
      );
    }
  }

  Future<void> _handleStripeVerificationSuccess(
    VerifiedUserData verifiedUserData,
  ) async {
    _log(
      "UserSessionManager: Stripe verification successful. Updating session with new comprehensive user data...",
    );

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
    );

    await UserStorageService.saveUserJson(jsonEncode(_currentUser!.toJson()));

    _isAuthenticated = true;
    _isVerified = true;

    bool reconnectedWs = false;
    if (verifiedUserData.wsUrl != null && verifiedUserData.wsUrl!.isNotEmpty) {
      _mainWsRelativePath = verifiedUserData.wsUrl;
      _chatWsRelativePath = verifiedUserData.chatWsUrl;

      await UserStorageService.saveWebSocketPaths(
        _mainWsRelativePath!,
        _chatWsRelativePath,
      );
      _log(
        "UserSessionManager: New WebSocket paths received and saved. Main: $_mainWsRelativePath",
      );

      disconnectMainWebSocket();
      await _connectWebSocketUsingRelativePath(
        _mainWsRelativePath!,
        isMainSocket: true,
      );
      reconnectedWs = true;
    } else {
      _log(
        "UserSessionManager: No new ws_url provided in VerifiedUserData. Existing connection (if any) will be used or re-attempted on resume.",
      );
      if (!_isMainWSConnected &&
          !_isMainWSConnecting &&
          _mainWsRelativePath != null) {
        await _connectWebSocketUsingRelativePath(
          _mainWsRelativePath!,
          isMainSocket: true,
        );
        reconnectedWs = true;
      }
    }

    notifyListeners();
    _log(
      "UserSessionManager: Session updated after Stripe verification. User: ${_currentUser?.username}, Verified: $_isVerified, MainWS Connected: $_isMainWSConnected (after potential reconnect: $reconnectedWs)",
    );
  }

  void disconnectVerificationWebSocket() {
    if (_verificationWebSocket == null && _verificationWsSubscription == null) {
      return;
    }
    _log("UserSessionManager: Disconnecting Verification WebSocket...");
    _verificationWsSubscription?.cancel();
    _verificationWebSocket?.sink.close().catchError((e) {
      _log(
        "UserSessionManager: Error closing verification WebSocket sink: $e",
      );
    });
    _verificationWebSocket = null;
    _verificationWsSubscription = null;
  }

  Future<void> _attemptReconnectWebSockets() async {
    _log("🔄 Legacy reconnect called - using enhanced version");
    await _attemptReconnectionWithRetry();
  }

  Future<void> _attemptReconnectionWithRetry() async {
    if (_isReconnecting) return;
    if (!_isAuthenticated || _mainWsRelativePath == null) {
      _log("Cannot reconnect: not authenticated or no WS path");
      return;
    }

    if (_reconnectionAttempts >= _maxReconnectionAttempts) {
      _log("Max reconnection attempts reached");
      _handleMaxReconnectionAttemptsReached();
      return;
    }

    _isReconnecting = true;
    _reconnectionAttempts++;
    _log(
      "🔄 Reconnection attempt $_reconnectionAttempts/$_maxReconnectionAttempts",
    );

    try {
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

      if (_isMainWSConnected) {
        _log("Reconnection successful");
        _resetReconnectionState();
        _processQueuedMessages();
        notifyListeners();
      } else {
        _log("Reconnection failed - scheduling retry");
        _scheduleReconnectionRetry();
      }
    } catch (e) {
      _log("Reconnection error: $e");
      _scheduleReconnectionRetry();
    } finally {
      _isReconnecting = false;
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

  Future<bool> refreshSessionTokens() async {
    final success = await BaseApiService.refreshToken();
    if (success) {
      _sessionExpiredReason = null;
      _isAuthenticated = true;
      notifyListeners();
      return true;
    } else {
      _sessionExpiredReason = 'Your session has expired. Please log in again.';
      await logout(notifyApi: false);
      return false;
    }
  }

  Future<bool> handleApiUnauthorized() async {
    return await refreshSessionTokens();
  }

  Future<void> updateUser(
    User newUserData, {
    String? newAccessToken,
    String? newRefreshToken,
  }) async {
    _log("🔄 UserSessionManager: Updating user data...");
    _log(
      "🔄 Old user: ${_currentUser?.username} | ${_currentUser?.profilePicture}",
    );
    _log(
      "🔄 New user: ${newUserData.username} | ${newUserData.profilePicture}",
    );

    _currentUser = newUserData;
    _isVerified = _currentUser?.verificationStatus == 'verified';
    await UserStorageService.saveUserJson(jsonEncode(_currentUser!.toJson()));

    if (newAccessToken != null && newRefreshToken != null) {
      await TokenStorageService.saveTokens(newAccessToken, newRefreshToken);
      _log("UserSessionManager: New tokens saved during user update.");
    }

    _log("✅ UserSessionManager: User updated successfully");
    _log("✅ Final profile picture: ${_currentUser?.profilePicture}");
    notifyListeners();
  }

  Future<bool> attemptReconnectMainWebSocket() async {
    _log(
      "UserSessionManager: Public request to reconnect Main WebSocket (isAuthenticated: $_isAuthenticated, mainWsPath: $_mainWsRelativePath)",
    );
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
      _log(
        "UserSessionManager: Main WebSocket already connected or connecting during public attempt.",
      );
      return _isMainWSConnected;
    }
    _log(
      "UserSessionManager: Cannot attempt public reconnect - not authenticated or no path.",
    );
    return false;
  }

  // ✅ ADD THESE HELPER METHODS:
  void _scheduleReconnectionRetry() {
    if (_reconnectionAttempts >= _maxReconnectionAttempts) {
      _handleMaxReconnectionAttemptsReached();
      return;
    }

    final delayIndex = (_reconnectionAttempts - 1).clamp(
      0,
      _reconnectionDelays.length - 1,
    );
    final delay = _reconnectionDelays[delayIndex];

    _log("⏰ Scheduling reconnection retry in ${delay}s");

    _cancelReconnectionTimer();
    _reconnectionTimer = Timer(Duration(seconds: delay), () {
      if (_isAppInForeground) {
        _attemptReconnectionWithRetry();
      } else {
        _log("📱 App in background - postponing reconnection");
      }
    });

    notifyListeners();
  }

  void _resetReconnectionState() {
    _reconnectionAttempts = 0;
    _cancelReconnectionTimer();
  }

  void _cancelReconnectionTimer() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
  }

  void _handleMaxReconnectionAttemptsReached() {
    _log("🔴 Max reconnection attempts reached");
    _cancelReconnectionTimer();

    if (!_wsMessageController.isClosed) {
      _wsMessageController.add({
        'type': 'connection_failed',
        'data': {
          'message':
              'Unable to establish connection after $_maxReconnectionAttempts attempts',
          'attempts': _reconnectionAttempts,
        },
      });
    }

    notifyListeners();
  }

  void _sendPingMessage() {
    if (_mainWebSocket != null && _isMainWSConnected) {
      try {
        _mainWebSocket!.sink.add(
          jsonEncode({
            'type': 'ping',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }),
        );
        _log("📡 Ping sent");
      } catch (e) {
        _log("❌ Failed to send ping: $e");
        _handleConnectionError();
      }
    }
  }

  void _handleConnectionError() {
    _log("🔴 Connection error detected");
    _isMainWSConnected = false;
    _isMainWSConnecting = false;

    if (_isAppInForeground) {
      _log("📱 App in foreground - attempting immediate reconnection");
      _attemptReconnectionWithRetry();
    }

    notifyListeners();
  }

  Future<void> _processQueuedMessages() async {
    if (_isProcessingQueue || _messageQueue.isEmpty) {
      return;
    }

    _isProcessingQueue = true;
    _log("🔄 Processing ${_messageQueue.length} queued messages");

    try {
      while (_messageQueue.isNotEmpty) {
        final message = _messageQueue.removeAt(0);
        message.remove('queued_at');

        if (!_wsMessageController.isClosed) {
          _wsMessageController.add(message);
        }

        await Future.delayed(const Duration(milliseconds: 100));
      }

      _log("✅ All queued messages processed");
    } catch (e) {
      _log("❌ Error processing queued messages: $e");
    } finally {
      _isProcessingQueue = false;
    }
  }
}
