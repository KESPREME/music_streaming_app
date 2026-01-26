import 'dart:io'; // Added for Platform check
import 'package:device_info_plus/device_info_plus.dart'; // Added for DeviceInfoPlugin
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter_bloc/flutter_bloc.dart'; // Commented out
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/music_provider.dart'; // To get current user's listening status
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/nearby_service.dart'; // This now contains the standalone FriendRequestAction enum


// --- Social Screen Widget ---

// --- Social Screen Widget (Simplified Placeholder) ---
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  // Replace BLoC with simple state for now
  bool _isDiscovering = false;
  final List<UserModel> _discoveredUsers = [];
  String? _errorMessage;
  // NearbyService instance will be created in initState or passed
  NearbyService? _nearbyService;
  AuthService? _authService;
  FirestoreService? _firestoreService;
  MusicProvider? _musicProvider;


  @override
  void initState() {
    super.initState();
    // Services would typically be injected via Provider or GetIt
    // For this temporary fix, we'll look them up from context if possible,
    // but proper DI is better.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authService = Provider.of<AuthService>(context, listen: false);
      _firestoreService = Provider.of<FirestoreService>(context, listen: false);
      _musicProvider = Provider.of<MusicProvider>(context, listen: false);

      // Initialize NearbyService here
      // It's important that _authService and _firestoreService are available
      if (_authService != null && _firestoreService != null) {
        _nearbyService = NearbyService(
          onUserDiscovered: (deviceId, user) {
            if (mounted) {
              setState(() {
                // Avoid duplicates
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
          // Add other callbacks if needed
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
    if (_nearbyService == null || _authService == null || _firestoreService == null || _musicProvider == null) {
      if (mounted) setState(() => _errorMessage = "Services not initialized.");
      return;
    }

    if (mounted) setState(() { _isDiscovering = true; _errorMessage = null; });

    if (!await _checkAndRequestPermissions()) {
      if (mounted) setState(() { _errorMessage = "Permissions not granted."; _isDiscovering = false; });
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      if (mounted) setState(() { _errorMessage = "User not logged in."; _isDiscovering = false; });
      return;
    }
    UserModel? currentUser = await _firestoreService!.getUser(firebaseUser.uid);
     if (currentUser == null) {
        currentUser = UserModel(id: firebaseUser.uid, name: firebaseUser.displayName ?? firebaseUser.email?.split('@').first ?? "User");
        await _firestoreService!.createUser(currentUser);
    }

    final currentTrack = _musicProvider!.currentTrack;
    currentUser = currentUser.copyWith(
        currentTrackName: currentTrack?.trackName,
        currentTrackArtist: currentTrack?.artistName,
    );
    await _firestoreService!.updateUser(currentUser); // Update Firestore with current listening status

    try {
      await _nearbyService!.initialize(currentUser);
      await _nearbyService!.startAdvertising();
      await _nearbyService!.startBrowsing();
      await _nearbyService!.broadcastCurrentUser();
    } catch (e) {
      if (mounted) setState(() { _errorMessage = e.toString(); _isDiscovering = false; });
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
    // Special handling for nearbyWifiDevices as it's Android 12+
    if (Platform.isAndroid) {
        final deviceInfo = await DeviceInfoPlugin().androidInfo; // Needs device_info_plus
        if (deviceInfo.version.sdkInt < 31 && statuses[Permission.nearbyWifiDevices]!.isDenied) {
            // For older Android, this permission might not be applicable or auto-granted if others are.
            // Consider it granted if others are. This logic might need refinement based on flutter_nearby_connections behavior.
            print("Nearby Wifi Devices permission not strictly required for this Android version or handled by other BT permissions.");
        } else if (deviceInfo.version.sdkInt >= 31 && !statuses[Permission.nearbyWifiDevices]!.isGranted) {
            allGranted = false; // Explicitly require for Android 12+
        }
    }
    return allGranted;
  }


  Future<void> _stopDiscoveryProcess() async {
    if (_nearbyService == null) return;
    await _nearbyService!.stopAdvertising();
    await _nearbyService!.stopBrowsing();
    if (mounted) setState(() { _isDiscovering = false; _discoveredUsers.clear(); });
  }

  @override
  void dispose() {
    _nearbyService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Nearby Friends', style: theme.textTheme.headlineSmall),
        actions: [
          IconButton(
            icon: Icon(_isDiscovering ? Icons.stop_circle_outlined : Icons.radar_outlined),
            tooltip: _isDiscovering ? "Stop Discovery" : "Start Discovery",
            onPressed: _isDiscovering ? _stopDiscoveryProcess : _startDiscoveryProcess,
          ),
        ],
      ),
      body: Builder( // Use Builder to ensure context for ScaffoldMessenger
        builder: (context) {
          if (_errorMessage != null) {
            // Show error prominently, perhaps allow retry
             WidgetsBinding.instance.addPostFrameCallback((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_errorMessage!), backgroundColor: theme.colorScheme.error),
                );
             });
          }

          if (_isDiscovering && _discoveredUsers.isEmpty && _errorMessage == null) {
            return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Scanning for nearby users...")]));
          }
          if (_discoveredUsers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  _errorMessage ?? 'No users found nearby. Make sure others have the app open and are discoverable!',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: _discoveredUsers.length,
            itemBuilder: (context, index) {
              final user = _discoveredUsers[index];
              // final bool isConnected = state.connectedDeviceIds.contains(user.id); // Cannot get this from simple state easily
              // final requestAction = state.friendRequestActions[user.id]; // Cannot get this easily

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: user.avatarUrl == null
                        ? Text(user.name.isNotEmpty ? user.name.substring(0,1).toUpperCase() : "?", style: TextStyle(color: theme.colorScheme.onPrimaryContainer))
                        // : NetworkImage(user.avatarUrl!), // Use NetworkImage if available
                        : null, // Placeholder for NetworkImage if using CachedNetworkImage later
                  ),
                  title: Text(user.name, style: theme.textTheme.titleMedium),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Text(isConnected ? "Connected" : "Discoverable", style: theme.textTheme.bodySmall?.copyWith(color: isConnected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.6))),
                      if(user.currentTrackName != null)
                        Text('Listening to: ${user.currentTrackName} by ${user.currentTrackArtist ?? "Unknown"}',
                            style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.secondary),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                  trailing: _buildTrailingButton(context, theme, user, null), // Pass null for action for now
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Tapped on ${user.name}")));
                  },
                ),
              );
            },
          );
        }
      ),
    );
  }

  // Updated to accept nullable FriendRequestAction
  Widget _buildTrailingButton(BuildContext context, ThemeData theme, UserModel user, FriendRequestAction? action) {
    if (action == FriendRequestAction.sent) {
      return TextButton(onPressed: null, child: Text("Requested", style: TextStyle(color: theme.disabledColor)));
    }
    return ElevatedButton.icon(
        icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
        label: const Text("Add"),
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: theme.textTheme.labelMedium,
        ),
        onPressed: () async {
            final firebaseUser = FirebaseAuth.instance.currentUser;
            if (firebaseUser?.uid == null || _firestoreService == null) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot send request: User not logged in or service unavailable.")));
                 return;
            }
            try {
                await _firestoreService!.sendFriendRequest(firebaseUser!.uid, user.id);
                _nearbyService?.sendFriendRequestAction(user.id, FriendRequestAction.sent);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Friend request sent to ${user.name}.")));
                 // Optionally update local state to show "Requested" immediately
                // This requires managing request state per user in _SocialScreenState
            } catch (e) {
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to send friend request: ${e.toString()}"), backgroundColor: theme.colorScheme.error));
            }
        },
    );
  }
}