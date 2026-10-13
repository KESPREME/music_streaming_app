// lib/services/lyrics/lyrics_service.dart
// BitChord-matching multi-source lyrics service: a priority race over every
// enabled source, word/syllable-first, two-tier caching, in-flight
// de-duplication, and instrumental gap synthesis.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';
import '../innertube/innertube_service.dart';
import 'apple_lyrics_common.dart';
import 'better_lyrics_provider.dart';
import 'bini_lyrics_provider.dart';
import 'genius_provider.dart';
import 'kugou_provider.dart';
import 'lrc_red_provider.dart';
import 'lrclib_provider.dart';
import 'lyric_timings_codec.dart';
import 'lyrics_cache_db.dart';
import 'lyrics_http.dart';
import 'lyrics_plus_provider.dart';
import 'lyrics_query.dart';
import 'megalobiz_provider.dart';
import 'musixmatch_provider.dart';
import 'paxsenix_key_store.dart';
import 'paxsenix_provider.dart';
import 'provider_race.dart';
import 'simp_music_provider.dart';
import 'unison_provider.dart';
import 'youtube_music_provider.dart';

/// Provider types for lyrics matching BitChord LyricsSource
enum LyricsProvider {
  lrcRed,
  betterLyrics,
  biniLyrics,
  paxSenix,
  paxSenixSpotify,
  paxSenixMusixmatch,
  betterLyricsPortato,
  lyricsPlus,
  simpMusic,
  kugou,
  lrclib,
  unison,
  musixmatch,
  youtubeTranscript,
  youtubeMusic,
  megalobiz,
  genius,
}

/// Where a provider is in its attempt for a track.
enum ProviderState {
  /// Not asked yet.
  notFetched,

  /// Asked, still waiting.
  fetching,

  /// Answered with usable lyrics.
  found,

  /// Asked and answered with nothing. A genuine miss.
  notFound,
}

extension LyricsProviderExtension on LyricsProvider {
  String get displayName {
    switch (this) {
      case LyricsProvider.lrcRed:
        return 'lrc.red';
      case LyricsProvider.betterLyrics:
        return 'BetterLyrics';
      case LyricsProvider.biniLyrics:
        return 'BiniLyrics';
      case LyricsProvider.paxSenix:
        return 'PaxSenix';
      case LyricsProvider.paxSenixSpotify:
        return 'PaxSenix: Spotify';
      case LyricsProvider.paxSenixMusixmatch:
        return 'PaxSenix: Musixmatch';
      case LyricsProvider.betterLyricsPortato:
        return 'BetterLyrics Portato';
      case LyricsProvider.youtubeMusic:
        return 'YouTube Music';
      case LyricsProvider.megalobiz:
        return 'Megalobiz';
      case LyricsProvider.lyricsPlus:
        return 'LyricsPlus';
      case LyricsProvider.simpMusic:
        return 'SimpMusic';
      case LyricsProvider.kugou:
        return 'KuGou';
      case LyricsProvider.lrclib:
        return 'LRCLIB';
      case LyricsProvider.unison:
        return 'Unison';
      case LyricsProvider.musixmatch:
        return 'Musixmatch';
      case LyricsProvider.genius:
        return 'Genius';
      case LyricsProvider.youtubeTranscript:
        return 'YouTube Transcript';
    }
  }

  String get description {
    switch (this) {
      case LyricsProvider.lrcRed:
        return 'Apple timings by recording, syllable by syllable';
      case LyricsProvider.betterLyrics:
        return 'Apple Music TTML syllable sync';
      case LyricsProvider.biniLyrics:
        return 'The same Apple timings, matched on the recording';
      case LyricsProvider.paxSenix:
        return 'Apple catalog search, then the same TTML';
      case LyricsProvider.paxSenixSpotify:
        return 'Spotify lyrics. Needs your own PaxSenix API key';
      case LyricsProvider.paxSenixMusixmatch:
        return 'Musixmatch timings. Needs your own PaxSenix API key';
      case LyricsProvider.betterLyricsPortato:
        return 'QQ Music karaoke timings, sung note by note';
      case LyricsProvider.youtubeMusic:
        return 'Plain lyrics from the playing video\'s Lyrics tab';
      case LyricsProvider.megalobiz:
        return 'Community-made, whole-line LRC';
      case LyricsProvider.lyricsPlus:
        return 'Finest timing of the lot, least reliable hosting';
      case LyricsProvider.simpMusic:
        return 'RichSync word-level timing';
      case LyricsProvider.kugou:
        return 'Massive synced catalog';
      case LyricsProvider.lrclib:
        return 'Community synced lyrics';
      case LyricsProvider.unison:
        return 'Multi-catalogue mirror, TTML or LRC';
      case LyricsProvider.musixmatch:
        return 'Rich-sync word timing, needs a rotating token';
      case LyricsProvider.genius:
        return 'Plain text only. Last resort';
      case LyricsProvider.youtubeTranscript:
        return 'Video transcript fallback';
    }
  }

  /// Whether this provider can return word or syllable timings, rather than
  /// whole lines.
  ///
  /// Matches `LyricsSource.wordSynced` in the reference. KuGou and LRCLIB are
  /// NOT here: they used to be, and they looked it only because the LRC parser
  /// invented word timings for every plain line.
  bool get canWordSync => switch (this) {
        LyricsProvider.lrcRed ||
        LyricsProvider.betterLyrics ||
        LyricsProvider.biniLyrics ||
        LyricsProvider.paxSenix ||
        LyricsProvider.paxSenixMusixmatch ||
        LyricsProvider.betterLyricsPortato ||
        LyricsProvider.lyricsPlus ||
        LyricsProvider.simpMusic ||
        LyricsProvider.unison ||
        LyricsProvider.musixmatch =>
          true,
        LyricsProvider.paxSenixSpotify ||
        LyricsProvider.kugou ||
        LyricsProvider.lrclib ||
        LyricsProvider.genius ||
        LyricsProvider.youtubeTranscript ||
        LyricsProvider.youtubeMusic ||
        LyricsProvider.megalobiz =>
          false,
      };

  /// Whether the provider is contacted at all for a given attempt.
  ///
  /// Genius and Megalobiz are HTML scrapers: starting them eagerly spends a
  /// scrape and a rate-limit budget on every track before the providers that can
  /// actually synchronise have answered.
  bool get isLazy =>
      this == LyricsProvider.genius || this == LyricsProvider.megalobiz;

  /// Whether the provider needs a key the listener supplies themselves.
  ///
  /// Shown in the sheet either way, but disabled and labelled "API key
  /// required" without one - and never raced, because a request that cannot
  /// succeed is not made.
  bool get requiresApiKey =>
      this == LyricsProvider.paxSenixSpotify ||
      this == LyricsProvider.paxSenixMusixmatch;

  /// Kept in code but off the list: never shown, never asked - not even by
  /// someone whose saved choices still name it.
  ///
  /// For a host that has stopped answering. Deleting the provider outright would
  /// only mean writing it again if it comes back, which is the situation this is
  /// for.
  ///
  /// SimMusic is here because it is keyed on the video id and therefore only works
  /// when the track genuinely came from YouTube, which is not true of a queue built
  /// from any other source. Megalobiz is here because it is an HTML scrape whose
  /// markup has changed before and will again - the reference hides both
  /// (LyricsSource.kt:87, 108).
  bool get isOffered =>
      this != LyricsProvider.simpMusic && this != LyricsProvider.megalobiz;
}

/// What a lookup found, and who found it.
class LyricsLookupResult {
  const LyricsLookupResult({
    required this.entries,
    this.provider,
    this.fromCache = false,
    this.isFallback = false,
  });

  const LyricsLookupResult.none()
      : entries = const [],
        provider = null,
        fromCache = false,
        isFallback = false;

  final List<LyricsEntry> entries;

  /// Who produced [entries], or null when nobody did or the cache row predates
  /// the source being recorded. Null is a real answer: callers must show
  /// something honest for it rather than defaulting to the first provider.
  final LyricsProvider? provider;

  /// Whether this came from a stored snapshot rather than a live request.
  final bool fromCache;

  /// Whether this is a held answer (line-synced when word-synced was wanted, or
  /// plain text) rather than a settled win.
  final bool isFallback;

  bool get isEmpty => entries.isEmpty;
}

/// Whether any line of [entries] carries a timestamp.
///
/// The one definition of "synced" for the race, the cache and the strip. A plain
/// lyric has every line at 0.
bool lyricsAreTimed(List<LyricsEntry> entries) =>
    entries.any((e) => e.timeMs > 0);

/// Main lyrics service that orchestrates multiple providers
/// with syllable-first priority, two-tier caching, and instrumental gap handling
class LyricsService {
  static final LyricsService _instance = LyricsService._create();
  factory LyricsService() => _instance;

  LyricsService._create()
      : _better = BetterLyricsProvider(),
        _simpMusic = SimpMusicProvider(),
        _kugou = KuGouProvider(),
        _lrcRed = LrcRedProvider(),
        _bini = BiniLyricsProvider(),
        _paxSenix = PaxSenixProvider(),
        _lyricsPlus = LyricsPlusProvider(),
        _unison = UnisonProvider(),
        _musixmatch = MusixmatchProvider(),
        _genius = GeniusProvider(),
        _youtubeMusic = YouTubeMusicLyricsProvider(),
        _megalobiz = MegalobizProvider(),
        _lrcLib = LrcLibProvider(),
        _innerTube = InnerTubeService(),
        _diskCache = LyricsCacheDb(),
        _keys = PaxSenixKeyStore(),
        _documentHttp = LyricsHttp.shared;

  /// A service over fakes, for tests of the lookup itself.
  @visibleForTesting
  LyricsService.forTesting({
    BetterLyricsProvider? better,
    KuGouProvider? kugou,
    LrcRedProvider? lrcRed,
    BiniLyricsProvider? bini,
    PaxSenixProvider? paxSenix,
    LyricsPlusProvider? lyricsPlus,
    UnisonProvider? unison,
    MusixmatchProvider? musixmatch,
    GeniusProvider? genius,
    YouTubeMusicLyricsProvider? youtubeMusic,
    LrcLibProvider? lrcLib,
    LyricsCacheDb? cache,
    PaxSenixKeyStore? keys,
    LyricsHttp? http,
  })  : _better = better ?? BetterLyricsProvider(),
        _simpMusic = SimpMusicProvider(),
        _kugou = kugou ?? KuGouProvider(),
        _lrcRed = lrcRed ?? LrcRedProvider(),
        _bini = bini ?? BiniLyricsProvider(),
        _paxSenix = paxSenix ?? PaxSenixProvider(),
        _lyricsPlus = lyricsPlus ?? LyricsPlusProvider(),
        _unison = unison ?? UnisonProvider(),
        _musixmatch = musixmatch ?? MusixmatchProvider(),
        _genius = genius ?? GeniusProvider(),
        _youtubeMusic = youtubeMusic ?? YouTubeMusicLyricsProvider(),
        _megalobiz = MegalobizProvider(),
        _lrcLib = lrcLib ?? LrcLibProvider(),
        _innerTube = InnerTubeService(),
        _diskCache = cache ?? LyricsCacheDb(),
        _keys = keys ?? PaxSenixKeyStore(),
        _documentHttp = http ?? LyricsHttp.shared;

  /// Declaration order IS the default priority, and it is not arbitrary.
  ///
  /// The three Apple hosts lead, because they carry the same catalogue and that
  /// catalogue is the one with the voices in it. lrc.red goes first of them: it is
  /// where the other mirrors now get their documents, so asking it directly is
  /// the same Apple timing without the middleman, and it is the one a dead mirror
  /// cannot take down with it.
  ///
  /// LyricsPlus has the finest timing available and the least reliable hosting.
  /// It sits behind the Apple hosts rather than in front, so a track does not wait
  /// on a mirror that is down to be told what three other hosts already had.
  ///
  /// The two keyed PaxSenix routes sit right behind the keyless one, as in the
  /// reference. Without a key they are never asked, so their place costs nothing.
  ///
  /// Genius and the YouTube transcript can only produce whole lines. They are last
  /// because nothing here can synchronise, and showing unsynced words beats showing
  /// nothing only once the synchronised sources have genuinely missed.
  ///
  /// EVERY member of [LyricsProvider] must appear here, and there is a test that
  /// says so. Three of them once did not: `betterLyricsPortato`, `youtubeMusic`
  /// and `megalobiz` were declared in the enum and in the settings sheet, but
  /// never reached this list - so the race never asked them, and the sheet, which
  /// lists the order, never showed them. A provider the user could see and reorder
  /// but which no lookup could ever consult is worse than not offering it.
  static const List<LyricsProvider> defaultProviderOrder = [
    LyricsProvider.lrcRed,
    LyricsProvider.betterLyrics,
    LyricsProvider.biniLyrics,
    LyricsProvider.paxSenix,
    LyricsProvider.paxSenixSpotify,
    LyricsProvider.paxSenixMusixmatch,
    LyricsProvider.betterLyricsPortato,
    LyricsProvider.lyricsPlus,
    LyricsProvider.simpMusic,
    LyricsProvider.kugou,
    LyricsProvider.lrclib,
    LyricsProvider.unison,
    LyricsProvider.musixmatch,
    LyricsProvider.youtubeTranscript,
    LyricsProvider.youtubeMusic,
    LyricsProvider.megalobiz,
    LyricsProvider.genius,
  ];

  static const String _orderPrefKey = 'lyrics_providers_order';
  static const String _enabledPrefKey = 'lyrics_providers_enabled';

  List<LyricsProvider> _providerOrder = List.from(defaultProviderOrder);
  Set<LyricsProvider> _enabledProviders = Set.from(defaultProviderOrder);

  List<LyricsProvider> get providerOrder => List.unmodifiable(_providerOrder);
  Set<LyricsProvider> get enabledProviders =>
      Set.unmodifiable(_enabledProviders);

  bool isProviderEnabled(LyricsProvider provider) =>
      _enabledProviders.contains(provider);

  Future<void> updateProviderOrder(List<LyricsProvider> newOrder) async {
    _providerOrder = List.from(newOrder);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _orderPrefKey, _providerOrder.map((e) => e.name).toList());
  }

  Future<void> setProviderEnabled(LyricsProvider provider, bool enabled) async {
    if (!enabled &&
        provider.isOffered &&
        _enabledProviders.where((p) => p.isOffered).length <= 1 &&
        _enabledProviders.contains(provider)) {
      // Must keep at least one provider enabled. Counted over the providers the
      // listener can see: a retired one still sitting in the set would otherwise
      // let them switch off the last source they can actually reach.
      return;
    }
    if (enabled) {
      _enabledProviders.add(provider);
    } else {
      _enabledProviders.remove(provider);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _enabledPrefKey, _enabledProviders.map((e) => e.name).toList());
  }

  Future<void> resetProvidersToDefault() async {
    _providerOrder = List.from(defaultProviderOrder);
    _enabledProviders = Set.from(defaultProviderOrder);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_orderPrefKey);
    await prefs.remove(_enabledPrefKey);
  }

  final BetterLyricsProvider _better;
  final SimpMusicProvider _simpMusic;
  final KuGouProvider _kugou;
  final LrcRedProvider _lrcRed;
  final BiniLyricsProvider _bini;
  final PaxSenixProvider _paxSenix;
  final LyricsPlusProvider _lyricsPlus;
  final UnisonProvider _unison;
  final MusixmatchProvider _musixmatch;
  final GeniusProvider _genius;
  final YouTubeMusicLyricsProvider _youtubeMusic;
  final MegalobizProvider _megalobiz;
  final LrcLibProvider _lrcLib;
  final InnerTubeService _innerTube;
  final LyricsCacheDb _diskCache;
  final PaxSenixKeyStore _keys;
  final LyricsHttp _documentHttp;

  // ---------------------------------------------------------------------------
  // The PaxSenix API key
  // ---------------------------------------------------------------------------

  String _paxKey = '';

  /// Whether a PaxSenix key is stored. Drives the settings row and the
  /// "API key required" labels in the provider sheet.
  ValueListenable<bool> get paxSenixKeyConfigured => _keys.hasKey;

  bool get hasPaxSenixKey => _paxKey.isNotEmpty;

  /// Stores (or, when blank, clears) the listener's PaxSenix key.
  ///
  /// Saving a key switches the two keyed sources on: somebody who went and got
  /// a key meant to use it, and a saved enabled-set from before these sources
  /// existed would otherwise leave them off with nothing to say why.
  Future<void> setPaxSenixKey(String value) async {
    await _keys.write(value);
    _paxKey = await _keys.read();
    if (_paxKey.isEmpty) return;
    var changed = false;
    for (final p in const [
      LyricsProvider.paxSenixSpotify,
      LyricsProvider.paxSenixMusixmatch,
    ]) {
      changed = _enabledProviders.add(p) || changed;
    }
    if (changed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _enabledPrefKey, _enabledProviders.map((e) => e.name).toList());
    }
  }

  /// Whether [provider] can be asked right now: it is offered, and if it needs
  /// a key there is one.
  bool isAvailable(LyricsProvider provider) =>
      provider.isOffered && (!provider.requiresApiKey || hasPaxSenixKey);

  // ---------------------------------------------------------------------------
  // Caches
  // ---------------------------------------------------------------------------

  // Memory cache for parsed entries (including word-level timing)
  final Map<String, List<LyricsEntry>> _parsedCache = {};
  static const int _maxMemCacheSize = 100;

  /// Which provider produced each memory-cached entry.
  ///
  /// Kept beside the entries rather than inside them: the cache is keyed on title
  /// and artist, which says nothing about who answered, so without this a
  /// memory hit would report an unknown source and the deck would say "Lyrics
  /// unavailable" for a lyric that is plainly there.
  final Map<String, String> _parsedCacheProviders = {};

  /// Recording ids, remembered per track so the second lookup of a song skips
  /// the identify round trip. Bounded; the oldest entry goes first.
  final LinkedHashMap<String, String> _isrcByTrack = LinkedHashMap();
  static const int _maxIsrcEntries = 100;

  /// Records which provider answered for a memory-cached entry.
  void _rememberSource(String cacheKey, String? providerName) {
    if (providerName == null) {
      _parsedCacheProviders.remove(cacheKey);
      return;
    }
    _parsedCacheProviders[cacheKey] = providerName;
  }

  /// Resolves a persisted provider name, tolerating a name this build no longer
  /// has.
  ///
  /// A cache row written by a build that had a source this build dropped is
  /// still perfectly good lyrics; it just cannot be named. Null says exactly
  /// that, where `firstWhere(orElse:)` would silently mislabel it as whichever
  /// provider happens to be first today.
  static LyricsProvider? _providerFromName(String? name) {
    if (name == null) return null;
    for (final provider in LyricsProvider.values) {
      if (provider.name == name) return provider;
    }
    return null;
  }

  /// Whether a provider is enabled by the listener's own choices.
  ///
  /// A source somebody has turned off is a source this app does not contact, not
  /// even to help the sources they left on.
  bool isEnabled(LyricsProvider provider) =>
      _enabledProviders.contains(provider) && provider.isOffered;

  /// Brings a saved order up to date with this build.
  ///
  /// Drops providers that are no longer offered, and slots any provider added
  /// since the order was saved in right after the one it is declared behind - at
  /// the top if nothing is declared ahead of it. Without this a new provider would
  /// be appended below every line-only fallback, where it would never get to
  /// answer at all.
  static List<LyricsProvider> reconcileOrder(List<LyricsProvider> saved) {
    final result = <LyricsProvider>[];
    for (final provider in saved) {
      if (provider.isOffered && !result.contains(provider)) {
        result.add(provider);
      }
    }
    for (final provider in defaultProviderOrder) {
      // The same filter as the saved list above.
      //
      // Without it this loop put straight back everything the first loop had just
      // dropped: `initialize()` handed `reconcileOrder` a saved order, the method
      // correctly removed the retired providers, and then re-seeded them from the
      // default order a few lines later. A returning user kept paying for a scrape
      // the sheet could not even show them.
      if (!provider.isOffered) continue;
      if (result.contains(provider)) continue;
      // The nearest declared predecessor that the saved order actually kept.
      LyricsProvider? before;
      for (var i = defaultProviderOrder.indexOf(provider) - 1; i >= 0; i--) {
        final candidate = defaultProviderOrder[i];
        if (result.contains(candidate)) {
          before = candidate;
          break;
        }
      }
      if (before == null) {
        result.insert(0, provider);
      } else {
        result.insert(result.indexOf(before) + 1, provider);
      }
    }
    return result;
  }

  /// How long past the first held answer the race keeps looking for a better
  /// one, and the longest a lookup may take. Instance fields only so a test can
  /// shorten them; nothing else writes them.
  @visibleForTesting
  Duration raceGrace = prioritizeGrace;
  @visibleForTesting
  Duration raceDeadline = overallDeadline;

  /// How long the ISRC lookup may delay the sources that prefer one.
  @visibleForTesting
  Duration identifyTimeout = _LookupContext.defaultIdentifyTimeout;

  // In-flight request deduplication, keyed on (track, onlyProvider).
  final Map<String, _InFlight> _inFlight = {};

  // Prefetch queue
  final List<_PrefetchTask> _prefetchQueue = [];
  bool _isPrefetching = false;

  bool _isInitialized = false;

  /// Initialize the service (call once on app start)
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _diskCache.initialize();
    _paxKey = await _keys.read();

    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList(_orderPrefKey);
    if (savedOrder != null && savedOrder.isNotEmpty) {
      final parsed = <LyricsProvider>[];
      for (final name in savedOrder) {
        final p = LyricsProvider.values.where((e) => e.name == name).firstOrNull;
        if (p != null && !parsed.contains(p)) parsed.add(p);
      }
      // Goes through [reconcileOrder] rather than an inline loop: that one had
      // no `isOffered` filter, so a provider retired in this build stayed in a
      // returning user's order, and it appended providers a new arrival could
      // never reach.
      _providerOrder = reconcileOrder(parsed);
    }

    final savedEnabled = prefs.getStringList(_enabledPrefKey);
    if (savedEnabled != null) {
      final parsed = <LyricsProvider>{};
      for (final name in savedEnabled) {
        final p = LyricsProvider.values.where((e) => e.name == name).firstOrNull;
        if (p != null) parsed.add(p);
      }
      // Never let a retired provider come back through a saved enabled-set.
      parsed.removeWhere((p) => !p.isOffered);
      if (parsed.isNotEmpty) {
        _enabledProviders = parsed;
      }
    }

    _isInitialized = true;
    if (kDebugMode) {
      debugPrint('LyricsService: Initialized with disk cache and custom providers');
    }
  }

  /// Whether a line-synced hit is held back while the rest of the sources are
  /// still asked, on the chance one carries word or syllable timings.
  ///
  /// TRUE by default - the product decision for this app, and the reason the
  /// race has a grace period: holding costs a wait on every remaining source,
  /// so it is bounded ([prioritizeGrace]) rather than open-ended.
  ///
  /// Persisted under a NEW key ([prioritizePrefKey]). The old key was never a
  /// user's decision: it was a default the app shipped as `false` and wrote back
  /// the first time anything touched the setting. Reading the old key would
  /// carry that accident forward for everybody.
  ///
  /// A NAMED constant rather than a literal at each use site, so the provider,
  /// the service and the test all read the same one and it cannot drift.
  static const bool prioritizeSyllableDefault = true;

  /// Where the "prioritize word sync" choice is stored.
  static const String prioritizePrefKey = 'prioritize_syllable_sync_v2';

  /// "Unknown Album" is the model's placeholder, not a title: sent to a
  /// provider it only ever makes the match worse.
  static String? cleanAlbum(String? album) {
    final trimmed = album?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower == 'unknown album' || lower == 'unknown') return null;
    return trimmed;
  }

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  /// Lyrics for a track, with the provider that produced them.
  ///
  /// [callbacks] hear every provider's progress for THIS lookup - not a global
  /// hook on the singleton, so a lookup that outlives its track cannot report
  /// into the next one. A caller that joins a lookup already in flight (the
  /// user reaching a track the prefetcher is working on) is replayed what it
  /// missed.
  Future<LyricsLookupResult> lookup({
    required String title,
    required String artist,
    int? durationMs,
    String? videoId,
    String? album,

    /// When false, a line-synced result is accepted as soon as it arrives.
    ///
    /// When true, a line-synced hit is held back and the remaining sources are
    /// still asked, on the chance one of them carries word or syllable timings
    /// worth the wait (see [prioritizeGrace]). This is the "Prioritize word
    /// sync" setting. See [prioritizeSyllableDefault].
    bool prioritizeSyllable = prioritizeSyllableDefault,

    /// When true, an unsynced plain-text result is not accepted.
    ///
    /// The "Synced lyrics" setting. Left at its default the plain-text sources
    /// can still answer, because refusing them outright would leave the screen
    /// empty for a song nothing has ever synced.
    bool syncedOnly = false,

    /// Asks exactly this provider and nothing else.
    ///
    /// For the provider sheet's manual choice. It bypasses the priority order and
    /// the enabled set - the listener has just pointed at a source on purpose, so
    /// declining to ask it because it sits below another one in their saved order
    /// would ignore the very thing they asked for. Being a deliberate choice, it
    /// also bypasses "prioritize word sync": that setting exists to improve an
    /// automatic search, and holding back the answer from a source the listener
    /// picked by hand would just show them nothing.
    ///
    /// A manual lookup never writes the shared cache; the caller decides whether
    /// the choice sticks (see [rememberChoice]).
    LyricsProvider? onlyProvider,

    /// Ignores both caches for this call.
    bool skipCache = false,

    /// Set by the prefetcher. A prefetch must not leave an unsynced answer
    /// behind for the track to be stuck with when it is actually played.
    bool prefetch = false,
    LyricsRaceCallbacks callbacks = const LyricsRaceCallbacks(),
  }) async {
    final cacheKey = _buildCacheKey(title, artist, videoId: videoId);

    // 1. Memory
    if (!skipCache && _parsedCache.containsKey(cacheKey)) {
      if (kDebugMode) debugPrint('LyricsService: Parsed cache hit for "$title"');
      return LyricsLookupResult(
        entries: _parsedCache[cacheKey]!,
        provider: _providerFromName(_parsedCacheProviders[cacheKey]),
        fromCache: true,
      );
    }

    // 2. Disk
    if (!skipCache) {
      final cached = await _readDisk(cacheKey, title);
      if (cached != null) return cached;
    }

    // 3. Deduplicate in-flight requests. A manual single-provider fetch never
    // joins an automatic lookup (and vice versa): it asks a different question,
    // and answering it with the other's result is how a manual choice used to
    // come back as "the lyrics you already had".
    final flightKey = '$cacheKey|${onlyProvider?.name ?? ''}';
    final existing = _inFlight[flightKey];
    if (existing != null) {
      if (kDebugMode) {
        debugPrint('LyricsService: Deduplicating request for "$title"');
      }
      existing.join(callbacks);
      return existing.future;
    }

    final flight = _InFlight()..join(callbacks);
    _inFlight[flightKey] = flight;
    flight.future = _race(
      flight: flight,
      cacheKey: cacheKey,
      title: title,
      artist: artist,
      onlyProvider: onlyProvider,
      durationMs: durationMs,
      videoId: videoId,
      album: cleanAlbum(album),
      prioritizeSyllable: prioritizeSyllable,
      syncedOnly: syncedOnly,
      cacheUnsynced: !prefetch,
    ).whenComplete(() => _inFlight.remove(flightKey));
    return flight.future;
  }

  /// Get parsed lyrics entries with BitChord's syllable/word-first prioritization.
  ///
  /// Kept for callers that only want the lines. Use [lookup] to learn who
  /// produced them.
  Future<List<LyricsEntry>> getParsedLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? videoId,
    String? album,
    bool prioritizeSyllable = prioritizeSyllableDefault,
    bool syncedOnly = false,
    LyricsProvider? onlyProvider,
    bool skipCache = false,
  }) async {
    final result = await lookup(
      title: title,
      artist: artist,
      durationMs: durationMs,
      videoId: videoId,
      album: album,
      prioritizeSyllable: prioritizeSyllable,
      syncedOnly: syncedOnly,
      onlyProvider: onlyProvider,
      skipCache: skipCache,
    );
    return result.entries;
  }

  Future<LyricsLookupResult?> _readDisk(String cacheKey, String title) async {
    final diskEntry = await _diskCache.get(cacheKey);
    if (diskEntry == null || diskEntry.lyrics.isEmpty) return null;

    final entries = decodeCachedLyrics(diskEntry.lyrics, diskEntry.timings);

    // Invalidate if contaminated by legacy BetterLyrics unspaced bug
    final isContaminated = diskEntry.provider == LyricsProvider.betterLyrics.name &&
        entries.any((e) =>
            e.text.length >= 18 &&
            !e.text.contains(' ') &&
            RegExp(r'^[a-zA-Z0-9\x27\x22\.,!?\-]+$').hasMatch(e.text));
    if (isContaminated) {
      if (kDebugMode) {
        debugPrint('LyricsService: Invalidating unspaced legacy disk cache for "$title"');
      }
      return null;
    }

    if (kDebugMode) debugPrint('LyricsService: Disk cache hit for "$title"');
    final withGaps = withInstrumentalGaps(entries);
    _storeMemory(cacheKey, withGaps, diskEntry.provider);
    return LyricsLookupResult(
      entries: withGaps,
      // The disk row records which source produced it, so a cached lyric can
      // still be attributed honestly instead of showing "unknown".
      provider: _providerFromName(diskEntry.provider),
      fromCache: true,
    );
  }

  /// Asks every enabled provider at once and takes the answers in priority
  /// order.
  ///
  /// The concurrency is the latency win; the ordered consumption is the
  /// correctness win. Neither survives without the other - see [ProviderRace],
  /// which is where the reasoning lives.
  Future<LyricsLookupResult> _race({
    required _InFlight flight,
    required String cacheKey,
    required String title,
    required String artist,
    LyricsProvider? onlyProvider,
    int? durationMs,
    String? videoId,
    String? album,
    required bool prioritizeSyllable,
    required bool syncedOnly,
    required bool cacheUnsynced,
  }) async {
    // A provider kept in code but off the list is never asked, whatever a saved
    // order or a stale enabled-set still says about it. One that needs a key is
    // not asked without one.
    final sequence = onlyProvider != null
        ? <LyricsProvider>[onlyProvider]
        : _providerOrder
            .where((p) => isEnabled(p) && isAvailable(p))
            .toList(growable: false);
    if (sequence.isEmpty) return const LyricsLookupResult.none();

    final context = _LookupContext(
      title: forLyricsSearch(title),
      artist: artistForLyricsSearch(artist),
      album: album,
      durationMs: durationMs != null && durationMs > 0 ? durationMs : null,
      videoId: videoId,
      isrc: _isrcByTrack[cacheKey],
      documents: _SharedDocuments(_documentHttp),
    );

    // Identify the recording before the Apple-family sources need it - but do
    // not make the sources that do not need it wait. Each ISRC-aware fetch
    // awaits [_LookupContext.resolveIsrc]; everything else is already away.
    final identifyAllowed = onlyProvider == null
        ? isEnabled(LyricsProvider.biniLyrics)
        : onlyProvider == LyricsProvider.biniLyrics ||
            ((onlyProvider == LyricsProvider.lrcRed ||
                    onlyProvider == LyricsProvider.lyricsPlus) &&
                isEnabled(LyricsProvider.biniLyrics));
    if (context.isrc == null && identifyAllowed) {
      context.startIdentify(
        _bini,
        timeout: identifyTimeout,
        onIsrc: (isrc) => _rememberIsrc(cacheKey, isrc),
      );
    }

    final specs = <ProviderRaceSpec>[
      for (final provider in sequence)
        ProviderRaceSpec(
          provider: provider,
          // Genius scrapes a web page. Started eagerly it spends a scrape and a
          // rate-limit budget on every track, including the many where the
          // providers ahead of it already had the words. An explicit request for
          // it is eager on purpose - the listener asked for it by name.
          lazy: provider.isLazy && onlyProvider == null,
          fetch: () => _fetchFrom(provider, context, cacheKey),
        ),
    ];

    final manual = onlyProvider != null;
    final outcome = await ProviderRace.run(
      specs: specs,
      judge: (entries) => judge(
        entries,
        // Not applied to a source the listener picked by hand. Both lyrics
        // settings shape an automatic search; overriding an explicit choice
        // would show the listener nothing for having been specific.
        manual: manual,
        prioritizeSyllable: prioritizeSyllable,
        syncedOnly: syncedOnly,
      ),
      callbacks: flight.callbacks,
      grace: raceGrace,
      deadline: raceDeadline,
    );

    if (!outcome.hasResult) {
      if (kDebugMode) debugPrint('LyricsService: No lyrics found for "$title"');
      return const LyricsLookupResult.none();
    }

    final withGaps = withInstrumentalGaps(outcome.entries);
    final provider = outcome.provider!;

    if (kDebugMode) {
      debugPrint(
        'LyricsService: '
        '${outcome.isFallback ? 'Falling back to held hit from' : 'Hit from'} '
        '${provider.displayName} (${withGaps.length} lines)',
      );
    }

    if (!manual) {
      await _cacheParsed(
        cacheKey,
        withGaps,
        provider,
        keepUnsynced: cacheUnsynced,
      );
    }
    return LyricsLookupResult(
      entries: withGaps,
      provider: provider,
      isFallback: outcome.isFallback,
    );
  }

  /// Decides whether an answer settles the race, is kept only as a fallback, or
  /// is discarded.
  ///
  /// Both lyrics settings are answered here rather than at each call site, so
  /// every provider goes through the same decision instead of each one
  /// re-deriving it from raw entries.
  ///
  ///   * a manual choice is always accepted;
  ///   * unsynced text is the last resort ([LyricsVerdict.holdPlain]) - or, with
  ///     "Synced lyrics" on, refused;
  ///   * word-synced is accepted at once, because nothing later can beat it;
  ///   * line-synced is accepted at once with "prioritize" off, and held (while
  ///     the rest keep being asked) with it on.
  @visibleForTesting
  static LyricsVerdict judge(
    List<LyricsEntry> entries, {
    bool manual = false,
    required bool prioritizeSyllable,
    required bool syncedOnly,
  }) {
    if (entries.isEmpty) return LyricsVerdict.reject;
    if (manual) return LyricsVerdict.accept;

    if (!lyricsAreTimed(entries)) {
      return syncedOnly ? LyricsVerdict.reject : LyricsVerdict.holdPlain;
    }
    if (entries.any((e) => e.isWordSynced)) return LyricsVerdict.accept;
    return prioritizeSyllable ? LyricsVerdict.hold : LyricsVerdict.accept;
  }

  /// Asks one provider. Returns null for a genuine miss.
  ///
  /// Split out of the race so the provider calls are not nested inside the
  /// scheduling logic: changing WHERE an answer is read from should never mean
  /// rewriting HOW a source is asked.
  Future<List<LyricsEntry>?> _fetchFrom(
    LyricsProvider provider,
    _LookupContext c,
    String cacheKey,
  ) async {
    try {
      switch (provider) {
        case LyricsProvider.betterLyrics:
          return await _better.getLyrics(
            title: c.title,
            artist: c.artist,
            durationMs: c.durationMs,
            album: c.album,
          );

        case LyricsProvider.betterLyricsPortato:
          return await _better.getPortato(
            title: c.title,
            artist: c.artist,
            durationMs: c.durationMs,
            album: c.album,
          );

        case LyricsProvider.simpMusic:
          final id = c.videoId;
          if (id == null || id.isEmpty) return null;
          return await _simpMusic.getLyrics(videoId: id, durationMs: c.durationMs);

        case LyricsProvider.lrcRed:
          final isrc = await c.resolveIsrc();
          return await _lrcRed.getLyrics(
            c.appleQuery(isrc: isrc),
            get: c.documents.get,
            onIsrc: (value) => _rememberIsrc(cacheKey, value),
          );

        case LyricsProvider.biniLyrics:
          // Identified once, up front, and the hit reused: asking Bini a second
          // time for the same recording is a request for an answer already held.
          final hit = await c.identifyResult();
          if (hit == null && c.isrc == null) return null;
          return await _bini.getLyrics(
            c.appleQuery(isrc: c.isrc),
            hit: hit,
            get: c.documents.get,
            onIsrc: (value) => _rememberIsrc(cacheKey, value),
          );

        case LyricsProvider.paxSenix:
          return await _paxSenix.getLyrics(c.appleQuery());

        case LyricsProvider.paxSenixSpotify:
          if (!hasPaxSenixKey) return null;
          return await _paxSenix.getSpotifyLyrics(
            title: c.title,
            artist: c.artist,
            durationMs: c.durationMs,
            apiKey: _paxKey,
          );

        case LyricsProvider.paxSenixMusixmatch:
          if (!hasPaxSenixKey) return null;
          return await _paxSenix.getMusixmatchLyrics(
            title: c.title,
            artist: c.artist,
            durationMs: c.durationMs,
            apiKey: _paxKey,
          );

        case LyricsProvider.lyricsPlus:
          final isrc = await c.resolveIsrc();
          return await _lyricsPlus.getLyrics(
            title: c.title,
            artist: c.artist,
            durationMs: c.durationMs,
            album: c.album,
            isrc: isrc,
          );

        case LyricsProvider.unison:
          return await _unison.getLyrics(
            title: c.title,
            artist: c.artist,
            durationMs: c.durationMs,
            album: c.album,
          );

        case LyricsProvider.musixmatch:
          return await _musixmatch.getLyrics(
            title: c.title,
            artist: c.artist,
            durationMs: c.durationMs,
          );

        case LyricsProvider.genius:
          return await _genius.getLyrics(title: c.title, artist: c.artist);

        case LyricsProvider.megalobiz:
          return await _megalobiz.getLyrics(title: c.title, artist: c.artist);

        case LyricsProvider.youtubeMusic:
          return await _youtubeMusic.getLyrics(videoId: c.videoId);

        case LyricsProvider.kugou:
          return await _kugou.getLyrics(
            title: c.title,
            artist: c.artist,
            durationMs: c.durationMs,
            album: c.album,
          );

        case LyricsProvider.lrclib:
          // ONE call with the cleaned name. This used to try up to four spelling
          // variants in sequence, each a full round trip, to compensate for a
          // title nobody had cleaned; the title is cleaned once, up front, now.
          final lrc = await _lrcLib.getLyrics(
            title: c.title,
            artist: c.artist,
            durationSeconds: c.durationMs != null ? c.durationMs! ~/ 1000 : null,
            album: c.album,
          );
          return _parseLrcAnswer(lrc);

        case LyricsProvider.youtubeTranscript:
          final id = c.videoId;
          if (id == null || id.isEmpty) return null;
          final transcript = await _innerTube.getTranscript(id);
          return _parseLrcAnswer(transcript);
      }
    } catch (e) {
      // A dead host is a miss, not a crash: one unreachable source must not take
      // the whole lookup down with it.
      if (kDebugMode) {
        debugPrint('LyricsService: Provider ${provider.name} failed: $e');
      }
      return null;
    }
  }

  static List<LyricsEntry>? _parseLrcAnswer(String? lrc) {
    if (lrc == null || lrc.trim().isEmpty) return null;
    final parsed = LyricsUtils.parseLrc(lrc);
    return parsed.any((e) => e.text.trim().isNotEmpty) ? parsed : null;
  }

  void _rememberIsrc(String cacheKey, String isrc) {
    final value = LrcRedProvider.normalizeIsrc(isrc);
    if (value == null) return;
    _isrcByTrack.remove(cacheKey);
    _isrcByTrack[cacheKey] = value;
    while (_isrcByTrack.length > _maxIsrcEntries) {
      _isrcByTrack.remove(_isrcByTrack.keys.first);
    }
  }

  static const String gapMarker = '• • •';

  /// Synthesizes musical breaks / instrumental pauses between distant timestamps (BitChord LyricGaps parity)
  ///
  /// Idempotent: lyrics that already carry a gap marker are returned as they
  /// are. A disk-cached row was stored AFTER this ran, so running it again used
  /// to add a second set of markers on top of the first.
  static List<LyricsEntry> withInstrumentalGaps(List<LyricsEntry> entries) {
    if (entries.isEmpty) return entries;
    if (entries.any((e) => e.text.trim() == gapMarker)) return entries;
    // Nothing is timed, so there is no silence to measure.
    if (!lyricsAreTimed(entries)) return entries;
    const minGapMs = 3800;
    final out = <LyricsEntry>[];

    // Find the first actual sung lyric entry (skipping empty headEntry)
    final firstVocalIdx = entries.indexWhere(
      (e) => e.text.trim().isNotEmpty && !e.isMusicalBreak,
    );

    // If first vocal line starts after intro gap (>= 3.5s), insert intro break
    if (firstVocalIdx >= 0 && entries[firstVocalIdx].timeMs >= 3500) {
      out.add(LyricsEntry(timeMs: 0, text: gapMarker));
    }

    for (int i = 0; i < entries.length; i++) {
      final line = entries[i];
      // Avoid duplicate empty head entries at 0ms if we inserted an intro break
      if (line.text.trim().isEmpty && out.isNotEmpty) continue;
      out.add(line);

      if (i + 1 < entries.length) {
        final next = entries[i + 1];
        if (next.text.trim().isEmpty) continue;
        final lineEnd = line.endMs ?? (line.timeMs + 3200);
        final silence = next.timeMs - lineEnd;
        if (silence >= minGapMs && lineEnd > line.timeMs) {
          out.add(LyricsEntry(timeMs: lineEnd, text: gapMarker));
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Caching
  // ---------------------------------------------------------------------------

  void _storeMemory(String cacheKey, List<LyricsEntry> entries, String? source) {
    if (_parsedCache.length >= _maxMemCacheSize &&
        !_parsedCache.containsKey(cacheKey)) {
      final oldest = _parsedCache.keys.first;
      _parsedCache.remove(oldest);
      _parsedCacheProviders.remove(oldest);
    }
    _parsedCache[cacheKey] = entries;
    _rememberSource(cacheKey, source);
  }

  /// Stores a winner.
  ///
  /// Memory always (unless [keepUnsynced] is false and the lyric is untimed -
  /// the prefetcher's case); disk only when the lyric is TIMED. An untimed
  /// answer on disk would pin the track to plain text for a week, hiding any
  /// synced source that turns up in that time - and it is the answer of last
  /// resort anyway, cheap to find again.
  Future<void> _cacheParsed(
    String cacheKey,
    List<LyricsEntry> entries,
    LyricsProvider provider, {
    bool keepUnsynced = true,
  }) async {
    final timed = lyricsAreTimed(entries);
    if (!timed && !keepUnsynced) return;
    _storeMemory(cacheKey, entries, provider.name);
    if (!timed) return;

    // Convert to LRC text for disk persistence.
    //
    // Line text only, deliberately: this column stays readable as plain LRC so
    // an export or another reader works on it. The word and syllable timings go
    // beside it in their own column, because flattening them here - which is
    // what this used to do - meant a word-synced song came back line-synced
    // after every restart.
    final buffer = StringBuffer();
    for (final e in entries) {
      final m = (e.timeMs ~/ 60000).toString().padLeft(2, '0');
      final s = ((e.timeMs % 60000) / 1000).toStringAsFixed(2).padLeft(5, '0');
      buffer.writeln('[$m:$s]${e.text}');
    }
    await _diskCache.put(
      cacheKey,
      buffer.toString(),
      true,
      provider.name,
      timings: encodeTimings(entries),
    );
  }

  /// Makes a manual provider choice the track's cached lyric.
  ///
  /// The provider sheet fetches a chosen source with [lookup]'s `onlyProvider`,
  /// which deliberately does not touch the cache. When the listener's choice is
  /// applied, this records it, so the next play of the track opens on the
  /// lyrics they picked rather than whatever the race would have chosen.
  Future<void> rememberChoice({
    required String title,
    required String artist,
    String? videoId,
    required LyricsProvider provider,
    required List<LyricsEntry> entries,
  }) =>
      _cacheParsed(
        _buildCacheKey(title, artist, videoId: videoId),
        entries,
        provider,
      );

  String _buildCacheKey(String title, String artist, {String? videoId}) {
    final base = '${title.toLowerCase().trim()}_${artist.toLowerCase().trim()}';
    if (videoId != null && videoId.isNotEmpty) {
      return '${videoId}_$base';
    }
    return base;
  }

  /// Prefetch lyrics for upcoming tracks.
  ///
  /// Each map carries `title`, `artist`, `videoId`, `durationMs` and `album`.
  /// A track with no known duration is skipped: asked without one, the sources
  /// cannot tell the studio cut from a live edit, and what comes back is cached
  /// as if it were right.
  void prefetchLyrics(
    List<Map<String, String>> tracks, {
    bool prioritizeSyllable = prioritizeSyllableDefault,
    bool syncedOnly = false,
  }) {
    for (final track in tracks) {
      final title = track['title'] ?? '';
      final artist = track['artist'] ?? '';
      final videoId = track['videoId'];
      final durationMs = int.tryParse(track['durationMs'] ?? '');

      if (title.isEmpty || artist.isEmpty) continue;
      if (durationMs == null || durationMs <= 0) continue;
      final cacheKey = _buildCacheKey(title, artist, videoId: videoId);

      if (_parsedCache.containsKey(cacheKey)) continue;
      if (_prefetchQueue.any((t) => t.cacheKey == cacheKey)) continue;

      _prefetchQueue.add(_PrefetchTask(
        cacheKey: cacheKey,
        title: title,
        artist: artist,
        videoId: videoId,
        durationMs: durationMs,
        album: track['album'],
        prioritizeSyllable: prioritizeSyllable,
        syncedOnly: syncedOnly,
      ));
    }
    _processPrefetchQueue();
  }

  Future<void> _processPrefetchQueue() async {
    if (_isPrefetching || _prefetchQueue.isEmpty) return;
    _isPrefetching = true;

    try {
      while (_prefetchQueue.isNotEmpty) {
        final task = _prefetchQueue.removeAt(0);
        try {
          final diskEntry = await _diskCache.get(task.cacheKey);
          if (diskEntry != null) continue;

          await Future.delayed(const Duration(milliseconds: 100));
          await lookup(
            title: task.title,
            artist: task.artist,
            videoId: task.videoId,
            durationMs: task.durationMs,
            album: task.album,
            prioritizeSyllable: task.prioritizeSyllable,
            syncedOnly: task.syncedOnly,
            prefetch: true,
          );
        } catch (_) {}
      }
    } finally {
      _isPrefetching = false;
    }
  }

  Future<void> clearCache() async {
    _parsedCache.clear();
    _parsedCacheProviders.clear();
    _isrcByTrack.clear();
    await _diskCache.clear();
    if (kDebugMode) debugPrint('LyricsService: All caches cleared');
  }

  void dispose() {
    _diskCache.close();
  }
}

/// Everything one lookup shares between the providers it runs.
///
/// The cleaned name (applied ONCE, so no provider re-cleans it differently),
/// the recording id when it is known or found, and the memoized document
/// fetcher.
class _LookupContext {
  _LookupContext({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.videoId,
    required this.isrc,
    required this.documents,
  });

  final String title;
  final String artist;
  final String? album;
  final int? durationMs;
  final String? videoId;
  final _SharedDocuments documents;

  /// The recording id, once known (remembered from an earlier lookup, or found
  /// by [startIdentify]).
  String? isrc;

  Future<BiniHit?>? _identify;

  /// How long to wait for the recording to be identified before carrying on
  /// without it. Bini's own answer is small and quick; a host that is not
  /// answering must not hold up the sources that merely prefer an ISRC.
  static const Duration defaultIdentifyTimeout = Duration(milliseconds: 2500);

  AppleLyricsQuery appleQuery({String? isrc}) => AppleLyricsQuery(
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
        isrc: isrc ?? this.isrc,
      );

  void startIdentify(
    BiniLyricsProvider bini, {
    required Duration timeout,
    required void Function(String isrc) onIsrc,
  }) {
    _identify = () async {
      try {
        final hit = await bini
            .identify(appleQuery())
            .timeout(timeout, onTimeout: () => null);
        if (hit != null && hit.isrc.isNotEmpty) {
          isrc = hit.isrc;
          onIsrc(hit.isrc);
        }
        return hit;
      } catch (_) {
        return null;
      }
    }();
  }

  /// The identified recording, or null when it could not be (or Bini is not in
  /// this lookup).
  Future<BiniHit?> identifyResult() => _identify ?? Future<BiniHit?>.value();

  /// The recording id, waiting (bounded) for identification if it is under way.
  Future<String?> resolveIsrc() async {
    if (isrc != null) return isrc;
    await identifyResult();
    return isrc;
  }
}

/// A per-lookup memo of fetched documents.
///
/// Bini's `lyricsUrl` and lrc.red's document are the same file. Whichever asks
/// first fetches it; the other is handed the same future.
class _SharedDocuments {
  _SharedDocuments(this._http);

  final LyricsHttp _http;
  final Map<String, Future<String?>> _documents = {};

  Future<String?> get(String url) => _documents.putIfAbsent(
        url,
        () => _http.getText(
          url,
          headers: const {'Accept': 'application/xml, text/xml, */*'},
        ),
      );
}

/// A lookup in progress, and everybody listening to it.
///
/// A second caller for the same track (the user arriving at a song the
/// prefetcher is working on) joins rather than starting a duplicate, and is
/// replayed what it missed so its provider sheet is not blank.
class _InFlight {
  late final Future<LyricsLookupResult> future;

  final List<LyricsRaceCallbacks> _listeners = [];
  final List<void Function(LyricsRaceCallbacks)> _log = [];

  void join(LyricsRaceCallbacks callbacks) {
    for (final event in List.of(_log)) {
      event(callbacks);
    }
    _listeners.add(callbacks);
  }

  void _emit(void Function(LyricsRaceCallbacks) event) {
    _log.add(event);
    for (final listener in List.of(_listeners)) {
      event(listener);
    }
  }

  /// What the race reports into. Results are given their instrumental gaps
  /// here, once, so every listener holds display-ready lyrics.
  late final LyricsRaceCallbacks callbacks = LyricsRaceCallbacks(
    onStarted: (p) => _emit((cb) => cb.onStarted?.call(p)),
    onResult: (p, entries) {
      final ready =
          entries == null ? null : LyricsService.withInstrumentalGaps(entries);
      _emit((cb) => cb.onResult?.call(p, ready));
    },
    onCancelled: (p) => _emit((cb) => cb.onCancelled?.call(p)),
  );
}

class _PrefetchTask {
  final String cacheKey;
  final String title;
  final String artist;
  final String? videoId;
  final int durationMs;
  final String? album;
  final bool prioritizeSyllable;
  final bool syncedOnly;

  _PrefetchTask({
    required this.cacheKey,
    required this.title,
    required this.artist,
    this.videoId,
    required this.durationMs,
    this.album,
    required this.prioritizeSyllable,
    required this.syncedOnly,
  });
}
