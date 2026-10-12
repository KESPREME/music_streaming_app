// lib/services/lyrics/paxsenix_key_store.dart
// Where the listener's PaxSenix API key lives.
//
// The Spotify and Musixmatch routes on api.paxsenix.org are keyed, and the key
// is the listener's own: it is typed in by hand, never shipped with the app.
// That makes it a credential, so it goes in the platform keystore rather than
// SharedPreferences, and it is never logged - not even its length.

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The three operations the store needs from a secret store.
///
/// A seam so a test can supply an in-memory map instead of the platform
/// keystore. [FlutterSecureStorage] is adapted to it by default.
abstract class PaxSenixSecretStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _SecureStorageAdapter implements PaxSenixSecretStorage {
  const _SecureStorageAdapter(this._inner);

  final FlutterSecureStorage _inner;

  @override
  Future<String?> read(String key) => _inner.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _inner.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _inner.delete(key: key);
}

/// Persists the PaxSenix API key.
///
/// Every method is safe to call on a device whose keystore is unusable: a read
/// that fails is an empty key, and a write that fails is dropped. A lyrics
/// setting must never be the reason the app cannot start.
class PaxSenixKeyStore {
  PaxSenixKeyStore({PaxSenixSecretStorage? storage})
      : _storage =
            storage ?? const _SecureStorageAdapter(FlutterSecureStorage());

  /// Storage key under which the API key is kept.
  static const String storageKey = 'paxsenix_api_key';

  final PaxSenixSecretStorage _storage;

  /// Whether a key is currently stored, for the settings UI to listen to.
  ///
  /// Starts false and is corrected by the first [read]; call [read] once at
  /// startup so the settings row reflects what is on the device.
  final ValueNotifier<bool> hasKey = ValueNotifier<bool>(false);

  /// The stored key, or an empty string when there is none.
  Future<String> read() async {
    try {
      final raw = await _storage.read(storageKey);
      final key = normalize(raw ?? '');
      hasKey.value = key.isNotEmpty;
      return key;
    } catch (e) {
      // Deliberately not interpolating anything but the error type: the
      // message of a storage failure is not guaranteed free of the value.
      if (kDebugMode) {
        debugPrint('PaxSenixKeyStore: read failed (${e.runtimeType})');
      }
      return '';
    }
  }

  /// Stores [value] after [normalize]. A blank value clears the key.
  Future<void> write(String value) async {
    final key = normalize(value);
    if (key.isEmpty) {
      await clear();
      return;
    }
    try {
      await _storage.write(storageKey, key);
      hasKey.value = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PaxSenixKeyStore: write failed (${e.runtimeType})');
      }
    }
  }

  /// Removes the stored key.
  Future<void> clear() async {
    try {
      await _storage.delete(storageKey);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PaxSenixKeyStore: clear failed (${e.runtimeType})');
      }
    }
    hasKey.value = false;
  }

  /// Trims [value] and strips a leading `Bearer ` (any case).
  ///
  /// Listeners paste the key straight from the dashboard, and the dashboard
  /// shows it as a ready-made Authorization header. Sent as-is it would arrive
  /// as `Bearer Bearer abc` and every request would be refused as unauthorised.
  static String normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.length > 7 &&
        trimmed.substring(0, 7).toLowerCase() == 'bearer ') {
      return trimmed.substring(7).trim();
    }
    // A bare "Bearer" with nothing after it is not a key.
    if (trimmed.toLowerCase() == 'bearer') return '';
    return trimmed;
  }
}
