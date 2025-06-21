// import 'package:equatable/equatable.dart'; // Commented out
import 'package:cloud_firestore/cloud_firestore.dart';

enum FriendRequestStatus {
  pending,
  accepted,
  declined,
}

class FriendRequestModel { // Removed "extends Equatable"
  final String id;
  final String senderId;
  final String receiverId;
  final FriendRequestStatus status;
  final Timestamp timestamp;

  const FriendRequestModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.timestamp,
  });

  // @override
  // List<Object?> get props => [id, senderId, receiverId, status, timestamp]; // Commented out

  factory FriendRequestModel.fromMap(Map<String, dynamic> map, String documentId) {
    return FriendRequestModel(
      id: documentId,
      senderId: map['senderId'] as String,
      receiverId: map['receiverId'] as String,
      status: FriendRequestStatus.values.firstWhere(
        (e) => e.toString() == 'FriendRequestStatus.${map['status']}',
        orElse: () => FriendRequestStatus.pending,
      ),
      timestamp: map['timestamp'] as Timestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'status': status.toString().split('.').last, // Store enum as string
      'timestamp': timestamp,
    };
  }

  FriendRequestModel copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    FriendRequestStatus? status,
    Timestamp? timestamp,
  }) {
    return FriendRequestModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
