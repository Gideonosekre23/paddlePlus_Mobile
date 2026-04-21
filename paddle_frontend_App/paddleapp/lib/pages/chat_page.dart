import 'package:flutter/material.dart';
import '../Apiendpoints/apiservices/chat_api_service.dart';
import '../Apiendpoints/apiservices/user_session_manager.dart';
import '../Apiendpoints/models/chat_models.dart';
import 'dart:async';

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
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final UserSessionManager _sessionManager = UserSessionManager();
  final ChatWebSocketService _chatService = ChatWebSocketService();

  final List<ChatMessage> _messages = [];
  late StreamSubscription<ChatMessage> _messageSubscription;
  late StreamSubscription<String> _errorSubscription;
  late StreamSubscription<bool> _connectionSubscription;
  late StreamSubscription<String> _tripStatusSubscription;

  bool _isConnected = false;
  bool _isConnecting = false;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    print('ChatPage: initState called with tripId: ${widget.tripId}');
    _currentUserId = _sessionManager.currentUser?.id;

    // ✅ ADD: Listen to text changes for send button reactivity
    _messageController.addListener(() {
      setState(() {}); // Rebuild to update send button color
    });

    _setupSubscriptions();
    _connectToChat();
  }

  @override
  void dispose() {
    print('ChatPage: dispose called');
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription.cancel();
    _errorSubscription.cancel();
    _connectionSubscription.cancel();
    _tripStatusSubscription.cancel();
    super.dispose();
  }

  void _setupSubscriptions() {
    print('ChatPage: Setting up subscriptions...');

    // Listen to incoming messages
    _messageSubscription = _chatService.messageStream.listen(
      (message) {
        print('ChatPage: ✅ Received message: ${message.content}');
        if (mounted) {
          setState(() {
            _messages.add(message);
          });
          _scrollToBottom();
        }
      },
      onError: (error) {
        print('ChatPage: Message stream error: $error');
      },
    );

    // Listen to errors
    _errorSubscription = _chatService.errorStream.listen(
      (error) {
        print('ChatPage: ❌ Error: $error');
        if (mounted) {
          _showErrorSnackbar(error);
        }
      },
      onError: (error) {
        print('ChatPage: Error stream error: $error');
      },
    );

    // Listen to connection status
    _connectionSubscription = _chatService.connectionStream.listen(
      (isConnected) {
        print('ChatPage: Connection status changed: $isConnected');
        if (mounted) {
          setState(() {
            _isConnected = isConnected;
            _isConnecting = false;
          });
        }
      },
      onError: (error) {
        print('ChatPage: Connection stream error: $error');
      },
    );

    // Listen to trip status changes (just show dialog, navbar handles navigation)
    _tripStatusSubscription = _chatService.tripStatusStream.listen(
      (status) {
        print('ChatPage: Trip status changed: $status');
        if (mounted) {
          _handleTripStatusChange(status);
        }
      },
      onError: (error) {
        print('ChatPage: Trip status stream error: $error');
      },
    );
  }

  void _handleTripStatusChange(String status) {
    if (status == 'completed' || status == 'cancelled' || status == 'ended') {
      print('ChatPage: Trip ended, showing message...');
      _showTripEndedDialog(status);
    }
  }

  Future<void> _showTripEndedDialog(String status) async {
    if (!mounted) return;

    String title;
    String message;
    IconData icon;
    Color color;

    switch (status) {
      case 'completed':
        title = 'Trip Completed';
        message =
            '🎉 Trip completed successfully!\nThank you for using our service.';
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'cancelled':
        title = 'Trip Cancelled';
        message = '❌ Trip was cancelled.\nYou can start a new trip anytime.';
        icon = Icons.cancel;
        color = Colors.orange;
        break;
      default:
        title = 'Trip Ended';
        message = '🔚 Trip has ended.\nChat will close automatically.';
        icon = Icons.info;
        color = Colors.blue;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _connectToChat() async {
    if (widget.tripId == null) {
      _showErrorSnackbar('No trip ID provided');
      return;
    }

    if (mounted) {
      setState(() {
        _isConnecting = true;
      });
    }

    print('ChatPage: Attempting to connect to chat for trip: ${widget.tripId}');
    final success = await _chatService.connectToChat(tripId: widget.tripId!);

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _isConnected = success;
      });
    }

    if (!success && mounted) {
      _showErrorSnackbar('Failed to connect to chat');
    } else if (success) {
      print('ChatPage: ✅ Successfully connected to chat');
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    if (!_isConnected) {
      _showErrorSnackbar('Not connected to chat');
      return;
    }

    final messageText = _messageController.text.trim();
    print('ChatPage: Sending message: $messageText');

    _messageController.clear();
    _chatService.sendMessage(messageText);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    if (_isConnecting) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: Colors.orange.shade100,
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Connecting to chat...', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    if (!_isConnected) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: Colors.red.shade100,
        child: Row(
          children: [
            const Icon(Icons.error, size: 16, color: Colors.red),
            const SizedBox(width: 8),
            const Text('Disconnected', style: TextStyle(fontSize: 12)),
            const Spacer(),
            TextButton(
              onPressed: _connectToChat,
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.green.shade100,
      child: const Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: Colors.green),
          SizedBox(width: 8),
          Text('Connected', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final bool isMe = message.isFromCurrentUser(_currentUserId ?? 0);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color:
              isMe
                  ? const Color.fromARGB(255, 118, 172, 198)
                  : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              Text(
                message.senderUsername,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message.content,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation with ${widget.bikeOwnerName ?? 'the bike owner'}',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat with ${widget.bikeOwnerName ?? 'Bike Owner'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (widget.tripId != null)
              Text(
                'Trip #${widget.tripId}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        backgroundColor: const Color.fromARGB(255, 118, 172, 198),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Connection status bar
          _buildConnectionStatus(),

          // Messages area
          Expanded(
            child:
                _messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return _buildMessageBubble(_messages[index]);
                      },
                    ),
          ),

          // Message input area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0, -1),
                  blurRadius: 4,
                  color: Colors.black.withOpacity(0.1),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText:
                            _isConnected
                                ? 'Type a message...'
                                : 'Reconnect to send messages',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        enabled: _isConnected,
                      ),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      enabled: _isConnected,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color:
                          _isConnected &&
                                  _messageController.text.trim().isNotEmpty
                              ? const Color.fromARGB(255, 118, 172, 198)
                              : Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed:
                          _isConnected &&
                                  _messageController.text.trim().isNotEmpty
                              ? _sendMessage
                              : null, // ✅ Also disable button when no text
                      icon: const Icon(Icons.send, color: Colors.white),
                      splashRadius: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
