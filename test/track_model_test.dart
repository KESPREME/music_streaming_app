import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/models/track.dart';

void main() {
  test('copyWith preserves _durationMs', () {
    final original = Track(
      id: 'abc',
      trackName: 'Song',
      artistName: 'Artist',
      albumName: 'Album',
      previewUrl: 'https://example.com',
      durationMs: 215000,
    );

    final renamed = original.copyWith(trackName: 'Renamed');

    expect(renamed.trackName, 'Renamed');
    expect(renamed.durationMs, 215000,
        reason: 'copyWith must not drop InnerTube duration');
    expect(renamed.id, original.id);
    expect(renamed.source, original.source);
  });

  test('copyWith can override durationMs and albumArt alias stays synced',
      () {
    final original = Track(
      id: 'x',
      trackName: 'a',
      artistName: 'b',
      albumName: 'c',
      previewUrl: '',
      albumArt: 'https://art/1.jpg',
      durationMs: 1000,
    );

    final updated = original.copyWith(durationMs: 2000);

    expect(updated.durationMs, 2000);
    expect(updated.albumArt, original.albumArtUrl);
  });
}
