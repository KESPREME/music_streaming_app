import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/music_provider.dart'; // To get current user's listening status
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/nearby_service.dart';

// --- BLoC for Social Screen State Management ---
// Events
abstract class SocialEvent {}
class StartNearbyDiscovery extends SocialEvent {}
class StopNearbyDiscovery extends SocialEvent {}
class SendFriendRequestNearby extends SocialEvent {
  final String toDeviceId;
  SendFriendRequestNearby(this.toDeviceId);
}
class NearbyUsersUpdated extends SocialEvent {
  final List<UserModel> users;
  NearbyUsersUpdated(this.users);
}
class FriendRequestActionReceived extends SocialEvent {
  final String deviceId;
  final NearbyService.FriendRequestAction action; // Use aliased enum
  FriendRequestActionReceived(this.deviceId, this.action);
}


// States
enum SocialStatus { initial, discovering, discoveryFailed, connected, disconnected }

class SocialState {
  final SocialStatus status;
  final List<UserModel> discoveredUsers;
  final List<String> connectedDeviceIds; // IDs of devices directly connected via Nearby
  final String? errorMessage;
  final Map<String, NearbyService.FriendRequestAction> friendRequestActions; // Track actions

  SocialState({
    this.status = SocialStatus.initial,
    this.discoveredUsers = const [],
    this.connectedDeviceIds = const [],
    this.errorMessage,
    this.friendRequestActions = const {},
  });

  SocialState copyWith({
    SocialStatus? status,
    List<UserModel>? discoveredUsers,
    List<String>? connectedDeviceIds,
    String? errorMessage,
    Map<String, NearbyService.FriendRequestAction>? friendRequestActions,
    bool clearErrorMessage = false,
  }) {
    return SocialState(
      status: status ?? this.status,
      discoveredUsers: discoveredUsers ?? this.discoveredUsers,
      connectedDeviceIds: connectedDeviceIds ?? this.connectedDeviceIds,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      friendRequestActions: friendRequestActions ?? this.friendRequestActions,
    );
  }
}

// BLoC
class SocialBloc extends Bloc<SocialEvent, SocialState> {
  final NearbyService _nearbyService;
  final AuthService _authService;
  final FirestoreService _firestoreService;
  StreamSubscription? _discoveredUsersSubscription;
  StreamSubscription? _connectedDeviceIdsSubscription;

  SocialBloc(this._nearbyService, this._authService, this._firestoreService) : super(SocialState()) {
    on<StartNearbyDiscovery>(_onStartNearbyDiscovery);
    on<StopNearbyDiscovery>(_onStopNearbyDiscovery);
    on<SendFriendRequestNearby>(_onSendFriendRequestNearby);
    on<NearbyUsersUpdated>(_onNearbyUsersUpdated);
    on<FriendRequestActionReceived>(_onFriendRequestActionReceived);

    // Listen to streams from NearbyService
    _discoveredUsersSubscription = _nearbyService.discoveredUsersStream.listen((users) {
      add(NearbyUsersUpdated(users));
    });
     _connectedDeviceIdsSubscription = _nearbyService.connectedDeviceIdsStream.listen((ids) {
      // Potentially update state based on connected IDs if needed, e.g. for direct messaging status
    });

    _nearbyService.onFriendRequestAction = (deviceId, action) {
        add(FriendRequestActionReceived(deviceId, action));
    };
  }

  Future<void> _onStartNearbyDiscovery(StartNearbyDiscovery event, Emitter<SocialState> emit) async {
    emit(state.copyWith(status: SocialStatus.discovering, clearErrorMessage: true));
    try {
      // Permissions for Nearby Connections (Location is often required)
      if (!await _checkAndRequestPermissions()) {
        emit(state.copyWith(status: SocialStatus.discoveryFailed, errorMessage: "Permissions not granted."));
        return;
      }

      final firebaseUser = _authService.currentFirebaseUser;
      if (firebaseUser == null) {
        emit(state.copyWith(status: SocialStatus.discoveryFailed, errorMessage: "User not logged in."));
        return;
      }
      UserModel? currentUser = await _firestoreService.getUser(firebaseUser.uid);
      if (currentUser == null) {
           // Fallback: This shouldn't happen if signup ensures profile creation
            currentUser = UserModel(id: firebaseUser.uid, name: firebaseUser.displayName ?? "User");
            await _firestoreService.createUser(currentUser); // Create a basic profile
      }

      // Update current user's listening status from MusicProvider before initializing NearbyService
      // This assumes MusicProvider is accessible, or this logic is handled before calling start.
      // For simplicity, we'll assume UserModel passed to initialize is up-to-date.

      await _nearbyService.initialize(currentUser); // Pass the up-to-date UserModel
      await _nearbyService.startAdvertising();
      await _nearbyService.startBrowsing();
      // Initial broadcast of user data
      await _nearbyService.broadcastCurrentUser();

    } catch (e) {
      emit(state.copyWith(status: SocialStatus.discoveryFailed, errorMessage: e.toString()));
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothAdvertise, // For advertising
      Permission.bluetoothScan,     // For browsing
      Permission.bluetoothConnect,  // For connections
      Permission.nearbyWifiDevices, // For Wi-Fi Direct/Awareness on Android 12+
    ].request();

    return statuses[Permission.location]?.isGranted == true &&
           statuses[Permission.bluetoothAdvertise]?.isGranted == true &&
           statuses[Permission.bluetoothScan]?.isGranted == true &&
           statuses[Permission.bluetoothConnect]?.isGranted == true &&
           (statuses[Permission.nearbyWifiDevices]?.isGranted == true || !Platform.isAndroid); // nearbyWifiDevices is Android specific
  }


  Future<void> _onStopNearbyDiscovery(StopNearbyDiscovery event, Emitter<SocialState> emit) async {
    await _nearbyService.stopAdvertising();
    await _nearbyService.stopBrowsing();
    emit(state.copyWith(status: SocialStatus.initial, discoveredUsers: []));
  }

  void _onNearbyUsersUpdated(NearbyUsersUpdated event, Emitter<SocialState> emit) {
    emit(state.copyWith(discoveredUsers: event.users, status: SocialStatus.discovering));
  }

  void _onFriendRequestActionReceived(FriendRequestActionReceived event, Emitter<SocialState> emit) {
    // Update UI based on friend request actions, e.g., show a snackbar or update button state
    final updatedActions = Map<String, NearbyService.FriendRequestAction>.from(state.friendRequestActions);
    updatedActions[event.deviceId] = event.action;
    emit(state.copyWith(friendRequestActions: updatedActions));

    // Example: Show a snackbar (UI logic should ideally be in the widget, listening to state)
    String message = "";
    switch(event.action) {
        case NearbyService.FriendRequestAction.sent: message = "Friend request sent to device ${event.deviceId.substring(0,5)}..."; break;
        case NearbyService.FriendRequestAction.accepted: message = "Friend request accepted by ${event.deviceId.substring(0,5)}..."; break;
        case NearbyService.FriendRequestAction.declined: message = "Friend request declined by ${event.deviceId.substring(0,5)}..."; break;
    }
    // This is just for logging, actual UI update should be declarative based on state.
    print("SocialBloc: FriendRequestActionReceived - $message");
  }

  Future<void> _onSendFriendRequestNearby(SendFriendRequestNearby event, Emitter<SocialState> emit) async {
    final firebaseUser = _authService.currentFirebaseUser;
    if (firebaseUser == null) {
      emit(state.copyWith(errorMessage: "Cannot send request: Not logged in."));
      return;
    }
    try {
      // Send friend request via Firestore
      await _firestoreService.sendFriendRequest(firebaseUser.uid, state.discoveredUsers.firstWhere((u) => u.id == event.toDeviceId).id); // Assuming deviceId is user.id for discovered users
      // Also send a notification via Nearby if connected
      await _nearbyService.sendFriendRequestAction(event.toDeviceId, NearbyService.FriendRequestAction.sent);

      // Update local state to reflect pending request (optional, Firestore is source of truth)
      final updatedActions = Map<String, NearbyService.FriendRequestAction>.from(state.friendRequestActions);
      updatedActions[event.toDeviceId] = NearbyService.FriendRequestAction.sent;
      emit(state.copyWith(friendRequestActions: updatedActions));

    } catch (e) {
      emit(state.copyWith(errorMessage: "Failed to send friend request: ${e.toString()}"));
    }
  }


  @override
  Future<void> close() {
    _discoveredUsersSubscription?.cancel();
    _connectedDeviceIdsSubscription?.cancel();
    _nearbyService.dispose(); // Ensure NearbyService is also disposed
    return super.close();
  }
}


// --- Social Screen Widget ---
class SocialScreen extends StatelessWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final musicProvider = Provider.of<MusicProvider>(context, listen: false); // For current track info

    return BlocProvider(
      create: (context) => SocialBloc(
        NearbyService( // Initialize with callbacks if needed for direct UI updates from service
            // onUserDiscovered: (deviceId, user) => print("Discovered via callback: ${user.name}"),
        ),
        authService,
        firestoreService,
      )..add(StartNearbyDiscovery()), // Start discovery when BLoC is created
      child: Scaffold(
        appBar: AppBar(
          title: Text('Nearby Friends', style: theme.textTheme.headlineSmall),
          actions: [
            BlocBuilder<SocialBloc, SocialState>(
              builder: (context, state) {
                if (state.status == SocialStatus.discovering) {
                  return IconButton(
                    icon: const Icon(Icons.stop_circle_outlined),
                    tooltip: "Stop Discovery",
                    onPressed: () => context.read<SocialBloc>().add(StopNearbyDiscovery()),
                  );
                }
                return IconButton(
                  icon: const Icon(Icons.radar_outlined),
                  tooltip: "Start Discovery",
                  onPressed: () => context.read<SocialBloc>().add(StartNearbyDiscovery()),
                );
              },
            ),
          ],
        ),
        body: BlocConsumer<SocialBloc, SocialState>(
          listener: (context, state) {
            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.errorMessage!), backgroundColor: theme.colorScheme.error),
              );
            }
             // Listen for friend request actions and show Snackbars
            state.friendRequestActions.forEach((deviceId, action) {
                String userName = state.discoveredUsers.firstWhere((u) => u.id == deviceId, orElse: () => UserModel(id: deviceId, name: "Device ${deviceId.substring(0,5)}")).name;
                String message = "";
                 switch(action) {
                    case NearbyService.FriendRequestAction.sent: message = "Friend request sent to $userName."; break;
                    // Accepted/Declined would typically come from Firestore streams for pending requests
                    // but this handles direct nearby notifications if implemented.
                    case NearbyService.FriendRequestAction.accepted: message = "$userName accepted your friend request!"; break;
                    case NearbyService.FriendRequestAction.declined: message = "$userName declined your friend request."; break;
                 }
                 if (message.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                 }
            });
            // Clear actions after showing them to prevent re-showing on every build
            if (state.friendRequestActions.isNotEmpty) {
                context.read<SocialBloc>().emit(state.copyWith(friendRequestActions: {}));
            }

          },
          builder: (context, state) {
            if (state.status == SocialStatus.discovering && state.discoveredUsers.isEmpty) {
              return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Scanning for nearby users...")]));
            }
            if (state.discoveredUsers.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    'No users found nearby. Make sure others have the app open and are discoverable!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                  ),
                ),
              );
            }

            // Update current user's listening status before broadcasting
            // This logic should ideally be more robust, perhaps in MusicProvider or a dedicated service
            final currentTrack = musicProvider.currentTrack;
            final authUser = authService.currentFirebaseUser;
            if (authUser != null) {
                 _firestoreService.updateUserListeningStatus(authUser.uid, currentTrack?.trackName, currentTrack?.artistName);
                 // Also update the local UserModel in NearbyService if it changes
                 // context.read<SocialBloc>()._nearbyService._currentUser = context.read<SocialBloc>()._nearbyService._currentUser.copyWith(
                 //   currentTrackName: currentTrack?.trackName,
                 //   currentTrackArtist: currentTrack?.artistName
                 // );
                 // context.read<SocialBloc>()._nearbyService.broadcastCurrentUser(); // Re-broadcast if status changed
            }


            return ListView.builder(
              itemCount: state.discoveredUsers.length,
              itemBuilder: (context, index) {
                final user = state.discoveredUsers[index];
                final bool isConnected = state.connectedDeviceIds.contains(user.id); // Check if directly connected
                final requestAction = state.friendRequestActions[user.id];

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      // backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                      child: user.avatarUrl == null ? Text(user.name.substring(0,1).toUpperCase(), style: TextStyle(color: theme.colorScheme.onPrimaryContainer)) : null,
                    ),
                    title: Text(user.name, style: theme.textTheme.titleMedium),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isConnected ? "Connected" : "Discoverable", style: theme.textTheme.bodySmall?.copyWith(color: isConnected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.6))),
                        if(user.currentTrackName != null)
                          Text('Listening to: ${user.currentTrackName} by ${user.currentTrackArtist ?? "Unknown"}',
                              style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.secondary),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: _buildTrailingButton(context, theme, user, requestAction),
                    onTap: () {
                      // TODO: Navigate to a user profile screen or chat screen if already friends
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Tapped on ${user.name}")));
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrailingButton(BuildContext context, ThemeData theme, UserModel user, NearbyService.FriendRequestAction? action) {
    if (action == NearbyService.FriendRequestAction.sent) {
      return TextButton(onPressed: null, child: Text("Requested", style: TextStyle(color: theme.disabledColor)));
    }
    // TODO: Check actual friend status from Firestore here, not just nearby action
    // For now, just an Add Friend button if no action or not connected for that action.
    return ElevatedButton.icon(
        icon: Icon(Icons.person_add_alt_1_outlined, size: 18),
        label: Text("Add"),
        style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: theme.textTheme.labelMedium,
        ),
        onPressed: () {
            context.read<SocialBloc>().add(SendFriendRequestNearby(user.id));
        },
    );
  }
}