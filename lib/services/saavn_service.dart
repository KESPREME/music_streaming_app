import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

/// One matched song from the JioSaavn search API.
@immutable
class SaavnMatch {
  final String id;
  final String title;
  final String encryptedMediaUrl;
  final String imageUrl;
  final int? durationMs;

  const SaavnMatch({
    required this.id,
    required this.title,
    required this.encryptedMediaUrl,
    required this.imageUrl,
    this.durationMs,
  });
}

/// Client-side JioSaavn resolution.
///
/// Searches the public `jiosaavn.com/api.php` endpoint and decrypts
/// `encrypted_media_url` (DES-ECB, well-known public key) locally —
/// no third-party proxy instance required.
class SaavnService {
  SaavnService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Publicly documented Saavn media-URL decryption key (same constant used
  /// by every open-source Saavn client).
  static const String _desKey = '38346591';

  static const String _searchUrl = 'https://www.jiosaavn.com/api.php';
  static const String _browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Decrypt a Saavn `encrypted_media_url` value.
  static String? decryptMediaUrl(String encrypted) {
    try {
      final cipher = _cipher(forEncryption: false);
      final out = cipher.process(Uint8List.fromList(base64.decode(encrypted)));
      return utf8.decode(out);
    } catch (e) {
      if (kDebugMode) debugPrint('SaavnService: decrypt failed: $e');
      return null;
    }
  }

  /// Inverse of [decryptMediaUrl]; exposed only for tests.
  @visibleForTesting
  static String encryptForTest(String plaintext) {
    final cipher = _cipher(forEncryption: true);
    return base64.encode(cipher.process(Uint8List.fromList(utf8.encode(
      plaintext,
    ))));
  }

  /// DES-ECB with PKCS7. pointycastle only ships 3DES, so the 8-byte Saavn
  /// key is fed twice (K1‖K1): EDE with K2==K1 collapses to plain single-DES
  /// — the exact scheme Saavn uses for `encrypted_media_url`.
  static PaddedBlockCipherImpl _cipher({required bool forEncryption}) {
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(
      DESedeEngine(),
    ));
    final k = _keyBytes();
    final doubled = Uint8List(k.length * 2)
      ..setAll(0, k)
      ..setAll(k.length, k);
    cipher.init(
      forEncryption,
      PaddedBlockCipherParameters(KeyParameter(doubled), null),
    );
    return cipher;
  }

  static Uint8List _keyBytes() => Uint8List.fromList(utf8.encode(_desKey));

  /// Build the direct CDN URL at the requested bitrate (kbps).
  /// Saavn stores one file per bitrate; the suffix selects it.
  static String buildStreamUrl(String decryptedUrl, int kbps) {
    final suffix = '_$kbps';
    if (RegExp(r'_\d+\.mp4$').hasMatch(decryptedUrl)) {
      return decryptedUrl.replaceFirstMapped(
        RegExp(r'_\d+\.mp4$'),
        (_) => '$suffix.mp4',
      );
    }
    return decryptedUrl.replaceFirst('.mp4', '$suffix.mp4');
  }

  /// True when [candidateMs] is within ±3s of [targetMs].
  /// Null on either side never rejects.
  static bool isDurationWithinTolerance(int? targetMs, int? candidateMs) {
    if (targetMs == null || candidateMs == null) return true;
    return (targetMs - candidateMs).abs() <= 3000;
  }

  /// Pick the best duration-matched result from a `search.getResults`
  /// response. Returns null when no candidate is within tolerance.
  static SaavnMatch? parseBestMatch(
    Map<String, dynamic> response, {
    required String artistQuery,
    int? targetDurationMs,
  }) {
    final results = response['results'];
    if (results is! List || results.isEmpty) return null;

    for (final raw in results) {
      if (raw is! Map<String, dynamic>) continue;
      final moreInfo = raw['moreInfo'];
      if (moreInfo is! Map<String, dynamic>) continue;

      final encrypted = moreInfo['encrypted_media_url'] as String?;
      if (encrypted == null || encrypted.isEmpty) continue;

      final durationSec = int.tryParse(moreInfo['duration']?.toString() ?? '');
      if (!isDurationWithinTolerance(
        targetDurationMs,
        durationSec == null ? null : durationSec * 1000,
      )) {
        continue;
      }

      return SaavnMatch(
        id: raw['id']?.toString() ?? '',
        title: (raw['title']?.toString() ?? '').isNotEmpty
            ? raw['title'].toString()
            : moreInfo['title']?.toString() ?? '',
        encryptedMediaUrl: encrypted,
        imageUrl: upgradeImageUrl(moreInfo['image']?.toString() ?? ''),
        durationMs: durationSec == null ? null : durationSec * 1000,
      );
    }
    return null;
  }

  /// Saavn returns `50x50` thumbnails; swap to 500x500 for crisp artwork.
  static String upgradeImageUrl(String url) =>
      url.replaceFirst('_50x50', '_500x500');

  /// Resolve a direct 320kbps stream URL for [title]/[artist].
  /// [targetDurationMs] guards against wrong-song matches.
  Future<String?> resolveStreamUrl({
    required String title,
    required String artist,
    int? targetDurationMs,
    int kbps = 320,
  }) async {
    try {
      // artistName often carries subtitle junk: "Artist, Album, 3:45".
      // Sanitize: first comma segment only, strip duration tokens.
      final cleanArtist = artist
          .split(',')
          .first
          .trim()
          .replaceFirst(RegExp(r'\s*\d+:\d{2}\s*$'), '')
          .trim();
      final query = '$title $cleanArtist'.trim();
      final uri = Uri.parse(_searchUrl).replace(queryParameters: {
        '__call': 'search.getResults',
        'p': '1',
        'q': query,
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'android',
      });

      final response = await _client
          .get(uri, headers: {'User-Agent': _browserUa})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('SaavnService: search HTTP ${response.statusCode}');
        }
        return null;
      }

      final body = response.body;
      final decrypted = await Isolate.run(() {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final match = parseBestMatch(
          data,
          artistQuery: artist,
          targetDurationMs: targetDurationMs,
        );
        if (match == null) return null;
        return decryptMediaUrl(match.encryptedMediaUrl);
      });

      if (decrypted == null || !decrypted.contains('saavncdn.com')) {
        if (kDebugMode) {
          debugPrint('SaavnService: decrypt/match failed for "$query"');
        }
        return null;
      }
      final url = buildStreamUrl(decrypted, kbps);
      if (kDebugMode) debugPrint('SaavnService: resolved "$query" -> $url');
      return url;
    } catch (e) {
      if (kDebugMode) debugPrint('SaavnService: resolveStreamUrl failed: $e');
      return null;
    }
  }

  void dispose() => _client.close();
}
