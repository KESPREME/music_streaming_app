import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/music_provider.dart';
import '../services/firestore_service.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  final Set<String> _requestedUserIds = {};
  String? _errorMessage;
  FirestoreService? _firestoreService;
  MusicProvider? _musicProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firestoreService = Provider.of<FirestoreService>(context, listen: false);
      _musicProvider = Provider.of<MusicProvider>(context, listen: false);
      _syncCurrentUserStatus();
    });
  }

  /// Publishes the current listening status to Firestore.
  Future<void> _syncCurrentUserStatus() async {
    if (_firestoreService == null || _musicProvider == null) return;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      if (mounted) setState(() => _errorMessage = "User not logged in.");
      return;
    }

    UserModel? currentUser = await _firestoreService!.getUser(firebaseUser.uid);
    if (currentUser == null) {
      currentUser = UserModel(
        id: firebaseUser.uid,
        name: firebaseUser.displayName ??
            firebaseUser.email?.split('@').first ??
            "User",
      );
      await _firestoreService!.createUser(currentUser);
    }

    final currentTrack = _musicProvider!.currentTrack;
    currentUser = currentUser.copyWith(
      currentTrackName: currentTrack?.trackName,
      currentTrackArtist: currentTrack?.artistName,
    );
    await _firestoreService!.updateUser(currentUser);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('Social', style: theme.textTheme.headlineSmall)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 80,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'No friends yet',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Nearby discovery is not available in this build.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Kept for future friend-list UI: sends a Firestore-backed friend request.
  Future<void> sendFriendRequest(UserModel user) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser?.uid == null || _firestoreService == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Cannot send request: User not logged in or service unavailable."),
      ));
      return;
    }
    try {
      await _firestoreService!.sendFriendRequest(firebaseUser!.uid, user.id);
      if (mounted) setState(() => _requestedUserIds.add(user.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Friend request sent to ${user.name}.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Failed to send friend request: ${e.toString()}"),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }
}