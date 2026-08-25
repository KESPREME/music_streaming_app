import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/services/saavn_service.dart';

void main() {
  group('SaavnService pure helpers', () {
    test('decryptMediaUrl round-trips DES-ECB with the Saavn key', () {
      // Encrypt a known saavncdn path with the same cipher parameters the
      // production code uses (DES-ECB, key '38346591', PKCS7). Our decrypt
      // must recover it exactly — proving mode/padding/key handling.
      final plaintext =
          'https://aac.saavncdn.com/999/abc123_96.mp4'; // decrypted form
      final encrypted = SaavnService.encryptForTest(plaintext);

      final decrypted = SaavnService.decryptMediaUrl(encrypted);
      expect(decrypted, plaintext);
    });

    test('buildStreamUrl swaps bitrate suffix to requested quality', () {
      expect(
        SaavnService.buildStreamUrl(
            'https://aac.saavncdn.com/999/abc_96.mp4', 320),
        'https://aac.saavncdn.com/999/abc_320.mp4',
      );
      expect(
        SaavnService.buildStreamUrl(
            'https://aac.saavncdn.com/999/abc_320.mp4', 160),
        'https://aac.saavncdn.com/999/abc_160.mp4',
      );
      // No suffix present → append before extension.
      expect(
        SaavnService.buildStreamUrl('https://aac.saavncdn.com/999/abc.mp4', 320),
        'https://aac.saavncdn.com/999/abc_320.mp4',
      );
    });

    test('isDurationWithinTolerance accepts ±3s and rejects outliers', () {
      expect(SaavnService.isDurationWithinTolerance(200000, 201000), isTrue);
      expect(SaavnService.isDurationWithinTolerance(200000, 197500), isTrue);
      expect(SaavnService.isDurationWithinTolerance(200000, 204000), isFalse);
      expect(SaavnService.isDurationWithinTolerance(200000, null), isTrue,
          reason: 'unknown duration must not reject a match');
      expect(SaavnService.isDurationWithinTolerance(null, 200000), isTrue);
    });

    test('parseSearchResults extracts best duration-matched song', () {
      final fixture = <String, dynamic>{
        'results': [
          {
            'id': 'wrong_song',
            'title': 'Similar Title (Remix)',
            'moreInfo': {
              'duration': '300',
              'encrypted_media_url': 'ENCRYPTED_REMIX',
              'image': 'https://c.saavncdn.com/x_50x50.jpg',
            },
          },
          {
            'id': 'right_song',
            'title': 'Similar Title',
            'moreInfo': {
              'duration': '201',
              'encrypted_media_url': 'ENCRYPTED_RIGHT',
              'image': 'https://c.saavncdn.com/y_50x50.jpg',
            },
          },
        ],
      };

      final match = SaavnService.parseBestMatch(
        fixture,
        artistQuery: '',
        targetDurationMs: 201000,
      );

      expect(match, isNotNull);
      expect(match!.id, 'right_song');
      expect(match.encryptedMediaUrl, 'ENCRYPTED_RIGHT');
    });

    test('parseSearchResults returns null when nothing matches duration', () {
      final fixture = <String, dynamic>{
        'results': [
          {
            'id': 'long_song',
            'title': 'T',
            'moreInfo': {'duration': '600', 'encrypted_media_url': 'E'},
          },
        ],
      };

      final match = SaavnService.parseBestMatch(
        fixture,
        artistQuery: '',
        targetDurationMs: 200000,
      );
      expect(match, isNull);
    });

    test('parseSearchResults upgrades low-res image URL', () {
      final fixture = <String, dynamic>{
        'results': [
          {
            'id': 's',
            'title': 'T',
            'moreInfo': {
              'duration': '200',
              'encrypted_media_url': 'E',
              'image': 'https://c.saavncdn.com/abc_50x50.jpg',
            },
          },
        ],
      };

      final match = SaavnService.parseBestMatch(
        fixture,
        artistQuery: '',
        targetDurationMs: null,
      );
      expect(
        match!.imageUrl,
        'https://c.saavncdn.com/abc_500x500.jpg',
      );
    });
  });
}
