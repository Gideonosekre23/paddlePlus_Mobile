import 'dart:convert';
import 'dart:async';
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

  bool _isConnected = false;
  bool _isConnecting = false;
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
    _tripStatusController ??= StreamController<String>.broadcast(); // ✅ New
  }

  Future<bool> connectToChat({required String tripId}) async {
    if (_isConnecting || (_isConnected && _currentTripId == tripId)) {
      print('ChatService: Already connecting or connected to trip $tripId');
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
      print("ChatService: Connecting to WebSocket: $fullWsUrl");

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

      print('ChatService: ✅ Connected to chat for trip: $tripId');
      return true;
    } catch (e) {
      print('ChatService: ❌ Failed to connect to chat: $e');
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

      print('ChatService: Sending message: $messageJson');
      _channel!.sink.add(messageJson);
      return true;
    } catch (e) {
      print('ChatService: ❌ Failed to send message: $e');
      _errorController?.add('Failed to send message: $e');
      return false;
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      print('ChatService: Received message: $json');

      switch (json['type']) {
        case 'new_message':
          final messageData = json['message'] as Map<String, dynamic>;
          final chatMessage = ChatMessage.fromJson(messageData);
          _messageController?.add(chatMessage);
          print('ChatService: ✅ New message added to stream');
          break;

        case 'connection_established':
          print('ChatService: Connection established: ${json['message']}');
          break;

        // ✅ Handle trip status changes
        case 'trip_status_update':
          final status = json['status'] as String;
          print('ChatService: Trip status changed to: $status');
          _tripStatusController?.add(status);

          // If trip ends, close the connection
          if (status == 'completed' || status == 'cancelled') {
            print('ChatService: Trip ended, disconnecting...');
            Future.delayed(const Duration(seconds: 2), disconnect);
          }
          break;

        case 'trip_ended':
          print('ChatService: Trip ended notification');
          _tripStatusController?.add('ended');
          Future.delayed(const Duration(seconds: 2), disconnect);
          break;

        case 'error':
          final error = json['error'] ?? json['message'] ?? 'Unknown error';
          print('ChatService: Server error: $error');
          _errorController?.add(error);
          break;

        default:
          print('ChatService: Unknown message type: ${json['type']}');
      }
    } catch (e) {
      print('ChatService: ❌ Failed to parse message: $e');
      _errorController?.add('Failed to parse message: $e');
    }
  }

  void _handleError(dynamic error) {
    final errorMessage = error.toString();
    print('ChatService: ❌ WebSocket error: $errorMessage');
    _isConnected = false;
    _isConnecting = false;
    _connectionController?.add(false);
    _errorController?.add('Connection error: $errorMessage');
  }

  void _handleDisconnect() {
    print('ChatService: 🔌 WebSocket disconnected');
    _isConnected = false;
    _isConnecting = false;
    _currentTripId = null;
    _connectionController?.add(false);
  }

  Future<void> disconnect() async {
    print('ChatService: Disconnecting...');

    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }

    _isConnected = false;
    _isConnecting = false;
    _currentTripId = null;
  }

  Future<void> dispose() async {
    print('ChatService: Disposing...');
    await disconnect();

    await _messageController?.close();
    await _errorController?.close();
    await _connectionController?.close();
    await _tripStatusController?.close();

    _messageController = null;
    _errorController = null;
    _connectionController = null;
    _tripStatusController = null;
  }
}
