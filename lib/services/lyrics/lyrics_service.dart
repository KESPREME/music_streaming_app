// lib/services/lyrics/lyrics_service.dart
// BitChord-matching multi-source lyrics service with syllable/word-first priority,
// tiered fallbacks, two-tier caching, deduplication, and instrumental gap synthesis.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'better_lyrics_provider.dart';
import 'simp_music_provider.dart';
import 'kugou_provider.dart';
import 'lrclib_provider.dart';
import 'provider_race.dart';
import 'lyrics_cache_db.dart';
import '../innertube/innertube_service.dart';
import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';
import 'lyric_timings_codec.dart';
import 'apple_lyrics_common.dart';
import 'lrc_red_provider.dart';
import 'bini_lyrics_provider.dart';
import 'lyrics_plus_provider.dart';
import 'megalobiz_provider.dart';
import 'youtube_music_provider.dart';
import 'unison_provider.dart';
import 'musixmatch_provider.dart';
import 'genius_provider.dart';

/// Provider types for lyrics matching BitChord LyricsSource
enum LyricsProvider {
  lrcRed,
  betterLyrics,
  biniLyrics,
  paxSenix,
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
  /// Drives the "prioritize word sync" rule: a line-synced answer from one of
  /// these is held back rather than accepted outright.
  bool get canWordSync => switch (this) {
LyricsProvider.lrcRed ||
  LyricsProvider.betterLyrics ||
  LyricsProvider.biniLyrics ||
  LyricsProvider.paxSenix ||
  LyricsProvider.betterLyricsPortato ||
  LyricsProvider.lyricsPlus ||
  LyricsProvider.simpMusic ||
  LyricsProvider.lrclib ||
  LyricsProvider.unison ||
  LyricsProvider.musixmatch =>
    true,
  LyricsProvider.kugou => true,
  LyricsProvider.genius => false,
  LyricsProvider.youtubeTranscript => false,
  LyricsProvider.youtubeMusic => false,
  LyricsProvider.megalobiz => false,
  };

  /// Whether the provider is contacted at all for a given attempt.
  ///
  /// Genius and Megalobiz are HTML scrapers: starting them eagerly spends a
  /// scrape and a rate-limit budget on every track before the providers that can
  /// actually synchronise have answered.
  bool get isLazy =>
      this == LyricsProvider.genius || this == LyricsProvider.megalobiz;

  /// Kept in code but off the list: never shown, never asked - not even by
  /// someone whose saved choices still name it.
  ///
  /// For a host that has stopped answering. Deleting the provider outright would
  /// only mean writing it again if it comes back, which is the situation this is
  /// for. SimMusic is here because it is keyed on the video id and therefore only
  /// works when the track genuinely came from YouTube, which is not true of a
  /// queue built from any other source.
  bool get isOffered => this != LyricsProvider.simpMusic;
}

/// Main lyrics service that orchestrates multiple providers
/// with syllable-first priority, two-tier caching, and instrumental gap handling
class LyricsService {
  static final LyricsService _instance = LyricsService._internal();
  factory LyricsService() => _instance;
  LyricsService._internal();

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
/// Genius and the YouTube transcript can only produce whole lines. They are last
/// because nothing here can synchronise, and showing unsynced words beats showing
/// nothing only once the synchronised sources have genuinely missed.
static const List<LyricsProvider> defaultProviderOrder = [
  LyricsProvider.lrcRed,
  LyricsProvider.betterLyrics,
  LyricsProvider.biniLyrics,
  LyricsProvider.paxSenix,
  LyricsProvider.lyricsPlus,
  LyricsProvider.simpMusic,
  LyricsProvider.kugou,
  LyricsProvider.lrclib,
  LyricsProvider.unison,
  LyricsProvider.musixmatch,
  LyricsProvider.youtubeTranscript,
  LyricsProvider.genius,
];

  static const String _orderPrefKey = 'lyrics_providers_order';
  static const String _enabledPrefKey = 'lyrics_providers_enabled';

  List<LyricsProvider> _providerOrder = List.from(defaultProviderOrder);
  Set<LyricsProvider> _enabledProviders = Set.from(defaultProviderOrder);

  List<LyricsProvider> get providerOrder => List.unmodifiable(_providerOrder);
  Set<LyricsProvider> get enabledProviders => Set.unmodifiable(_enabledProviders);

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
        _enabledProviders.length <= 1 &&
        _enabledProviders.contains(provider)) {
      // Must keep at least one provider enabled
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

  final BetterLyricsProvider _betterLyricsProvider = BetterLyricsProvider();
  final SimpMusicProvider _simpMusicProvider = SimpMusicProvider();
  final KuGouProvider _kugouProvider = KuGouProvider();
  final LrcRedProvider _lrcRedProvider = LrcRedProvider();
  final BiniLyricsProvider _biniLyricsProvider = BiniLyricsProvider();
  final PaxSenixProvider _paxSenixProvider = PaxSenixProvider();
  final LyricsPlusProvider _lyricsPlusProvider = LyricsPlusProvider();
  final UnisonProvider _unisonProvider = UnisonProvider();
  final MusixmatchProvider _musixmatchProvider = MusixmatchProvider();
  final GeniusProvider _geniusProvider = GeniusProvider();
  final YouTubeMusicLyricsProvider _youtubeMusicProvider =
      YouTubeMusicLyricsProvider();
  final MegalobizProvider _megalobizProvider = MegalobizProvider();
  final LrcLibProvider _lrcLibProvider = LrcLibProvider();
  final InnerTubeService _innerTubeService = InnerTubeService();
  final LyricsCacheDb _diskCache = LyricsCacheDb();

  // Memory cache for raw results
  final Map<String, LyricsResult> _memCache = {};
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

  /// Which provider produced the lyrics returned by the last
  /// [getParsedLyrics] call.
  ///
  /// Recorded on every path that returns a non-empty result and cleared when
  /// nothing was found, so the caller can attribute the words it is about to
  /// show. Attribution is the point: a listener reading a translation or a
  /// crowd-edited source has a right to know which one it is.
  LyricsProvider? _lastSourceProvider;

  /// Whether that result came from the disk cache rather than a live request.
  /// Lets the UI be honest that the attribution is from a stored snapshot.
  bool _lastSourceIsCached = false;

  LyricsProvider? get lastSourceProvider => _lastSourceProvider;

  bool get lastSourceIsCached => _lastSourceIsCached;

  /// Resolves a persisted provider name, tolerating a name this build no longer
  /// has.
  ///
  /// A cache row written by a build that had a source this build dropped is
  /// still perfectly good lyrics; it just cannot be named. Null says exactly
  /// that, where `firstWhere(orElse:)` would silently mislabel it as whichever
  /// provider happens to be first today.
  /// Records which provider answered for a memory-cached entry.
  void _rememberSource(String cacheKey, String? providerName) {
    if (providerName == null) {
      _parsedCacheProviders.remove(cacheKey);
      return;
    }
    _parsedCacheProviders[cacheKey] = providerName;
  }

  static LyricsProvider? _providerFromName(String? name) {
    if (name == null) return null;
    for (final provider in LyricsProvider.values) {
      if (provider.name == name) return provider;
    }
    return null;
  }

  /// Reports that a provider has just been asked.
  ///
  /// Fired for a lazily-started provider at the moment it is finally asked, not
  /// when it was queued: a row showing "fetching" for a source that has not
  /// issued a request yet is lying about what the network is doing.
  void Function(LyricsProvider provider)? onProviderStarted;

  /// Reports a completed attempt. `found == false` is a genuine miss.
  void Function(LyricsProvider provider, bool found)? onProviderResult;

  /// Reports a provider that was still working when the race settled elsewhere.
  ///
  /// Deliberately not folded into a miss. This provider never said it had no
  /// lyrics - it lost a race it was still winning. Reporting it as a miss paints
  /// a permanent red cross on sources the app never finished asking, and the
  /// listener is then told not to bother choosing them.
  void Function(LyricsProvider provider)? onProviderCancelled;

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

  // In-flight request deduplication
  final Map<String, Future<List<LyricsEntry>>> _inFlightRequests = {};

  // Prefetch queue
  final List<_PrefetchTask> _prefetchQueue = [];
  bool _isPrefetching = false;

  bool _isInitialized = false;

  /// Initialize the service (call once on app start)
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _diskCache.initialize();

    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList(_orderPrefKey);
    if (savedOrder != null && savedOrder.isNotEmpty) {
      final parsed = <LyricsProvider>[];
      for (final name in savedOrder) {
        final p = LyricsProvider.values.where((e) => e.name == name).firstOrNull;
        if (p != null && !parsed.contains(p)) parsed.add(p);
      }
      for (final p in defaultProviderOrder) {
        if (!parsed.contains(p)) parsed.add(p);
      }
      _providerOrder = parsed;
    }

    final savedEnabled = prefs.getStringList(_enabledPrefKey);
    if (savedEnabled != null) {
      final parsed = <LyricsProvider>{};
      for (final name in savedEnabled) {
        final p = LyricsProvider.values.where((e) => e.name == name).firstOrNull;
        if (p != null) parsed.add(p);
      }
      if (parsed.isNotEmpty) {
        _enabledProviders = parsed;
      }
    }

    _isInitialized = true;
    if (kDebugMode) debugPrint('LyricsService: Initialized with disk cache and custom providers');
  }

  /// Get parsed lyrics entries with BitChord's syllable/word-first prioritization
  Future<List<LyricsEntry>> getParsedLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? videoId,
    String? album,
    /// When false, a line-synced result is accepted as soon as it arrives.
    ///
    /// When true (the default), a line-synced hit is held back and the remaining
    /// sources are still asked, on the chance one of them carries word or
    /// syllable timings worth the wait. This is the "Prioritize word sync"
    /// setting, and until it was threaded through here it was a switch that
    /// wrote a preference and changed nothing.
    bool prioritizeSyllable = true,

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
    LyricsProvider? onlyProvider,

    /// Ignores both caches for this call.
    ///
    /// Only for an explicit "use this source" request. The cache is keyed on
    /// title and artist alone, so it cannot tell which provider answered, and
    /// handing back the previous lookup's result would ignore the request while
    /// appearing to satisfy it.
    bool skipCache = false,
  }) async {
    final cacheKey = _buildCacheKey(title, artist, videoId: videoId);

    // 1. Check memory parsed cache
    if (!skipCache && _parsedCache.containsKey(cacheKey)) {
      if (kDebugMode) debugPrint('LyricsService: Parsed cache hit for "$title"');
      _lastSourceProvider = _providerFromName(
        _parsedCacheProviders[cacheKey],
      );
      _lastSourceIsCached = true;
      return _parsedCache[cacheKey]!;
    }

    // 2. Check disk cache
    final diskEntry = skipCache ? null : await _diskCache.get(cacheKey);
    if (diskEntry != null && diskEntry.lyrics.isNotEmpty) {
      final entries = diskEntry.isSynced
          ? LyricsUtils.parseLrc(diskEntry.lyrics)
          : LyricsUtils.parsePlainText(diskEntry.lyrics);

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
      } else {
        if (kDebugMode) debugPrint('LyricsService: Disk cache hit for "$title"');
        // Re-attach the word/syllable timings stored beside the line text.
        // Without this a word-synced song reads back line-synced and the
        // progressive wipe has nothing to draw from until the next refetch.
        final withTimings = attachTimings(entries, diskEntry.timings);
        final withGaps = withInstrumentalGaps(withTimings);
        _parsedCache[cacheKey] = withGaps;
        // The disk row records which source produced it, so a cached lyric can
        // still be attributed honestly instead of showing "unknown".
        _lastSourceProvider = _providerFromName(diskEntry.provider);
        _lastSourceIsCached = true;
        _rememberSource(cacheKey, diskEntry.provider);
        return withGaps;
      }
    }

    // 3. Deduplicate in-flight requests
    if (_inFlightRequests.containsKey(cacheKey)) {
      if (kDebugMode) debugPrint('LyricsService: Deduplicating request for "$title"');
      return _inFlightRequests[cacheKey]!;
    }

    final future = _fetchWithSyllablePriority(
      cacheKey: cacheKey,
      title: title,
      artist: artist,
      onlyProvider: onlyProvider,
      durationMs: durationMs,
      videoId: videoId,
      album: album,
      prioritizeSyllable: prioritizeSyllable,
      syncedOnly: syncedOnly,
    );

    _inFlightRequests[cacheKey] = future;
    try {
      final result = await future;
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  /// Fetches lyrics trying enabled providers in user-configured priority order
  /// Asks every enabled provider at once and takes the answers in priority
  /// order.
  ///
  /// The concurrency is the latency win; the ordered consumption is the
  /// correctness win. Neither survives without the other - see [ProviderRace],
  /// which is where the reasoning lives.
  Future<List<LyricsEntry>> _fetchWithSyllablePriority({
    required String cacheKey,
    required String title,
    required String artist,
    LyricsProvider? onlyProvider,
    int? durationMs,
    String? videoId,
    String? album,
    String? isrc,
    required bool prioritizeSyllable,
    required bool syncedOnly,
  }) async {
    // A provider kept in code but off the list is never asked, whatever a saved
    // order or a stale enabled-set still says about it.
    final sequence = onlyProvider != null
        ? <LyricsProvider>[onlyProvider]
        : _providerOrder
            .where((p) => p.isOffered && _enabledProviders.contains(p))
            .toList(growable: false);
    if (sequence.isEmpty) return [];

    final specs = <ProviderRaceSpec>[
      for (final provider in sequence)
        ProviderRaceSpec(
          provider: provider,
          // Genius scrapes a web page. Started eagerly it spends a scrape and a
          // rate-limit budget on every track, including the many where the
          // providers ahead of it already had the words. An explicit request for
          // it is eager on purpose - the listener asked for it by name.
          lazy: provider.isLazy && onlyProvider == null,
          fetch: () => _fetchFrom(
            provider,
            title: title,
            artist: artist,
            durationMs: durationMs,
            videoId: videoId,
            album: album,
            isrc: isrc,
          ),
        ),
    ];

    final outcome = await ProviderRace.run(
      specs: specs,
      judge: (entries) => _judge(
        entries,
        // Not applied to a source the listener picked by hand. Both lyrics
        // settings shape an automatic search; overriding an explicit choice
        // would show the listener nothing for having been specific.
        prioritizeSyllable: onlyProvider == null && prioritizeSyllable,
        syncedOnly: onlyProvider == null && syncedOnly,
      ),
      onStarted: onProviderStarted,
      onSettled: (provider, found) => onProviderResult?.call(provider, found),
      onAbandoned: onProviderCancelled,
    );

    if (!outcome.hasResult) {
      if (kDebugMode) debugPrint('LyricsService: No lyrics found for "$title"');
      _lastSourceProvider = null;
      return [];
    }

    final withGaps = withInstrumentalGaps(outcome.entries);
    final provider = outcome.provider!;

    if (kDebugMode) {
      debugPrint(
        'LyricsService: '
        '${outcome.isFallback ? 'Falling back to line-synced hit from' : 'Hit from'} '
        '${provider.displayName} (${withGaps.length} lines)',
      );
    }

    await _cacheParsed(cacheKey, withGaps, provider);
    _lastSourceProvider = provider;
    _lastSourceIsCached = false;
    return withGaps;
  }

  /// Decides whether an answer settles the race, is kept only as a fallback, or
  /// is discarded.
  ///
  /// Both lyrics settings are answered here rather than at each call site, so
  /// every provider goes through the same three-way decision instead of each one
  /// re-deriving it from raw entries.
  static LyricsVerdict _judge(
    List<LyricsEntry> entries, {
    required bool prioritizeSyllable,
    required bool syncedOnly,
  }) {
    if (entries.isEmpty) return LyricsVerdict.reject;
    final isWordSynced = entries.any((e) => e.isWordSynced);
    final isSynced = entries.any((e) => e.timeMs > 0);

    // "Prioritize word sync": hold a line-synced answer back and keep asking the
    // remaining sources for word or syllable timings. A word-synced answer is
    // accepted outright, because nothing later can beat it - that is what makes
    // this a bounded wait rather than a full sweep of every source.
    if (prioritizeSyllable && isSynced && !isWordSynced) {
      return LyricsVerdict.hold;
    }

    // "Synced lyrics": refuse a plain-text result when the listener asked for
    // synced only. Checked after the hold so a line-synced answer has already
    // become the fallback rather than being thrown away.
    if (syncedOnly && !isSynced) return LyricsVerdict.reject;

    return LyricsVerdict.accept;
  }

  /// Asks one provider. Returns null for a genuine miss.
  ///
  /// Split out of the race so the provider calls are not nested inside the
  /// scheduling logic: changing WHERE an answer is read from should never mean
  /// rewriting HOW a source is asked.
  Future<List<LyricsEntry>?> _fetchFrom(
    LyricsProvider provider, {
    required String title,
    required String artist,
    int? durationMs,
    String? videoId,
    String? album,
    String? isrc,
  }) async {
    /// The lookup the three Apple mirrors share. They serve the same catalogue
    /// with the same timings and differ only in how the recording is found.
    AppleLyricsQuery appleQuery({
      required String title,
      required String artist,
      String? album,
      int? durationMs,
      String? isrc,
    }) =>
        AppleLyricsQuery(
          title: title,
          artist: artist,
          album: album,
          durationMs: durationMs,
          isrc: isrc,
        );

    try {
      List<LyricsEntry>? entries;

      switch (provider) {
        case LyricsProvider.betterLyrics:
          entries = await _betterLyricsProvider.getLyrics(
            title: title,
            artist: artist,
            durationMs: durationMs,
            album: album,
          );
          break;

        case LyricsProvider.simpMusic:
          if (videoId != null && videoId.isNotEmpty) {
            final simpEntries = await _simpMusicProvider.getLyrics(
              videoId: videoId,
              durationMs: durationMs,
            );
            if (simpEntries != null && simpEntries.isNotEmpty) {
              entries = simpEntries;
            }
          }
          break;

        case LyricsProvider.lrcRed:
          entries = await _lrcRedProvider.getLyrics(appleQuery(
            title: title,
            artist: artist,
            album: album,
            durationMs: durationMs,
          ));
          break;

        case LyricsProvider.biniLyrics:
          entries = await _biniLyricsProvider.getLyrics(appleQuery(
            title: title,
            artist: artist,
            album: album,
            durationMs: durationMs,
            isrc: isrc,
          ));
          break;

        case LyricsProvider.paxSenix:
          entries = await _paxSenixProvider.getLyrics(appleQuery(
            title: title,
            artist: artist,
            durationMs: durationMs,
          ));
          break;

case LyricsProvider.betterLyricsPortato:
        entries = await _betterLyricsProvider.getPortato(
          title: title,
          artist: artist,
          durationMs: durationMs,
          album: album,
        );
        break;

      case LyricsProvider.megalobiz:
        entries = await _megalobizProvider.getLyrics(
          title: title,
          artist: artist,
        );
        break;

      case LyricsProvider.youtubeMusic:
        entries = await _youtubeMusicProvider.getLyrics(videoId: videoId);
        break;

      case LyricsProvider.lyricsPlus:
        entries = await _lyricsPlusProvider.getLyrics(
            title: title,
            artist: artist,
            durationMs: durationMs,
            album: album,
            isrc: isrc,
          );
          break;

        case LyricsProvider.unison:
          entries = await _unisonProvider.getLyrics(
            title: title,
            artist: artist,
            durationMs: durationMs,
          );
          break;

        case LyricsProvider.musixmatch:
          entries = await _musixmatchProvider.getLyrics(
            title: title,
            artist: artist,
            durationMs: durationMs,
          );
          break;

        case LyricsProvider.genius:
          entries = await _geniusProvider.getLyrics(
            title: title,
            artist: artist,
          );
          break;

        case LyricsProvider.kugou:
          entries = await _kugouProvider.getLyrics(
            title: title,
            artist: artist,
            durationMs: durationMs,
          );
          break;

        case LyricsProvider.lrclib:
          final lrcResult = await _tryLrcLib(title, artist, durationMs);
          if (lrcResult != null && lrcResult.lyrics.isNotEmpty) {
            final parsed = LyricsUtils.parseLrc(lrcResult.lyrics);
            if (parsed.isNotEmpty) {
              entries = parsed;
            }
          }
          break;

        case LyricsProvider.youtubeTranscript:
          if (videoId != null && videoId.isNotEmpty) {
            final ytResult = await _tryYouTubeTranscript(videoId);
            if (ytResult != null && ytResult.lyrics.isNotEmpty) {
              final parsed = LyricsUtils.parseLrc(ytResult.lyrics);
              if (parsed.isNotEmpty) {
                entries = parsed;
              }
            }
          }
          break;
      }
      return entries;
    } catch (e) {
      // A dead host is a miss, not a crash: one unreachable source must not take
      // the whole lookup down with it.
      if (kDebugMode) {
        debugPrint('LyricsService: Provider ${provider.name} failed: $e');
      }
      return null;
    }
  }

  /// Synthesizes musical breaks / instrumental pauses between distant timestamps (BitChord LyricGaps parity)
  static List<LyricsEntry> withInstrumentalGaps(List<LyricsEntry> entries) {
    if (entries.isEmpty) return entries;
    const minGapMs = 3800;
    final out = <LyricsEntry>[];

    // Find the first actual sung lyric entry (skipping empty headEntry)
    final firstVocalIdx = entries.indexWhere(
      (e) => e.text.trim().isNotEmpty && !e.isMusicalBreak,
    );

    // If first vocal line starts after intro gap (>= 3.5s), insert intro break
    if (firstVocalIdx >= 0 && entries[firstVocalIdx].timeMs >= 3500) {
      out.add(LyricsEntry(timeMs: 0, text: '• • •'));
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
          out.add(LyricsEntry(timeMs: lineEnd, text: '• • •'));
        }
      }
    }
    return out;
  }

  Future<void> _cacheParsed(
      String cacheKey, List<LyricsEntry> entries, LyricsProvider provider) async {
    if (_parsedCache.length >= _maxMemCacheSize) {
      _parsedCache.remove(_parsedCache.keys.first);
      _parsedCacheProviders.remove(_parsedCacheProviders.keys.first);
    }
    _parsedCache[cacheKey] = entries;
    _rememberSource(cacheKey, provider.name);

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

  /// Backward-compatible getLyrics method
  Future<LyricsResult?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? videoId,
    List<LyricsProvider> providerOrder = const [
      LyricsProvider.betterLyrics,
      LyricsProvider.simpMusic,
      LyricsProvider.kugou,
      LyricsProvider.lrclib,
      LyricsProvider.youtubeTranscript,
    ],
  }) async {
    final entries = await getParsedLyrics(
      title: title,
      artist: artist,
      durationMs: durationMs,
      videoId: videoId,
    );
    if (entries.isEmpty) return null;

    final buffer = StringBuffer();
    for (final e in entries) {
      final m = (e.timeMs ~/ 60000).toString().padLeft(2, '0');
      final s = ((e.timeMs % 60000) / 1000).toStringAsFixed(2).padLeft(5, '0');
      buffer.writeln('[$m:$s]${e.text}');
    }
    return LyricsResult(
      lyrics: buffer.toString(),
      isSynced: true,
      provider: LyricsProvider.betterLyrics,
    );
  }

  /// Try to get lyrics from LrcLib with enhanced metadata normalization
  Future<LyricsResult?> _tryLrcLib(
      String title, String artist, int? durationMs) async {
    final variants = _generateSearchVariants(title, artist);

    for (final variant in variants) {
      final result = await _lrcLibProvider.getLyrics(
        title: variant.title,
        artist: variant.artist,
        durationSeconds: durationMs != null ? durationMs ~/ 1000 : null,
      );

      if (result != null) {
        final isSynced = result.trimLeft().startsWith('[');
        return LyricsResult(
          lyrics: result,
          isSynced: isSynced,
          provider: LyricsProvider.lrclib,
        );
      }
    }

    return null;
  }

  /// Generate search variants for better matching
  List<_SearchVariant> _generateSearchVariants(String title, String artist) {
    final variants = <_SearchVariant>[];
    variants.add(_SearchVariant(title, artist));

    final cleanTitle = _cleanTitle(title);
    final cleanArtist = _cleanArtist(artist);

    if (cleanTitle != title || cleanArtist != artist) {
      variants.add(_SearchVariant(cleanTitle, cleanArtist));
    }
    if (cleanTitle != title) {
      variants.add(_SearchVariant(cleanTitle, artist));
    }
    if (cleanArtist != artist) {
      variants.add(_SearchVariant(title, cleanArtist));
    }

    return variants;
  }

  String _cleanTitle(String title) {
    return title
        .replaceAll(
            RegExp(r'[\(\[].*?feat.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?ft\.?.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'[\(\[].*?remaster.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'[\(\[].*?remix.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?mix.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'[\(\[].*?live.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'[\(\[].*?version.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'[\(\[].*?edit.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'-\s*live.*', caseSensitive: false), '')
        .trim();
  }

  String _cleanArtist(String artist) {
    var cleaned = artist.replaceAll(' - Topic', '').trim();
    if (cleaned.contains(',')) {
      cleaned = cleaned.split(',').first.trim();
    }
    cleaned = cleaned.replaceAll(RegExp(r'\s*VEVO', caseSensitive: false), '');
    return cleaned.trim();
  }

  Future<LyricsResult?> _tryYouTubeTranscript(String videoId) async {
    final transcript = await _innerTubeService.getTranscript(videoId);
    if (transcript != null && transcript.isNotEmpty) {
      return LyricsResult(
        lyrics: transcript,
        isSynced: true,
        provider: LyricsProvider.youtubeTranscript,
      );
    }
    return null;
  }

  String _buildCacheKey(String title, String artist, {String? videoId}) {
    final base = '${title.toLowerCase().trim()}_${artist.toLowerCase().trim()}';
    if (videoId != null && videoId.isNotEmpty) {
      return '${videoId}_$base';
    }
    return base;
  }

  /// Prefetch lyrics for upcoming tracks
  void prefetchLyrics(List<Map<String, String>> tracks) {
    for (final track in tracks) {
      final title = track['title'] ?? '';
      final artist = track['artist'] ?? '';
      final videoId = track['videoId'];

      if (title.isEmpty || artist.isEmpty) continue;
      final cacheKey = _buildCacheKey(title, artist, videoId: videoId);

      if (_parsedCache.containsKey(cacheKey)) continue;
      if (_prefetchQueue.any((t) => t.cacheKey == cacheKey)) continue;

      _prefetchQueue.add(_PrefetchTask(
        cacheKey: cacheKey,
        title: title,
        artist: artist,
        videoId: videoId,
      ));
    }
    _processPrefetchQueue();
  }

  Future<void> _processPrefetchQueue() async {
    if (_isPrefetching || _prefetchQueue.isEmpty) return;
    _isPrefetching = true;

    while (_prefetchQueue.isNotEmpty) {
      final task = _prefetchQueue.removeAt(0);
      try {
        final diskEntry = await _diskCache.get(task.cacheKey);
        if (diskEntry != null) continue;

        await Future.delayed(const Duration(milliseconds: 100));
        await getParsedLyrics(
          title: task.title,
          artist: task.artist,
          videoId: task.videoId,
        );
      } catch (_) {}
    }
    _isPrefetching = false;
  }

  Future<void> clearCache() async {
    _memCache.clear();
    _parsedCache.clear();
    await _diskCache.clear();
    if (kDebugMode) debugPrint('LyricsService: All caches cleared');
  }

  void dispose() {
    _diskCache.close();
  }
}

/// Result from lyrics lookup
class LyricsResult {
  final String lyrics;
  final bool isSynced;
  final LyricsProvider provider;

  const LyricsResult({
    required this.lyrics,
    required this.isSynced,
    required this.provider,
  });
}

class _PrefetchTask {
  final String cacheKey;
  final String title;
  final String artist;
  final String? videoId;

  _PrefetchTask({
    required this.cacheKey,
    required this.title,
    required this.artist,
    this.videoId,
  });
}

class _SearchVariant {
  final String title;
  final String artist;

  _SearchVariant(this.title, this.artist);
}
