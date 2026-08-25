import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/music_provider.dart';
import '../services/firestore_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/glass_surface.dart';

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
    final accent = theme.colorScheme.primary;
    final loggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [
              Color(0xFF141414),
              Color(0xFF1E1E1E),
              Color(0xFF000000),
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
            children: [
              Text(
                'Social',
                style: GoogleFonts.splineSans(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
              _GlassPanel(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Icon(
                      Icons.people_outline_rounded,
                      size: 72,
                      color: accent.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      loggedIn
                          ? 'Your circle is empty'
                          : 'Share what you play',
                      style: GoogleFonts.splineSans(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loggedIn
                          ? 'Add friends to see their live listening, react to tracks and build shared queues.'
                          : 'Sign in to broadcast your listening live to friends and react to theirs.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.white54,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _FeatureChip(
                            icon: Icons.graphic_eq_rounded, label: 'Live'),
                        const SizedBox(width: 10),
                        _FeatureChip(
                            icon: Icons.favorite_rounded, label: 'React'),
                        const SizedBox(width: 10),
                        _FeatureChip(
                            icon: Icons.queue_music_rounded,
                            label: 'Co-listen'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 16, color: accent),
                        const SizedBox(width: 8),
                        Text(
                          'COMING SOON',
                          style: GoogleFonts.splineSans(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Friend requests are already wired to the backend — the friend picker and live feed land in the next drop.',
                      style: GoogleFonts.outfit(
                        color: Colors.white38,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ],
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
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: 24,
      padding: const EdgeInsets.all(22),
      child: child,
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12.5)),
        ],
      ),
    );
  }
}