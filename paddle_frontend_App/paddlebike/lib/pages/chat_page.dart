import 'dart:async';
import 'package:flutter/material.dart';
import 'package:paddlebike/Apiendpoints/apiservices/chat_api_service.dart'; // Your service
import 'package:paddlebike/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddlebike/Apiendpoints/models/chat_models.dart';

class ChatPage extends StatefulWidget {
  final String? tripId;
  final String? bikeOwnerName;
  final int? bikeOwnerId;

  const ChatPage({
    super.key,
    this.tripId,
    this.bikeOwnerName,
    this.bikeOwnerId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  // Controllers
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Services - Using YOUR singleton services
  final UserSessionManager _sessionManager = UserSessionManager();
  final ChatWebSocketService _chatService = ChatWebSocketService();
  final NotificationWebSocketService _notificationService =
      NotificationWebSocketService();

  // Data
  final List<ChatMessage> _messages = [];

  // Subscriptions
  late StreamSubscription<ChatMessage> _messageSubscription;
  late StreamSubscription<String> _chatErrorSubscription;
  late StreamSubscription<bool> _connectionSubscription;
  late StreamSubscription<ChatNotification> _notificationSubscription;
  late StreamSubscription<Map<String, dynamic>> _tripSubscription;

  // State
  bool _isSendingMessage = false;
  bool _tripCompleted = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  // ✅ INITIALIZATION
  Future<void> _initializeChat() async {
    try {
      _setupSubscriptions();
      await _connectToChat();
      await _connectToNotifications();
    } catch (e) {
      print('❌ ChatPage: Initialization error: $e');
      if (mounted) {
        _showErrorSnackbar('Failed to initialize chat: $e');
      }
    }
  }

  // ✅ SETUP SUBSCRIPTIONS
  void _setupSubscriptions() {
    try {
      // Listen to chat messages
      _messageSubscription = _chatService.messageStream.listen(
        (message) {
          if (mounted && !_tripCompleted) {
            setState(() {
              // Avoid duplicate messages
              if (!_messages.any((m) => m.id == message.id)) {
                _messages.add(message);
              }
            });
            _scrollToBottom();
          }
        },
        onError: (error) {
          print('❌ ChatPage: Message stream error: $error');
          if (mounted) {
            _showErrorSnackbar('Message error: $error');
          }
        },
      );

      // Listen to chat errors
      _chatErrorSubscription = _chatService.errorStream.listen((error) {
        print('❌ ChatPage: Chat error stream: $error');
        if (mounted) {
          _showErrorSnackbar(error);
        }
      });

      // Listen to connection status
      _connectionSubscription = _chatService.connectionStream.listen((
        isConnected,
      ) {
        if (mounted) {
          setState(() {
            // Connection status changed
          });

          if (isConnected) {
            _showSuccessSnackbar('Connected to chat');
          } else if (!_tripCompleted) {
            _showErrorSnackbar('Disconnected from chat');
          }
        }
      });

      // Listen to notifications
      _notificationSubscription = _notificationService.notificationStream
          .listen(
            (notification) {
              _handleChatNotification(notification);
            },
            onError: (error) {
              print('❌ ChatPage: Notification stream error: $error');
            },
          );

      // Listen for trip completion from main WebSocket
      _tripSubscription = _sessionManager.wsMessageStream.listen(
        (message) {
          _handleWebSocketMessage(message);
        },
        onError: (error) {
          print('❌ ChatPage: Trip subscription error: $error');
        },
      );
    } catch (e) {
      print('❌ ChatPage: Subscription setup error: $e');
      if (mounted) {
        _showErrorSnackbar('Failed to setup chat subscriptions');
      }
    }
  }

  // ✅ CONNECT TO CHAT
  Future<void> _connectToChat() async {
    if (widget.tripId == null) {
      _showErrorSnackbar('No trip ID provided');
      return;
    }

    try {
      final success = await _chatService.connectToChat(tripId: widget.tripId!);
      if (!success && mounted && !_tripCompleted) {
        _showErrorSnackbar('Failed to connect to chat');
      }
    } catch (e) {
      print('❌ ChatPage: Connect error: $e');
      if (mounted) {
        _showErrorSnackbar('Connection error: $e');
      }
    }
  }

  // ✅ CONNECT TO NOTIFICATIONS
  Future<void> _connectToNotifications() async {
    try {
      final currentUser = _sessionManager.currentUser;
      if (currentUser != null) {
        final userId = _getUserId(currentUser);
        final token = await _getNotificationToken();

        if (token != null) {
          await _notificationService.connectToNotifications(
            userId: userId,
            token: token,
          );
        }
      }
    } catch (e) {
      print('❌ ChatPage: Notification connect error: $e');
    }
  }

  // ✅ GET NOTIFICATION TOKEN
  Future<String?> _getNotificationToken() async {
    try {
      // You might need to implement this based on your token structure
      return _sessionManager.currentUser?.username; // Or access token
    } catch (e) {
      print('❌ ChatPage: Failed to get notification token: $e');
      return null;
    }
  }

  // ✅ HANDLE CHAT NOTIFICATIONS
  void _handleChatNotification(ChatNotification notification) {
    if (!mounted || _tripCompleted) return;

    try {
      if (notification.tripId == widget.tripId) {
        // This is a notification for our current chat
        if (notification.type == 'trip_completed') {
          _handleTripCompletion();
        }
      }
    } catch (e) {
      print('❌ ChatPage: Chat notification handling error: $e');
    }
  }

  // ✅ HANDLE WEBSOCKET MESSAGES (from main notification system)
  void _handleWebSocketMessage(Map<String, dynamic> message) {
    if (!mounted || _tripCompleted) return;

    try {
      if (message['type'] == 'notification') {
        final data = message['data'] as Map<String, dynamic>?;
        if (data == null) return;

        final tripId = data['trip_id']?.toString();
        final messageTitle = message['title']?.toString() ?? '';

        // Check if this is a trip completion notification for this trip
        if (tripId == widget.tripId &&
            (messageTitle.contains('Trip Completed') ||
                data['trip_status'] == 'completed' ||
                data['action'] == 'trip_ended')) {
          print('ChatPage: Trip $tripId completed via main WS');
          _handleTripCompletion();
        }
      }
    } catch (e) {
      print('❌ ChatPage: WebSocket message handling error: $e');
    }
  }

  // ✅ HANDLE TRIP COMPLETION
  void _handleTripCompletion() {
    if (!mounted || _tripCompleted) return;

    setState(() {
      _tripCompleted = true;
    });

    // Add a system message
    final completionMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch,
      content:
          "🎉 Trip completed successfully! This chat will close automatically in 10 seconds.",
      sender: -1,
      senderId: -1,
      senderUsername: "System",
      timestamp: DateTime.now(),
      isRead: true,
    );

    setState(() {
      _messages.add(completionMessage);
    });
    _scrollToBottom();

    // Handle trip completion in chat service
    _chatService.handleTripCompletion(widget.tripId!);

    // Show completion dialog
    _showTripCompletionDialog();
  }

  // ✅ SEND MESSAGE WITH YOUR SERVICE
  Future<void> _sendMessage() async {
    if (_isSendingMessage || _tripCompleted) return;

    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    final currentUser = _sessionManager.currentUser;
    if (currentUser == null) {
      _showErrorSnackbar('User not logged in');
      return;
    }

    setState(() {
      _isSendingMessage = true;
    });

    try {
      _messageController.clear();

      // ✅ USE YOUR SERVICE'S SEND METHOD
      final success = await _chatService.sendMessage(messageText);

      if (!success) {
        _showErrorSnackbar('Failed to send message');
        // Restore message in input
        _messageController.text = messageText;
      }
    } catch (e) {
      print('❌ ChatPage: Send message error: $e');
      _showErrorSnackbar('Failed to send message: $e');
      _messageController.text = messageText; // Restore message
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }

  // ✅ GET USER ID (SAME AS BEFORE)
  int _getUserId(dynamic user) {
    try {
      if (user.id != null) {
        return user.id as int;
      }
    } catch (e) {
      // ID field doesn't exist, use username hash
    }
    return user.username.hashCode.abs();
  }

  // ✅ SCROLL TO BOTTOM
  void _scrollToBottom() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ✅ CHECK IF MESSAGE IS FROM CURRENT USER
  bool _isMessageFromCurrentUser(ChatMessage message) {
    final currentUser = _sessionManager.currentUser;
    if (currentUser == null) return false;

    final currentUserId = _getUserId(currentUser);
    return message.senderId == currentUserId;
  }

  // ✅ CLEANUP
  void _cleanup() {
    try {
      _messageController.dispose();
      _scrollController.dispose();
      _messageSubscription.cancel();
      _chatErrorSubscription.cancel();
      _connectionSubscription.cancel();
      _notificationSubscription.cancel();
      _tripSubscription.cancel();

      // Your services handle their own cleanup
      _chatService.disconnect();
      _notificationService.disconnect();
    } catch (e) {
      print('❌ ChatPage: Cleanup error: $e');
    }
  }

  // ✅ SHOW TRIP COMPLETION DIALOG
  void _showTripCompletionDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 30),
              SizedBox(width: 12),
              Text('Trip Completed!'),
            ],
          ),
          content: const Text(
            'The trip has been completed successfully. This chat will be closed automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                _cleanup();
                Navigator.of(context).pop(); // Close chat
              },
              child: const Text('Close Chat'),
            ),
          ],
        );
      },
    );

    // Auto-close after delay
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        _cleanup();
        Navigator.of(context).pop();
      }
    });
  }

  // ✅ SHOW ERROR SNACKBAR
  void _showErrorSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  // ✅ SHOW SUCCESS SNACKBAR
  void _showSuccessSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ✅ BUILD CONNECTION STATUS
  Widget _buildConnectionStatus() {
    if (_tripCompleted) {
      return Container(
        padding: const EdgeInsets.all(8.0),
        color: Colors.blue.withOpacity(0.2),
        child: const Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.blue),
            SizedBox(width: 8),
            Text(
              'Trip completed',
              style: TextStyle(fontSize: 12, color: Colors.blue),
            ),
          ],
        ),
      );
    }

    if (_chatService.isConnecting) {
      return Container(
        padding: const EdgeInsets.all(8.0),
        color: Colors.orange.withOpacity(0.2),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Connecting...', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    } else if (!_chatService.isConnected) {
      return Container(
        padding: const EdgeInsets.all(8.0),
        color: Colors.red.withOpacity(0.2),
        child: Row(
          children: [
            const Icon(Icons.error, size: 16, color: Colors.red),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Not connected to chat',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: () => _chatService.reconnect(),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(8.0),
        color: Colors.green.withOpacity(0.2),
        child: const Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'Connected',
              style: TextStyle(fontSize: 12, color: Colors.green),
            ),
          ],
        ),
      );
    }
  }

  // ✅ BUILD EMPTY CHAT STATE
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _chatService.isConnected
                ? 'No messages yet.\nSay hello to start the conversation!'
                : _chatService.isConnecting
                ? 'Connecting to chat...'
                : 'Failed to connect to chat',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          if (!_chatService.isConnected && !_chatService.isConnecting) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _chatService.reconnect(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 118, 172, 198),
                foregroundColor: Colors.white,
              ),
              child: const Text('Try Again'),
            ),
          ],
        ],
      ),
    );
  }

  // ✅ BUILD MESSAGE BUBBLE
  Widget _buildMessageBubble(ChatMessage message, int index) {
    final isMe = _isMessageFromCurrentUser(message);
    final isSystemMessage = message.senderId == -1;
    final showTimestamp = _shouldShowTimestamp(index);

    if (isSystemMessage) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message.content,
                style: const TextStyle(
                  color: Colors.blue,
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (showTimestamp)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              _formatTimestampFull(message.timestamp),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            margin: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isMe
                  ? const Color.fromARGB(255, 118, 172, 198)
                  : Colors.grey[300],
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      message.senderUsername,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                Text(
                  message.content,
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87,
                    fontSize: 15,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTimestamp(message.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: isMe ? Colors.white70 : Colors.black45,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.isRead ? Icons.done_all : Icons.done,
                        size: 12,
                        color: message.isRead
                            ? Colors.lightBlueAccent
                            : (isMe ? Colors.white70 : Colors.black45),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ✅ CHECK IF TIMESTAMP SHOULD BE SHOWN
  bool _shouldShowTimestamp(int index) {
    if (index == 0) return true;

    final currentMessage = _messages[index];
    final previousMessage = _messages[index - 1];

    final timeDifference = currentMessage.timestamp.difference(
      previousMessage.timestamp,
    );
    return timeDifference.inMinutes > 30;
  }

  // ✅ BUILD MESSAGE INPUT
  Widget _buildMessageInput() {
    final bool canSendMessages = _chatService.isConnected && !_tripCompleted;

    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: canSendMessages
                        ? Colors.grey[300]!
                        : Colors.grey[400]!,
                  ),
                  color: canSendMessages ? Colors.grey[50] : Colors.grey[200],
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: _tripCompleted
                        ? "Chat ended"
                        : canSendMessages
                        ? "Type your message..."
                        : "Connecting...",
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    hintStyle: TextStyle(color: Colors.grey[500]),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => canSendMessages ? _sendMessage() : null,
                  enabled: canSendMessages,
                  maxLines: null,
                  maxLength: 500,
                  buildCounter:
                      (
                        context, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) {
                        return currentLength > 400
                            ? Text(
                                '${maxLength! - currentLength} characters left',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                ),
                              )
                            : null;
                      },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: canSendMessages && !_isSendingMessage
                    ? const Color.fromARGB(255, 118, 172, 198)
                    : Colors.grey,
                borderRadius: BorderRadius.circular(24),
              ),
              child: IconButton(
                icon: _isSendingMessage
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white),
                onPressed: canSendMessages && !_isSendingMessage
                    ? _sendMessage
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ FORMAT TIMESTAMP (SHORT VERSION)
  // ✅ FORMAT TIMESTAMP (SHORT VERSION)
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    } else if (difference.inDays < 1) {
      return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return _getDayName(timestamp.weekday);
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }

  // ✅ FORMAT TIMESTAMP (FULL VERSION FOR SEPARATORS)
  String _formatTimestampFull(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays < 1) {
      return 'Today ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 2) {
      return 'Yesterday ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${_getDayName(timestamp.weekday)} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  // ✅ GET DAY NAME
  String _getDayName(int weekday) {
    switch (weekday) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return '';
    }
  }

  // ✅ MAIN BUILD METHOD
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.1),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.tripId != null
                  ? 'Trip Chat (${widget.tripId!.substring(0, 8)}...)'
                  : 'Trip Chat',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              _tripCompleted
                  ? 'Trip completed'
                  : widget.bikeOwnerName ?? 'Chat with bike owner',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        backgroundColor: _tripCompleted
            ? Colors.grey[600]
            : const Color.fromARGB(255, 118, 172, 198),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            _cleanup();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          // Connection status icon
          IconButton(
            icon: Icon(
              _tripCompleted
                  ? Icons.check_circle
                  : _chatService.isConnected
                  ? Icons.wifi
                  : _chatService.isConnecting
                  ? Icons.wifi_off
                  : Icons.wifi_off,
              color: _tripCompleted
                  ? Colors.green
                  : _chatService.isConnected
                  ? Colors.green
                  : Colors.red,
            ),
            onPressed: _chatService.isConnected || _tripCompleted
                ? null
                : () => _chatService.reconnect(),
            tooltip: _tripCompleted
                ? 'Trip completed'
                : _chatService.isConnected
                ? 'Connected'
                : 'Tap to reconnect',
          ),
          // Message count badge
          if (_messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_messages.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ✅ CONNECTION STATUS BAR
          _buildConnectionStatus(),

          // ✅ MESSAGES LIST
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index], index);
                    },
                  ),
          ),

          // ✅ DIVIDER
          if (!_tripCompleted) const Divider(height: 1),

          // ✅ MESSAGE INPUT
          if (!_tripCompleted) _buildMessageInput(),

          // ✅ TRIP COMPLETED MESSAGE
          if (_tripCompleted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              color: Colors.blue.withOpacity(0.1),
              child: const Text(
                '🎉 Trip completed! This chat is now read-only.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
