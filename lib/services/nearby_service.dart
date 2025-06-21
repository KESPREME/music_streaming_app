import 'dart:async';
import 'dart:convert'; // For encoding/decoding JSON payloads
import 'dart:io'; // For Platform checks
import 'package:flutter/foundation.dart'; // For kDebugMode
// import 'package:flutter_nearby_connections/flutter_nearby_connections.dart'; // Commented out
// import 'package:uuid/uuid.dart'; // Commented out - Uuid was only for Firestore IDs before
import '../models/user_model.dart'; // Your UserModel

// --- Mock classes for flutter_nearby_connections ---
// These are simplified placeholders to allow the code to compile without the actual package.
// The functionality will not work.

class Nearby {
  Future<void> stopAdvertising() async {}
  Future<void> stopBrowsing() async {}
  Future<void> stopAllEndpoints() async {}
  void stateChangedSubscription({required Function(List<ConnectionInfo> devicesList) callback}) {}
  void dataReceivedSubscription({required Function(dynamic data) callback}) {}
  Future<bool> startAdvertising(String userName, dynamic strategy, {required String serviceId, Function? onConnectionInitiated, Function? onConnectionResult, Function? onDisconnected}) async { return true; }
  Future<bool> startBrowsing(String userName, dynamic strategy, {required String serviceId, Function? onServiceFound, Function? onServiceLost}) async { return true; }
  Future<void> requestConnection(String userName, String deviceId, {Function? onConnectionInitiated, Function? onConnectionResult, Function? onDisconnected}) async {}
  Future<void> acceptConnection(String deviceId, {Function? onPayLoadRecieved, Function? onPayloadTransferUpdate}) async {}
  Future<void> sendBytesPayload(String deviceId, Uint8List bytes) async {}
  Future<void> disconnectFromEndpoint(String deviceId) async {}
}

enum SessionState { connected, disconnected, notConnected } // Simplified
enum Strategy { P2P_STAR } // Simplified
enum Status { CONNECTED, REJECTED, ERROR } // Simplified

class ConnectionInfo {
  final String deviceId;
  final SessionState state;
  final String endpointName;
  final String authenticationToken;
  ConnectionInfo({required this.deviceId, required this.state, this.endpointName = "", this.authenticationToken = ""});
}

class ReceivedData {
  final String deviceId;
  final String message;
  final Uint8List bytes;
  ReceivedData({required this.deviceId, required this.message, required this.bytes});
}
// --- End Mock classes ---


// Payload structure for nearby communication
class NearbyPayload {
  final String type; // e.g., 'userData', 'friendRequest', 'chatMessage'
  final dynamic data;

  NearbyPayload({required this.type, required this.data});

  Map<String, dynamic> toJson() => {'type': type, 'data': data};

  factory NearbyPayload.fromJson(Map<String, dynamic> json) {
    return NearbyPayload(type: json['type'], data: json['data']);
  }
}

class NearbyService {
  final Nearby _nearby = Nearby();
  final String _serviceType = 'tune-link'; // Unique service type for your app

  // User details for broadcasting (should be updated from Auth/MusicProvider)
  late UserModel _currentUser;
  String get currentUserId => _currentUser.id;

  // Discovered devices: key is deviceId, value is UserModel
  final Map<String, UserModel> _discoveredUsers = {};
  final StreamController<List<UserModel>> _discoveredUsersController = StreamController.broadcast();
  Stream<List<UserModel>> get discoveredUsersStream => _discoveredUsersController.stream;

  // Connected devices: key is deviceId
  final Map<String, ConnectionInfo> _connectedDevices = {};
  final StreamController<List<String>> _connectedDeviceIdsController = StreamController.broadcast();
  Stream<List<String>> get connectedDeviceIdsStream => _connectedDeviceIdsController.stream;


  // Callbacks for UI updates
  final Function(String deviceId, UserModel user)? onUserDiscovered; // User found via browsing
  final Function(String deviceId)? onUserLost; // User no longer discoverable
  final Function(String deviceId, String message)? onMessageReceived; // Generic message
  final Function(String deviceId, FriendRequestAction action)? onFriendRequestAction; // Specific action


NearbyService({this.onUserDiscovered, this.onUserLost, this.onMessageReceived, this.onFriendRequestAction});

// Moved FriendRequestAction enum outside the class
enum FriendRequestAction { sent, accepted, declined }

  Future<void> initialize(UserModel currentUser) async {
    _currentUser = currentUser;
    await _nearby.stopAdvertising();
    await _nearby.stopBrowsing();
    await _nearby.stopAllEndpoints();
    _subscribeToStateChanges();
  }

  void _subscribeToStateChanges() {
    _nearby.stateChangedSubscription(callback: (devicesList) {
      devicesList.forEach((device) {
        if (kDebugMode) {
          print("Nearby State Change: DeviceId: ${device.deviceId}, State: ${device.state}");
        }
        if (device.state == SessionState.connected) {
          if (!_connectedDevices.containsKey(device.deviceId)) {
            _connectedDevices[device.deviceId] = device;
             _connectedDeviceIdsController.add(_connectedDevices.keys.toList());
            if (kDebugMode) print("Connected to: ${device.deviceId}");
            // Optionally send current user data upon connection
            // sendCurrentUserPayload(device.deviceId, _currentUser);
          }
        } else if (device.state == SessionState.disconnected) {
          if (_connectedDevices.containsKey(device.deviceId)) {
            _connectedDevices.remove(device.deviceId);
            _connectedDeviceIdsController.add(_connectedDevices.keys.toList());
            if (kDebugMode) print("Disconnected from: ${device.deviceId}");
          }
        }
      });
    });

    _nearby.dataReceivedSubscription(callback: (data) {
      if (kDebugMode) {
        print("Data received from ${data.deviceId}: ${data.message}");
      }
      try {
        final payloadJson = jsonDecode(data.message);
        final payload = NearbyPayload.fromJson(payloadJson);

        switch(payload.type) {
          case 'userData':
            final userMap = payload.data as Map<String, dynamic>;
            final user = UserModel.fromMap(userMap);
            _discoveredUsers[data.deviceId] = user;
            _discoveredUsersController.add(_discoveredUsers.values.toList());
            onUserDiscovered?.call(data.deviceId, user);
            break;
          case 'friendRequestSent':
             onFriendRequestAction?.call(data.deviceId, FriendRequestAction.sent);
            break;
          case 'friendRequestAccepted':
             onFriendRequestAction?.call(data.deviceId, FriendRequestAction.accepted);
             break;
          case 'friendRequestDeclined':
             onFriendRequestAction?.call(data.deviceId, FriendRequestAction.declined);
             break;
          // Add more cases for chat messages, etc.
          default:
            onMessageReceived?.call(data.deviceId, data.message); // Generic message
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error decoding received data: $e");
        }
        onMessageReceived?.call(data.deviceId, data.message); // Treat as generic if decode fails
      }
    });
  }

  Future<bool> startAdvertising() async {
    try {
      await _nearby.startAdvertising(
        _currentUser.name, // Advertise current user's name
        Strategy.P2P_STAR, // Recommended strategy
        serviceId: _serviceType,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: (deviceId, status) {
          if (kDebugMode) print("Advertising Connection Result: $deviceId, Status: $status");
           if (status == Status.CONNECTED) {
             sendCurrentUserPayload(deviceId, _currentUser); // Send user data after connection
           }
        },
        onDisconnected: (deviceId) {
          if (kDebugMode) print("Advertising Disconnected: $deviceId");
          _connectedDevices.remove(deviceId);
          _connectedDeviceIdsController.add(_connectedDevices.keys.toList());
        },
      );
      if (kDebugMode) print("Started advertising as ${_currentUser.name}");
      return true;
    } catch (e) {
      if (kDebugMode) print("Error starting advertising: $e");
      return false;
    }
  }

  Future<bool> startBrowsing() async {
    try {
      await _nearby.startBrowsing(
        _currentUser.name, // Your user's name (can be anything for browsing)
        Strategy.P2P_STAR,
        serviceId: _serviceType,
        onServiceFound: (deviceId, name, serviceId) {
          // This callback is for service discovery, not direct user data.
          // Connection needs to be initiated to exchange user data.
          if (kDebugMode) print("Service found: $deviceId, Name: $name, ServiceId: $serviceId. Requesting connection...");
          if (!_connectedDevices.containsKey(deviceId) && deviceId != _currentUser.id) { // Avoid connecting to self
             _nearby.requestConnection(
              _currentUser.name,
              deviceId,
              onConnectionInitiated: _onConnectionInitiated,
              onConnectionResult: (id, status) {
                if (kDebugMode) print("Browsing Connection Result: $id, Status: $status");
                 if (status == Status.CONNECTED) {
                    sendCurrentUserPayload(id, _currentUser); // Send own data after connecting
                 }
              },
              onDisconnected: (id) {
                if (kDebugMode) print("Browsing Disconnected: $id");
                 _connectedDevices.remove(id);
                 _connectedDeviceIdsController.add(_connectedDevices.keys.toList());
                 _discoveredUsers.remove(id); // Also remove from discovered if disconnected
                 _discoveredUsersController.add(_discoveredUsers.values.toList());
                 onUserLost?.call(id);
              },
            );
          }
        },
        onServiceLost: (deviceId) {
          if (kDebugMode) print("Service lost: $deviceId");
          _discoveredUsers.remove(deviceId);
          _discoveredUsersController.add(_discoveredUsers.values.toList());
          onUserLost?.call(deviceId);
        },
      );
      if (kDebugMode) print("Started browsing for services");
      return true;
    } catch (e) {
      if (kDebugMode) print("Error starting browsing: $e");
      return false;
    }
  }

  void _onConnectionInitiated(String deviceId, ConnectionInfo connectionInfo) {
    if (kDebugMode) {
      print("Connection initiated with $deviceId, Name: ${connectionInfo.endpointName}, AuthToken: ${connectionInfo.authenticationToken}");
    }
    // Automatically accept connections for simplicity in this example
    // In a real app, you might want to show a confirmation dialog
    _nearby.acceptConnection(
      deviceId,
      onPayLoadRecieved: (endpointId, payload) async {
        // This is where you'd handle direct payloads during connection if needed,
        // but primary data exchange is handled by dataReceivedSubscription after connection.
        if (kDebugMode) print("Payload received during connection from $endpointId: ${payload.bytes}");
      },
      onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {
        // Handle payload transfer updates (e.g., progress)
      },
    );
  }

  Future<void> sendPayload(String deviceId, NearbyPayload payload) async {
    if (_connectedDevices.containsKey(deviceId)) {
      try {
        final message = jsonEncode(payload.toJson());
        await _nearby.sendBytesPayload(deviceId, Uint8List.fromList(message.codeUnits));
        if (kDebugMode) print("Sent payload to $deviceId: ${payload.type}");
      } catch (e) {
        if (kDebugMode) print("Error sending payload to $deviceId: $e");
      }
    } else {
      if (kDebugMode) print("Cannot send payload: $deviceId not connected.");
    }
  }

  // Specific payload sending methods
  Future<void> sendCurrentUserPayload(String deviceId, UserModel user) async {
    final payload = NearbyPayload(type: 'userData', data: user.toMap());
    await sendPayload(deviceId, payload);
  }

  Future<void> broadcastCurrentUser() async {
    final payload = NearbyPayload(type: 'userData', data: _currentUser.toMap());
    for (String deviceId in _connectedDevices.keys) {
       await sendPayload(deviceId, payload);
    }
     if (kDebugMode && _connectedDevices.isNotEmpty) print("Broadcasted current user data to all connected devices.");
  }

  // Example: Send a friend request action
  Future<void> sendFriendRequestAction(String toDeviceId, FriendRequestAction action) async {
    String type;
    switch(action) {
      case FriendRequestAction.sent: type = 'friendRequestSent'; break;
      case FriendRequestAction.accepted: type = 'friendRequestAccepted'; break;
      case FriendRequestAction.declined: type = 'friendRequestDeclined'; break;
      // Add a default case to satisfy the non-nullable assignment, though with an enum this should ideally not be hit.
      default:
        if (kDebugMode) print("Error: Unknown FriendRequestAction: $action");
        throw ArgumentError("Unknown FriendRequestAction: $action");
    }
    // Data could include sender/receiver IDs if needed, or just the action type
    final payload = NearbyPayload(type: type, data: {'fromUserId': _currentUser.id});
    await sendPayload(toDeviceId, payload);
  }


  Future<void> stopAdvertising() async {
    await _nearby.stopAdvertising();
    if (kDebugMode) print("Stopped advertising");
  }

  Future<void> stopBrowsing() async {
    await _nearby.stopBrowsing();
    if (kDebugMode) print("Stopped browsing");
  }

  Future<void> disconnectFromDevice(String deviceId) async {
    if (_connectedDevices.containsKey(deviceId)) {
      await _nearby.disconnectFromEndpoint(deviceId);
      _connectedDevices.remove(deviceId);
       _connectedDeviceIdsController.add(_connectedDevices.keys.toList());
      if (kDebugMode) print("Disconnected from $deviceId");
    }
  }

  Future<void> dispose() async {
    await _nearby.stopAdvertising();
    await _nearby.stopBrowsing();
    await _nearby.stopAllEndpoints(); // Disconnects from all connected devices
    _discoveredUsersController.close();
    _connectedDeviceIdsController.close();
    if (kDebugMode) print("NearbyService disposed");
  }

  // Helper to get a copy of discovered users
  List<UserModel> getDiscoveredUsersList() {
    return List<UserModel>.from(_discoveredUsers.values);
  }
}
