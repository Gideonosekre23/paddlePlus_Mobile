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

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as int,
    content: json['content'] as String,
    sender: json['sender'] as int,
    senderId: json['sender_id'] as int,
    senderUsername: json['sender_username'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    isRead: json['is_read'] as bool? ?? false,
  );

  bool isFromCurrentUser(int currentUserId) => senderId == currentUserId;
}

// Chat Notification
class ChatNotification {
  final String type;
  final String title;
  final String message;
  final String? tripId;
  final String sender;
  final int senderId;
  final DateTime timestamp;
  final String action;
  final String notificationCategory;

  const ChatNotification({
    required this.type,
    required this.title,
    required this.message,
    this.tripId,
    required this.sender,
    required this.senderId,
    required this.timestamp,
    required this.action,
    required this.notificationCategory,
  });

  factory ChatNotification.fromJson(Map<String, dynamic> json) =>
      ChatNotification(
        type: json['type'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        tripId: json['trip_id']?.toString(),
        sender: json['sender'] as String,
        senderId: json['sender_id'] as int,
        timestamp: DateTime.parse(json['timestamp'] as String),
        action: json['action'] as String,
        notificationCategory: json['notification_category'] as String,
      );

  bool get isChatNotification => notificationCategory == 'chat';
  bool get shouldOpenChat => action == 'open_chat';
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
  final String action;
  final String content;

  const SendMessageRequest({
    required this.content,
    this.action = 'send_message',
  });

  Map<String, dynamic> toJson() => {'action': action, 'content': content};
}

// Mark Read Request
class MarkReadRequest {
  final String action;

  const MarkReadRequest({this.action = 'mark_read'});

  Map<String, dynamic> toJson() => {'action': action};
}

// Chat session data to pass to ChatPage
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
