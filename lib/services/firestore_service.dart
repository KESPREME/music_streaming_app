import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/friend_listening.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<FriendListening>> getFriendListening() {
    return _firestore.collection('friend_listening').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return FriendListening.fromJson(doc.data());
      }).toList();
    });
  }
}