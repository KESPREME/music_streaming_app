import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:uuid/uuid.dart'; // Commented out
import '../models/friend_listening.dart'; // Keep if still used for a different feature
import '../models/user_model.dart';
import '../models/friend_request_model.dart';
import '../models/chat_message_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // final Uuid _uuid = Uuid(); // Commented out - replaced with Firestore auto-ID for friend requests

  // Collection references
  final CollectionReference _usersCollection = FirebaseFirestore.instance.collection('users');
  final CollectionReference _friendRequestsCollection = FirebaseFirestore.instance.collection('friend_requests');
  final CollectionReference _chatRoomsCollection = FirebaseFirestore.instance.collection('chat_rooms');

  // --- User Management ---

  Future<void> createUser(UserModel user) async {
    try {
      await _usersCollection.doc(user.id).set(user.toMap());
    } catch (e) {
      print('Error creating user: $e');
      throw Exception('Failed to create user profile.');
    }
  }

  Future<UserModel?> getUser(String userId) async {
    try {
      final doc = await _usersCollection.doc(userId).get();
      if (doc.exists) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      print('Error fetching user: $e');
      return null;
    }
  }

  Future<void> updateUser(UserModel user) async {
    try {
      await _usersCollection.doc(user.id).update(user.toMap());
    } catch (e) {
      print('Error updating user: $e');
      throw Exception('Failed to update user profile.');
    }
  }

  Future<void> updateUserListeningStatus(String userId, String? trackName, String? artistName) async {
    try {
      await _usersCollection.doc(userId).update({
        'currentTrackName': trackName,
        'currentTrackArtist': artistName,
        'lastSeenActive': FieldValue.serverTimestamp(), // Optional: track activity
      });
    } catch (e) {
      print('Error updating user listening status: $e');
      // Non-critical, so don't throw an exception that breaks user flow
    }
  }

  // --- Friend Requests ---

  Future<void> sendFriendRequest(String senderId, String receiverId) async {
    // Check if a request already exists or if they are already friends
    final existingRequestQuery = await _friendRequestsCollection
        .where('senderId', whereIn: [senderId, receiverId])
        .where('receiverId', whereIn: [senderId, receiverId])
        .get();

    if (existingRequestQuery.docs.isNotEmpty) {
      final existingRequest = FriendRequestModel.fromMap(existingRequestQuery.docs.first.data() as Map<String, dynamic>, existingRequestQuery.docs.first.id);
      if (existingRequest.status == FriendRequestStatus.pending) {
        throw Exception('Friend request already pending.');
      } else if (existingRequest.status == FriendRequestStatus.accepted) {
        throw Exception('You are already friends.');
      }
      // If declined, allow sending a new one by creating a new request document.
    }

    // final requestId = _uuid.v4(); // Using Firestore's auto-generated ID
    final requestDocRef = _friendRequestsCollection.doc(); // Create a new doc ref for auto-ID
    final newRequest = FriendRequestModel(
      id: requestDocRef.id, // Use Firestore's auto-generated ID
      senderId: senderId,
      receiverId: receiverId,
      status: FriendRequestStatus.pending,
      timestamp: Timestamp.now(),
    );
    try {
      // await _friendRequestsCollection.doc(requestId).set(newRequest.toMap()); // Old way
      await requestDocRef.set(newRequest.toMap()); // Set data using the new doc ref
    } catch (e) {
      print('Error sending friend request: $e');
      throw Exception('Failed to send friend request.');
    }
  }

  Future<void> respondToFriendRequest(String requestId, FriendRequestStatus newStatus) async {
    try {
      final requestDoc = await _friendRequestsCollection.doc(requestId).get();
      if (!requestDoc.exists) throw Exception("Request not found.");

      final request = FriendRequestModel.fromMap(requestDoc.data() as Map<String, dynamic>, requestDoc.id);

      await _friendRequestsCollection.doc(requestId).update({'status': newStatus.toString().split('.').last});

      if (newStatus == FriendRequestStatus.accepted) {
        // Add to each other's friend lists (e.g., a subcollection or an array in user doc)
        await _usersCollection.doc(request.senderId).collection('friends').doc(request.receiverId).set({'friendSince': Timestamp.now()});
        await _usersCollection.doc(request.receiverId).collection('friends').doc(request.senderId).set({'friendSince': Timestamp.now()});
      }
    } catch (e) {
      print('Error responding to friend request: $e');
      throw Exception('Failed to respond to friend request.');
    }
  }

  Stream<List<FriendRequestModel>> getPendingFriendRequests(String userId) {
    return _friendRequestsCollection
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: FriendRequestStatus.pending.toString().split('.').last)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => FriendRequestModel.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
    });
  }

  Stream<List<UserModel>> getFriends(String userId) {
    return _usersCollection.doc(userId).collection('friends').snapshots().asyncMap((snapshot) async {
      final friendIds = snapshot.docs.map((doc) => doc.id).toList();
      if (friendIds.isEmpty) return [];

      // Fetch user details for each friend ID
      // Firestore 'in' queries are limited to 10 items. For more, batch or fetch individually.
      // This example assumes a small number of friends for simplicity or requires batching for larger lists.
      final List<UserModel> friends = [];
      for (String id in friendIds) {
        final user = await getUser(id);
        if (user != null) friends.add(user);
      }
      return friends;
    });
  }

  // --- Chat ---

  String getChatRoomId(String userId1, String userId2) {
    // Create a consistent chat room ID regardless of who initiated
    return userId1.compareTo(userId2) < 0 ? '${userId1}_$userId2' : '${userId2}_$userId1';
  }

  Future<ChatRoomModel> getOrCreateChatRoom(String userId1, String userId2) async {
    final chatRoomId = getChatRoomId(userId1, userId2);
    final docRef = _chatRoomsCollection.doc(chatRoomId);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      return ChatRoomModel.fromMap(docSnapshot.data() as Map<String, dynamic>, docSnapshot.id);
    } else {
      final newChatRoom = ChatRoomModel(
        id: chatRoomId,
        participantIds: [userId1, userId2],
        lastMessageTimestamp: Timestamp.now(),
        unreadCounts: {userId1: 0, userId2: 0},
      );
      await docRef.set(newChatRoom.toMap());
      return newChatRoom;
    }
  }

  Future<void> sendMessage(String chatRoomId, ChatMessageModel message) async {
    try {
      // Add message to the messages subcollection of the chat room
      await _chatRoomsCollection.doc(chatRoomId).collection('messages').add(message.toMap());
      // Update last message info in the chat room document
      await _chatRoomsCollection.doc(chatRoomId).update({
        'lastMessage': message.text,
        'lastMessageTimestamp': message.timestamp,
        // Increment unread count for the receiver
        'unreadCounts.${message.receiverId}': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error sending message: $e');
      throw Exception('Failed to send message.');
    }
  }

  Stream<List<ChatMessageModel>> getChatMessages(String chatRoomId) {
    return _chatRoomsCollection
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ChatMessageModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  Stream<List<ChatRoomModel>> getUserChatRooms(String userId) {
    return _chatRoomsCollection
        .where('participantIds', arrayContains: userId)
        .orderBy('lastMessageTimestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ChatRoomModel.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
    });
  }

  Future<void> markMessagesAsRead(String chatRoomId, String userId) async {
    // This is a simplified version. A more robust solution might involve
    // updating individual message read status or using batched writes.
    try {
      await _chatRoomsCollection.doc(chatRoomId).update({
        'unreadCounts.$userId': 0,
      });
      // Optionally, update individual messages if needed:
      // final messagesQuery = await _chatRoomsCollection.doc(chatRoomId).collection('messages')
      //   .where('receiverId', isEqualTo: userId).where('isRead', isEqualTo: false).get();
      // WriteBatch batch = _firestore.batch();
      // for (var doc in messagesQuery.docs) {
      //   batch.update(doc.reference, {'isRead': true});
      // }
      // await batch.commit();
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }


  // --- Kept from original for potential different feature ---
  Stream<List<FriendListening>> getFriendListening() {
    // This might need to be adapted or removed if UserModel's currentTrack fields are used instead
    return _firestore.collection('friend_listening').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return FriendListening.fromJson(doc.data() as Map<String, dynamic>);
      }).toList();
    });
  }
}