// Chat Message
class ChatMessage {
  final int id;
  final String content;
  final int sender;
  final int senderId;
  final String senderUsername;
  final DateTime timestamp;
  final bool isRead;

  const ChatMessage({
    required this.id,
    required this.content,
    required this.sender,
    required this.senderId,
    required this.senderUsername,
    required this.timestamp,
    required this.isRead,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    print('ChatMessage.fromJson: $json');

    return ChatMessage(
      id: json['id'] as int,
      content: json['content'] as String,
      sender: json['sender'] as int,
      senderId: json['sender_id'] as int,
      senderUsername: json['sender_username'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['is_read'] as bool? ?? false,
    );
  }

  bool isFromCurrentUser(int currentUserId) => senderId == currentUserId;

  @override
  String toString() {
    return 'ChatMessage(id: $id, content: $content, sender: $senderUsername, timestamp: $timestamp)';
  }
}

// New Message Notification
class NewMessageNotification {
  final String type;
  final ChatMessage message;
  final String tripId;
  final DateTime timestamp;

  const NewMessageNotification({
    required this.type,
    required this.message,
    required this.tripId,
    required this.timestamp,
  });

  factory NewMessageNotification.fromJson(Map<String, dynamic> json) =>
      NewMessageNotification(
        type: json['type'] as String,
        message: ChatMessage.fromJson(json['message'] as Map<String, dynamic>),
        tripId: json['trip_id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

// Send Message Request
class SendMessageRequest {
  final String content;

  const SendMessageRequest({required this.content});

  Map<String, dynamic> toJson() {
    return {'type': 'send_message', 'content': content};
  }
}

class ChatRoom {
  final int id;
  final String tripId;
  final List<ChatMessage> messages;
  final DateTime createdAt;

  const ChatRoom({
    required this.id,
    required this.tripId,
    required this.messages,
    required this.createdAt,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'] as int,
      tripId: json['trip_id'] as String,
      messages:
          (json['messages'] as List<dynamic>?)
              ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

// Mark Read Request
class MarkReadRequest {
  final String action;

  const MarkReadRequest({this.action = 'mark_read'});

  Map<String, dynamic> toJson() => {'action': action};
}

// ✨ ADD: Chat session data to pass to ChatPage
class ChatSession {
  final String tripId;
  final String? bikeOwnerName;
  final int? bikeOwnerId;
  final String token;

  const ChatSession({
    required this.tripId,
    this.bikeOwnerName,
    this.bikeOwnerId,
    required this.token,
  });
}
