import 'dart:async';
import 'package:cast/cast.dart';
import 'package:flutter/foundation.dart';

class CastService {
  List<CastDevice> _devices = [];
  CastDevice? _connectedDevice;
  CastSession? _session;
  final _deviceController = StreamController<List<CastDevice>>.broadcast();

  Stream<List<CastDevice>> get devicesStream => _deviceController.stream;
  CastDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;

  Future<void> startDiscovery() async {
    _devices = [];
    _deviceController.add(_devices);

    if (kDebugMode) print('CastService: Starting discovery...');
    
    try {
      // CastDiscoveryService().search() returns a Future<List<CastDevice>>
      _devices = await CastDiscoveryService().search();
      if (kDebugMode) print('CastService: Found ${_devices.length} devices');
      _deviceController.add(List.from(_devices));
    } catch (e) {
      if (kDebugMode) print('CastService: Discovery error: $e');
    }
  }

  void stopDiscovery() {
    // The cast package search stream doesn't have an explicit stop, 
    // but typically we just stop listening. Since CastDevice.search() returns a stream,
    // we just let it be or manage subscriptions if needed. 
    // For now, we just clear our local list.
    if (kDebugMode) print('CastService: Discovery stopped (logically).');
  }

  Future<bool> connect(CastDevice device) async {
    try {
      if (kDebugMode) print('CastService: Connecting to ${device.name}...');
      _session = await CastSessionManager().startSession(device);
      
      if (_session != null) {
        _connectedDevice = device;
        if (kDebugMode) print('CastService: Connected to ${device.name}');
        return true;
      }
    } catch (e) {
      if (kDebugMode) print('CastService: Connection failed: $e');
    }
    return false;
  }

  Future<void> disconnect() async {
    if (_session != null) {
      await _session!.close(); 
      _session = null;
      _connectedDevice = null;
      if (kDebugMode) print('CastService: Disconnected');
    }
  }

  Future<void> loadMedia({
    required String url,
    required String title,
    required String artist,
    required String imageUrl,
    String mimeType = 'audio/mpeg',
  }) async {
    if (_session == null) return;

    if (kDebugMode) print('CastService: Loading media: $title from $url');

    try {
      _session!.sendMessage(CastSession.kNamespaceMedia, {
        'type': 'LOAD',
        'autoPlay': true,
        'currentTime': 0,
        'media': {
          'contentId': url,
          'contentType': mimeType,
          'streamType': 'BUFFERED',
          'metadata': {
            'metadataType': 3, // Music Track
            'title': title,
            'artist': artist,
            'images': [
              {'url': imageUrl}
            ]
          }
        }
      });
    } catch (e) {
      print('CastService: Error loading media: $e');
    }
  }

  Future<void> play() async {
    _sendMessage({'type': 'PLAY'});
  }

  Future<void> pause() async {
    _sendMessage({'type': 'PAUSE'});
  }
  
  Future<void> stop() async {
    _sendMessage({'type': 'STOP'});
  }

  Future<void> seek(double position) async {
    _sendMessage({
      'type': 'SEEK',
      'currentTime': position,
    });
  }
  
  // Helper to send media messages
  void _sendMessage(Map<String, dynamic> message) {
     if (_session == null) return;
     // Add mediaSessionId if available, usually tracked from status updates
     // For simple integration, try standard structure
     // Typically need to listen to MEDIA_STATUS to get mediaSessionId
     // For now, simpler implementation:
     _session!.sendMessage(CastSession.kNamespaceMedia, message);
  }
}
