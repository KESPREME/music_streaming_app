import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/now_playing_screen.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/queue_screen.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_detail.dart';
import 'package:music_streaming_app/widgets/glass_options_sheet.dart';
import 'package:music_streaming_app/widgets/glass_surface.dart';
import 'package:music_streaming_app/widgets/mini_player.dart';
import 'package:music_streaming_app/widgets/wavy_progress_bar.dart';

class FakeMusicProvider extends MusicProvider {
  FakeMusicProvider({this.track, bool playing = false}) : _playing = playing;

  Track? track;
  bool _playing;
  int resumeCalls = 0;
  int pauseCalls = 0;
  final List<Track> queueTracks = [];
  final List<Track> collectionTracks = [];
  final List<Track> autoplayTracks = [];
  bool autoplayOn = false;
  int reorderCollectionCalls = 0;
  Track? lastPlayed;
  bool? lastClearQueue;
  bool failQueuePlay = false;

  @override
  Track? get currentTrack => track;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isMiniPlayerVisible => true;

  @override
  Duration get duration => const Duration(minutes: 3);

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Future<void> resumeTrack() async {
    resumeCalls++;
    _playing = true;
  }

  @override
  Future<void> pauseTrack() async {
    pauseCalls++;
    _playing = false;
  }

  @override
  Future<void> skipToPrevious() async {}

  @override
  Future<void> skipToNext() async {}

  @override
  List<Track> get queue => List.unmodifiable(queueTracks);

  // The collection and station sections used to fall through to the real
  // provider (empty), so no test ever rendered them and a queue page with no
  // drag handle or no autoplay block still went green.
  @override
  List<Track> get upcomingCollection => List.unmodifiable(collectionTracks);

  @override
  List<Track> get autoplayQueue => List.unmodifiable(autoplayTracks);

  @override
  bool get autoplayEnabled => autoplayOn;

  @override
  bool isAutoplayTrack(String id) => autoplayTracks.any((t) => t.id == id);

  @override
  void toggleAutoplay() {
    autoplayOn = !autoplayOn;
    notifyListeners();
  }

  @override
  void reorderCollectionItem(int oldIndex, int newIndex) {
    reorderCollectionCalls++;
    final iIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final tr = collectionTracks.removeAt(oldIndex);
    collectionTracks.insert(iIdx.clamp(0, collectionTracks.length), tr);
    notifyListeners();
  }

  @override
  List<Track> get upNext => List.unmodifiable(queueTracks);

  @override
  Future<void> playTrack(
    Track track, {
    String? playlistId,
    List<Track>? playlistTracks,
    bool setContext = true,
    bool clearQueue = true,
    bool prefetchMetadata = true,
    bool recordHistory = true,
  }) async {
    if (failQueuePlay) throw StateError('Queue playback failed');
    lastPlayed = track;
    lastClearQueue = clearQueue;
  }

  @override
  void removeFromQueue(dynamic item) => queueTracks.remove(item);

  @override
  void reorderQueueItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= queueTracks.length || newIndex < 0) {
      return;
    }
    final iIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final tr = queueTracks.removeAt(oldIndex);
    queueTracks.insert(iIdx.clamp(0, queueTracks.length), tr);
    notifyListeners();
  }

  @override
  void clearQueue() => queueTracks.clear();
}

Track buildTrack() => Track(
      id: 'track-1',
      trackName: 'Glass track',
      artistName: 'Glass artist',
      albumName: 'Glass album',
      previewUrl: '',
    );

Future<void> pumpMiniPlayer(
  WidgetTester tester,
  FakeMusicProvider provider,
) async {
  final theme = GlassTheme.build(AccentColors.peach).copyWith(
    splashFactory: NoSplash.splashFactory,
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<MusicProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: theme,
        home: const Scaffold(body: MiniPlayer()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> pumpQueue(
  WidgetTester tester,
  FakeMusicProvider provider, {
  bool embedded = false,
  Size size = const Size(500, 2400),
}) async {
  final theme = GlassTheme.build(AccentColors.peach).copyWith(
    splashFactory: NoSplash.splashFactory,
  );

  // Tall surface by default: the queue is a sliver list, so on the default
  // 800x600 viewport the sections below the fold are never built and a test
  // asserting on them passes vacuously - or fails for the wrong reason. Tests
  // that need to *scroll* pass their own smaller size.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<MusicProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: theme,
        home: QueueScreen(
          isEmbedded: embedded,
          showPlayingNow: false,
          showMiniHeader: embedded,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders no player content without a track', (tester) async {
    final provider = FakeMusicProvider();

    await pumpMiniPlayer(tester, provider);

    expect(find.byType(GlassSurface), findsNothing);
  });

  testWidgets('renders track title and artist', (tester) async {
    final provider = FakeMusicProvider(track: buildTrack());

    await pumpMiniPlayer(tester, provider);

    expect(find.text('Glass track'), findsOneWidget);
    expect(find.text('Glass artist'), findsOneWidget);
  });

  testWidgets('play control calls resumeTrack', (tester) async {
    final provider = FakeMusicProvider(track: buildTrack());

    await pumpMiniPlayer(tester, provider);

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();

    expect(provider.resumeCalls, 1);
  });

  testWidgets('renders Now Playing content and labeled player controls',
      (tester) async {
    final provider = FakeMusicProvider(track: buildTrack());
    final theme = GlassTheme.build(AccentColors.peach).copyWith(
      splashFactory: NoSplash.splashFactory,
    );
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: NowPlayingScreen(track: buildTrack()),
        ),
      ),
    );
    await tester.pump();

    final titleMatches = find.text('Glass track');
    expect(titleMatches, findsWidgets); // header bar + body metadata
    expect(find.text('Glass artist'), findsWidgets);
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    expect(find.bySemanticsLabel('Previous track'), findsOneWidget);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);
    // Player page: lyrics + queue side buttons around a canvas/lofi pill.
    expect(find.bySemanticsLabel('Lyrics tab'), findsOneWidget);
    expect(find.bySemanticsLabel('Queue tab'), findsOneWidget);
    expect(find.bySemanticsLabel('Film tab'), findsOneWidget);
    expect(find.bySemanticsLabel('Canvas tab'), findsOneWidget);
    // Queue page: the bottom bar swaps to the controls-only pill. The
    // player transport above keeps its own set, so scope into the pill.
    await tester.tap(find.bySemanticsLabel('Queue tab'));
    await tester.pumpAndSettle();
    final controlsPill = find.byKey(const ValueKey('controls'));
    expect(controlsPill, findsOneWidget);
    expect(
      find.descendant(
        of: controlsPill,
        matching: find.bySemanticsLabel('Shuffle'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: controlsPill,
        matching: find.bySemanticsLabel('Repeat'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: controlsPill,
        matching: find.bySemanticsLabel('Autoplay'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('queue row plays track without clearing queue', (tester) async {
    final provider = FakeMusicProvider();
    final track = buildTrack();
    provider.queueTracks.add(track);
    final theme = GlassTheme.build(AccentColors.peach).copyWith(
      splashFactory: NoSplash.splashFactory,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: const QueueScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Glass track'));
    await tester.pump();

    expect(provider.lastPlayed, same(track));
    expect(provider.lastClearQueue, isFalse);
  });

  testWidgets('queue drag handle reorders user picks', (tester) async {
    final provider = FakeMusicProvider();
    provider.queueTracks.addAll([
      buildTrack().copyWith(id: 'reorder_aa1', trackName: 'Alpha'),
      buildTrack().copyWith(id: 'reorder_bb2', trackName: 'Beta'),
      buildTrack().copyWith(id: 'reorder_cc3', trackName: 'Gamma'),
    ]);
    final theme = GlassTheme.build(AccentColors.peach).copyWith(
      splashFactory: NoSplash.splashFactory,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: const QueueScreen(),
        ),
      ),
    );
    await tester.pump();

    final before = provider.queue.map((t) => t.id).toList();
    await tester.drag(
      find.byIcon(Icons.drag_handle_rounded).first,
      const Offset(0, 150),
    );
    await tester.pumpAndSettle();

    // Same tracks, genuinely moved (exact slot is the framework's math;
    // what matters is the drag reaches the provider and reorders).
    final after = provider.queue.map((t) => t.id).toList();
    expect(after, hasLength(before.length));
    expect(after.toSet(), before.toSet());
    expect(after, isNot(equals(before)));
  });

  testWidgets('collection rows carry a drag handle and reorder', (tester) async {
    final provider = FakeMusicProvider()..track = buildTrack();
    provider.collectionTracks.addAll([
      buildTrack().copyWith(id: 'ctx1_aaaa', trackName: 'Ctx one'),
      buildTrack().copyWith(id: 'ctx2_bbbb', trackName: 'Ctx two'),
      buildTrack().copyWith(id: 'ctx3_cccc', trackName: 'Ctx three'),
    ]);

    await pumpQueue(tester, provider);

    // A context row without a handle is what made the collection look
    // unorderable even though BitChord drags every section.
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(3));

    await tester.drag(
      find.byIcon(Icons.drag_handle_rounded).first,
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();

    expect(provider.reorderCollectionCalls, 1);
  });

  testWidgets('a single collection row offers no drag handle', (tester) async {
    final provider = FakeMusicProvider()..track = buildTrack();
    provider.collectionTracks
        .add(buildTrack().copyWith(id: 'solo_aaaa', trackName: 'Solo'));

    await pumpQueue(tester, provider);

    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
  });

  testWidgets('sections are labelled so rows are not orphans', (tester) async {
    final provider = FakeMusicProvider()..track = buildTrack();
    provider.queueTracks
        .add(buildTrack().copyWith(id: 'usr1_aaaa', trackName: 'Pick'));
    provider.collectionTracks
        .add(buildTrack().copyWith(id: 'ctx1_aaaa', trackName: 'Ctx'));

    await pumpQueue(tester, provider);

    expect(find.text('Next in queue'), findsOneWidget);
    expect(find.textContaining('Next from'), findsOneWidget);
  });

  testWidgets('autoplay heading toggles the station', (tester) async {
    final provider = FakeMusicProvider()..track = buildTrack();
    provider.autoplayOn = true;
    provider.autoplayTracks
        .add(buildTrack().copyWith(id: 'auto_aaaa', trackName: 'Station'));

    await pumpQueue(tester, provider);

    expect(find.text('Autoplay'), findsOneWidget);
    expect(find.text('Similar tracks'), findsOneWidget);

    await tester.tap(find.text('Autoplay'));
    await tester.pump();
    expect(provider.autoplayOn, isFalse);
    expect(find.text('Off - tap to turn on'), findsOneWidget);
  });

  testWidgets('autoplay block survives an otherwise empty queue',
      (tester) async {
    final provider = FakeMusicProvider()..track = buildTrack();
    provider.autoplayOn = true;

    await pumpQueue(tester, provider);

    expect(find.text('Autoplay'), findsOneWidget);
    expect(find.text('Finding similar tracks...'), findsOneWidget);
    expect(find.text('Queue is empty'), findsNothing);
  });

  testWidgets('landed queue header keeps the track actions', (tester) async {
    final provider = FakeMusicProvider()..track = buildTrack();
    provider.queueTracks
        .add(buildTrack().copyWith(id: 'usr1_aaaa', trackName: 'Pick'));

    await pumpQueue(tester, provider, embedded: true);

    // These three are the whole point of the flight handing off: the overlay
    // cannot carry them, so the page header has to. Matched on the widget, not
    // bySemanticsLabel: the pronunciation button's node merges with its inner
    // 'a?' label, so the node text is never exactly 'Pronunciation'.
    Finder labelled(String label) => find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label,
          description: 'Semantics("$label")',
        );

    expect(find.byKey(const ValueKey('queueHeaderArt')), findsOneWidget);
    expect(labelled('Favorite'), findsOneWidget);
    expect(labelled('Pronunciation'), findsOneWidget);
    expect(labelled('Options'), findsOneWidget);
  });

  testWidgets('no row is highlighted, not even the current one',
      (tester) async {
    final current = buildTrack().copyWith(id: 'cur1_aaaa', trackName: 'Current');
    final provider = FakeMusicProvider()..track = current;
    provider.autoplayTracks.add(current);

    await pumpQueue(tester, provider);

    // The current track appears twice by design - its own section and, here, the
    // station - so both rows carry the same container key.
    final decoration = tester
        .widget<Container>(
          find.byKey(const ValueKey('container_cur1_aaaa')).first,
        )
        .decoration! as BoxDecoration;
    // BitChord keeps every row transparent and marks the current one with the
    // title colour plus the eq glyph only.
    expect(decoration.color, isNull);
    expect(decoration.border, isNull);
  });

  testWidgets('explicit tracks are badged in the queue', (tester) async {
    final provider = FakeMusicProvider()..track = buildTrack();
    provider.queueTracks.addAll([
      buildTrack().copyWith(id: 'exp1_aaaa', trackName: 'Clean', isExplicit: false),
      buildTrack().copyWith(id: 'exp2_bbbb', trackName: 'Dirty', isExplicit: true),
    ]);

    await pumpQueue(tester, provider);

    expect(find.byType(BitchordExplicitBadge), findsOneWidget);
  });

  testWidgets('now playing scrolls away with the queue', (tester) async {
    final provider = FakeMusicProvider()..track = buildTrack();
    provider.queueTracks.addAll([
      for (var i = 0; i < 20; i++)
        buildTrack().copyWith(id: 'row${i}_aaaa', trackName: 'Row $i'),
    ]);

    // Small surface on purpose: a tall one has nothing to scroll, so the
    // assertion would pass whether or not the row is inside the list.
    await pumpQueue(tester, provider, size: const Size(400, 600));
    expect(find.text('Now playing'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    // It was pinned above the scroll area before; BitChord emits it as a
    // list item (PlayerQueue.kt L294) so it leaves with the rest.
    expect(find.text('Now playing'), findsNothing);
  });

  testWidgets('queue X removes the row', (tester) async {
    final provider = FakeMusicProvider();
    provider.queueTracks.addAll([
      buildTrack().copyWith(id: 'removex_aa1', trackName: 'Alpha'),
      buildTrack().copyWith(id: 'removex_bb2', trackName: 'Beta'),
    ]);
    final theme = GlassTheme.build(AccentColors.peach).copyWith(
      splashFactory: NoSplash.splashFactory,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: const QueueScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Remove from queue').first);
    await tester.pump();

    expect(provider.queue.map((t) => t.id).toList(), ['removex_bb2']);
  });

  testWidgets('queue row shows failure snackbar and keeps track',
      (tester) async {
    final provider = FakeMusicProvider()..failQueuePlay = true;
    final track = buildTrack();
    provider.queueTracks.add(track);
    final theme = GlassTheme.build(AccentColors.peach).copyWith(
      splashFactory: NoSplash.splashFactory,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: const QueueScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Glass track'));
    await tester.pump();

    expect(provider.queue, hasLength(1));
    expect(provider.queue.single, same(track));
    expect(find.text('Could not play Glass track'), findsOneWidget);
  });

  test('queue-row validation failure rethrows without consuming queue',
      () async {
    final provider = MusicProvider();
    final queuedTrack = buildTrack();
    final invalidTrack = queuedTrack.copyWith(id: 'PL_test');
    provider.addToQueue(queuedTrack);

    try {
      await expectLater(
        provider.playTrack(
          invalidTrack,
          setContext: false,
          clearQueue: false,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        provider.errorMessage,
        'Cannot play Glass track - it is a playlist/album, not a song.',
      );
      expect(provider.queue, hasLength(1));
      expect(provider.queue.single, same(queuedTrack));
    } finally {
      provider.dispose();
    }
  });

  test('non-queue invalid track does not rethrow queue-row error', () async {
    final provider = MusicProvider();
    final invalidTrack = buildTrack().copyWith(id: 'PL_test');

    try {
      await provider.playTrack(
        invalidTrack,
        setContext: false,
        clearQueue: true,
      );
      expect(
        provider.errorMessage,
        'Cannot play Glass track - it is a playlist/album, not a song.',
      );
    } finally {
      provider.dispose();
    }
  });

  testWidgets('renders progress labels with reduced motion', (tester) async {
    final provider = FakeMusicProvider();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: WavyProgressBar(
              provider: provider,
              accentColor: Colors.white,
            ),
          ),
        ),
      ),
    );

    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('3:00'), findsOneWidget);
  });

  test('default progress style has no halo', () {
    expect(const WavyBarStyle().glowAlpha, 0.0);
  });

  testWidgets('glass options sheet uses GlassSurface and restores mini player',
      (tester) async {
    final track = buildTrack();
    final provider = FakeMusicProvider(track: track);
    final theme = GlassTheme.build(AccentColors.peach)
        .copyWith(splashFactory: NoSplash.splashFactory);

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(body: GlassOptionsSheet(track: track)),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(GlassSurface), findsOneWidget);

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(appBar: AppBar(), body: const SizedBox()),
        ),
      ),
    );
    await tester.pump();
    final BuildContext context = tester.element(find.byType(Scaffold));
    final Future<void> future = GlassOptionsSheet.show(context, track: track);
    await tester.pumpAndSettle();
    expect(provider.hideMiniPlayer, isTrue);
    try {
      await tester.pageBack();
    } catch (_) {
      // Fallback when no BackButton widget is present for the modal route.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
    }
    await tester.pumpAndSettle();
    await future;
    expect(provider.hideMiniPlayer, isFalse);
  });
}
