import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/screens/search_screen.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/account_button.dart';
import 'package:music_streaming_app/widgets/animated_equalizer_icon.dart';
import 'package:music_streaming_app/widgets/search_glass_pills.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'muzo_enhancements_test.dart' show MockMusicProvider;

/// Search's scope row ends in the account avatar - the same button as Home's - not an
/// equalizer that only reopened the player. And touch-and-hold on an ALBUM or PLAYLIST
/// result opens the collection sheet, not the song sheet (whose rows - Song Info, Sleep
/// Timer, Download - had nothing to act on for a browse id).
class _Albums extends MockMusicProvider {
  _Albums() : super(loggedIn: true);

  @override
  List<Track> get albumSearchResults => [
        Track(
          id: 'MPREb_troubadour',
          trackName: 'Troubadour',
          artistName: "K'naan",
          albumName: 'Troubadour',
          albumArtUrl: '',
          previewUrl: '',
        ),
      ];

  @override
  List<Track> get playlistSearchResults => [
        Track(
          id: 'VLPLroadtrip',
          trackName: 'Road trip mix',
          artistName: '',
          albumName: '',
          albumArtUrl: '',
          previewUrl: '',
        ),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the scope row has the account button and no equalizer', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicProvider>.value(value: MockMusicProvider(loggedIn: true)),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        home: const SearchScreen(embedded: true),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SearchScopeSegmented), findsOneWidget);
    expect(
      find.descendant(of: find.byType(SearchScopeSegmented), matching: find.byType(AccountButton)),
      findsOneWidget,
      reason: 'the profile is where the equalizer was',
    );
    expect(find.byType(AnimatedEqualizerIcon), findsNothing);
  });

  Future<void> pumpSearch(WidgetTester tester, MusicProvider p) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicProvider>.value(value: p),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        home: const SearchScreen(embedded: true),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('holding an album result opens the collection sheet, not the song sheet', (tester) async {
    await pumpSearch(tester, _Albums());
    await tester.tap(find.text('Albums'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Troubadour'), findsWidgets);

    await tester.longPress(find.text('Troubadour').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    for (final label in ['Play', 'Shuffle', 'Play next', 'Add to queue', 'Add to a playlist...', 'Share', 'Go to artist']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text("Album \u00b7 K'naan"), findsOneWidget);
    expect(find.text('Song Info'), findsNothing, reason: 'an album has no song info');
    expect(find.text('Sleep Timer'), findsNothing);
  });

  testWidgets('holding a playlist result opens the collection sheet', (tester) async {
    await pumpSearch(tester, _Albums());
    await tester.ensureVisible(find.text('Playlists'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Playlists'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.longPress(find.text('Road trip mix').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Shuffle'), findsWidgets);
    expect(find.text('Add to a playlist...'), findsWidgets);
    expect(find.text('Go to artist'), findsNothing, reason: 'a playlist result names no artist');
    expect(find.text('Song Info'), findsNothing);
  });
}