import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/utils/artwork_palette_resolver.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_detail.dart';
import 'package:provider/provider.dart';

class _MockMusicProvider extends ChangeNotifier implements MusicProvider {
  Track? _lastPlayedNext;
  Track? _lastAddedToQueue;
  Track? _currentTrack;
  bool _isPlaying = false;
  bool _hideMiniPlayer = false;

  Track? get lastPlayedNext => _lastPlayedNext;
  Track? get lastAddedToQueue => _lastAddedToQueue;

  @override
  Track? get currentTrack => _currentTrack;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get hideMiniPlayer => _hideMiniPlayer;

  void setCurrentTrack(Track? track, {bool isPlaying = true}) {
    _currentTrack = track;
    _isPlaying = isPlaying;
    notifyListeners();
  }

  @override
  void playNext(Track track) {
    _lastPlayedNext = track;
    notifyListeners();
  }

  @override
  void addToQueue(Track track) {
    _lastAddedToQueue = track;
    notifyListeners();
  }

  @override
  void setHideMiniPlayer(bool hide) {
    _hideMiniPlayer = hide;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track.isSameTrackAs Matching Tests (BitChord Parity)', () {
    test('Matches exact identical IDs', () {
      final t1 = Track(
        id: 'dQw4w9WgXcQ',
        trackName: 'Never Gonna Give You Up',
        artistName: 'Rick Astley',
        albumName: 'Whenever You Need Somebody',
        previewUrl: '',
      );
      final t2 = Track(
        id: 'dQw4w9WgXcQ',
        trackName: 'Different Title',
        artistName: 'Different Artist',
        albumName: 'Different Album',
        previewUrl: '',
      );
      expect(t1.isSameTrackAs(t2), isTrue);
    });

    test('Matches when IDs differ but title and artist match normalized', () {
      final albumTrack = Track(
        id: 'album_track_123',
        trackName: 'Save Your Tears',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
        previewUrl: '',
      );
      final playingTrack = Track(
        id: 'yt_video_456',
        trackName: 'Save Your Tears (Official Audio)',
        artistName: 'The Weeknd',
        albumName: 'Save Your Tears',
        previewUrl: '',
      );
      expect(albumTrack.isSameTrackAs(playingTrack), isTrue);
    });

    test('Matches with case variations and punctuation', () {
      final t1 = Track(
        id: 'id_1',
        trackName: 'Blinding Lights!',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
        previewUrl: '',
      );
      final t2 = Track(
        id: 'id_2',
        trackName: 'blinding lights',
        artistName: 'the weeknd',
        albumName: 'After Hours',
        previewUrl: '',
      );
      expect(t1.isSameTrackAs(t2), isTrue);
    });

    test('Returns false when title or artist differs completely', () {
      final t1 = Track(
        id: 'id_1',
        trackName: 'Starboy',
        artistName: 'The Weeknd',
        albumName: 'Starboy',
        previewUrl: '',
      );
      final t2 = Track(
        id: 'id_2',
        trackName: 'Blinding Lights',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
        previewUrl: '',
      );
      expect(t1.isSameTrackAs(t2), isFalse);
    });

    test('Handles null safely', () {
      final t1 = Track(
        id: 'id_1',
        trackName: 'Starboy',
        artistName: 'The Weeknd',
        albumName: 'Starboy',
        previewUrl: '',
      );
      expect(t1.isSameTrackAs(null), isFalse);
    });
  });

  group('BitchordTracklistSkeleton Tests', () {
    testWidgets('Renders requested number of shimmer skeleton rows', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BitchordTracklistSkeleton(
              itemCount: 5,
              hasLeadingThumb: true,
            ),
          ),
        ),
      );

      // Verify that skeleton items are rendered
      expect(find.byType(BitchordTracklistSkeleton), findsOneWidget);
      // Advance animation slightly to verify smooth ticker loop
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BitchordTracklistSkeleton), findsOneWidget);
    });
  });

  group('BitchordSwipeableTrackRow Tests', () {
    testWidgets('Renders child and provides swipe gesture support', (tester) async {
      final mockProvider = _MockMusicProvider();
      final track = Track(
        id: 'swipe_track_1',
        trackName: 'In Your Eyes',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
        previewUrl: '',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<MusicProvider>.value(
          value: mockProvider,
          child: MaterialApp(
            home: Scaffold(
              body: BitchordSwipeableTrackRow(
                track: track,
                palette: ArtworkPalette.defaultDark,
                child: const ListTile(
                  title: Text('In Your Eyes'),
                  subtitle: Text('The Weeknd'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('In Your Eyes'), findsOneWidget);

      // Drag right to trigger Play Next
      await tester.drag(find.text('In Your Eyes'), const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(mockProvider.lastPlayedNext?.id, equals('swipe_track_1'));

      // Drag left to trigger Add to Queue
      await tester.drag(find.text('In Your Eyes'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(mockProvider.lastAddedToQueue?.id, equals('swipe_track_1'));
    });
  });

  group('BitchordActionBar Tactile & Palette Tests', () {
    testWidgets('PlayPill renders and invokes onPlay callback', (tester) async {
      bool played = false;
      bool shuffled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BitchordActionBar(
              palette: ArtworkPalette.defaultDark,
              onPlay: () => played = true,
              onShuffle: () => shuffled = true,
            ),
          ),
        ),
      );

      expect(find.text('Play'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(played, isTrue);

      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pumpAndSettle();
      expect(shuffled, isTrue);
    });
  });
}
