import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class ChatMessageModel extends Equatable {
  final String id; // Message ID
  final String chatId; // ID of the chat room/conversation
  final String senderId;
  final String receiverId; // Could be useful for notifications or direct addressing
  final String text;
  final Timestamp timestamp;
  final bool isRead;

  const ChatMessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.timestamp,
    this.isRead = false,
  });

  @override
  List<Object?> get props => [id, chatId, senderId, receiverId, text, timestamp, isRead];

  factory ChatMessageModel.fromMap(Map<String, dynamic> map, String documentId) {
    return ChatMessageModel(
      id: documentId,
      chatId: map['chatId'] as String,
      senderId: map['senderId'] as String,
      receiverId: map['receiverId'] as String,
      text: map['text'] as String,
      timestamp: map['timestamp'] as Timestamp,
      isRead: map['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'timestamp': timestamp,
      'isRead': isRead,
    };
  }

  ChatMessageModel copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? receiverId,
    String? text,
    Timestamp? timestamp,
    bool? isRead,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }
}

// Represents a chat room or conversation between two users
class ChatRoomModel extends Equatable {
  final String id; // Chat room ID (e.g., combination of user IDs)
  final List<String> participantIds;
  final String lastMessage;
  final Timestamp lastMessageTimestamp;
  final Map<String, int> unreadCounts; // Key: userId, Value: unread count for that user

  const ChatRoomModel({
    required this.id,
    required this.participantIds,
    this.lastMessage = '',
    required this.lastMessageTimestamp,
    this.unreadCounts = const {},
  });

  @override
  List<Object?> get props => [id, participantIds, lastMessage, lastMessageTimestamp, unreadCounts];

  factory ChatRoomModel.fromMap(Map<String, dynamic> map, String documentId) {
    return ChatRoomModel(
      id: documentId,
      participantIds: List<String>.from(map['participantIds'] as List<dynamic>),
      lastMessage: map['lastMessage'] as String? ?? '',
      lastMessageTimestamp: map['lastMessageTimestamp'] as Timestamp? ?? Timestamp.now(),
      unreadCounts: Map<String, int>.from(map['unreadCounts'] as Map<dynamic,dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participantIds': participantIds,
      'lastMessage': lastMessage,
      'lastMessageTimestamp': lastMessageTimestamp,
      'unreadCounts': unreadCounts,
    };
  }

  ChatRoomModel copyWith({
    String? id,
    List<String>? participantIds,
    String? lastMessage,
    Timestamp? lastMessageTimestamp,
    Map<String, int>? unreadCounts,
  }) {
    return ChatRoomModel(
      id: id ?? this.id,
      participantIds: participantIds ?? this.participantIds,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTimestamp: lastMessageTimestamp ?? this.lastMessageTimestamp,
      unreadCounts: unreadCounts ?? this.unreadCounts,
    );
  }
}
