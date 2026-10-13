// Fakes for the lyric providers, so the LOOKUP can be tested without a network.
//
// Every real provider is subclassed and its public lookup overridden; anything a
// test does not script answers "no lyrics" at once. A subclass rather than an
// interface because LyricsService holds the concrete types.

import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/apple_lyrics_common.dart';
import 'package:music_streaming_app/services/lyrics/better_lyrics_provider.dart';
import 'package:music_streaming_app/services/lyrics/bini_lyrics_provider.dart';
import 'package:music_streaming_app/services/lyrics/genius_provider.dart';
import 'package:music_streaming_app/services/lyrics/kugou_provider.dart';
import 'package:music_streaming_app/services/lyrics/lrc_red_provider.dart';
import 'package:music_streaming_app/services/lyrics/lrclib_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_cache_db.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_plus_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_service.dart';
import 'package:music_streaming_app/services/lyrics/musixmatch_provider.dart';
import 'package:music_streaming_app/services/lyrics/paxsenix_key_store.dart';
import 'package:music_streaming_app/services/lyrics/paxsenix_provider.dart';
import 'package:music_streaming_app/services/lyrics/unison_provider.dart';
import 'package:music_streaming_app/services/lyrics/youtube_music_provider.dart';

/// One call a fake received.
class Call {
  Call(this.provider, this.args);

  final LyricsProvider provider;
  final Map<String, Object?> args;

  @override
  String toString() => '$provider $args';
}

typedef Answer = Future<List<LyricsEntry>?> Function(Map<String, Object?> args);

/// A scripted answer for one provider, plus a log of what it was asked.
class Script {
  Script(this.log, this.provider);

  final List<Call> log;
  final LyricsProvider provider;

  /// The reply. Null means "no lyrics, immediately".
  Answer? answer;

  /// Replies after [delay] with [lines].
  void reply(List<LyricsEntry>? lines, {Duration delay = Duration.zero}) {
    answer = (_) async {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      return lines;
    };
  }

  Future<List<LyricsEntry>?> run(Map<String, Object?> args) {
    log.add(Call(provider, args));
    final a = answer;
    return a == null ? Future.value() : a(args);
  }

  int get calls => log.where((c) => c.provider == provider).length;

  Call? get last {
    for (var i = log.length - 1; i >= 0; i--) {
      if (log[i].provider == provider) return log[i];
    }
    return null;
  }
}

class _Better extends BetterLyricsProvider {
  _Better(this.main, this.portato);
  final Script main, portato;

  @override
  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) =>
      main.run({'title': title, 'artist': artist, 'durationMs': durationMs, 'album': album});

  @override
  Future<List<LyricsEntry>?> getPortato({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) =>
      portato.run({'title': title, 'artist': artist, 'durationMs': durationMs, 'album': album});
}

class _KuGou extends KuGouProvider {
  _KuGou(this.s);
  final Script s;

  @override
  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) =>
      s.run({'title': title, 'artist': artist, 'durationMs': durationMs, 'album': album});
}

class FakeLrcRed extends LrcRedProvider {
  FakeLrcRed(this.s);
  final Script s;

  /// Fetches this document through the lookup's shared fetcher, if set.
  String? documentUrl;

  @override
  Future<List<LyricsEntry>?> getLyrics(
    AppleLyricsQuery query, {
    DocumentFetcher? get,
    void Function(String isrc)? onIsrc,
  }) async {
    if (documentUrl != null && get != null) await get(documentUrl!);
    return s.run({
      'title': query.title,
      'artist': query.artist,
      'album': query.album,
      'durationMs': query.durationMs,
      'isrc': query.isrc,
    });
  }
}

class _Bini extends BiniLyricsProvider {
  _Bini(this.s, this.world);
  final Script s;
  final FakeLyricsWorld world;

  @override
  Future<BiniHit?> identify(AppleLyricsQuery query) async {
    world.identifyCalls++;
    final run = world.identifyAnswer;
    return run == null ? null : await run();
  }

  @override
  Future<List<LyricsEntry>?> getLyrics(
    AppleLyricsQuery query, {
    BiniHit? hit,
    DocumentFetcher? get,
    void Function(String isrc)? onIsrc,
  }) async {
    if (world.biniDocumentUrl != null && get != null) {
      await get(world.biniDocumentUrl!);
    }
    return s.run({
      'title': query.title,
      'isrc': query.isrc,
      'hit': hit?.isrc,
    });
  }
}

class _LyricsPlus extends LyricsPlusProvider {
  _LyricsPlus(this.s);
  final Script s;

  @override
  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
    String? isrc,
  }) =>
      s.run({'title': title, 'artist': artist, 'album': album, 'isrc': isrc});
}

class _Unison extends UnisonProvider {
  _Unison(this.s);
  final Script s;

  @override
  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) =>
      s.run({'title': title, 'artist': artist, 'album': album});
}

class _Musixmatch extends MusixmatchProvider {
  _Musixmatch(this.s);
  final Script s;

  @override
  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
  }) =>
      s.run({'title': title, 'artist': artist});
}

class _Genius extends GeniusProvider {
  _Genius(this.s);
  final Script s;

  @override
  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
  }) =>
      s.run({'title': title, 'artist': artist});
}

class _YouTubeMusic extends YouTubeMusicLyricsProvider {
  _YouTubeMusic(this.s);
  final Script s;

  @override
  Future<List<LyricsEntry>?> getLyrics({required String? videoId}) =>
      s.run({'videoId': videoId});
}

class _LrcLib extends LrcLibProvider {
  _LrcLib(this.world);
  final FakeLyricsWorld world;

  @override
  Future<String?> getLyrics({
    required String title,
    required String artist,
    int? durationSeconds,
    String? album,
  }) async {
    world.lrcLibCalls.add({
      'title': title,
      'artist': artist,
      'durationSeconds': durationSeconds,
      'album': album,
    });
    return world.lrcLibAnswer;
  }
}

class _PaxSenix extends PaxSenixProvider {
  _PaxSenix(this.apple, this.spotify, this.musixmatch);
  final Script apple, spotify, musixmatch;

  @override
  Future<List<LyricsEntry>?> getLyrics(AppleLyricsQuery query) =>
      apple.run({'title': query.title});

  @override
  Future<List<LyricsEntry>?> getSpotifyLyrics({
    required String title,
    required String artist,
    int? durationMs,
    required String apiKey,
  }) =>
      spotify.run({'title': title, 'apiKey': apiKey});

  @override
  Future<List<LyricsEntry>?> getMusixmatchLyrics({
    required String title,
    required String artist,
    int? durationMs,
    required String apiKey,
  }) =>
      musixmatch.run({'title': title, 'apiKey': apiKey});
}

/// An in-memory cache standing in for the SQLite one.
class FakeLyricsCache extends LyricsCacheDb {
  final Map<String, LyricsCacheEntry> rows = {};
  int puts = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<LyricsCacheEntry?> get(String key) async => rows[key];

  @override
  Future<void> put(
    String key,
    String lyrics,
    bool isSynced,
    String provider, {
    String? timings,
  }) async {
    puts++;
    rows[key] = LyricsCacheEntry(
      key: key,
      lyrics: lyrics,
      isSynced: isSynced,
      provider: provider,
      cachedAt: DateTime.now(),
      timings: timings,
    );
  }

  @override
  Future<void> delete(String key) async => rows.remove(key);

  @override
  Future<void> clear() async => rows.clear();

  @override
  Future<void> close() async {}
}

class MemorySecrets implements PaxSenixSecretStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A service wired to fakes, with every provider's script exposed by name.
class FakeLyricsWorld {
  FakeLyricsWorld() {
    scripts = {
      for (final p in LyricsProvider.values) p: Script(log, p),
    };
    cache = FakeLyricsCache();
    secrets = MemorySecrets();
    keys = PaxSenixKeyStore(storage: secrets);
    documentRequests = [];
    documentBody = '<tt/>';
    final client = MockClient((request) async {
      documentRequests.add(request.url.toString());
      return http.Response(documentBody, 200);
    });
    service = LyricsService.forTesting(
      better: _Better(scripts[LyricsProvider.betterLyrics]!,
          scripts[LyricsProvider.betterLyricsPortato]!),
      kugou: _KuGou(scripts[LyricsProvider.kugou]!),
      lrcRed: lrcRed = FakeLrcRed(scripts[LyricsProvider.lrcRed]!),
      bini: _Bini(scripts[LyricsProvider.biniLyrics]!, this),
      lyricsPlus: _LyricsPlus(scripts[LyricsProvider.lyricsPlus]!),
      unison: _Unison(scripts[LyricsProvider.unison]!),
      musixmatch: _Musixmatch(scripts[LyricsProvider.musixmatch]!),
      genius: _Genius(scripts[LyricsProvider.genius]!),
      youtubeMusic: _YouTubeMusic(scripts[LyricsProvider.youtubeMusic]!),
      lrcLib: _LrcLib(this),
      paxSenix: _PaxSenix(
        scripts[LyricsProvider.paxSenix]!,
        scripts[LyricsProvider.paxSenixSpotify]!,
        scripts[LyricsProvider.paxSenixMusixmatch]!,
      ),
      cache: cache,
      keys: keys,
      http: LyricsHttp(client: client),
    );
  }

  final List<Call> log = [];
  late final Map<LyricsProvider, Script> scripts;
  late final FakeLyricsCache cache;
  late final MemorySecrets secrets;
  late final PaxSenixKeyStore keys;
  late final LyricsService service;
  late final FakeLrcRed lrcRed;

  Script operator [](LyricsProvider p) => scripts[p]!;

  // Bini's identify step.
  int identifyCalls = 0;
  Future<BiniHit?> Function()? identifyAnswer;
  String? biniDocumentUrl;

  // LRCLIB returns text, not entries.
  final List<Map<String, Object?>> lrcLibCalls = [];
  String? lrcLibAnswer;

  // The shared document client.
  late final List<String> documentRequests;
  late String documentBody;
}

// ---- Lines ----------------------------------------------------------------

List<LyricsEntry> lineSyncedLines(String text) => [
      LyricsEntry.headEntry,
      LyricsEntry(timeMs: 5000, endMs: 8000, text: text),
      LyricsEntry(timeMs: 8000, endMs: 11000, text: '$text two'),
    ];

List<LyricsEntry> wordSyncedLines(String text) => [
      LyricsEntry.headEntry,
      LyricsEntry(timeMs: 5000, endMs: 8000, text: text, words: [
        WordTiming(timeMs: 5000, durationMs: 1500, text: text),
      ]),
      LyricsEntry(timeMs: 8000, endMs: 11000, text: '$text two', words: [
        WordTiming(timeMs: 8000, durationMs: 1500, text: '$text two'),
      ]),
    ];

List<LyricsEntry> plainLines(String text) => [
      LyricsEntry.headEntry,
      LyricsEntry(timeMs: 0, text: text),
      LyricsEntry(timeMs: 0, text: '$text two'),
    ];
