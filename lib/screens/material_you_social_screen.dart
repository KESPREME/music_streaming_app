import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/music_provider.dart';
import '../services/firestore_service.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouSocialScreen extends StatefulWidget {
  const MaterialYouSocialScreen({super.key});

  @override
  State<MaterialYouSocialScreen> createState() => _MaterialYouSocialScreenState();
}

class _MaterialYouSocialScreenState extends State<MaterialYouSocialScreen> {
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

  Future<void> sendFriendRequest(UserModel user, ColorScheme colorScheme) async {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Friend request sent to ${user.name}.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Failed to send friend request: ${e.toString()}"),
          backgroundColor: colorScheme.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      appBar: AppBar(
        backgroundColor: MaterialYouTokens.surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Social',
          style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 80,
                color: colorScheme.onSurface.withValues(alpha: 0.1),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'No friends yet',
                textAlign: TextAlign.center,
                style: MaterialYouTypography.titleMedium(
                  colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Nearby discovery is not available in this build.',
                textAlign: TextAlign.center,
                style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
