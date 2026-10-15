import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/listening_stats.dart';
import 'package:music_streaming_app/services/replay/replay_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Library's listening number is measured time with audio playing. These pin
/// that it counts what was played and nothing else, survives a restart, starts
/// over with the year, and refuses a clock jump.

class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

Track _t(String artist) => Track(
      id: artist,
      trackName: 'Song',
      artistName: artist,
      albumName: 'Album',
      previewUrl: '',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ListeningStats', () {
    test('counts only time spent playing', () {
      final clock = _Clock(DateTime(2026, 5, 1, 10));
      final s = ListeningStats(clock: clock.call);

      s.onPlayingChanged(true);
      clock.advance(const Duration(minutes: 3));
      s.onPlayingChanged(false);
      clock.advance(const Duration(hours: 2)); // paused: not counted
      s.onPlayingChanged(true);
      clock.advance(const Duration(minutes: 4, seconds: 30));
      s.onPlayingChanged(false);

      expect(s.minutesThisYear, 7);
    });

    test('an open session is included without being stored twice', () {
      final clock = _Clock(DateTime(2026, 5, 1, 10));
      final s = ListeningStats(clock: clock.call);
      s.onPlayingChanged(true);
      clock.advance(const Duration(minutes: 10));
      expect(s.minutesThisYear, 10);
      s.onPlayingChanged(true); // repeated "playing" does not restart it
      clock.advance(const Duration(minutes: 5));
      s.onPlayingChanged(false);
      expect(s.minutesThisYear, 15);
    });

    test('a stop without a start, and a clock going backwards, count nothing', () {
      final clock = _Clock(DateTime(2026, 5, 1, 10));
      final s = ListeningStats(clock: clock.call);
      s.onPlayingChanged(false);
      s.onPlayingChanged(true);
      clock.advance(const Duration(minutes: -30));
      s.onPlayingChanged(false);
      expect(s.msThisYear, 0);
    });

    test('a session longer than the cap is a clock jump and is capped', () {
      final clock = _Clock(DateTime(2026, 5, 1));
      final s = ListeningStats(clock: clock.call);
      s.onPlayingChanged(true);
      clock.advance(const Duration(days: 3));
      s.onPlayingChanged(false);
      expect(s.msThisYear, ListeningStats.maxSession.inMilliseconds);
    });

    test('survives a restart', () async {
      final clock = _Clock(DateTime(2026, 5, 1, 10));
      final a = ListeningStats(clock: clock.call);
      await a.load();
      a.onPlayingChanged(true);
      clock.advance(const Duration(minutes: 20));
      a.onPlayingChanged(false);
      await Future<void>.delayed(Duration.zero);

      final b = ListeningStats(clock: clock.call);
      await b.load();
      expect(b.minutesThisYear, 20);
    });

    test('listening before the stored total loads is added, not overwritten',
        () async {
      SharedPreferences.setMockInitialValues({
        ListeningStats.storageKey: '{"y":2026,"ms":${60 * 60000}}',
      });
      final clock = _Clock(DateTime(2026, 5, 1, 10));
      final s = ListeningStats(clock: clock.call);
      s.onPlayingChanged(true);
      clock.advance(const Duration(minutes: 5));
      s.onPlayingChanged(false);
      await s.load();
      expect(s.minutesThisYear, 65);
    });

    test('a new year starts at zero; a session across midnight counts this year only',
        () async {
      SharedPreferences.setMockInitialValues({
        ListeningStats.storageKey: '{"y":2025,"ms":${900 * 60000}}',
      });
      final clock = _Clock(DateTime(2025, 12, 31, 23, 50));
      final s = ListeningStats(clock: clock.call);
      s.onPlayingChanged(true);
      clock.advance(const Duration(minutes: 25)); // 00:15 on Jan 1
      await s.load();
      s.onPlayingChanged(false);
      expect(s.minutesThisYear, 15);
    });

    test('a corrupt stored value is ignored', () async {
      SharedPreferences.setMockInitialValues(
          {ListeningStats.storageKey: 'not json'});
      final s = ListeningStats(clock: () => DateTime(2026, 5, 1));
      await s.load();
      expect(s.msThisYear, 0);
      expect(s.isLoaded, isTrue);
    });
  });

  group('card copy', () {
    test('thousands are grouped', () {
      expect(groupThousands(0), '0');
      expect(groupThousands(999), '999');
      expect(groupThousands(1513), '1,513');
      expect(groupThousands(1234567), '1,234,567');
    });

    test('top artist needs a pattern, not one play', () {
      expect(topRecentArtist([_t('A'), _t('B')]), isNull);
      expect(topRecentArtist([_t('A'), _t('B'), _t('B')]), 'B');
      expect(topRecentArtist(const []), isNull);
    });
  });
}
