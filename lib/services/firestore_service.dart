import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/friend_request_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  final CollectionReference _usersCollection = FirebaseFirestore.instance.collection('users');
  final CollectionReference _friendRequestsCollection = FirebaseFirestore.instance.collection('friend_requests');

  // --- User Management ---

  Future<void> createUser(UserModel user) async {
    try {
      await _usersCollection.doc(user.id).set(user.toMap());
    } catch (e) {
      debugPrint('Error creating user: $e');
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
      debugPrint('Error fetching user: $e');
      return null;
    }
  }

  Future<void> updateUser(UserModel user) async {
    try {
      await _usersCollection.doc(user.id).update(user.toMap());
    } catch (e) {
      debugPrint('Error updating user: $e');
      throw Exception('Failed to update user profile.');
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

    final requestDocRef = _friendRequestsCollection.doc(); // Create a new doc ref for auto-ID
    final newRequest = FriendRequestModel(
      id: requestDocRef.id, // Use Firestore's auto-generated ID
      senderId: senderId,
      receiverId: receiverId,
      status: FriendRequestStatus.pending,
      timestamp: Timestamp.now(),
    );
    try {
      await requestDocRef.set(newRequest.toMap());
    } catch (e) {
      debugPrint('Error sending friend request: $e');
      throw Exception('Failed to send friend request.');
    }
  }
}
