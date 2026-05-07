import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:paddleapp/Apiendpoints/apiservices/base_api_service.dart';
import 'package:paddleapp/Apiendpoints/apiservices/token_storage_service.dart';
import '../models/chat_models.dart';

class ChatWebSocketService {
  WebSocketChannel? _channel;
  StreamController<ChatMessage>? _messageController;
  StreamController<String>? _errorController;
  StreamController<bool>? _connectionController;
  StreamController<String>? _tripStatusController;
  StreamController<int>? _messagesReadController;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _intentionalDisconnect = false;
  String? _currentTripId;

  // Streams
  Stream<ChatMessage> get messageStream =>
      _messageController?.stream ?? const Stream.empty();
  Stream<String> get errorStream =>
      _errorController?.stream ?? const Stream.empty();
  Stream<bool> get connectionStream =>
      _connectionController?.stream ?? const Stream.empty();
  Stream<String> get tripStatusStream =>
      _tripStatusController?.stream ?? const Stream.empty();
  Stream<int> get messagesReadStream =>
      _messagesReadController?.stream ?? const Stream.empty();

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get currentTripId => _currentTripId;

  // Singleton pattern
  static final ChatWebSocketService _instance =
      ChatWebSocketService._internal();
  factory ChatWebSocketService() => _instance;
  ChatWebSocketService._internal();

  void _initializeStreams() {
    _messageController ??= StreamController<ChatMessage>.broadcast();
    _errorController ??= StreamController<String>.broadcast();
    _connectionController ??= StreamController<bool>.broadcast();
    _tripStatusController ??= StreamController<String>.broadcast();
    _messagesReadController ??= StreamController<int>.broadcast();
  }

  Future<bool> connectToChat({required String tripId}) async {
    if (_isConnecting || (_isConnected && _currentTripId == tripId)) {
      debugPrint('ChatService: Already connecting or connected to trip $tripId');
      return _isConnected;
    }

    _isConnecting = true;
    _connectionController?.add(false);

    try {
      await disconnect();
      _initializeStreams();

      final token = await TokenStorageService.getAccessToken();
      if (token == null) {
        throw Exception('No access token available');
      }

      // Build WebSocket URL
      String httpBaseUrl = BaseApiService.baseUrl;
      Uri parsedHttpBaseUrl = Uri.parse(httpBaseUrl);
      String wsScheme = parsedHttpBaseUrl.scheme == 'https' ? 'wss' : 'ws';
      String wsHostPort = parsedHttpBaseUrl.host;
      if (parsedHttpBaseUrl.hasPort &&
          parsedHttpBaseUrl.port != 80 &&
          parsedHttpBaseUrl.port != 443) {
        wsHostPort += ':${parsedHttpBaseUrl.port}';
      }

      String fullWsUrl =
          '$wsScheme://$wsHostPort/ws/chat/$tripId/?token=$token';
      debugPrint('[ChatService] Connecting to chat WS for trip $tripId');

      _channel = WebSocketChannel.connect(Uri.parse(fullWsUrl));

      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );

      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );

      _isConnected = true;
      _isConnecting = false;
      _currentTripId = tripId;
      _connectionController?.add(true);

      debugPrint('ChatService: ✅ Connected to chat for trip: $tripId');
      return true;
    } catch (e) {
      debugPrint('ChatService: ❌ Failed to connect to chat: $e');
      _isConnecting = false;
      _isConnected = false;
      _connectionController?.add(false);
      _errorController?.add('Failed to connect: $e');
      return false;
    }
  }

  Future<bool> sendMessage(String content) async {
    if (!_isConnected || _channel == null) {
      _errorController?.add('Not connected to chat');
      return false;
    }

    if (content.trim().isEmpty) {
      _errorController?.add('Message cannot be empty');
      return false;
    }

    try {
      final request = SendMessageRequest(content: content.trim());
      final messageJson = jsonEncode(request.toJson());

      debugPrint('ChatService: Sending message: $messageJson');
      _channel!.sink.add(messageJson);
      return true;
    } catch (e) {
      debugPrint('ChatService: ❌ Failed to send message: $e');
      _errorController?.add('Failed to send message: $e');
      return false;
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      debugPrint('ChatService: Received message: $json');

      switch (json['type']) {
        case 'new_message':
          final messageData = json['message'] as Map<String, dynamic>?;
          if (messageData == null) break;
          final chatMessage = ChatMessage.fromJson(messageData);
          _messageController?.add(chatMessage);
          debugPrint('ChatService: ✅ New message added to stream');
          break;

        case 'connection_established':
          debugPrint('ChatService: Connection established: ${json['message']}');
          break;

        case 'messages_read':
          final readerId = json['reader_id'] as int?;
          if (readerId != null) _messagesReadController?.add(readerId);
          break;

        case 'error':
          final error = json['error'] ?? json['message'] ?? 'Unknown error';
          debugPrint('ChatService: Server error: $error');
          _errorController?.add(error);
          break;

        default:
          debugPrint('ChatService: Unknown message type: ${json['type']}');
      }
    } catch (e) {
      debugPrint('ChatService: ❌ Failed to parse message: $e');
      _errorController?.add('Failed to parse message: $e');
    }
  }

  void _handleError(dynamic error) {
    final errorMessage = error.toString();
    debugPrint('ChatService: ❌ WebSocket error: $errorMessage');
    _isConnected = false;
    _isConnecting = false;
    _connectionController?.add(false);
    _errorController?.add('Connection error: $errorMessage');
  }

  void _handleDisconnect() {
    debugPrint('[ChatService] WebSocket disconnected for trip $_currentTripId');
    _isConnected = false;
    _isConnecting = false;
    _connectionController?.add(false);

    if (!_intentionalDisconnect && _currentTripId != null) {
      final tripId = _currentTripId!;
      _currentTripId = null;
      Future.delayed(const Duration(seconds: 3), () => _reconnectToTrip(tripId));
    } else {
      _currentTripId = null;
    }
  }

  Future<void> _reconnectToTrip(String tripId) async {
    if (_isConnected || _isConnecting) return;
    // Refresh the access token before reconnecting so expired tokens don't block re-auth
    await BaseApiService.refreshToken();
    await connectToChat(tripId: tripId);
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }
    _isConnected = false;
    _isConnecting = false;
    _currentTripId = null;
    _intentionalDisconnect = false;
  }

  Future<void> dispose() async {
    debugPrint('ChatService: Disposing...');
    await disconnect();

    await _messageController?.close();
    await _errorController?.close();
    await _connectionController?.close();
    await _tripStatusController?.close();
    await _messagesReadController?.close();

    _messageController = null;
    _errorController = null;
    _connectionController = null;
    _tripStatusController = null;
    _messagesReadController = null;
  }

  static Future<Map<String, dynamic>?> getChatRoom(String tripId) async {
    final response = await BaseApiService.get<Map<String, dynamic>>(
      '/chat/room/$tripId/',
      fromJson: (json) => json,
      auth: true,
    );
    if (response.success && response.data != null) {
      final data = response.data!;
      final roomId = data['chat_room_id'] as int?;
      final rawMessages = data['messages'] as List<dynamic>? ?? [];
      final messages = rawMessages
          .whereType<Map<String, dynamic>>()
          .map((m) => ChatMessage.fromJson(m))
          .toList();
      return {'chat_room_id': roomId, 'messages': messages};
    }
    return null;
  }

  static Future<int?> getChatRoomId(String tripId) async {
    final result = await getChatRoom(tripId);
    return result?['chat_room_id'] as int?;
  }

  static Future<void> markMessagesRead(int chatRoomId) async {
    try {
      await BaseApiService.put<Map<String, dynamic>>(
        '/chat/read/$chatRoomId/',
        fromJson: (json) => json,
        auth: true,
      );
    } catch (e) {
      debugPrint('ChatService: markMessagesRead failed: $e');
    }
  }
}
