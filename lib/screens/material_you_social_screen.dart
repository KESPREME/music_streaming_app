import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/music_provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/nearby_service.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouSocialScreen extends StatefulWidget {
  const MaterialYouSocialScreen({super.key});

  @override
  State<MaterialYouSocialScreen> createState() => _MaterialYouSocialScreenState();
}

class _MaterialYouSocialScreenState extends State<MaterialYouSocialScreen> {
  bool _isDiscovering = false;
  final List<UserModel> _discoveredUsers = [];
  String? _errorMessage;
  NearbyService? _nearbyService;
  AuthService? _authService;
  FirestoreService? _firestoreService;
  MusicProvider? _musicProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authService = Provider.of<AuthService>(context, listen: false);
      _firestoreService = Provider.of<FirestoreService>(context, listen: false);
      _musicProvider = Provider.of<MusicProvider>(context, listen: false);

      if (_authService != null && _firestoreService != null) {
        _nearbyService = NearbyService(
          onUserDiscovered: (deviceId, user) {
            if (mounted) {
              setState(() {
                _discoveredUsers.removeWhere((u) => u.id == user.id);
                _discoveredUsers.add(user);
              });
            }
          },
          onUserLost: (deviceId) {
            if (mounted) {
              setState(() {
                _discoveredUsers.removeWhere((u) => u.id == deviceId);
              });
            }
          },
        );
        _startDiscoveryProcess();
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = "Core services not available.";
          });
        }
      }
    });
  }

  Future<void> _startDiscoveryProcess() async {
    if (_nearbyService == null || _authService == null || 
        _firestoreService == null || _musicProvider == null) {
      if (mounted) setState(() => _errorMessage = "Services not initialized.");
      return;
    }

    if (mounted) setState(() { _isDiscovering = true; _errorMessage = null; });

    if (!await _checkAndRequestPermissions()) {
      if (mounted) {
        setState(() { 
          _errorMessage = "Permissions not granted."; 
          _isDiscovering = false; 
        });
      }
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      if (mounted) {
        setState(() { 
          _errorMessage = "User not logged in."; 
          _isDiscovering = false; 
        });
      }
      return;
    }
    
    UserModel? currentUser = await _firestoreService!.getUser(firebaseUser.uid);
    if (currentUser == null) {
      currentUser = UserModel(
        id: firebaseUser.uid, 
        name: firebaseUser.displayName ?? 
              firebaseUser.email?.split('@').first ?? 
              "User"
      );
      await _firestoreService!.createUser(currentUser);
    }

    final currentTrack = _musicProvider!.currentTrack;
    currentUser = currentUser.copyWith(
      currentTrackName: currentTrack?.trackName,
      currentTrackArtist: currentTrack?.artistName,
    );
    await _firestoreService!.updateUser(currentUser);

    try {
      await _nearbyService!.initialize(currentUser);
      await _nearbyService!.startAdvertising();
      await _nearbyService!.startBrowsing();
      await _nearbyService!.broadcastCurrentUser();
    } catch (e) {
      if (mounted) {
        setState(() { 
          _errorMessage = e.toString(); 
          _isDiscovering = false; 
        });
      }
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothAdvertise,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    
    if (Platform.isAndroid) {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      if (deviceInfo.version.sdkInt < 31 && statuses[Permission.nearbyWifiDevices]!.isDenied) {
        // For older Android versions
      } else if (deviceInfo.version.sdkInt >= 31 && 
                 !statuses[Permission.nearbyWifiDevices]!.isGranted) {
        allGranted = false;
      }
    }
    return allGranted;
  }

  Future<void> _stopDiscoveryProcess() async {
    if (_nearbyService == null) return;
    await _nearbyService!.stopAdvertising();
    await _nearbyService!.stopBrowsing();
    if (mounted) {
      setState(() { 
        _isDiscovering = false; 
        _discoveredUsers.clear(); 
      });
    }
  }

  @override
  void dispose() {
    _nearbyService?.dispose();
    super.dispose();
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Nearby Friends',
          style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isDiscovering ? Icons.stop_circle_outlined : Icons.radar_outlined,
              color: _isDiscovering ? MaterialYouTokens.primaryVibrant : colorScheme.onSurface,
            ),
            tooltip: _isDiscovering ? "Stop Discovery" : "Start Discovery",
            onPressed: _isDiscovering ? _stopDiscoveryProcess : _startDiscoveryProcess,
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_errorMessage != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_errorMessage!),
                  backgroundColor: colorScheme.error,
                ),
              );
            });
          }

          if (_isDiscovering && _discoveredUsers.isEmpty && _errorMessage == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: MaterialYouTokens.primaryVibrant),
                  const SizedBox(height: 16),
                  Text(
                    "Scanning for nearby users...",
                    style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
                  ),
                ],
              ),
            );
          }
          
          if (_discoveredUsers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 80,
                      color: colorScheme.onSurface.withOpacity(0.1),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage ?? 'No users found nearby',
                      textAlign: TextAlign.center,
                      style: MaterialYouTypography.titleMedium(
                        colorScheme.onSurface.withOpacity(0.6)
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Make sure others have the app open and are discoverable!',
                      textAlign: TextAlign.center,
                      style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _discoveredUsers.length,
            itemBuilder: (context, index) {
              final user = _discoveredUsers[index];
              return _buildUserCard(context, user, colorScheme);
            },
          );
        },
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, UserModel user, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: MaterialYouTokens.surfaceContainerDark,
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
        border: Border.all(color: colorScheme.surfaceVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: MaterialYouTokens.primaryVibrant.withOpacity(0.2),
          child: user.avatarUrl == null
              ? Text(
                  user.name.isNotEmpty ? user.name.substring(0, 1).toUpperCase() : "?",
                  style: MaterialYouTypography.titleLarge(MaterialYouTokens.primaryVibrant),
                )
              : null,
        ),
        title: Text(
          user.name,
          style: MaterialYouTypography.titleMedium(colorScheme.onSurface),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user.currentTrackName != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.music_note_rounded,
                    size: 14,
                    color: MaterialYouTokens.primaryVibrant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${user.currentTrackName} • ${user.currentTrackArtist ?? "Unknown"}',
                      style: MaterialYouTypography.bodySmall(MaterialYouTokens.primaryVibrant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: MaterialYouTokens.primaryVibrant,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text("Add"),
          onPressed: () async {
            final firebaseUser = FirebaseAuth.instance.currentUser;
            if (firebaseUser?.uid == null || _firestoreService == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Cannot send request: User not logged in or service unavailable."),
                ),
              );
              return;
            }
            try {
              await _firestoreService!.sendFriendRequest(firebaseUser!.uid, user.id);
              _nearbyService?.sendFriendRequestAction(user.id, FriendRequestAction.sent);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Friend request sent to ${user.name}.")),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Failed to send friend request: ${e.toString()}"),
                    backgroundColor: colorScheme.error,
                  ),
                );
              }
            }
          },
        ),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Tapped on ${user.name}")),
          );
        },
      ),
    );
  }
}
