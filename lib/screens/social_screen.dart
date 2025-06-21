import 'dart:io'; // Added for Platform check
import 'package:device_info_plus/device_info_plus.dart'; // Added for DeviceInfoPlugin
import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart'; // Commented out
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/music_provider.dart'; // To get current user's listening status
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/nearby_service.dart';

// --- Commenting out BLoC and StreamSubscription for now to resolve package errors ---
// --- The SocialScreen will be a simple placeholder until packages can be added. ---
/*
import 'dart:async';
import 'dart:io'; // Added for Platform check
import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart'; // Commented out
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
  // final NearbyService.FriendRequestAction action; // Use aliased enum - Commented out
  final dynamic action; // Temp placeholder
  FriendRequestActionReceived(this.deviceId, this.action);
}


// States
enum SocialStatus { initial, discovering, discoveryFailed, connected, disconnected }

class SocialState {
  final SocialStatus status;
  final List<UserModel> discoveredUsers;
  final List<String> connectedDeviceIds; // IDs of devices directly connected via Nearby
  final String? errorMessage;
  // final Map<String, NearbyService.FriendRequestAction> friendRequestActions; // Track actions - Commented out
  final Map<String, dynamic> friendRequestActions; // Temp placeholder


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
    // Map<String, NearbyService.FriendRequestAction>? friendRequestActions, // Commented out
    Map<String, dynamic>? friendRequestActions, // Temp placeholder
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
// class SocialBloc extends Bloc<SocialEvent, SocialState> { // Commented out
class SocialBloc { // Temp placeholder
  final NearbyService _nearbyService;
  final AuthService _authService;
  final FirestoreService _firestoreService;
  // StreamSubscription? _discoveredUsersSubscription; // Commented out
  // StreamSubscription? _connectedDeviceIdsSubscription; // Commented out
  dynamic _discoveredUsersSubscription; // Temp placeholder
  dynamic _connectedDeviceIdsSubscription; // Temp placeholder


  // SocialBloc(this._nearbyService, this._authService, this._firestoreService) : super(SocialState()) { // Commented out
  SocialBloc(this._nearbyService, this._authService, this._firestoreService) { // Temp placeholder
    // on<StartNearbyDiscovery>(_onStartNearbyDiscovery); // Commented out
    // on<StopNearbyDiscovery>(_onStopNearbyDiscovery); // Commented out
    // on<SendFriendRequestNearby>(_onSendFriendRequestNearby); // Commented out
    // on<NearbyUsersUpdated>(_onNearbyUsersUpdated); // Commented out
    // on<FriendRequestActionReceived>(_onFriendRequestActionReceived); // Commented out

    // Listen to streams from NearbyService
    _discoveredUsersSubscription = _nearbyService.discoveredUsersStream.listen((users) {
      // add(NearbyUsersUpdated(users)); // Commented out
    });
     _connectedDeviceIdsSubscription = _nearbyService.connectedDeviceIdsStream.listen((ids) {
      // Potentially update state based on connected IDs if needed, e.g. for direct messaging status
    });

    // _nearbyService.onFriendRequestAction = (deviceId, action) { // Commented out
        // add(FriendRequestActionReceived(deviceId, action)); // Commented out
    // };
  }

  // Future<void> _onStartNearbyDiscovery(StartNearbyDiscovery event, Emitter<SocialState> emit) async { // Commented out
  Future<void> _onStartNearbyDiscovery(StartNearbyDiscovery event, dynamic emit) async { // Temp placeholder
    // emit(state.copyWith(status: SocialStatus.discovering, clearErrorMessage: true)); // Commented out
    try {
      // Permissions for Nearby Connections (Location is often required)
      if (!await _checkAndRequestPermissions()) {
        // emit(state.copyWith(status: SocialStatus.discoveryFailed, errorMessage: "Permissions not granted.")); // Commented out
        return;
      }

      final firebaseUser = _authService.currentFirebaseUser;
      if (firebaseUser == null) {
        // emit(state.copyWith(status: SocialStatus.discoveryFailed, errorMessage: "User not logged in.")); // Commented out
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
      // emit(state.copyWith(status: SocialStatus.discoveryFailed, errorMessage: e.toString())); // Commented out
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


  // Future<void> _onStopNearbyDiscovery(StopNearbyDiscovery event, Emitter<SocialState> emit) async { // Commented out
  Future<void> _onStopNearbyDiscovery(StopNearbyDiscovery event, dynamic emit) async { // Temp placeholder
    await _nearbyService.stopAdvertising();
    await _nearbyService.stopBrowsing();
    // emit(state.copyWith(status: SocialStatus.initial, discoveredUsers: [])); // Commented out
  }

  // void _onNearbyUsersUpdated(NearbyUsersUpdated event, Emitter<SocialState> emit) { // Commented out
  void _onNearbyUsersUpdated(NearbyUsersUpdated event, dynamic emit) { // Temp placeholder
    // emit(state.copyWith(discoveredUsers: event.users, status: SocialStatus.discovering)); // Commented out
  }

  // void _onFriendRequestActionReceived(FriendRequestActionReceived event, Emitter<SocialState> emit) { // Commented out
  void _onFriendRequestActionReceived(FriendRequestActionReceived event, dynamic emit) { // Temp placeholder
    // Update UI based on friend request actions, e.g., show a snackbar or update button state
    // final updatedActions = Map<String, NearbyService.FriendRequestAction>.from(state.friendRequestActions); // Commented out
    // updatedActions[event.deviceId] = event.action; // Commented out
    // emit(state.copyWith(friendRequestActions: updatedActions)); // Commented out

    // Example: Show a snackbar (UI logic should ideally be in the widget, listening to state)
    String message = "";
    // switch(event.action) { // Commented out
    //     case NearbyService.FriendRequestAction.sent: message = "Friend request sent to device ${event.deviceId.substring(0,5)}..."; break;
    //     case NearbyService.FriendRequestAction.accepted: message = "Friend request accepted by ${event.deviceId.substring(0,5)}..."; break;
    //     case NearbyService.FriendRequestAction.declined: message = "Friend request declined by ${event.deviceId.substring(0,5)}..."; break;
    // }
    // This is just for logging, actual UI update should be declarative based on state.
    print("SocialBloc: FriendRequestActionReceived - $message");
  }

  // Future<void> _onSendFriendRequestNearby(SendFriendRequestNearby event, Emitter<SocialState> emit) async { // Commented out
  Future<void> _onSendFriendRequestNearby(SendFriendRequestNearby event, dynamic emit) async { // Temp placeholder
    final firebaseUser = _authService.currentFirebaseUser;
    if (firebaseUser == null) {
      // emit(state.copyWith(errorMessage: "Cannot send request: Not logged in.")); // Commented out
      return;
    }
    try {
      // Send friend request via Firestore
      // await _firestoreService.sendFriendRequest(firebaseUser.uid, state.discoveredUsers.firstWhere((u) => u.id == event.toDeviceId).id); // Commented out
      // Also send a notification via Nearby if connected
      // await _nearbyService.sendFriendRequestAction(event.toDeviceId, NearbyService.FriendRequestAction.sent); // Commented out

      // Update local state to reflect pending request (optional, Firestore is source of truth)
      // final updatedActions = Map<String, NearbyService.FriendRequestAction>.from(state.friendRequestActions); // Commented out
      // updatedActions[event.toDeviceId] = NearbyService.FriendRequestAction.sent; // Commented out
      // emit(state.copyWith(friendRequestActions: updatedActions)); // Commented out

    } catch (e) {
      // emit(state.copyWith(errorMessage: "Failed to send friend request: ${e.toString()}")); // Commented out
    }
  }


  // @override // Commented out
  Future<void> close() async { // Changed to async to match super.close if it were Bloc
    _discoveredUsersSubscription?.cancel();
    _connectedDeviceIdsSubscription?.cancel();
    _nearbyService.dispose(); // Ensure NearbyService is also disposed
    // return super.close(); // Commented out
  }

  // Temp methods for placeholder UI
  void add(SocialEvent event) {
    if (event is StartNearbyDiscovery) _onStartNearbyDiscovery(event, null);
    if (event is StopNearbyDiscovery) _onStopNearbyDiscovery(event, null);
    // Add other event handlers if needed for placeholder
  }
  SocialState get state => SocialState(); // Placeholder state
  Stream<SocialState> get stream => Stream.value(SocialState()); // Placeholder stream
  void emit(SocialState state) {} // Placeholder emit
// --- Commenting out BLoC and StreamSubscription for now to resolve package errors ---
// --- The SocialScreen will be a simple placeholder until packages can be added. ---
/*
import 'dart:async';
// No longer needed here as Platform is only in _checkAndRequestPermissions
// import 'dart:io';
import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart'; // Commented out
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/music_provider.dart'; // To get current user's listening status
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/nearby_service.dart'; // This now contains the standalone FriendRequestAction enum

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
  final FriendRequestAction action; // Now refers to the standalone enum
  FriendRequestActionReceived(this.deviceId, this.action);
}


// States
enum SocialStatus { initial, discovering, discoveryFailed, connected, disconnected }

class SocialState {
  final SocialStatus status;
  final List<UserModel> discoveredUsers;
  final List<String> connectedDeviceIds; // IDs of devices directly connected via Nearby
  final String? errorMessage;
  final Map<String, FriendRequestAction> friendRequestActions; // Track actions


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
    Map<String, FriendRequestAction>? friendRequestActions,
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
// class SocialBloc extends Bloc<SocialEvent, SocialState> { // Commented out
class SocialBloc { // Temp placeholder
  final NearbyService _nearbyService;
  final AuthService _authService;
  final FirestoreService _firestoreService;
  // StreamSubscription? _discoveredUsersSubscription; // Commented out
  // StreamSubscription? _connectedDeviceIdsSubscription; // Commented out
  dynamic _discoveredUsersSubscription; // Temp placeholder
  dynamic _connectedDeviceIdsSubscription; // Temp placeholder


  // SocialBloc(this._nearbyService, this._authService, this._firestoreService) : super(SocialState()) { // Commented out
  SocialBloc(this._nearbyService, this._authService, this._firestoreService) { // Temp placeholder
    // on<StartNearbyDiscovery>(_onStartNearbyDiscovery); // Commented out
    // on<StopNearbyDiscovery>(_onStopNearbyDiscovery); // Commented out
    // on<SendFriendRequestNearby>(_onSendFriendRequestNearby); // Commented out
    // on<NearbyUsersUpdated>(_onNearbyUsersUpdated); // Commented out
    // on<FriendRequestActionReceived>(_onFriendRequestActionReceived); // Commented out

    // Listen to streams from NearbyService
    _discoveredUsersSubscription = _nearbyService.discoveredUsersStream.listen((users) {
      // add(NearbyUsersUpdated(users)); // Commented out
    });
     _connectedDeviceIdsSubscription = _nearbyService.connectedDeviceIdsStream.listen((ids) {
      // Potentially update state based on connected IDs if needed, e.g. for direct messaging status
    });

    _nearbyService.onFriendRequestAction = (deviceId, action) {
        // add(FriendRequestActionReceived(deviceId, action)); // Commented out
    };
  }

  // Future<void> _onStartNearbyDiscovery(StartNearbyDiscovery event, Emitter<SocialState> emit) async { // Commented out
  Future<void> _onStartNearbyDiscovery(StartNearbyDiscovery event, dynamic emit) async { // Temp placeholder
    // emit(state.copyWith(status: SocialStatus.discovering, clearErrorMessage: true)); // Commented out
    try {
      // Permissions for Nearby Connections (Location is often required)
      if (!await _checkAndRequestPermissions()) {
        // emit(state.copyWith(status: SocialStatus.discoveryFailed, errorMessage: "Permissions not granted.")); // Commented out
        return;
      }

      final firebaseUser = _authService.currentFirebaseUser;
      if (firebaseUser == null) {
        // emit(state.copyWith(status: SocialStatus.discoveryFailed, errorMessage: "User not logged in.")); // Commented out
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
      // emit(state.copyWith(status: SocialStatus.discoveryFailed, errorMessage: e.toString())); // Commented out
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

    bool allGranted = statuses.values.every((status) => status.isGranted);
     // Special handling for nearbyWifiDevices as it's Android 12+
    if (Platform.isAndroid) { // Need to import 'dart:io' for Platform
        final deviceInfo = await DeviceInfoPlugin().androidInfo; // Needs device_info_plus
        if (deviceInfo.version.sdkInt < 31 && statuses[Permission.nearbyWifiDevices]!.isDenied) {
            print("Nearby Wifi Devices permission not strictly required for this Android version or handled by other BT permissions.");
        } else if (deviceInfo.version.sdkInt >= 31 && !statuses[Permission.nearbyWifiDevices]!.isGranted) {
            allGranted = false;
        }
    }
    return allGranted;
  }


  // Future<void> _onStopNearbyDiscovery(StopNearbyDiscovery event, Emitter<SocialState> emit) async { // Commented out
  Future<void> _onStopNearbyDiscovery(StopNearbyDiscovery event, dynamic emit) async { // Temp placeholder
    await _nearbyService.stopAdvertising();
    await _nearbyService.stopBrowsing();
    // emit(state.copyWith(status: SocialStatus.initial, discoveredUsers: [])); // Commented out
  }

  // void _onNearbyUsersUpdated(NearbyUsersUpdated event, Emitter<SocialState> emit) { // Commented out
  void _onNearbyUsersUpdated(NearbyUsersUpdated event, dynamic emit) { // Temp placeholder
    // emit(state.copyWith(discoveredUsers: event.users, status: SocialStatus.discovering)); // Commented out
  }

  // void _onFriendRequestActionReceived(FriendRequestActionReceived event, Emitter<SocialState> emit) { // Commented out
  void _onFriendRequestActionReceived(FriendRequestActionReceived event, dynamic emit) { // Temp placeholder
    // Update UI based on friend request actions, e.g., show a snackbar or update button state
    // final updatedActions = Map<String, FriendRequestAction>.from(state.friendRequestActions); // Corrected type
    // updatedActions[event.deviceId] = event.action;
    // emit(state.copyWith(friendRequestActions: updatedActions)); // Commented out

    // Example: Show a snackbar (UI logic should ideally be in the widget, listening to state)
    String message = "";
    switch(event.action) {
        case FriendRequestAction.sent: message = "Friend request sent to device ${event.deviceId.substring(0,5)}..."; break;
        case FriendRequestAction.accepted: message = "Friend request accepted by ${event.deviceId.substring(0,5)}..."; break;
        case FriendRequestAction.declined: message = "Friend request declined by ${event.deviceId.substring(0,5)}..."; break;
    }
    // This is just for logging, actual UI update should be declarative based on state.
    print("SocialBloc: FriendRequestActionReceived - $message");
  }

  // Future<void> _onSendFriendRequestNearby(SendFriendRequestNearby event, Emitter<SocialState> emit) async { // Commented out
  Future<void> _onSendFriendRequestNearby(SendFriendRequestNearby event, dynamic emit) async { // Temp placeholder
    final firebaseUser = _authService.currentFirebaseUser;
    if (firebaseUser == null) {
      // emit(state.copyWith(errorMessage: "Cannot send request: Not logged in.")); // Commented out
      return;
    }
    try {
      // Send friend request via Firestore
      // await _firestoreService.sendFriendRequest(firebaseUser.uid, state.discoveredUsers.firstWhere((u) => u.id == event.toDeviceId).id); // Commented out
      // Also send a notification via Nearby if connected
      // await _nearbyService.sendFriendRequestAction(event.toDeviceId, FriendRequestAction.sent); // Corrected type

      // Update local state to reflect pending request (optional, Firestore is source of truth)
      // final updatedActions = Map<String, FriendRequestAction>.from(state.friendRequestActions); // Corrected type
      // updatedActions[event.toDeviceId] = FriendRequestAction.sent; // Corrected type
      // emit(state.copyWith(friendRequestActions: updatedActions)); // Commented out

    } catch (e) {
      // emit(state.copyWith(errorMessage: "Failed to send friend request: ${e.toString()}")); // Commented out
    }
  }


  // @override // Commented out
  Future<void> close() async { // Changed to async to match super.close if it were Bloc
    _discoveredUsersSubscription?.cancel();
    _connectedDeviceIdsSubscription?.cancel();
    _nearbyService.dispose(); // Ensure NearbyService is also disposed
    // return super.close(); // Commented out
  }

  // Temp methods for placeholder UI
  void add(SocialEvent event) {
    if (event is StartNearbyDiscovery) _onStartNearbyDiscovery(event, null);
    if (event is StopNearbyDiscovery) _onStopNearbyDiscovery(event, null);
    // Add other event handlers if needed for placeholder
  }
  SocialState get state => SocialState(); // Placeholder state
  Stream<SocialState> get stream => Stream.value(SocialState()); // Placeholder stream
  void emit(SocialState state) {} // Placeholder emit
}
*/

// --- Social Screen Widget (Simplified Placeholder) ---
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  // Replace BLoC with simple state for now
  bool _isDiscovering = false;
  List<UserModel> _discoveredUsers = [];
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

    final firebaseUser = _authService!.currentFirebaseUser;
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
        icon: Icon(Icons.person_add_alt_1_outlined, size: 18),
        label: Text("Add"),
        style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: theme.textTheme.labelMedium,
        ),
        onPressed: () async {
            if (_authService?.currentFirebaseUser?.uid == null || _firestoreService == null) {
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cannot send request: User not logged in or service unavailable.")));
                 return;
            }
            try {
                await _firestoreService!.sendFriendRequest(_authService!.currentFirebaseUser!.uid, user.id);
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