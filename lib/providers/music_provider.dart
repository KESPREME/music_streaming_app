// lib/providers/music_provider.dart

// Dart Core Libraries
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:just_audio/just_audio.dart'; // Import for PlayerState
import 'dart:math';

// Flutter Foundation & Material
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    hide RepeatMode; // Added for NetworkImage

// Flutter Packages
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
// For network diagnostics
import 'package:collection/collection.dart'; // For firstWhereOrNull

// Your Project Model Imports
import '../models/track.dart';
import '../models/playlist.dart'; // Ensure this has fromJson, toJson, and copyWith methods
import '../models/artist.dart'; // Import new model
import '../models/album.dart'; // Import new model
import '../models/bitchord_page_models.dart';
// import '../models/friend_listening.dart'; // Uncomment if FriendListening model and FirestoreService are used

// Your Project Service Imports
import '../services/audio_service.dart'; // Your audio player wrapper
import '../services/spotify_service.dart';
import '../services/local_music_service.dart';
import '../services/network_service.dart';
import '../services/innertube/innertube_service.dart';
import '../services/auth_service.dart';
import '../services/stream_resolution_service.dart';
import '../services/downloads/download_manager.dart';
import '../services/home/home_diagnostics.dart';
import '../services/home/home_models.dart';
import '../services/home/ytm_home_source.dart';
import '../services/home/home_composer.dart';
import '../services/palette/palette_service.dart';
import 'accent_controller.dart';
import 'lofi_controller.dart';
import 'playback/playback_state.dart';
import 'playback/playback_controller.dart';
export 'playback/playback_state.dart' show RepeatMode;
import '../services/cast_service.dart'; // Cast Service
import 'package:cast/cast.dart'; // Cast Models
import '../services/lyrics/lyrics_service.dart'; // Multi-provider lyrics service
import '../services/recommendation_service.dart'; // AI recommendation engine
import '../services/recommendation/ranker.dart';
import '../services/recommendation/taste_profile.dart';
import '../services/recommendation/candidate_metadata.dart';
import '../services/recommendation/search_followup_graph.dart';
import '../services/recommendation/search_followup_store.dart';
import '../services/recommendation/quick_picks_engine.dart';
import '../services/recommendation/section_engines_v2.dart';
import '../models/lyrics_entry.dart'; // Lyrics data model
import '../services/metadata/track_metadata_enricher.dart';
import '../services/recommendation/queue_builder.dart';
// import '../services/firestore_service.dart'; // Uncomment if used

// Your Project Utility Imports
import '../utils/network_config.dart';

// Your Project Model Imports (Music Source)
// Your Project Model Imports (Music Source)
import '../models/music_source.dart'; // Music source enum


// Enums
// RepeatMode now lives in providers/playback/playback_state.dart (re-exported above).

/// Search screen lifecycle — one phase at a time, shared across the three
/// result kinds (tracks/artists/playlists).
enum SearchPhase { idle, loading, results, empty, error }

/// Which result kind the current search session belongs to. Tabs render
/// loading/error only when the session kind matches their own — otherwise a
/// track search would flash spinners on the Artists tab (BitChord parity: one
/// session, kind-tagged).
enum SearchKind { songs, videos, albums, artists, playlists }

// Helper function for list comparison (can be moved to a utils file)
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (int i = 0; i < a.length; i++) {
    // Assumes Track model has a correct == operator override
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Top-level so it can run in an isolate via [compute]; keeps large JSON
/// encodes off the UI thread.
String _jsonEncode(Object data) => jsonEncode(data);

List<dynamic> _jsonDecode(String s) => jsonDecode(s) as List<dynamic>;

class MusicProvider
    with ChangeNotifier, WidgetsBindingObserver
    implements MusicProviderLike {
  /// Album-art accent feed (null when not injected).
  final AccentController? _accentController;

  final GlobalKey<NavigatorState> playerNavigatorKey =
      GlobalKey<NavigatorState>();

  // BATTERY FIX: App lifecycle management
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool get isInBackground =>
      _appLifecycleState == AppLifecycleState.paused ||
      _appLifecycleState == AppLifecycleState.inactive;

  // --- State Properties ---
  List<Track> _tracks = [];
  List<Track> _trendingTracks = [];
  List<Track> _fullTrendingTracks = [];
  List<Track> _recentlyPlayed = [];
  List<Track> _likedSongs = [];
  List<Track> _searchedTracks = []; // For generic track search results
  List<Track> _artistTracks = [];
  List<Track> _genreTracks = [];
  List<Track> _recommendedTracks = []; // New field for "For You"
  List<Playlist> _userPlaylists = [];

  /// Home-page content version: bumped ONLY when one of the lists the Home
  /// screen renders changes. Playback position ticks and palette updates do
  /// NOT bump it, so Home sections can select on this int and stay idle
  /// during playback.
  int _homeContentVersion = 0;
  int get homeContentVersion => _homeContentVersion;
  void _bumpHomeContent() => _homeContentVersion++;

  /// New releases (InnerTube browse, service-level TTL cache).
  List<Track> _newReleases = [];
  List<Track> get newReleases => List.unmodifiable(_newReleases);

  // --- Structured Home feed (curated YTM home → fallback, SWR-cached) ---
  late final YouTubeMusicHomeSource _homeSource =
      YouTubeMusicHomeSource(_innerTubeService);
  late final FallbackHomeSource _homeFallbackSource =
      FallbackHomeSource(_innerTubeService);
  final HomeComposer _homeComposer = const HomeComposer();
  late final HomeRepository _homeRepository = HomeRepository(
    primary: _homeSource,
    fallback: _homeFallbackSource,
  );

  // ── Recommendation engines (spec: Quick Picks / Trending / New Releases) ─
  late final SearchFollowupGraph _searchGraph = SearchFollowupGraph(
    store: SearchFollowupStore(),
  );
  late final QuickPicksEngine _quickPicksEngine = QuickPicksEngine(
    signalProvider: _QuickPicksSignalAdapter(_recommendationService),
  );

  /// Search query pending follow-up attribution (set by searchTracks,
  /// consumed by the next playTrack). Records: "searched X, then played Y"
  /// (spec #7).
  String? _pendingSearchQuery;
  static const _searchFollowupWindow = Duration(minutes: 10);
  DateTime? _searchQueryAt;

  /// Recent search queries for ranking features (spec #61), capped.
  final List<String> _recentSearchQueries = <String>[];
  static const _maxSearchQueries = 20;

  void _rememberSearchQuery(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return;
    _recentSearchQueries.remove(query);
    _recentSearchQueries.add(query); // newest last
    while (_recentSearchQueries.length > _maxSearchQueries) {
      _recentSearchQueries.removeAt(0);
    }
  }

  /// Public entry to record explicit search queries into the taste profile
  void rememberSearchQuery(String raw) => _rememberSearchQuery(raw);

  HomeFeed? _homeFeed;
  HomeFeed? get homeFeed => _homeFeed;

  /// Quick Picks section (spec #2A) — generated from local signals +
  /// chart + native feed; deterministic, no randomization.
  List<Track> get quickPicks => _quickPicks;
  List<Track> _quickPicks = [];

  /// Ranked candidates with their explainable reasons (spec: explanation
  /// UI). Index-aligned with nothing — match via [QuickPickCandidate.track].
  List<QuickPickCandidate> get quickPickCandidates =>
      List.unmodifiable(_quickPickCandidates);
  List<QuickPickCandidate> _quickPickCandidates = [];

  /// Cache-first: instant snapshot when available, background refresh when
  /// stale. Concurrent callers coalesce in the repository.
  Future<void> loadHomeFeed() async {
    // Warm the InnerTube session while the feed loads. Playback needs
    // visitorData and a signature timestamp, and both cost seconds on a cold
    // start; doing it here keeps that cost off the listener's first tap, which
    // is what made the first tap look broken and a second press look instant.
    unawaited(_innerTubeService.warmUp());
    await _searchGraph.loadFromStore();
    final feed = await _homeRepository.load();
    _publishHomeFeed(feed);
  }

  Future<void> refreshHomeFeed() async {
    final previous = _homeFeed;
    // Controlled rotation (spec #37/#38): explicit refresh advances the
    // generation so exposure penalties open slots for unseen candidates.
    _quickPicksGeneration++;
    final feed = await _homeRepository.refresh();
    if (kDebugMode)
      HomeDiagnostics.logRefreshDiff(previous: previous, next: feed);
    _publishHomeFeed(feed);
  }

  /// Dev action: clear Home cache only, reinit context, refetch, log.
  Future<void> debugRefreshHomeSource() async {
    if (!kDebugMode) return;
    await _homeRepository.clearHomeCache();
    debugPrint('HomeDiagnostics: cache cleared, requesting fresh feed');
    await refreshHomeFeed();
  }

  /// Exposure memory + refresh generation for controlled Quick Picks
  /// rotation (spec #35-38).
  final ExposureLedger _quickPicksExposure = ExposureLedger();
  int _quickPicksGeneration = 0;

  /// Debug/diagnostics version (spec #67): grows with profile evidence.
  int get tasteProfileVersion => _buildTasteProfile().profileVersion;

  /// Current refresh generation (spec #37) — UI can derive honest
  /// deterministic variation (e.g. hero shelf rotation) from it.
  int get quickPicksGeneration => _quickPicksGeneration;

  void _publishHomeFeed(HomeFeed? raw) {
    // Composer: validation gate + cross-section dedupe + artist diversity.
    final feed = _homeComposer.compose(
      primary: raw,
      fallback: null,
    );
    if (feed == null || identical(feed, _homeFeed)) return;
    _homeFeed = feed;
    _generateQuickPicks(feed);
    _bumpHomeContent();
    notifyListeners();
  }

  /// Curated pool of verified Top Global & English Hits and Popular Hindi Hits
  /// used to seed Quick Picks when not logged in (spec: Guest Quality Floor).
  static final List<Track> _kGuestCuratedHitTracks = [
    // ── Top Global & English Hits ──
    Track(
      id: '4NRXx6U8ABQ',
      trackName: 'Blinding Lights',
      artistName: 'The Weeknd',
      albumName: 'After Hours',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
      source: 'youtube',
      genre: 'Pop',
    ),
    Track(
      id: 'H5v3kku4y6Q',
      trackName: 'As It Was',
      artistName: 'Harry Styles',
      albumName: "Harry's House",
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/H5v3kku4y6Q/hqdefault.jpg',
      source: 'youtube',
      genre: 'Pop',
    ),
    Track(
      id: 'TUVcZfQe-Kw',
      trackName: 'Levitating',
      artistName: 'Dua Lipa',
      albumName: 'Future Nostalgia',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/TUVcZfQe-Kw/hqdefault.jpg',
      source: 'youtube',
      genre: 'Pop',
    ),
    Track(
      id: 'ApXoWvfEYVU',
      trackName: 'Sunflower',
      artistName: 'Post Malone, Swae Lee',
      albumName: 'Spider-Man: Into the Spider-Verse',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/ApXoWvfEYVU/hqdefault.jpg',
      source: 'youtube',
      genre: 'Hip-Hop',
    ),
    Track(
      id: 'V1Pl8CzNzCw',
      trackName: 'Birds of a Feather',
      artistName: 'Billie Eilish',
      albumName: 'HIT ME HARD AND SOFT',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/V1Pl8CzNzCw/hqdefault.jpg',
      source: 'youtube',
      genre: 'Pop',
    ),
    Track(
      id: 'kPhpHvnnn0E',
      trackName: 'Die With A Smile',
      artistName: 'Lady Gaga, Bruno Mars',
      albumName: 'Die With A Smile',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/kPhpHvnnn0E/hqdefault.jpg',
      source: 'youtube',
      genre: 'Pop',
    ),
    Track(
      id: 'ic8j13piAhQ',
      trackName: 'Cruel Summer',
      artistName: 'Taylor Swift',
      albumName: 'Lover',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/ic8j13piAhQ/hqdefault.jpg',
      source: 'youtube',
      genre: 'Pop',
    ),
    Track(
      id: '2S24h8LJvpc',
      trackName: 'Borderline',
      artistName: 'Tame Impala',
      albumName: 'The Slow Rush',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/2S24h8LJvpc/hqdefault.jpg',
      source: 'youtube',
      genre: 'Alternative',
    ),
    Track(
      id: 'dvgZkm1xWPE',
      trackName: 'Viva La Vida',
      artistName: 'Coldplay',
      albumName: 'Viva la Vida',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/dvgZkm1xWPE/hqdefault.jpg',
      source: 'youtube',
      genre: 'Alternative',
    ),
    // ── Top Popular Hindi Hits ──
    Track(
      id: 'BddP6PYotfs',
      trackName: 'Kesariya',
      artistName: 'Arijit Singh, Pritam, Amitabh Bhattacharya',
      albumName: 'Brahmastra',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/BddP6PYotfs/hqdefault.jpg',
      source: 'youtube',
      genre: 'Hindi Pop',
    ),
    Track(
      id: 'gljiO88hYrg',
      trackName: 'Pehle Bhi Main',
      artistName: 'Vishal Mishra, Raj Shekhar',
      albumName: 'ANIMAL',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/gljiO88hYrg/hqdefault.jpg',
      source: 'youtube',
      genre: 'Hindi Pop',
    ),
    Track(
      id: 'ElZfdU54Cp8',
      trackName: 'Apna Bana Le',
      artistName: 'Arijit Singh, Sachin-Jigar',
      albumName: 'Bhediya',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/ElZfdU54Cp8/hqdefault.jpg',
      source: 'youtube',
      genre: 'Hindi Pop',
    ),
    Track(
      id: '284Ov7ysmfA',
      trackName: 'Channa Mereya',
      artistName: 'Arijit Singh, Pritam',
      albumName: 'Ae Dil Hai Mushkil',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/284Ov7ysmfA/hqdefault.jpg',
      source: 'youtube',
      genre: 'Hindi Pop',
    ),
    Track(
      id: 'hhuHYI0_q20',
      trackName: 'Ranjha',
      artistName: 'Jasleen Royal, B Praak',
      albumName: 'Shershaah',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/hhuHYI0_q20/hqdefault.jpg',
      source: 'youtube',
      genre: 'Hindi Romantic',
    ),
    Track(
      id: 'VuG7FT9dUJ4',
      trackName: 'Maan Meri Jaan',
      artistName: 'King',
      albumName: 'Champagne Talk',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/VuG7FT9dUJ4/hqdefault.jpg',
      source: 'youtube',
      genre: 'Hindi Pop',
    ),
    Track(
      id: 'gvyUuxdRdR4',
      trackName: 'Husn',
      artistName: 'Anuv Jain',
      albumName: 'Husn',
      previewUrl: '',
      albumArt: 'https://i.ytimg.com/vi/gvyUuxdRdR4/hqdefault.jpg',
      source: 'youtube',
      genre: 'Indie Pop',
    ),
  ];

  /// Generate Quick Picks from the composed feed + local signals +
  /// chart data (Recommendation Engine 2.0). Deterministic; no randomization.
  void _generateQuickPicks(HomeFeed feed) {
    final nativeTracks = feed.sections
        .expand((s) => s.items)
        .where((i) => i.videoId != null)
        .map((i) => Track(
              id: i.videoId!,
              trackName: i.title,
              artistName:
                  i.artists.isNotEmpty ? i.artists.join(', ') : i.subtitle,
              albumName: '',
              previewUrl: '',
              albumArt: i.artworkUrl,
              source: 'youtube',
            ))
        .toList();

    // When not logged in or during cold-start, seed Quick Picks with verified
    // top Global & English hits and Popular Hindi hits instead of random regional items.
    final isGuest = !isLoggedIn ||
        (_likedSongs.isEmpty &&
            _recentlyPlayed.isEmpty &&
            _recentSearchQueries.isEmpty);

    // Chart tracks carry their chart position — the only legitimate
    // numeric popularity signal we receive (popularity prior, spec #19).
    final baseChart = _chartRankedTracks();
    final List<Track> chartWithRank;
    if (isGuest) {
      final seenChartIds = <String>{};
      chartWithRank = [
        ..._kGuestCuratedHitTracks,
        ...baseChart,
      ].where((t) => seenChartIds.add(t.id)).toList();
    } else {
      chartWithRank = baseChart;
    }

    final picks = _quickPicksEngine.generate(
      nativeTracks: nativeTracks,
      chartTracks: chartWithRank,
      favorites: _likedSongs,
      recentlyPlayed: _recentlyPlayed,
      newReleases: _newReleases,
      profile: _buildTasteProfile(),
      searchQueries: List.unmodifiable(_recentSearchQueries),
      generation: _quickPicksGeneration,
      exposure: _quickPicksExposure,
      limit: 8,
    );
    if (picks.isEmpty) return;
    _quickPickCandidates = picks;
    _quickPicks = picks.map((c) => c.track).toList();
    // Record what was actually shown so the next generation rotates
    // (spec #35/#38). Without this the ledger stays empty and picks
    // repeat forever.
    _quickPicksExposure.recordGeneration(
        _quickPicksGeneration, picks.map((c) => c.trackId));
    if (kDebugMode) {
      debugPrint('QUICK_PICKS: ${_quickPicks.length} picks generated, '
          'first="${_quickPicks.first.trackName}"');
    }
  }

  /// Chart list with position metadata for popularity normalization.
  /// Falls back to the trending cache; never fabricates ranks.
  List<Track> _chartRankedTracks() => _fullTrendingTracks;

  /// Explicit rich taste profile (spec #9) built from local signals,
  /// favorites and search intent. Deterministic.
  TasteProfile _buildTasteProfile() {
    final favoriteArtists = <String>{
      for (final track in _likedSongs)
        if (track.artistName.trim().isNotEmpty) track.artistName.trim(),
    }.toList();
    return TasteProfile.build(
      events: _recommendationService.eventViews(),
      favoriteArtists: favoriteArtists,
      searchQueries: _recentSearchQueries,
    );
  }

  Future<void> fetchNewReleases({bool forceRefresh = false}) async {
    if (!forceRefresh && _newReleases.isNotEmpty) return;
    if (_isOfflineMode || !_networkService.isConnected) return;
    try {
      final releases = await _innerTubeService.getNewReleases(limit: 24);
      // Rank by affinity + freshness (spec #42): a new release from a
      // favorite artist is highly visible; validation drops staleness.
      final ranked = NewReleasesEngineV2().generate(
        releases: [
          for (final track in releases)
            RichCandidate.fromTrack(
              trackId: track.id,
              title: track.trackName,
              artistName: track.artistName,
              source: 'new_release', // trusted new-releases shelf
              genre: track.genre,
              albumName: track.albumName,
              durationMs: track.durationMs,
            ),
        ],
        profile: _buildTasteProfile(),
        limit: 12,
      );
      _newReleases = ranked.map((c) => c.track).toList();
      _bumpHomeContent();
      // New arrival → recompute picks with fresh candidate pool (spec
      // #36: variation from changing pools, not randomization).
      if (_homeFeed != null) _generateQuickPicks(_homeFeed!);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: New releases failed: $e');
    }
  }

  /// Moods & Genres category tracks (real InnerTube params, cached).
  /// Tracks carry the mood title as a genre tag — the only genre evidence
  /// YTM gives us without login; feeds genre affinity (spec: genre wiring).
  Future<List<Track>> fetchMoodTracks(String params, {String? genre}) async {
    if (_isOfflineMode || !_networkService.isConnected) return [];
    try {
      final tracks = await _innerTubeService.getMoodTracks(params, limit: 30);
      if (genre == null || genre.isEmpty) return tracks;
      return tracks
          .map((t) => t.genre == null ? t.copyWith(genre: genre) : t)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: mood tracks failed: $e');
      return [];
    }
  }

  List<Track> _localTracks = [];
  SortCriteria _localTracksSortCriteria = SortCriteria.nameAsc;

  bool _isOfflineContext = false; // Explicit flag for offline playback context
  final bool _isMiniPlayerVisible =
      true; // Control mini player visibility (e.g. hide when bottom sheet is open)

  bool get isMiniPlayerVisible => _isMiniPlayerVisible;

  // Search State
  List<Track> _playlistSearchResults = [];
  List<Track> get playlistSearchResults =>
      List.unmodifiable(_playlistSearchResults);

  /// Explicit search lifecycle shared by all three result kinds
  /// (tracks/artists/playlists). One search session at a time — the UI
  /// renders exactly one of idle/loading/results/empty/error, no
  /// contradictory boolean combinations.
  SearchPhase _searchPhase = SearchPhase.idle;
  SearchPhase get searchPhase => _searchPhase;
  String _activeSearchQuery = '';
  String get activeSearchQuery => _activeSearchQuery;

  /// Kind of the current session (see [SearchKind]). Reset to songs on clear.
  SearchKind _activeSearchKind = SearchKind.songs;
  SearchKind get activeSearchKind => _activeSearchKind;

  /// Typeahead suggestions for the active query (BitChord suggest parity).
  /// Empty until fetched; failures stay empty and the UI echoes typed text.
  List<String> _searchSuggestions = const [];
  List<String> get searchSuggestions => _searchSuggestions;

  /// Video/album result lists for the Videos/Albums filter chips.
  List<Track> _videoSearchResults = [];
  List<Track> get videoSearchResults =>
      List.unmodifiable(_videoSearchResults);
  List<Track> _albumSearchResults = [];
  List<Track> get albumSearchResults =>
      List.unmodifiable(_albumSearchResults);

  /// Bumped per search session; completions from superseded sessions are
  /// discarded so an older response can never overwrite a newer query.
  int _searchGeneration = 0;

  void _beginSearchSession(String query, {SearchKind kind = SearchKind.songs}) {
    _searchGeneration++;
    _searchPhase = SearchPhase.loading;
    _activeSearchQuery = query;
    _activeSearchKind = kind;
    if (kind != SearchKind.songs) _searchSuggestions = const [];
    notifyListeners();
  }

  bool _isCurrentSearchSession(int gen) => gen == _searchGeneration;

  void _finishSearchSession(
    int gen, {
    required bool hasResults,
    String? error,
  }) {
    if (!_isCurrentSearchSession(gen)) return;
    _searchPhase = error != null
        ? SearchPhase.error
        : (hasResults ? SearchPhase.results : SearchPhase.empty);
    notifyListeners();
  }

  void _resetSearchSession() {
    _searchGeneration++;
    _searchPhase = SearchPhase.idle;
    _activeSearchQuery = '';
    _activeSearchKind = SearchKind.songs;
    _searchSuggestions = const [];
  }

  // Getters

  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isOfflineTrack = false;
  bool _hasPlayedCurrentTrack = false;
  bool _shuffleEnabled = false;

  /// Infinite autoplay: when a context ends or queue is empty, keep playing related tracks.
  bool _autoplayEnabled = true;
  bool get autoplayEnabled => _autoplayEnabled;
  bool get isAutoQueueEnabled => _autoplayEnabled;

  Future<void> setAutoQueueEnabled(bool enabled) => setAutoplayEnabled(enabled);

  Future<void> setAutoplayEnabled(bool enabled) async {
    if (_autoplayEnabled == enabled) return;
    _autoplayEnabled = enabled;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('autoQueueEnabled', enabled);
    await p.setBool('autoplayEnabled', enabled);
    if (enabled && _queue.isEmpty && _currentTrack != null) {
      unawaited(_autoFillQueue(_currentTrack!, generation: _playbackGeneration));
    }
  }

  RepeatMode _repeatMode = RepeatMode.off;
  String? _currentPlaylistId;
  List<Track>? _currentPlayingTracks;
  List<Track> _shuffledPlaylist = [];
  int _currentIndex = -1;
  final List<Track> _queue = []; // Added queue

  /// The radio tier: tracks the station supplied, kept apart from [_queue].
  ///
  /// These used to be pushed into [_queue] alongside the listener's own picks,
  /// which made them indistinguishable from an explicit "play next". Because
  /// the queue outranks the album, a radio pick would then be played *instead
  /// of* the next track on the album - the listener heard a skip they never
  /// asked for. A separate tier is what makes the order honest: user queue,
  /// then the collection, and only then the station.
  final List<Track> _autoplayQueue = [];
  final List<Track> _playbackHistory = []; // Session history stack for skipToPrevious
  static const int _maxPlaybackHistory = 50;
  List<Track> get playbackHistory => List.unmodifiable(_playbackHistory);
  int _wifiBitrate = NetworkConfig.goodNetworkBitrate;
  int _cellularBitrate = NetworkConfig.moderateNetworkBitrate;
  bool _isOfflineMode = false;

  // Navigation State
  bool _isPlayerExpanded = false;
  bool get isPlayerExpanded => _isPlayerExpanded;

  void setPlayerExpanded(bool expanded) {
    if (_isPlayerExpanded != expanded) {
      _isPlayerExpanded = expanded;
      notifyListeners();
    }
  }

  // Mini player visibility (for bottom sheets)
  bool _hideMiniPlayer = false;
  bool get hideMiniPlayer => _hideMiniPlayer;

  void setHideMiniPlayer(bool hide) {
    if (_hideMiniPlayer != hide) {
      _hideMiniPlayer = hide;
      notifyListeners();
    }
  }

  // Tab switch requested from a pushed route (Explore tab bar).
  // Consumed post-frame by MainScreen; null when idle.
  int? _requestedTab;
  int? get requestedTab => _requestedTab;

  void requestTab(int index) {
    if (_requestedTab == index) return;
    _requestedTab = index;
    notifyListeners();
  }

  void clearRequestedTab() {
    if (_requestedTab == null) return;
    _requestedTab = null;
    notifyListeners();
  }

  bool _userManuallySetOffline = false;
  bool _isLowDataMode = false;
  bool _isAutoBitrate = true; // Default to Auto
  bool _isReconnecting = false;
  String? _errorMessage;
  bool _isLoadingLocal = false;
  Artist? _currentArtistDetails; // Added state for artist screen
  Album? _currentAlbumDetails; // Added state for album screen
  bool _isLoadingArtist = false; // Loading state for artist screen
  bool _isLoadingAlbum = false; // Loading state for album screen

  final Map<String, List<Track>> _cachedTracks = {};

  // FIX: Audio subscription management for proper cleanup
  final List<StreamSubscription> _audioSubscriptions = [];
  Timer? _notifyDebouncer;
  bool _notifyPending = false;
  bool _isStopping = false; // Flag to prevent redundant stopTrack calls

  // Error Tracking for auto-failover
  int _consecutiveErrors = 0;
  final List<String> _failedTrackIds = [];

  // Discovery Caching (TTL based)
  final Map<String, DateTime> _discoveryCacheTimes = {};
  static const Duration _discoveryCacheTTL = Duration(minutes: 30);

  // Search Caching (Speed up back/forth)
  final Map<String, List<Track>> _searchCache = {};

  // Services
  final AudioService _audioService = AudioService();
  final SpotifyService _spotifyService = SpotifyService();
  final LocalMusicService _localMusicService = LocalMusicService();
  final NetworkService _networkService = NetworkService();
  final InnerTubeService _innerTubeService = InnerTubeService.instance;
  final StreamResolutionService _streamResolution =
      StreamResolutionService.instance;
  final CastService _castService = CastService(); // Cast Service Instance

  /// Download engine (state owner). MusicProvider stays the façade.
  late final DownloadManager _downloads = DownloadManager(
    resolveStreamForTrack: _resolveForDownload,
    onMessage: (m) {
      _errorMessage = m;
      notifyListeners();
    },
    onTransientFailure: (description, retry) =>
        _addToRetryQueue(_RetryOperation(description, retry)),
    isOffline: () => _isOfflineMode,
    isConnected: () => _networkService.isConnected,
    stopActiveTrack: (trackId) async {
      if (_isPlaying && _isOfflineTrack && _currentTrack?.id == trackId) {
        await stopTrack();
      }
    },
    removeLocalTrackByPath: (path) {
      final before = _localTracks.length;
      _localTracks.removeWhere((t) => t.previewUrl == path);
      if (_localTracks.length != before) {
        _localTracks = LocalMusicService.sortTracks(
            _localTracks, _localTracksSortCriteria);
        notifyListeners();
      }
    },
  );
  DownloadManager get downloads => _downloads;

  Future<ResolvedDownload?> _resolveForDownload(Track track) async {
    String sId = track.id;
    if (track.source == 'spotify') {
      final yt = await _spotifyService.findYouTubeTrack(track);
      if (yt != null) {
        sId = yt.id;
      } else {
        throw Exception("No playable version.");
      }
    }
    final dlResolved = await _streamResolution.resolve(ResolveRequest(
      videoId: sId,
      title: track.trackName,
      artist: track.artistName,
      durationMs: track.durationMs,
    ));
    if (dlResolved == null) return null;
    return ResolvedDownload(
        url: dlResolved.url, userAgent: dlResolved.userAgent);
  }

  // Cast State
  bool _isCasting = false;
  bool _isSearchingDevices = false;
  List<CastDevice> _castDevices = [];

  // Palette: delegated to PaletteService
  late final PaletteService _paletteService = PaletteService(
    artSourceResolver: _resolvePaletteArtSource,
    feedAlbumAccent: _feedAlbumAccent,
    isInBackground: () => isInBackground,
    backfillArtwork: _backfillDownloadedArtwork,
  );
  PaletteService get paletteService => _paletteService;
  PaletteGenerator? get paletteGenerator => _paletteService.palette;
  Color? get currentPaletteColor =>
      _paletteService.palette?.dominantColor?.color ??
      _paletteService.palette?.vibrantColor?.color;

  Future<PaletteArtSource> _resolvePaletteArtSource(Track track) async {
    ImageProvider? imageProvider;
    bool isLocalFile = false;

    // High priority for offline/local sources
    final offlineMeta = _downloads.metadata[track.id];
    final artPath = offlineMeta?['artPath'] as String?;

    if (artPath != null && artPath.isNotEmpty && File(artPath).existsSync()) {
      // 1. Downloaded track artwork
      isLocalFile = true;
      imageProvider = FileImage(File(artPath));
      if (kDebugMode)
        debugPrint('MusicProvider: Using offline art for ${track.trackName}');
    } else if (_downloads.metadata.containsKey(track.id)) {
      // LEGACY FALLBACK: art file exists even if not in metadata
      final fallbackPath = await recoverDownloadedArtPath(track.id);
      if (fallbackPath != null && File(fallbackPath).existsSync()) {
        isLocalFile = true;
        imageProvider = FileImage(File(fallbackPath));
        // Persist for next time (entry may be removed mid-flight)
        _downloads.metadata[track.id]?['artPath'] = fallbackPath;
        await saveDownloadedTracksMetadata();
      }
    }

    if (imageProvider == null && track.source == 'local') {
      // 2. Local device track artwork (via MediaStore)
      final bytes = await _localMusicService.getTrackArtwork(track.id);
      if (bytes != null) {
        imageProvider = MemoryImage(bytes);
        isLocalFile = true;
      } else if (track.albumArtUrl.isNotEmpty &&
          File(track.albumArtUrl).existsSync()) {
        imageProvider = FileImage(File(track.albumArtUrl));
        isLocalFile = true;
      }
    }

    return PaletteArtSource(provider: imageProvider, isLocalFile: isLocalFile);
  }

  Future<void> _backfillDownloadedArtwork(Track track) async {
    final dDir = await _downloads.getDownloadsDirectory();
    final aP = '${dDir.path}/${track.id}.jpg';
    if (track.albumArtUrl.isEmpty) return;
    await _networkService.downloadFile(track.albumArtUrl, aP);
    final meta = _downloads.metadata[track.id];
    if (meta == null) return; // entry removed while downloading
    meta['artPath'] = aP;
    await saveDownloadedTracksMetadata();
    if (kDebugMode)
      debugPrint('MusicProvider: Proactively saved artwork for ${track.id}');
  }

  // Cast Getters
  bool get isCasting => _isCasting;
  bool get isSearchingDevices => _isSearchingDevices;
  List<CastDevice> get castDevices => _castDevices;
  CastService get castService => _castService;

  // Audio Service getter (for equalizer access)
  AudioService get audioService => _audioService;

  // Download Status Check (sync for UI)
  bool isTrackDownloadedSync(String trackId) =>
      _downloads.isDownloadedMetadataSync(trackId);

  // Audio State // YouTube Music InnerTube API
  final LyricsService _lyricsService =
      LyricsService(); // Multi-provider lyrics service
  final RecommendationService _recommendationService =
      RecommendationService(); // AI recommendations
  /// Public access for discovery surfaces (swipe deck taste signals).
  RecommendationService get recommendationService => _recommendationService;
  MusicSource _currentMusicSource =
      MusicSource.youtube; // Default to YouTube (InnerTube)

  // Lyrics state
  List<LyricsEntry>? _currentLyrics;
  bool _isLoadingLyrics = false;
  String? _lyricsError;
  String? _lyricsTrackId; // To verify if cached lyrics belong to current track

  // Getters
  List<LyricsEntry>? get currentLyrics =>
      (_currentTrack != null && _lyricsTrackId == _currentTrack!.id)
          ? _currentLyrics
          : null;
  bool get isLoadingLyrics => _isLoadingLyrics;
  String? get lyricsError => _lyricsError;
  bool get hasSyncedLyrics =>
      currentLyrics != null && currentLyrics!.isNotEmpty;
  String? get lyricsTrackId => _lyricsTrackId;

  // Method to fetch lyrics
  Future<void> fetchLyrics({bool forceRefresh = false}) async {
    final targetTrack = _currentTrack;
    if (targetTrack == null) return;
    final targetTrackId = targetTrack.id;
    final int generation = _playbackGeneration;

    // Return if already loaded for this track AND not forcing refresh
    if (!forceRefresh &&
        _lyricsTrackId == targetTrackId &&
        _currentLyrics != null) {
      if (kDebugMode)
        debugPrint(
            "MusicProvider: Using cached lyrics for ${targetTrack.trackName}");
      return;
    }

    _isLoadingLyrics = true;
    _lyricsError = null;
    _currentLyrics = null;
    _lyricsTrackId = null;
    notifyListeners();

    try {
      if (kDebugMode)
        debugPrint(
            "MusicProvider: Fetching lyrics for ${targetTrack.trackName} (Force: $forceRefresh)");
      final entries = await _lyricsService.getParsedLyrics(
        title: targetTrack.trackName,
        artist: targetTrack.artistName,
        durationMs: targetTrack.durationMs ?? _duration.inMilliseconds,
        videoId: targetTrack.source == 'youtube' ? targetTrack.id : null,
      );

      // Verify that neither track nor playback generation changed while fetching
      if (generation != _playbackGeneration ||
          _currentTrack == null ||
          _currentTrack!.id != targetTrackId) {
        if (kDebugMode) {
          debugPrint(
              "MusicProvider: Discarding stale lyrics for ${targetTrack.trackName} (Target: $targetTrackId, Active: ${_currentTrack?.id})");
        }
        return;
      }

      _lyricsTrackId = targetTrackId;
      _currentLyrics = entries;
      if (entries.isEmpty) {
        _lyricsError = "No lyrics found";
      }
    } catch (e) {
      if (generation == _playbackGeneration &&
          _currentTrack != null &&
          _currentTrack!.id == targetTrackId) {
        _lyricsError = "Failed to load lyrics";
        debugPrint("Lyrics Fetch Error: $e");
      }
    } finally {
      if (generation == _playbackGeneration &&
          _currentTrack != null &&
          _currentTrack!.id == targetTrackId) {
        _isLoadingLyrics = false;
        notifyListeners();
      }
    }
  }

  final List<_RetryOperation> _retryQueue = [];
  Timer? _retryTimer;
  static const int _maxRetryAttempts = 3;
  StreamSubscription? _networkQualitySubscription;
  StreamSubscription? _connectivityStatusSubscription;

  // --- Getters ---
  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Track> get trendingTracks => List.unmodifiable(_trendingTracks);
  List<Track> get fullTrendingTracks => List.unmodifiable(_fullTrendingTracks);
  List<Track> get searchedTracks =>
      List.unmodifiable(_searchedTracks); // Getter for searched tracks
  List<Track> get recentlyPlayed => List.unmodifiable(_recentlyPlayed);
  List<Track> get likedSongs => List.unmodifiable(_likedSongs);
  List<Track> get artistTracks => List.unmodifiable(_artistTracks);
  List<Track> get genreTracks => List.unmodifiable(_genreTracks);
  List<Track> get recommendedTracks =>
      List.unmodifiable(_recommendedTracks); // Getter
  List<Playlist> get userPlaylists => List.unmodifiable(_userPlaylists);
  List<Track> get localTracks => List.unmodifiable(_localTracks);
  SortCriteria get localTracksSortCriteria => _localTracksSortCriteria;
  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get errorMessage => _errorMessage;
  bool get isLoadingLocal => _isLoadingLocal;
  Artist? get currentArtistDetails => _currentArtistDetails; // Added getter
  Album? get currentAlbumDetails => _currentAlbumDetails; // Added getter
  bool get isLoadingArtist => _isLoadingArtist; // Added getter
  bool get isLoadingAlbum => _isLoadingAlbum; // Added getter
  int get wifiBitrate => _wifiBitrate;
  int get cellularBitrate => _cellularBitrate;
  bool get isOfflineMode => _isOfflineMode;
  bool get isLowDataMode => _isLowDataMode;
  bool get isAutoBitrate => _isAutoBitrate;
  bool get shuffleEnabled => _shuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  String? get currentPlaylistId => _currentPlaylistId;
  MusicSource get currentMusicSource =>
      _currentMusicSource; // Music source getter
  NetworkQuality get networkQuality => _networkService.networkQuality;
  Map<String, double> get downloadProgress => _downloads.downloadProgress;
  Map<String, bool> get isDownloading => _downloads.isDownloading;
  List<Track> get currentlyDownloadingTracks =>
      _downloads.currentlyDownloadingTracks;
  List<Track> get downloadQueue => _downloads.downloadQueue;
  List<Track> get queue => List.unmodifiable(_queue); // Added queue getter

  /// What plays next, in the order it will actually play.
  ///
  /// The queue sheet renders this, so the order here has to be the order the
  /// listener hears: their own picks, then the rest of the collection, then the
  /// station. Showing the station as if it were already next - which is what
  /// happened when all three lived in one list - is what made the queue look
  /// empty and the playback look like it was skipping.
  ///
  /// Memoised on purpose. This used to build a fresh `List` on every access, so
  /// every rebuild of every listener handed the framework a different list
  /// instance for identical contents. When NowPlaying was pushed while the
  /// mini-player pill was still in the tree, the framework tried to reparent
  /// elements between a list that had already been torn down and tripped
  /// `_elements.contains(element): is not true` on the way in.
  List<Track> get upNext {
    final key = '${_queue.length}:${_autoplayQueue.length}:'
        '${_queue.map((t) => t.id).join()}'
        '|${_autoplayQueue.map((t) => t.id).join()}';
    if (key == _upNextKey && _upNextCache != null) return _upNextCache!;

    final out = <Track>[];
    final seen = <String>{};
    for (final t in [..._queue, ..._autoplayQueue]) {
      if (seen.add(t.id)) out.add(t);
    }
    _upNextKey = key;
    _upNextCache = List.unmodifiable(out);
    return _upNextCache!;
  }

  String? _upNextKey;
  List<Track>? _upNextCache;

  /// Where the current queue comes from, for the sheet's provenance line
  /// ("Playing from X"). Falls back to generic but truthful labels: tracks
  /// carry no playlist title, so an unnamed curated context is just Playlist.
  String get queueSourceLabel {
    final id = _currentPlaylistId;
    if (_isAutoQueueContext || id == 'auto_queue') return 'Autoplay';
    if (id == 'jump_back_in') return 'Jump Back In';
    if (id == 'recently_played') return 'Recently Played';
    if (_isRealCuratedPlaylist) return 'Playlist';
    return 'My Music';
  }

  /// The station's tracks, so the sheet can label where they came from.
  bool isAutoplayQueued(String trackId) => _autoplayTrackIds.contains(trackId);

  /// The radio station in running order, for the sheet's Autoplay section.
  List<Track> get autoplayQueue => List.unmodifiable(_autoplayQueue);

  /// The collection tracks still ahead of the current one, for the sheet's
  /// "Playing Next" section. Empty when there is no ordered context, which is
  /// itself the honest answer - not every tap has a collection behind it.
  List<Track> get upcomingCollection {
    final list = _getActivePlaylist();
    if (!_isRealCuratedPlaylist || list.isEmpty) return const [];
    final i = _currentTrack == null
        ? -1
        : list.indexWhere((t) => t.id == _currentTrack!.id);
    if (i < 0 || (i + 1) >= list.length) return const [];
    return List.unmodifiable(list.sublist(i + 1));
  }
  bool get isLoggedIn => AuthService().isLoggedIn;
  int get currentIndex => _currentIndex;
  @override
  List<Track>? get currentPlayingTracks => _currentPlayingTracks;

  /// Immutable playback projection for shell/player/queue/lyrics surfaces.
  /// Shares the same AudioService instance as playback itself.
  late final PlaybackController playback = PlaybackController(_audioService);
  late final PlaybackController _playback = playback;
  late final LofiController _lofi = LofiController(
    onChanged: (enabled) {
      unawaited(_audioService.setSpeed(
          enabled ? LofiController.speed : LofiController.normalSpeed));
      unawaited(_audioService.setPitch(
          enabled ? LofiController.pitch : LofiController.normalPitch));
      final prefsSet = SharedPreferences.getInstance()
          .then((p) => p.setBool('lofiEnabled', enabled));
      unawaited(prefsSet);
      notifyListeners();
    },
  );
  LofiController get lofi => _lofi;
  bool get isLofiEnabled => _lofi.enabled;
  Stream<Duration> get positionStream => _audioService.onPositionChanged;

  // --- Initialization & Setup ---
  DateTime? _lastPositionNotify;
  MusicProvider({AccentController? accentController})
      : _accentController = accentController {
    _paletteService.clearAlbumAccentOnEmptyArt = () {
      _accentController?.setAlbumAccent(null);
    };
    _paletteService.isCurrentTrackImpl = (id) => _currentTrack?.id == id;
    _paletteService.addListener(_paletteNotified);
    _downloads.addListener(notifyListeners);
    // Attach auth-flip session reset (owned handle; detached in dispose).
    _authSessionReset;
    _initialize();
  }

  /// Session reset handle for YouTube login/logout flips (owned).
  late final AuthSessionReset _authSessionReset = AuthSessionReset(
    onIdentityFlipped: _refreshFeedForNewIdentity,
  );

  /// Pull the feed for the new identity when online and a feed already
  /// exists; otherwise the next load picks it up.
  Future<void> _refreshFeedForNewIdentity() async {
    if (_homeFeed != null && _networkService.isConnected && !_isOfflineMode) {
      await refreshHomeFeed();
    }
  }

  Future<void> _initialize() async {
    if (kDebugMode) debugPrint('MusicProvider: Initializing...');

    await _loadSettings();
    await _loadLikedSongs();
    await _loadRecentlyPlayed();
    await loadUserPlaylists();
    await _downloads.loadMetadata();
    await _loadRecentlyShownIds(); // For You diversity persistence

    // Initialize lyrics service (disk cache)
    await _lyricsService.initialize();

    // Initialize recommendation engine
    await _recommendationService.initialize();

    _setupAudioListeners();
    _startRetryTimer();
    _setupConnectivityMonitoring();

    // BATTERY FIX: Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    final isConnected = _networkService.isConnected;
    if (isConnected && !_isOfflineMode) {
      // Each source is independent. `Future.wait` defaults to failing fast, so
      // one failure used to discard the other two successes and report a
      // blanket "Could not load initial content". `eagerError: false` waits for
      // all of them, and the per-call catch keeps one dead endpoint from
      // masquerading as a total failure.
      final loads = <Future<void>>[
        fetchTracks(),
        fetchTrendingTracks(),
        fetchNewReleases(),
      ];
      await Future.wait(
        loads.map((f) => f.catchError((Object e) {
          if (kDebugMode) debugPrint('MusicProvider: initial load failed: $e');
        })),
      );
      unawaited(loadHomeFeed());
    } else {
      _errorMessage = _isOfflineMode
          ? (_userManuallySetOffline
              ? 'Currently in offline mode.'
              : 'No internet connection.')
          : 'No internet connection.';
    }

    unawaited(loadLocalMusicFiles());
    if (kDebugMode) debugPrint('MusicProvider: Initialization complete.');
  }

  // FIX: Debounced notification to avoid excessive UI rebuilds
  void _debouncedNotify() {
    if (_notifyPending) return;
    _notifyPending = true;
    _notifyDebouncer?.cancel();
    _notifyDebouncer = Timer(const Duration(milliseconds: 50), () {
      _notifyPending = false;
      notifyListeners();
    });
  }

  // BATTERY FIX: Handle app lifecycle to pause background work
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;

    if (kDebugMode)
      debugPrint('MusicProvider: App lifecycle changed to $state');

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // App going to background - reduce work.
        // Audio continues via foreground service (just_audio_background).
        //
        // Note: Flutter already stops producing frames when the app is not
        // resumed, so all AnimationControllers are muted for free. Timers are
        // NOT muted, so the retry poller has to be stopped explicitly or it
        // keeps waking the device (and hitting the network) in the pocket.
        _retryTimer?.cancel();
        // Note: Palette generation is now skipped in updatePalette() via isInBackground check
        break;
      case AppLifecycleState.resumed:
        // App returning to foreground - resume normal operation
        _startRetryTimer();
        // Force refresh palette if track changed while in background
        if (_currentTrack != null && paletteGenerator == null) {
          updatePalette();
        }
        break;
      case AppLifecycleState.detached:
        _retryTimer?.cancel();
        break;
    }
  }

  void _setupAudioListeners() {
    if (kDebugMode) debugPrint('MusicProvider: Setting up audio listeners...');

    // FIX: Store all subscriptions for proper cleanup
    // Position stream
    _audioSubscriptions.add(_audioService.onPositionChanged.listen((pos) {
      // FIX: Skip position updates when not playing to save battery
      if (!_isPlaying) return;

      if (_position != pos) {
        _position = pos;
        if (pos > const Duration(seconds: 2)) {
          _hasPlayedCurrentTrack = true;
        }
      }
    }, onError: (e) {
      if (kDebugMode) debugPrint("MusicProvider: Position stream error: $e");
    }));

    // Duration stream
    _audioSubscriptions.add(_audioService.onDurationChanged.listen((dur) {
      if ((_duration - dur).abs() > const Duration(milliseconds: 500) &&
          dur > Duration.zero) {
        if (kDebugMode) debugPrint('MusicProvider: Duration updated: $dur');
        _duration = dur;
        _debouncedNotify();
      }
    }, onError: (e) {
      if (kDebugMode) debugPrint("MusicProvider: Duration stream error: $e");
    }));

    // Playback state stream - THIS IS CRITICAL
    _audioSubscriptions
        .add(_audioService.onPlaybackStateChanged.listen((playing) {
      if (kDebugMode) {
        debugPrint(
            'MusicProvider: Playback state changed: $playing (was: $_isPlaying)');
        if (_currentTrack != null) {
          debugPrint(
              'MusicProvider: Current track: ${_currentTrack!.trackName}');
        }
      }

      if (_isPlaying != playing) {
        _isPlaying = playing;
        if (playing) {
          _hasPlayedCurrentTrack = true;
        }

        if (!playing && _currentTrack != null) {
          if (kDebugMode)
            debugPrint('MusicProvider: ⚠️ Playback stopped unexpectedly!');
        }

        notifyListeners(); // Immediate notify for play/pause
      }
    }, onError: (e) {
      if (kDebugMode)
        debugPrint("MusicProvider: Playback state stream error: $e");
    }));

    // FIX: Restore track completion handling via playerStateStream
    // This listener handles both debugging AND track completion detection
    _audioSubscriptions.add(_audioService.playerStateStream.listen((state) {
      if (kDebugMode) {
        debugPrint(
            'MusicProvider: Player state: ${state.playing ? "PLAYING" : "PAUSED"}, '
            'Processing: ${state.processingState}');
      }

// Guards against treating a seek-to-zero or a sub-2s blip as a finished
      // track. ExoPlayer resets position when it wraps, so relying on position
      // alone left completion both missable and spuriously triggerable.
      final hasPlayedMeaningfully = _hasPlayedCurrentTrack ||
          (_duration > const Duration(seconds: 2) &&
              _position > const Duration(seconds: 1)) ||
          (_duration > Duration.zero &&
              _position >= _duration - const Duration(seconds: 3));

      // The player advances through its window on its own, so `completed` here is
      // NOT yet "the sequence ended". ExoPlayer reports the finishing item as
      // completed a moment before it steps to the next one, and advancing from
      // both places raced: this handler seeked while the window was already
      // moving, overshot the end of the sequence, and the UI fell back to the
      // stale current track - which looked like the next song playing for a
      // second and then snapping back to the finished one.
      //
      // So give the window a moment to move first, and only advance if it did
      // not. The old comment here referenced `_consumeDuplicateAutoAdvance`,
      // which no longer exists - that removal is what left this unguarded.
      if (state.processingState == ProcessingState.completed &&
          _currentTrack != null &&
          !_isStopping &&
          hasPlayedMeaningfully) {
        _hasPlayedCurrentTrack = false;
        unawaited(_onSequenceRanDry());
      }
    }, onError: (e) {
      if (kDebugMode)
        debugPrint("MusicProvider: Player state stream error: $e");
    }));

    if (kDebugMode)
      debugPrint('MusicProvider: Audio listeners set up complete');

    // --- Navigation Listeners ---
    //
    // The player now advances through its window on its own, so an index change
    // is the primary "the track changed" signal — not a synthetic skip event.
    // Everything the old dummy machine used to drive (current track, lyrics,
    // palette, history, prefetch) is driven from here instead.
    _audioSubscriptions.add(_audioService.windowIndexStream.listen((id) {
      if (id == null) return;
      if (_currentTrack?.id == id) return; // our own head, already applied
      unawaited(_onPlayerAdvancedTo(id));
    }));

    _audioSubscriptions.add(_audioService.onSkipToNext.listen((_) {
      if (kDebugMode)
        debugPrint(
            "MusicProvider: External SkipNext triggered (Notification/LockScreen)");
      _handleAutoSkipToNext();
    }));

    _audioSubscriptions.add(_audioService.onSkipToPrevious.listen((_) {
      if (kDebugMode)
        debugPrint(
            "MusicProvider: External SkipPrevious triggered (Notification/LockScreen)");
      skipToPrevious();
    }));

    // Listen for Critical Playback Errors (Corrupt Files)
    _audioSubscriptions.add(_audioService.onPlaybackError.listen((error) async {
      if (error == "Source error" && _currentTrack != null) {
        if (kDebugMode)
          debugPrint(
              "MusicProvider: Source error detected for ${_currentTrack!.trackName}");
        final id = _currentTrack!.id;
        final isDownloaded = _downloads.metadata.containsKey(id);

        if (isDownloaded || _currentTrack!.source == 'local') {
          final path = _currentTrack!.source == 'local'
              ? _currentTrack!.previewUrl
              : (_downloads.metadata[id]?['filePath'] ?? '');

          if (path.isNotEmpty) {
            await _downloads.handleMissingFile(id, path);
            if (!_isOfflineMode && _networkService.isConnected) {
              playTrack(_currentTrack!);
            } else {
              await stopTrack();
            }
          }
        } else {
          _handlePlaybackError("Source error: Stream unrecognized.");
        }
      } else {
        _handlePlaybackError(error);
      }
    }));
  }

  // --- Settings Persistence ---
  Future<void> _loadSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      _wifiBitrate =
          p.getInt('wifiBitrate') ?? NetworkConfig.goodNetworkBitrate;
      _cellularBitrate =
          p.getInt('cellularBitrate') ?? NetworkConfig.moderateNetworkBitrate;
      _isOfflineMode = p.getBool('offlineMode') ?? false;
      _userManuallySetOffline = p.getBool('userManuallySetOffline') ?? false;
      _isLowDataMode = p.getBool('lowDataMode') ?? false;
      _isAutoBitrate = p.getBool('isAutoBitrate') ?? true;
      _shuffleEnabled = p.getBool('shuffleEnabled') ?? false;
      _autoplayEnabled = p.getBool('autoQueueEnabled') ??
          p.getBool('autoplayEnabled') ??
          true;
      _animatedCanvasEnabled = p.getBool('animated_canvas') ?? false;
      _canvasOverCellular = p.getBool('canvas_over_cellular') ?? false;
      _fullBleedArtwork = p.getBool('full_bleed_artwork') ?? true;
      _syncedLyricsEnabled = p.getBool('synced_lyrics') ?? true;
      _prioritizeSyllableSync = p.getBool('prioritize_syllable_sync') ?? true;
      final lofiEnabled = p.getBool('lofiEnabled') ?? false;
      if (lofiEnabled && !_lofi.enabled) {
        _lofi.setEnabled(lofiEnabled);
        await _audioService.setSpeed(LofiController.speed);
        await _audioService.setPitch(LofiController.pitch);
      }

      final sourceValue = p.getString('musicSource') ?? 'youtube';
      _currentMusicSource = MusicSource.fromString(sourceValue);

      if (kDebugMode) {
        debugPrint(
            'Settings: Loaded music source = "$sourceValue" → ${_currentMusicSource.displayName}');
      }

      try {
        _repeatMode =
            RepeatMode.values[p.getInt('repeatMode') ?? RepeatMode.off.index];
      } catch (_) {
        _repeatMode = RepeatMode.off;
      }
      // The player is the one that has to know, so push the restored modes
      // onto it rather than waiting for the user to toggle.
      unawaited(_audioService.applyRepeatMode(repeatOne: _repeatMode == RepeatMode.one));
      unawaited(_audioService.setShuffleOn(_shuffleEnabled));
      try {
        _localTracksSortCriteria = SortCriteria.values[
            p.getInt('localSortCriteria') ?? SortCriteria.nameAsc.index];
      } catch (_) {
        _localTracksSortCriteria = SortCriteria.nameAsc;
      }

      if (kDebugMode) {
        debugPrint('Settings loaded successfully.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("Error loading settings: $e");
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('wifiBitrate', _wifiBitrate);
      await p.setInt('cellularBitrate', _cellularBitrate);
      await p.setBool('offlineMode', _isOfflineMode);
      await p.setBool('userManuallySetOffline', _userManuallySetOffline);
      await p.setBool('lowDataMode', _isLowDataMode);
      await p.setBool('isAutoBitrate', _isAutoBitrate);
      await p.setBool('shuffleEnabled', _shuffleEnabled);
      await p.setString('musicSource', _currentMusicSource.value);
      await p.setInt('repeatMode', _repeatMode.index);
      await p.setInt('localSortCriteria', _localTracksSortCriteria.index);

      if (kDebugMode) {
        debugPrint(
            'Settings: Saved music source = "${_currentMusicSource.value}" (${_currentMusicSource.displayName})');
        debugPrint('Settings saved successfully.');
      }
    } catch (e) {
      _errorMessage = "Failed to save settings.";
      if (kDebugMode) {
        debugPrint('Settings: Error saving - $e');
      }
      notifyListeners();
    }
  }

  // --- Playback Control & Context ---
  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    if (_shuffleEnabled && _currentPlayingTracks != null) {
      _shufflePlaylist();
    } else {
      _updateCurrentIndex();
    }
    // Hand the ordering to the player too, so the window it holds is walked in
    // the order the UI is showing. Dart keeps _shuffledPlaylist for what the
    // queue means; the player keeps the window consistent with it.
    unawaited(_audioService.setShuffleOn(_shuffleEnabled));
    _saveSettings();
    notifyListeners();
  }

  /// Shuffle and play a list of tracks immediately
  Future<void> shuffleAndPlay(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    // Enable shuffle if not already enabled
    if (!_shuffleEnabled) {
      _shuffleEnabled = true;
      _saveSettings();
    }

    // Set context and shuffle
    _setPlaybackContext(tracks);

    // Play first track from shuffled list
    if (_shuffledPlaylist.isNotEmpty) {
      await playTrack(_shuffledPlaylist[0], playlistTracks: tracks);
    }
  }

  void cycleRepeatMode() {
    setRepeatMode(
        RepeatMode.values[(_repeatMode.index + 1) % RepeatMode.values.length]);
  }

  void setRepeatMode(RepeatMode mode) {
    if (_repeatMode == mode) return;
    _repeatMode = mode;
    // Repeat-one is delegated: the player loops the current window entry
    // seamlessly, where the old path had to re-resolve the whole track because
    // the player was parked on a silent dummy. Repeat-all stays here — the
    // window is only a few tracks, so the player would loop the window rather
    // than the playlist.
    unawaited(_audioService.applyRepeatMode(repeatOne: mode == RepeatMode.one));
    _saveSettings();
    notifyListeners();
  }

  void _shufflePlaylist() {
    if (_currentPlayingTracks == null || _currentPlayingTracks!.isEmpty) {
      _shuffledPlaylist = [];
      _currentIndex = -1;
      return;
    }
    _shuffledPlaylist = List.from(_currentPlayingTracks!)..shuffle(Random());
    _rebuildTrackIndex();
    _updateCurrentIndex(); /* Preload handled by toggleShuffle or setPlaybackContext */
  }

  List<Track> _getActivePlaylist() =>
      _shuffleEnabled ? _shuffledPlaylist : (_currentPlayingTracks ?? []);

  /// id -> position for the active playlist.
  ///
  /// Rebuilt only when the active list changes, not per lookup. This used to be
  /// a linear `indexWhere` on every track advance and every context set, which
  /// is O(playlist) on the hot path and noticeable on a large library.
  Map<String, int> _trackIndex = const {};

  void _rebuildTrackIndex() {
    final list = _getActivePlaylist();
    _trackIndex = {for (var i = 0; i < list.length; i++) list[i].id: i};
  }

  void _updateCurrentIndex() {
    final id = _currentTrack?.id;
    if (id == null) {
      _currentIndex = -1;
      return;
    }
    final i = _trackIndex[id];
    if (i == null) {
      // The active list changed under us (shuffle toggled, context replaced);
      // rebuild once rather than scanning on every call.
      _rebuildTrackIndex();
      _currentIndex = _trackIndex[id] ?? -1;
      return;
    }
    _currentIndex = i;
  }

  // --- Advance-race protection ---
  // Natural end-of-track triggers BOTH the nav-monitor (dummy item) and the
  // completed handler. This guard suppresses the second advance for the same
  // track within a short window.
  /// Bumped whenever user intent starts/retargets playback; stale async
  /// continuations (e.g. autoplay fetches) compare and abort.
  int _playbackGeneration = 0;

  /// Token for autoplay's own asynchronous attempts.
  ///
  /// Deliberately separate from [_playbackGeneration]: that counter belongs to
  /// the listener. An autoplay attempt has to be abandonable the moment the
  /// listener taps something, but it must never be able to invalidate the
  /// playback that tap started - which is exactly what sharing the counter did.
  int _autoplayGeneration = 0;

  /// v5.2 autoqueue: true while playback context came from autoplay
  /// recommendations. Clearing the queue empties the upcoming autoqueue and
  /// shrinks context to the active song.
  bool _isAutoQueueContext = false;

  /// Set when the user cleared an autoqueue context — the next
  /// end-of-playlist must stop instead of re-spawning autoplay.
  bool _suppressAutoplayOnce = false;

  /// Force-reloads the current track.
  ///
  /// RETIRED as the repeat-one path: the player now loops the current window
  /// entry natively (see setRepeatMode), so repeat-one is a gapless loop rather
  /// than a full stream re-resolve. Kept as an explicit reload for the case
  /// where the user genuinely wants the track restarted from the top.
  Future<void> _replayCurrentTrack() async {
    final t = _currentTrack;
    if (t == null) return;
    _currentTrack = null; // force playTrack full path
    await playTrack(t,
        playlistTracks: _currentPlayingTracks, playlistId: _currentPlaylistId);
  }

  void _setPlaybackContext(List<Track>? tracks,
      {String? playlistId, bool clearQueue = true}) {
    if (!listEquals(_currentPlayingTracks, tracks) ||
        _currentPlaylistId != playlistId) {
      _isAutoQueueContext = (playlistId == 'auto_queue');
      debugPrint(
          "Setting playback context. ID: $playlistId, Tracks: ${tracks?.length ?? 0}, ClearQueue: $clearQueue");
      _currentPlayingTracks = tracks != null ? List.from(tracks) : null;
      _currentPlaylistId = playlistId;
      if (clearQueue && _queue.isNotEmpty) {
        _queue.clear();
        debugPrint("Playback context changed, queue cleared.");
      }
      // A new collection is a new seed. Keeping the station that was built for
      // the old one would start the listener off in music they did not choose.
      if (clearQueue && _autoplayQueue.isNotEmpty) {
        _autoplayQueue.clear();
        _rearmAutoplay();
      }
      if (_shuffleEnabled && _currentPlayingTracks != null) {
        _shufflePlaylist();
      } else {
        _rebuildTrackIndex();
        _updateCurrentIndex();
      }
    } else {
      _rebuildTrackIndex();
      _updateCurrentIndex();
    }
  }

  /// Handles skip events arriving via the audio-service stream (media-session
  /// next-track). The dummy-item auto-advance that used to arrive here is gone:
  /// the player now holds real tracks and reports its own index changes.
  Future<void> _handleAutoSkipToNext() async {
    // Sleep timer is honored here, at the authoritative advance signal —
    // ProcessingState.completed only ever fires on padding items, so the
    // old completed-path stop check was effectively unreachable.
    if (_stopAfterCurrentTrack) {
      _stopAfterCurrentTrack = false;
      stopTrack();
      return;
    }

    _recordListenSignal();

    if (_repeatMode == RepeatMode.one && _currentTrack != null) {
      // Replay the actual track: after auto-advance the player is parked on
      // the next dummy item, so seeking/resuming there would play silence.
      await _replayCurrentTrack();

      return;
    }
    await skipToNext();
  }

  String? _lastSignalTrackId;

  /// Records the recommendation-agent listen signal for the outgoing track.
  /// Called once per track from the authoritative advance path.
  void _recordListenSignal() {
    final track = _currentTrack;
    if (track == null || track.id == _lastSignalTrackId) return;
    _lastSignalTrackId = track.id;

    final listenTimeMs = _position.inMilliseconds;
    final durationMs = _duration.inMilliseconds;

    // Calculate completion rate (0-1)
    final completionRate =
        durationMs > 0 ? (listenTimeMs / durationMs).clamp(0.0, 1.0) : 1.0;

    // Skip timing if skipped early
    final skipTimingMs = completionRate < 0.5 ? listenTimeMs : null;

    _recommendationService.recordPlay(
      track,
      completionRate: completionRate,
      listenTimeMs: listenTimeMs,
      skipTimingMs: skipTimingMs,
    );
  }

  Future<void> _onTrackComplete() async {
    if (kDebugMode)
      debugPrint(
          'MusicProvider: _onTrackComplete event for ${_currentTrack?.trackName}');

    if (_stopAfterCurrentTrack) {
      _stopAfterCurrentTrack = false;
      stopTrack();
      return;
    }

    // Repeat-one is the player's job now (a gapless native loop), so this must
    // not also re-enter the decision path — that is what used to make repeat
    // a full re-resolve rather than a seek.
    if (_repeatMode == RepeatMode.one) return;

    // If the player still has the next track loaded, let it advance. This is
    // the whole point of the window: no resolve, no setAudioSources, no gap.
    if (_audioService.hasNextInWindow) {
      if (kDebugMode) {
        debugPrint('MusicProvider: advancing inside player window');
      }
      await _audioService.seekToNextInWindow();
      return;
    }

    _updateCurrentIndex();

    final isRealCuratedPlaylist = _isRealCuratedPlaylist;

    if (_queue.isNotEmpty) {
      final isFirstAutoplay = _autoplayTrackIds.contains(_queue.first.id);
      final list = _getActivePlaylist();
      final hasUpcomingPlaylistTracks =
          isRealCuratedPlaylist && (_currentIndex + 1) < list.length;

      // Only advance playlist first if the upcoming queue item is an AUTOPLAY track
      // and we are actively inside a curated playlist/album.
      // (User-added queue tracks have priority over the remaining playlist!)
      if (!isFirstAutoplay || !hasUpcomingPlaylistTracks) {
        final next = _queue.removeAt(0);
        if (kDebugMode) {
          debugPrint("MusicProvider: Playing next from queue: ${next.trackName}");
        }
        _playTrackInternal(next, setContext: false, clearQueue: false);
        notifyListeners();
        return;
      }
    }

    // 2. Standard Playlist Path
    final list = _getActivePlaylist();
    if (!isRealCuratedPlaylist || list.isEmpty) {
      if (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        _playTrackInternal(next, setContext: false, clearQueue: false);
        notifyListeners();
        return;
      }
      if (_autoplayEnabled && !_suppressAutoplayOnce) {
        _startAutoplayFromRecommendations();
        return;
      }
      stopTrack();
      return;
    }

    int nextIdx = _currentIndex + 1;
    if (nextIdx < list.length) {
      if (kDebugMode) debugPrint('MusicProvider: Advancing to index $nextIdx');
      _playTrackInternal(list[nextIdx], setContext: false, clearQueue: false);
    } else {
      if (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        if (kDebugMode) {
          debugPrint(
              'MusicProvider: Playlist finished -> Advancing to autoplay queue: ${next.trackName}');
        }
        _playTrackInternal(next, setContext: false, clearQueue: false);
        notifyListeners();
        return;
      }
      _handleEndOfPlaylist();
    }
  }

  /// Unified logic for when a playlist reaches the end (completion or SkipNext)
  void _handleEndOfPlaylist() {
    final list = _getActivePlaylist();
    if (list.isEmpty) {
      stopTrack();
      return;
    }

    if (_repeatMode == RepeatMode.all) {
      if (kDebugMode) debugPrint('MusicProvider: Looping context to start.');
      _playTrackInternal(list[0], setContext: false, clearQueue: false);
    } else {
      // Check playback context type
      bool isListNotEmpty = list.isNotEmpty;
      bool isFirstLocal = isListNotEmpty && list.first.source == 'local';
      bool isFirstDownloaded =
          isListNotEmpty && _downloads.metadata.containsKey(list.first.id);
      bool isOfflineContext = isListNotEmpty &&
          (isFirstLocal ||
              isFirstDownloaded ||
              _isOfflineTrack ||
              _isOfflineContext);

      if (isOfflineContext) {
        // Local/downloaded playlists loop
        if (kDebugMode)
          debugPrint(
              'MusicProvider: End of Downloaded List -> Looping to start');
        _playOfflineTrackInternal(list[0],
            setContext: false, clearQueue: false);
      } else if (_autoplayEnabled && !_suppressAutoplayOnce) {
        if (_queue.isNotEmpty) {
          final next = _queue.removeAt(0);
          if (kDebugMode) {
            debugPrint(
                'MusicProvider: End of Playlist -> Continuing with autoplay queue: ${next.trackName}');
          }
          _playTrackInternal(next, setContext: false, clearQueue: false);
          notifyListeners();
          return;
        }
        // ENHANCED: Smart Autoplay across online tracks/playlists (BitChord Parity)
        if (kDebugMode) {
          debugPrint('MusicProvider: End of Playlist -> Continuing with AutoPlay');
        }
        _startAutoplayFromRecommendations();
      } else if (isListNotEmpty &&
          _currentPlayingTracks != null &&
          _currentPlayingTracks!.length > 1) {
        // Multi-track playlists loop
        if (kDebugMode) {
          debugPrint(
              'MusicProvider: End of Online Playlist -> Looping to start');
        }
        _playTrackInternal(list[0], setContext: false, clearQueue: false);
      } else {
        stopTrack();
      }
    }
  }

  /// Streamable-song gate for autoplay candidates (streamable id, not the
  /// track currently playing).
  bool _isPlayableAutoplayCandidate(Track t) {
    final id = t.id;
    if (id.isEmpty) return false;
    if (id.startsWith('PL') ||
        id.startsWith('VL') ||
        id.startsWith('UC') ||
        id.startsWith('OLAK') ||
        id.startsWith('MPREb')) {
      return false;
    }
    if (id == _currentTrack?.id) return false;
    if (id.length == 11 ||
        t.source == 'saavn' ||
        t.source == 'spotify' ||
        (t.trackName.isNotEmpty && t.artistName.isNotEmpty)) {
      return true;
    }
    return false;
  }

  /// Start autoplay with AI/Radio recommended tracks based on current track
  Future<void> _startAutoplayFromRecommendations() async {
    if (_currentTrack == null) {
      stopTrack();
      return;
    }

    // Claim an autoplay attempt WITHOUT bumping the user playback generation.
    //
    // This used to do `++_playbackGeneration` - the very counter every
    // user-initiated playTrack checks at `if (gen != _playbackGeneration) return`.
    // The player sits in `completed` while the replacement track resolves, so
    // this handler re-fires, and every re-fire bumped the counter again. Any
    // track the listener tapped in that window was therefore silently abandoned
    // mid-resolve: the app looked completely frozen after an autoplay handover.
    //
    // Autoplay now has its own token, and aborts when the *user* generation
    // moves - so it can be cancelled by a tap but can never cancel one.
    final gen = ++_autoplayGeneration;
    final userGen = _playbackGeneration;

    if (kDebugMode) {
      debugPrint(
          'MusicProvider: Starting autoplay recommendations for ${_currentTrack!.trackName}');
    }

    try {
      // Get recommendations based on current track using YouTube Music's official RDAMVM radio mix
      List<Track> recommendations;

      if (_currentTrack!.source == 'youtube' &&
          _currentTrack!.id.length == 11) {
        recommendations =
            await _innerTubeService.getRadioTracks(_currentTrack!.id, limit: 20);
      } else if (_currentTrack!.source != 'local' &&
          _currentTrack!.trackName.isNotEmpty) {
        final query =
            '${_currentTrack!.trackName} ${_currentTrack!.artistName}'.trim();
        final searchResults =
            await _innerTubeService.searchSongs(query, limit: 10);
        if (searchResults.isNotEmpty && searchResults.first.id.length == 11) {
          recommendations = await _innerTubeService
              .getRadioTracks(searchResults.first.id, limit: 20);
          if (recommendations.isEmpty) {
            recommendations = searchResults;
          }
        } else {
          recommendations = searchResults;
        }
      } else {
        recommendations = [];
      }

      if (gen != _autoplayGeneration || userGen != _playbackGeneration) {
        if (kDebugMode) {
          debugPrint('MusicProvider: Autoplay aborted (user took over).');
        }
        return;
      }

      // Filter to streamable songs
      var filtered = recommendations.where(_isPlayableAutoplayCandidate).toList();

      if (filtered.isEmpty) {
        if (kDebugMode) {
          debugPrint('MusicProvider: /next unusable, falling back to local pools');
        }
        final seen = <String>{_currentTrack!.id};
        filtered = [
          ..._quickPicks,
          ..._recommendedTracks,
          ..._trendingTracks,
        ].where((t) => _isPlayableAutoplayCandidate(t) && seen.add(t.id)).toList();
      }

      if (filtered.isEmpty) {
        if (kDebugMode) {
          debugPrint('MusicProvider: No valid recommendations after filtering.');
        }
        stopTrack();
        return;
      }

      // Apply BitChord QueueBuilder: deduplicate recordings and balance artist caps
      final existingTracks = [
        if (_currentTrack != null) _currentTrack!,
        ..._queue,
      ];
      final extended = QueueBuilder.extend(existingTracks, filtered, limit: 15);
      final ranked = extended.isNotEmpty
          ? extended
          : _recommendationService.getAutoplayRecommendations(
              _currentTrack!,
              filtered,
              limit: 15,
            );

      if (ranked.isEmpty) {
        stopTrack();
        return;
      }

      // Set new context and play first recommendation
      if (gen != _autoplayGeneration || userGen != _playbackGeneration) {
        if (kDebugMode) {
          debugPrint(
              'MusicProvider: Autoplay aborted before start (user took over).');
        }
        return;
      }
      final nextTrack = ranked.first;
      if (kDebugMode) {
        debugPrint('MusicProvider: Autoplay -> ${nextTrack.trackName}');
      }

      // Set remaining as new playlist context
      _setPlaybackContext(ranked, playlistId: 'auto_queue', clearQueue: false);
      _isAutoQueueContext = true;
      await _playTrackInternal(nextTrack, setContext: false, clearQueue: false);
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: Autoplay error: $e');
      final localPool = [
        ..._quickPicks,
        ..._recommendedTracks,
        ..._trendingTracks,
      ].where(_isPlayableAutoplayCandidate).toList();
      if (localPool.isNotEmpty &&
          gen == _autoplayGeneration &&
          userGen == _playbackGeneration) {
        final fallbackNext = localPool.first;
        _setPlaybackContext(localPool, playlistId: 'auto_queue', clearQueue: false);
        _isAutoQueueContext = true;
        await _playTrackInternal(fallbackNext, setContext: false, clearQueue: false);
      } else {
        stopTrack();
      }
    }
  }

  final Set<String> _autoplayTrackIds = {};

  /// Returns whether a track in the queue was automatically added by autoplay
  bool isAutoplayTrack(String trackId) => _autoplayTrackIds.contains(trackId);



  /// How many radio tracks to keep queued ahead of the current one.
  ///
  /// This is the station's runway, not the whole station. A track runs minutes,
  /// so ten is far more than a resolve needs to replace, while keeping the
  /// queue honest about what the user actually chose.
  static const int _autoplayQueueTarget = 10;

  /// Every track radio has offered or played this session, so a station that
  /// wraps around does not replay what the listener just heard.
  final Set<String> _autoplaySessionHistory = {};

  /// The track the in-flight radio request was seeded with.
  ///
  /// One queue edit fires several player callbacks, so without this a single
  /// refill would be requested repeatedly. Released again when the response
  /// comes back empty — an empty or failed response is exactly the case where
  /// a latched seed would leave the toggle on with nothing to play.
  String? _autoplaySeed;

  /// Retry delay before re-arming an empty station.
  static const Duration _autoplayEmptyRetryDelay = Duration(seconds: 2);

  bool _autoplayEmptyRetried = false;

  /// Guarded by [_playbackGeneration]; only one radio request at a time.
  Future<void>? _autoplayFillJob;

  /// Whether the station has enough queued ahead of the current track.
  bool _autoplayStationIsFull() => _autoplayQueueLength >= _autoplayQueueTarget;

  /// Releases the seed latch so the next request re-arms the station.
  void _rearmAutoplay() {
    _autoplaySeed = null;
    _autoplayEmptyRetried = false;
  }

  /// Automatically populates the queue with the best and related tracks
  /// using InnerTube's official RDAMVM radio mix and BitChord's QueueBuilder algorithm.
  Future<void> _autoFillQueue(Track seedTrack, {int? generation}) async {
    final gen = generation ?? _playbackGeneration;
    if (kDebugMode) {
      debugPrint('MusicProvider: autoFill seed=${seedTrack.trackName} '
          'enabled=$_autoplayEnabled offline=$_isOfflineMode '
          'repeat=$_repeatMode station=${_autoplayQueueLength}/$_autoplayQueueTarget '
          'latched=${_autoplaySeed == seedTrack.id}');
    }
    if (!_autoplayEnabled || _isOfflineMode) return;

    // A full station does not need refilling, and a repeat-all loop is
    // deliberately playing what is already there.
    if (_autoplayStationIsFull() || _repeatMode == RepeatMode.all) return;

    // The seed latch: several callbacks from one queue edit must not each
    // start a request.
    if (_autoplaySeed == seedTrack.id) return;
    _autoplaySeed = seedTrack.id;
    _autoplayEmptyRetried = false;

    // One request at a time. A newer caller wins; the older one is dropped.
    final running = _autoplayFillJob;
    if (running != null) await running;

    final job = _fillAutoplayQueue(seedTrack, gen);
    _autoplayFillJob = job;
    try {
      await job;
    } finally {
      if (identical(_autoplayFillJob, job)) _autoplayFillJob = null;
    }
  }

  /// The actual radio request and insert. Split from [_autoFillQueue] so the
  /// latch and the single-flight guard above have a Future to hand around.
  Future<void> _fillAutoplayQueue(Track seedTrack, int gen) async {
    try {
      List<Track> recommendations;
      if (seedTrack.id.length == 11 && seedTrack.source != 'local') {
        recommendations =
            await _innerTubeService.getRadioTracks(seedTrack.id, limit: 20);
      } else if (seedTrack.source != 'local' &&
          seedTrack.trackName.isNotEmpty) {
        final query =
            '${seedTrack.trackName} ${seedTrack.artistName}'.trim();
        final searchResults =
            await _innerTubeService.searchSongs(query, limit: 10);
        if (searchResults.isNotEmpty && searchResults.first.id.length == 11) {
          recommendations = await _innerTubeService
              .getRadioTracks(searchResults.first.id, limit: 20);
          if (recommendations.isEmpty) {
            recommendations = searchResults;
          }
        } else {
          recommendations = searchResults;
        }
      } else {
        recommendations = [];
      }

      var filtered = recommendations.where(_isPlayableAutoplayCandidate).toList();

      if (filtered.isEmpty) {
        final seen = <String>{
          seedTrack.id,
          ..._autoplaySessionHistory,
        };
        filtered = [
          ..._quickPicks,
          ..._recommendedTracks,
          ..._trendingTracks,
        ].where((t) => _isPlayableAutoplayCandidate(t) && seen.add(t.id)).toList();
      }

      if (filtered.isEmpty) {
        await _retryEmptyAutoplay(seedTrack, gen);
        return;
      }

      // Apply BitChord QueueBuilder: deduplicate recordings and enforce artist diversity caps
      final existingTracks = <Track>[
        if (_currentTrack != null) _currentTrack!,
        ..._queue,
        // Anything the station already offered counts as taken, so a wrap-around
        // radio response does not hand back the tracks it just gave.
        ..._autoplaySessionHistory.map(_trackById).whereType<Track>(),
      ]..removeWhere((t) => t.id == seedTrack.id);

      final needed = _autoplayQueueTarget - _autoplayQueueLength;
      if (needed <= 0) return;

      final extended =
          QueueBuilder.extend(existingTracks, filtered, limit: needed);
      if (extended.isEmpty) {
        await _retryEmptyAutoplay(seedTrack, gen);
        return;
      }

      // Deliberately NOT gated on the current track or the playback generation.
      //
      // The station is a suggestion list, not a playback decision: dropping the
      // result because the listener skipped while the radio request was in
      // flight meant a station that was almost always empty by the time it
      // arrived. Anything that arrives is still valid to offer, and the
      // per-track re-seed tops it up for whatever is playing now.
      for (final t in extended) {
        _autoplayTrackIds.add(t.id);
        _autoplaySessionHistory.add(t.id);
      }
      _autoplayQueue.addAll(extended);
      notifyListeners();

      // Push the new station entries into the player as well.
      //
      // The window is only built once when the head starts, which is before the
      // station has returned anything - so from a tap with no ordered context
      // (anything that is not Jump Back In or a real album) the window stayed
      // empty, and the player had nothing to advance into at the end of the
      // track. Queueing is what makes the next song play.
      if (_currentTrack != null) {
        unawaited(_extendWindowFrom(_currentTrack!));
      }
      _prefetchNextTrack();
      if (kDebugMode) {
        debugPrint(
            'MusicProvider: Auto-filled queue with ${extended.length} BitChord-curated tracks for ${seedTrack.trackName}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: Auto-fill queue error: $e');
      await _retryEmptyAutoplay(seedTrack, gen);
    }
  }

  /// Re-arms an empty station once.
  ///
  /// An empty radio response would otherwise leave the toggle on with nothing
  /// to play: the seed stays latched, so nothing ever asks again. One delayed
  /// retry heals a flaky response without hammering the endpoint.
  Future<void> _retryEmptyAutoplay(Track seedTrack, int gen) async {
    if (_autoplayEmptyRetried) return;
    _autoplayEmptyRetried = true;
    _autoplaySeed = null;
    await Future<void>.delayed(_autoplayEmptyRetryDelay);
    if (gen != _playbackGeneration) return;
    if (!_autoplayEnabled || _autoplayStationIsFull()) return;
    await _autoFillQueue(seedTrack, generation: gen);
  }

  int get _autoplayQueueLength => _autoplayQueue.length;

  Track? _trackById(String id) {
    for (final t in _queue) {
      if (t.id == id) return t;
    }
    return _currentTrack?.id == id ? _currentTrack : null;
  }

  /// Asynchronously resolves authoritative artist and album metadata from YouTube Music's
  /// watch queue and updates the current track in-place (matching BitChord's `trackLinks`).
  Future<void> _enrichCurrentTrackMetadata(Track current) async {
    if (current.source == 'local') return;
    try {
      final enriched = await _innerTubeService.fetchTrackLinks(current.id);
      if (enriched != null && _currentTrack?.id == current.id) {
        bool changed = false;
        var updated = _currentTrack!;

        if (enriched.albumName.isNotEmpty &&
            (updated.albumName.isEmpty ||
                updated.albumName.toLowerCase().contains('unknown')) &&
            enriched.albumName != updated.albumName) {
          updated = updated.copyWith(albumName: enriched.albumName);
          changed = true;
        }

        if (enriched.artistName.isNotEmpty &&
            enriched.artistName != 'Unknown Artist' &&
            enriched.artistName != updated.artistName &&
            (updated.artistName.contains(',') ||
                updated.artistName.contains('•') ||
                updated.artistName == 'Unknown Artist')) {
          updated = updated.copyWith(artistName: enriched.artistName);
          changed = true;
        }

        if (changed) {
          _currentTrack = updated;
          notifyListeners();
          if (kDebugMode) {
            debugPrint(
                'MusicProvider: Enriched metadata for ${current.trackName}: album="${updated.albumName}", artist="${updated.artistName}"');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: Metadata enrichment error: $e');
    }
  }

  Future<void> _playTrackInternal(Track track,
      {bool setContext = true,
      bool clearQueue = true,
      bool recordHistory = true}) async {
    if (setContext) {
      _setPlaybackContext(_currentPlayingTracks,
          playlistId: _currentPlaylistId, clearQueue: clearQueue);
    } else {
      // Do NOT update _currentTrack here. playTrack() handles it.
      // Updating it here causes playTrack to think we are toggling the current song.
      // _currentTrack = track;
      _updateCurrentIndex();
    }

    // Check offline status
    bool offline = await _shouldPlayOffline(track);

    try {
      if (offline) {
        await playOfflineTrack(track,
            setContext: setContext,
            clearQueue: setContext ? clearQueue : false,
            recordHistory: recordHistory);
      } else {
        await playTrack(track,
            playlistTracks: _currentPlayingTracks,
            playlistId: _currentPlaylistId,
            setContext: setContext,
            clearQueue: setContext ? clearQueue : false,
            recordHistory: recordHistory);
      }
    } catch (e) {
      debugPrint("Error in _playTrackInternal: $e");
    }
  }

  Future<bool> _shouldPlayOffline(Track track) async =>
      track.source == 'local' || await isTrackDownloaded(track.id);

  // --- Player window -----------------------------------------------------
  //
  // The player holds a small window of real, already-resolved tracks laid out
  // as [preceding?] + [current] + [upcoming…], with the player started on the
  // current one. ExoPlayer then transitions between them seamlessly, so a
  // plain listen costs one setAudioSources per window instead of one per track,
  // and prev/next are the real thing rather than a synthetic event.
  //
  // The window is only ever a buffer. What plays next is still decided here
  // (see _peekNextAfter), so the window can never become a second source of
  // truth; it is refilled from the real decision as it is consumed.

  /// How many tracks to hold after the current one in the player window.
  ///
  /// A track runs minutes and a resolve takes well under a second once the
  /// InnerTube session is warm, so even a short window has plenty of runway for
  /// one failed resolve. BitChord keeps ten queued ahead for the same reason -
  /// the depth is what stops the queue running dry mid-listen - but it pays for
  /// that depth at the moment of the tap, which is the part that made playback
  /// feel slow to start here. This window is filled *after* the head is already
  /// audible, so depth costs nothing at the start.
  static const int _windowUpcoming = 4;

  /// Resolves one track into a tagged source, or null if it cannot play.
  /// Every track the player has been handed, by id.
  ///
  /// The transition handler resolves "what just became current" from the
  /// visible context, the user queue and the station - but the window is also
  /// fed by dry-window repairs and preceding-track inserts, whose entries can
  /// be in neither list when the player reaches them. This registry is the
  /// fallback that keeps working when all the lists fail: anything audible is
  /// something we windowed, so it is always in here.
  ///
  /// Bounded: only the recent past matters for a transition, and the map never
  /// grows past [_windowedTrackCap].
  final Map<String, Track> _windowedTracks = {};
  static const int _windowedTrackCap = 64;

  void _rememberWindowedTrack(Track t) {
    // Refresh recency so the cap trims the stalest, not the oldest-inserted.
    _windowedTracks.remove(t.id);
    _windowedTracks[t.id] = t;
    while (_windowedTracks.length > _windowedTrackCap) {
      _windowedTracks.remove(_windowedTracks.keys.first);
    }
  }

  Future<IndexedAudioSource?> _sourceForTrack(Track t) async {
    _rememberWindowedTrack(t);
    try {
      if (t.source == 'local' || await isTrackDownloaded(t.id)) {
        final path = await _localFileFor(t);
        if (path == null || path.isEmpty) return null;
        return _audioService.buildSource(
          url: path,
          isLocal: true,
          title: t.trackName,
          artist: t.artistName,
          artUri: t.albumArtUrl,
          id: t.id,
        );
      }
      final r = await _streamResolution.resolve(ResolveRequest(
        videoId: t.id,
        title: t.trackName,
        artist: t.artistName,
        durationMs: t.durationMs,
      ));
      if (r == null || r.url.isEmpty) return null;
      return _audioService.buildSource(
        url: r.url,
        headers: r.userAgent == null ? null : {'User-Agent': r.userAgent!},
        title: t.trackName,
        artist: t.artistName,
        artUri: t.albumArtUrl,
        id: t.id,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: window track ${t.id} failed: $e');
      return null;
    }
  }

  /// Completes the live window around whatever is playing.
  ///
  /// Runs unawaited, after the head is already audible. The upcoming entries
  /// are the same work the advance path does, so it goes through
  /// [_extendWindowFrom]; only the preceding entry is new, because nothing
  /// else puts one in and without it the lock screen has no previous button.
  Future<void> _fillWindowAround(Track head) async {
    if (_currentTrack?.id != head.id) return; // the user moved on
    final gen = _playbackGeneration;

    final prev = _precedingTrack(head);

    // Both halves run concurrently and neither is awaited before the other.
    // Awaiting the preceding track's resolve first meant a slow resolve left
    // the upcoming entries — the ones that actually keep the music going —
    // waiting on a lookup that only exists to light up a prev button.
    unawaited(_extendWindowFrom(head));

    if (prev != null) {
      unawaited(() async {
        final prevSource = await _sourceForTrack(prev);
        if (gen != _playbackGeneration) return;
        if (_currentTrack?.id != head.id) return;
        if (prevSource == null) return;
        try {
          await _audioService.insertWindowAt(0, prevSource);
          if (kDebugMode) {
            debugPrint('MusicProvider: window filled -> '
                '${_audioService.windowTrackIds.length} entries');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('MusicProvider: preceding insert failed: $e');
        }
      }());
    } else if (kDebugMode) {
      debugPrint('MusicProvider: window filled (no preceding) -> '
          '${_audioService.windowTrackIds.length} entries');
    }
  }


  /// Local file path for [track] when it is on disk, else null.
  Future<String?> _localFileFor(Track track) async {
    if (track.source == 'local' && track.previewUrl.isNotEmpty) {
      return track.previewUrl;
    }
    try {
      return await getDownloadedTrackPath(track.id);
    } catch (_) {
      return null;
    }
  }

  /// True when playback context is a real ordered list of tracks, as opposed to
  /// an autoplay seed.
  ///
  /// Any ordered list counts — an album or playlist, but also Jump Back In,
  /// which is genuinely walkable and is what a prev/next button should walk
  /// when the user starts from there. Earlier this also excluded the literal
  /// ids 'recently_played' and 'jump_back_in', but neither was ever assigned
  /// anywhere, so those clauses only made those contexts lose their prev/next
  /// and their ability to advance past the end.
  ///
  /// Autoplay stays out because it owns its own advance; [_isAutoQueueContext]
  /// is the flag that actually tracks that.
  bool get _isRealCuratedPlaylist =>
      _currentPlaylistId != null &&
      _currentPlaylistId != 'auto_queue' &&
      !_isAutoQueueContext;

  /// The player moved to a windowed track on its own.
  ///
  /// Everything a track change normally does is applied here — the window
  /// exists so this path is a state update rather than a re-resolve, which is
  /// the whole point of the phase.
  Future<void> _onPlayerAdvancedTo(String id) async {
    final list = _getActivePlaylist();
    final idx = list.indexWhere((t) => t.id == id);

    // Resolve what just became current. In order:
    //
    // 1. The window registry. This is authoritative for anything audible,
    //    because it records every track the player was actually handed -
    //    including dry-window repairs and preceding-track inserts that the
    //    lists below may no longer contain.
    // 2. The visible context, then the full user queue and the full station
    //    (not just their heads: the player can step past a head that has not
    //    been consumed yet if two transitions land close together).
    //
    // The old fallback of "_currentTrack or _quickPicks.first" is gone. It
    // returned a track whose id differed from `id`, hit the `next.id != id`
    // check, and bailed - leaving the audio on the new track while cover,
    // title and lyrics all kept showing the old one.
    final Track? resolved = _windowedTracks[id] ??
        (idx >= 0 ? list[idx] : null) ??
        _queue.firstWhereOrNull((t) => t.id == id) ??
        _autoplayQueue.firstWhereOrNull((t) => t.id == id);

    final next = resolved;
    if (next == null) {
      if (kDebugMode) {
        debugPrint('MusicProvider: window advanced to untracked $id '
            '- registry has ${_windowedTracks.length} entries');
      }
      return;
    }
    if (next.id == _currentTrack?.id) return;

// Observe, never invalidate.
    //
    // This runs because the player moved on by itself, and it does not start a
    // resolve of its own - it only applies state. It used to do
    // `++_playbackGeneration`, which is the counter a user-initiated playTrack
    // checks at `if (gen != _playbackGeneration) return`. So whenever a track
    // change raced a tap, the tap was cancelled mid-resolve and silently did
    // nothing: the listener pressed a song and heard silence, with no error.
    //
    // This is the same rule BitChord follows - `onMediaItemTransition` does
    // bookkeeping and never cancels an in-flight resolve.
    final gen = _playbackGeneration;

    // A track that came from the user queue is consumed now that it is
    // actually playing. _peekNextAfter deliberately does not consume it, so
    // this is the one place that does.
    if (_queue.isNotEmpty && _queue.first.id == next.id) {
      _queue.removeAt(0);
    } else if (_autoplayQueue.isNotEmpty && _autoplayQueue.first.id == next.id) {
      // Same for the station, or it would keep offering a track already playing
      // and the queue would drift one entry behind the audio forever.
      _autoplayQueue.removeAt(0);
    }

    // History before the move, so "previously played" records the track that
    // actually ended rather than the one that started.
    final previous = _currentTrack;
    if (previous != null && previous.id != next.id) {
      _playbackHistory.add(previous);
      if (_playbackHistory.length > _maxPlaybackHistory) {
        _playbackHistory.removeAt(0);
      }
    }

    _currentTrack = TrackMetadataEnricher.sanitizeTrack(next);
    // A new current track clears the dry-window latch, so whichever track
    // finishes next gets its own repair rather than being skipped as "already
    // handled".
    _dryRepairFor = null;
    // -1 when the track is not in the context list, which is the honest index:
    // prev/next then come from the window rather than from a list position.
    _currentIndex = idx;
    _paletteService.clear();
    _isOfflineTrack = next.source == 'local';
    _currentLyrics = null;
    _lyricsTrackId = null;
    _isLoadingLyrics = true;
    _lyricsError = null;
    notifyListeners();

    if (!_isOfflineMode) {
      unawaited(fetchLyrics());
    }
    updatePalette();
    _updateRecentlyPlayed(_currentTrack!);
    _recordSearchFollowup(_currentTrack!);

    // Keep the window topped up so the player never runs dry.
    unawaited(_extendWindowFrom(_currentTrack!));

    // Re-seed the station from the track that is actually playing now. Without
    // this the radio is frozen on whatever was playing when it was first
    // filled, so the queue keeps recommending music for a track that ended
    // minutes ago. The latch inside makes the extra callbacks from one queue
    // edit cost nothing.
    _autoplaySessionHistory.add(next.id);
    if (_autoplayEnabled && !_isOfflineMode) {
      unawaited(_autoFillQueue(_currentTrack!, generation: gen));
    }
    notifyListeners();

    if (gen != _playbackGeneration) return;
  }


  /// Repairs an exhausted player window, then lets the player do the advancing.
  ///
  /// Modelled on BitChord, which is the version of this that works. There, the
  /// player owns the queue outright: `onMediaItemTransition` is the only
  /// "track changed" signal, and `STATE_ENDED` deliberately does *not* advance —
  /// it only tops the queue up so ExoPlayer continues by itself. The listener's
  /// queue runs ~10 tracks deep precisely so the queue rarely runs dry at all.
  ///
  /// We had two advancers. The window moved on by itself *and* `completed` ran a
  /// second advance, which seeked past the end of the sequence, left the UI
  /// showing the finished track, and — because that path bumped the user
  /// playback generation — silently cancelled whatever the listener tapped next.
  ///
  /// So there is no second advancer. A dry window is a queue problem: top up the
  /// station, push one entry into the player, and the player continues on its
  /// own. [windowIndexStream] then applies the state change like any other.
  Future<void> _onSequenceRanDry() async {
    // The player reports `completed` repeatedly while it sits at the end of a
    // track, so without this latch every emission started another repair - which
    // is how a single track end turned into an unbounded pile of overlapping
    // radio requests.
    final finishedId = _currentTrack?.id;
    if (finishedId == null) return;
    if (_dryRepairFor == finishedId) return;
    _dryRepairFor = finishedId;
    _hasPlayedCurrentTrack = false;

    if (kDebugMode) {
      debugPrint('MusicProvider: window ran dry after "$finishedId" '
          '- topping up instead of advancing');
    }

    // Autoplay gets its own token so it can be abandoned when the listener
    // takes over, but can never invalidate what the listener asked for.
    final autoplayGen = ++_autoplayGeneration;
    final userGen = _playbackGeneration;
    bool superseded() =>
        autoplayGen != _autoplayGeneration || userGen != _playbackGeneration;

    try {
      if (_autoplayEnabled && !_isOfflineMode) {
        await _autoFillQueue(_currentTrack!, generation: userGen);
        if (superseded()) return;
      }

      final next = _peekNextAfter(_currentTrack?.id);
      if (next == null) {
        if (kDebugMode) {
          debugPrint('MusicProvider: nothing left to play - stopping');
        }
        _dryRepairFor = null;
        stopTrack();
        return;
      }

      // The window can still hold the next entry when the player reports
      // `completed` - an entry that fails to load leaves the sequence finished
      // with its successor queued behind it. Appending a second copy of a track
      // the window already has is exactly how one song came to play twice: once
      // from its original slot, then again from the duplicate. So check first
      // and move the cursor onto the copy that is already there.
      if (_audioService.windowTrackIds.contains(next.id)) {
        _dryRepairFor = null;
        if (kDebugMode) {
          debugPrint('MusicProvider: next "${next.trackName}" is already in '
              'the window - advancing onto it instead of appending');
        }
        await _audioService.advanceIntoWindow();
        return;
      }

      final source = await _sourceForTrack(next);
      if (superseded()) return;
      if (source == null) {
        // Could not resolve the one thing we meant to play. Try once more via
        // the queue decision so a single bad resolve does not end the session.
        _dryRepairFor = null;
        await _onTrackComplete();
        return;
      }

      await _audioService.appendWindow([source]);
      if (kDebugMode) {
        debugPrint('MusicProvider: appended "${next.trackName}" '
            '- the player will move on by itself');
      }

      // Appending to a finished sequence does not restart it. The repair only
      // runs when the track genuinely finished while playing - a paused player
      // never reaches `completed` - so moving on here cannot override a pause
      // the listener asked for. Stepping the cursor rather than resuming is
      // what keeps the finished track from being replayed from zero.
      if (superseded()) return;
      try {
        final advanced = await _audioService.advanceIntoWindow();
        if (!advanced && kDebugMode) {
          debugPrint('MusicProvider: appended but the window still reports no '
              'successor - leaving playback alone');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('MusicProvider: dry-window advance failed: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: dry-window repair failed: $e');
      _dryRepairFor = null;
    }
  }

  /// The track whose dry-window repair is already in flight, if any.
  ///
  /// Cleared whenever a different track becomes current, so the next track to
  /// finish gets its own repair.
  String? _dryRepairFor;

  /// Appends the tracks that follow the current one to the live window.
  ///
  /// Reads the same decision the advance path would make (see
  /// [_peekNextAfter]), so a refill never disagrees with playback. Best effort:
  /// a track that will not resolve is simply not added, and the next
  /// completion falls through to the existing decision path.
  Future<void> _extendWindowFrom(Track current) async {
    final pending = _upcomingTracks(current, _windowUpcoming);
    if (pending.isEmpty) return;

    final already = _audioService.windowTrackIds.toSet();
    pending.removeWhere((t) => already.contains(t.id));
    if (pending.isEmpty) return;

    final built = await Future.wait(pending.map(_sourceForTrack));
    final addable = built.whereType<IndexedAudioSource>().toList();
    if (addable.isNotEmpty) {
      await _audioService.appendWindow(addable);
      if (kDebugMode) {
        debugPrint('MusicProvider: window filled -> '
            '${_audioService.windowTrackIds.length} entries');
      }
    }
  }

  /// The playlist track that follows the current one, or null at the end.
  Track? _nextPlaylistTrack() {
    final list = _getActivePlaylist();
    if (!_isRealCuratedPlaylist || list.isEmpty) return null;
    final i = _currentIndex + 1;
    if (i < 0 || i >= list.length) return null;
    return list[i];
  }

  /// The playlist track that precedes the current one, or null at the start.
  Track? _previousPlaylistTrack() {
    final list = _getActivePlaylist();
    if (!_isRealCuratedPlaylist || list.isEmpty) return null;
    final i = _currentIndex - 1;
    if (i < 0 || i >= list.length) return null;
    return list[i];
  }

  /// What plays after [fromId], following the same precedence the advance path
  /// uses: a user-queued track first, then the playlist, then nothing.
  ///
  /// This is what the window is built from. An earlier version windowed only
  /// playlist successors, which made the window a single item whenever playback
  /// came from Home or Search (no curated context) — so the media session had
  /// no queue to offer and the lock screen lost prev/next, and a track that
  /// ended had nothing to advance into. Reading it from the real decision
  /// keeps the window honest in every context.
  ///
  /// Read-only: it never consumes the user queue. A track taken from the queue
  /// is dropped from the queue when it actually becomes current.
  Track? _peekNextAfter(String? fromId) {
    // Precedence, in order: what the listener queued by hand, then the
    // collection they are playing through, then the station.
    //
    // The station is last deliberately. It is a filler for when the real queue
    // runs out, never a reason to step over a track the listener can already
    // see queued. Keeping it in the same list as [_queue] made it outrank the
    // collection, which sounded like the app skipping a track on purpose.
    if (_queue.isNotEmpty) return _queue.first;

    final list = _getActivePlaylist();
    if (_isRealCuratedPlaylist && list.isNotEmpty) {
      final nextId = fromId ?? _currentTrack?.id;
      final i = nextId == null ? -1 : list.indexWhere((t) => t.id == nextId);
      if (i >= 0 && (i + 1) < list.length) return list[i + 1];
    }

    return _autoplayQueue.isEmpty ? null : _autoplayQueue.first;
  }

  /// The tracks to place after [current] in the window.
  List<Track> _upcomingTracks(Track current, int count) {
    final out = <Track>[];
    final seen = {current.id};
    var cursor = current;
    for (var i = 0; i < count; i++) {
      final next = _peekNextAfter(cursor.id);
      if (next == null || !seen.add(next.id)) break;
      out.add(next);
      cursor = next;
    }
    return out;
  }

  /// The track to place before [current], so prev/next are real rather than
  /// absent. Never more than one: history beyond that is not what anyone
  /// reaches for, and each entry costs a resolve.
  Track? _precedingTrack(Track current) {
    final prev = _previousPlaylistTrack();
    if (prev != null && prev.id != current.id) return prev;
    // Falling back to playback history covers the no-playlist case, where a
    // prev button is still expected.
    for (final h in _playbackHistory.reversed) {
      if (h.id != current.id) return h;
    }
    return null;
  }

  Future<void> skipToNext() async {
    debugPrint('MusicProvider: SkipNext requested.');
    _playbackGeneration++; // invalidate stale async continuations
    if (_currentTrack == null) return;

    // The window holds user picks, then the collection, then the station, in
    // the order they will actually play. If the player has a next item, that
    // item IS the answer: seeking to it is seamless, while re-resolving here
    // rebuilds the player (the audible gap) and routinely picks a different
    // track than the one the queue shows (the wrong song).
    //
    // This used to gate the seamless path on the window's next being the
    // playlist's next, which is almost never what a station-fed window holds,
    // so nearly every skip took the slow, wrong path - and the station had no
    // branch at all, so it was skipped over entirely.
    if (_audioService.hasNextInWindow) {
      if (kDebugMode) debugPrint('MusicProvider: skip inside window');
      await _audioService.seekToNextInWindow();
      return;
    }

    // The player has nothing after the current item. Make the same decision an
    // automatic advance would - user queue, then collection, then station -
    // and start it as a fresh head so the window rebuilds around it.
    Track? next = _peekNextAfter(_currentTrack?.id);
    if (next != null &&
        _suppressAutoplayOnce &&
        isAutoplayQueued(next.id)) {
      // The listener cleared autoplay and asked for it to stay off: a manual
      // skip honors that rather than handing them a station track.
      next = null;
    }
    if (next == null && _repeatMode == RepeatMode.all) {
      final list = _getActivePlaylist();
      if (_isRealCuratedPlaylist && list.isNotEmpty) next = list.first;
    }
    if (next == null &&
        _autoplayEnabled &&
        !_suppressAutoplayOnce &&
        !_isOfflineMode) {
      // Last resort before stopping dead: seed the station from the current
      // track, then read the decision again.
      await _autoFillQueue(_currentTrack!);
      next = _peekNextAfter(_currentTrack?.id);
    }
    if (next == null) {
      stopTrack();
      return;
    }
    final resolved = next;

    // Consume from whichever tier supplied it, and only when it is the head.
    // Anything deeper stays queued; the player reaches it in order, and the
    // sheet never disagrees with the audio about what was taken.
    if (_queue.isNotEmpty && _queue.first.id == resolved.id) {
      _queue.removeAt(0);
    } else if (_autoplayQueue.isNotEmpty &&
        _autoplayQueue.first.id == resolved.id) {
      _autoplayQueue.removeAt(0);
    }
    await _playTrackInternal(resolved, setContext: false, clearQueue: false);
    notifyListeners();
  }

  Future<void> skipToPrevious() async {
    debugPrint('SkipPrevious requested.');
    _playbackGeneration++;
    if (_currentTrack == null) return;
    if (_position > const Duration(seconds: 3)) {
      await seekTo(Duration.zero);
      if (!_isPlaying) await resumeTrack();
      return;
    }

    final list = _getActivePlaylist();
    final isRealCuratedPlaylist = _isRealCuratedPlaylist && list.isNotEmpty;

    _updateCurrentIndex();

    // 0. If the player already holds the preceding track, going back is a
    // seek inside its own window — instant, and no re-resolve.
    if (_audioService.hasPreviousInWindow) {
      if (kDebugMode) debugPrint('MusicProvider: previous inside window');
      await _audioService.seekToPreviousInWindow();
      return;
    }

    // 1. If in a real curated playlist with a previous index, go back in that playlist
    if (isRealCuratedPlaylist && _currentIndex > 0) {
      final prevTrack = list[_currentIndex - 1];
      await _playTrackInternal(prevTrack, setContext: false);
      return;
    }

    // 2. If we have a session playback history stack (e.g. from autoplay, queue, jump back in, search)
    if (_playbackHistory.isNotEmpty) {
      final prevTrack = _playbackHistory.removeLast();
      // Put current track back into the front of queue so 'next' goes back to it
      if (_currentTrack != null) {
        _queue.insert(0, _currentTrack!);
      }
      await _playTrackInternal(prevTrack,
          setContext: false, clearQueue: false, recordHistory: false);
      notifyListeners();
      return;
    }

    // 3. Fallback: if in curated playlist and repeat is on, wrap around to last track
    if (isRealCuratedPlaylist && _repeatMode != RepeatMode.off && list.isNotEmpty) {
      await _playTrackInternal(list.last, setContext: false);
      return;
    }

    // 4. Default: restart current song
    await seekTo(Duration.zero);
    if (!_isPlaying) await resumeTrack();
  }

  // --- Helper Methods for Navigation State ---
  bool _hasNext() {
    if (_queue.isNotEmpty) return true;
    final list = _getActivePlaylist();
    if (list.isEmpty) return false;
    return _currentIndex < list.length - 1;
  }

  bool _hasPrevious() {
    // If repeat is one or all, we can technically go back (restarts or wraps)
    if (_repeatMode != RepeatMode.off) return true;
    if (_playbackHistory.isNotEmpty) return true;
    final list = _getActivePlaylist();
    if (list.isEmpty) return false;
    return _currentIndex > 0;
  }

  // --- Core Playback Methods ---
  /// Plays a list of tracks starting from [initialIndex] (BitChord detail screen parity).
  Future<void> playTrackList(List<Track> tracks,
      {int initialIndex = 0, String? playlistId}) async {
    if (tracks.isEmpty) return;
    final index = initialIndex.clamp(0, tracks.length - 1);
    await playTrack(tracks[index],
        playlistTracks: tracks,
        playlistId: playlistId ?? 'curated_album_or_playlist');
  }

  Future<void> playTrack(
    Track track, {
    String? playlistId,
    List<Track>? playlistTracks,
    bool setContext = true,
    bool clearQueue = true,
    bool prefetchMetadata = true,
    bool recordHistory = true,
  }) async {
    final isQueueRowPlayback = !setContext && !clearQueue;

    if (kDebugMode) {
      debugPrint(
          'MusicProvider: Request playTrack: ${track.trackName} (ID: ${track.id})');
    }

    // If currently playing same track, pause (toggle)
    if (_currentTrack?.id == track.id && _isPlaying) {
      await pauseTrack();
      return;
    }

    // If currently loaded but paused, resume
    if (_currentTrack?.id == track.id && !_isPlaying && _currentTrack != null) {
      await resumeTrack();
      return;
    }

    final gen = ++_playbackGeneration; // invalidate stale async continuations

    // Resume audio service if it was stopped
    // await _audioService.resume(); // (Not needed, play() handles it)

    _clearError();

    // FIX: Early validation for non-playable track IDs
    // Playlist/Album/Channel IDs cannot be streamed - they need to be browsed first
    final trackId = track.id;
    if (trackId.startsWith('UC') || // Artist/Channel
        trackId.startsWith('VL') || // Playlist
        trackId.startsWith('PL') || // Playlist
        trackId.startsWith('OLAK') || // Album
        trackId.startsWith('MPREb')) {
      // Album browse ID
      if (kDebugMode)
        debugPrint(
            'MusicProvider: Skipping non-playable track: ${track.trackName} (ID: $trackId)');
      final message =
          'Cannot play ${track.trackName} - it is a ${trackId.startsWith("UC") ? "channel" : "playlist/album"}, not a song.';
      _errorMessage = message;
      notifyListeners();
      if (isQueueRowPlayback) {
        throw StateError(message);
      }
      return; // Don't try to play, don't skip - just return early
    }
    try {
      // Stop current playback if any
      if (_isPlaying) {
        await _audioService.stop();
      }

      // Set context before attempting playback
      if (setContext) {
        _setPlaybackContext(playlistTracks,
            playlistId: playlistId, clearQueue: clearQueue);
      }

      // Check if should play offline version
      bool playOffline = await _shouldPlayOffline(track);
      if (playOffline) {
        await playOfflineTrack(track,
            setContext: setContext,
            clearQueue: clearQueue,
            recordHistory: recordHistory);
        return;
      }

      // Check network availability for online playback
      if (_isOfflineMode) {
        throw Exception('Offline mode enabled. Track not available offline.');
      }

      if (!_networkService.isConnected) {
        throw Exception('No internet connection available.');
      }

      // Update current track state
      final sanitizedTrack = TrackMetadataEnricher.sanitizeTrack(track);

      // Record playback history before changing track
      if (recordHistory && _currentTrack != null && _currentTrack!.id != sanitizedTrack.id) {
        _playbackHistory.add(_currentTrack!);
        if (_playbackHistory.length > _maxPlaybackHistory) {
          _playbackHistory.removeAt(0);
        }
      }

      _currentTrack = sanitizedTrack;
      _paletteService.clear(); // Reset palette immediately
      _isOfflineTrack = false;
      _updateCurrentIndex();

      // Immediately clear previous lyrics so normal screen preview snippet
      // never displays stale lyrics from the previous song while the new song loads.
      _currentLyrics = null;
      _lyricsTrackId = null;
      _isLoadingLyrics = true;
      _lyricsError = null;
      notifyListeners();

      // Start fetching lyrics in PARALLEL early
      if (!_isOfflineMode) {
        unawaited(fetchLyrics());
      }

      // Start generating palette in parallel (don't await)
      updatePalette();

      String playableId = sanitizedTrack.id;
      Track effectiveTrack = sanitizedTrack; // Restored
      // Start bitrate check early (parallelize with other work)
      final bitrateFuture = _getBitrate();

      // Handle Spotify tracks - convert to YouTube
      if (track.source == 'spotify') {
        if (kDebugMode) {
          debugPrint(
              'MusicProvider: Converting Spotify track to YouTube: ${track.trackName}');
        }
        final yt = await _spotifyService.findYouTubeTrack(track);
        if (yt != null) {
          playableId = yt.id;
          // Keep _currentTrack as the ORIGINAL track so playlist index
          // lookups (which match by original id) stay valid.
          effectiveTrack = track.copyWith(
            id: playableId,
            source: 'youtube',
            previewUrl: yt.previewUrl,
          );
        } else {
          throw Exception(
              "Could not find playable version of '${track.trackName}'.");
        }
      }

      // Await the bitrate that was started earlier
      final bitrate = await bitrateFuture;
      if (bitrate == 0) {
        throw Exception('Cannot determine bitrate - check network connection.');
      }

      if (kDebugMode) {
        debugPrint(
            'MusicProvider: Fetching stream URL for ${effectiveTrack.trackName} (bitrate: $bitrate kbps)');
      }

      // Resolve stream URL via the racing resolution service
      // (InnerTube ANDROID_VR vs Saavn 320kbps, first validated wins).
      //
      // Retried before giving up. A cold start is the single worst moment for
      // this call - the DNS cache is empty, the socket is new, and both racing
      // sources have to be dialled from scratch - so a first-resolve failure
      // used to end in [_handlePlaybackError] -> `skipToNext()`, which threw the
      // listener's own song away one second after they asked for it. The skip is
      // still the fallback; it just is not the first thing we reach for.
      ResolvedStream? resolved;
      Object? lastResolveError;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (gen != _playbackGeneration) return;
        try {
          resolved = await _streamResolution.resolve(ResolveRequest(
            videoId: playableId,
            title: effectiveTrack.trackName,
            artist: effectiveTrack.artistName,
            durationMs: effectiveTrack.durationMs,
          ));
        } catch (e) {
          lastResolveError = e;
          resolved = null;
        }
        if (gen != _playbackGeneration) return;
        if (resolved != null && resolved!.url.isNotEmpty) break;
        if (attempt == 2) break;
        if (kDebugMode) {
          debugPrint('MusicProvider: resolve failed for '
              '"${effectiveTrack.trackName}" (attempt ${attempt + 1}/3)'
              '${lastResolveError == null ? '' : ' - $lastResolveError'}');
        }
        // Drop any negative cache entry before asking again.
        _streamResolution.invalidate(playableId);
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }

      if (gen != _playbackGeneration) return;

      if (resolved == null || resolved.url.isEmpty) {
        throw Exception(
            'Failed to get stream: all sources exhausted${lastResolveError == null ? '' : ' ($lastResolveError)'}');
      }
      if (kDebugMode) {
        debugPrint('MusicProvider: Stream resolved via ${resolved.source}');
      }

      // Play the resolved URL. YouTube bot-gates URLs per-request (rotation),
      // so a rejected URL often just needs a fresh resolution — retry up to
      // 3 times, invalidating the cache each round.
      //
      // The window is built here, alongside the retry: the head must be the
      // URL that actually played, and the upcoming entries are resolved
      // concurrently so a slow one cannot delay the first sample.
      ResolvedStream current = resolved;
      for (var attempt = 1; attempt <= 3; attempt++) {
        if (gen != _playbackGeneration) return;
        final headers = <String, String>{
          if (current.userAgent != null) 'User-Agent': current.userAgent!,
        };
        try {
          // The head is the URL that actually won the race; the window around
          // it is resolved alongside so a slow entry cannot delay first audio.
          final headSource = await _audioService.buildSource(
            url: current.url,
            headers: headers.isNotEmpty ? headers : null,
            title: effectiveTrack.trackName,
            artist: effectiveTrack.artistName,
            artUri: effectiveTrack.albumArtUrl,
            id: effectiveTrack.id,
          );
          if (gen != _playbackGeneration) return;
          if (headSource == null) {
            throw Exception('Failed to build a playable source');
          }
          // The head bypasses [_sourceForTrack], so register it by hand.
          // Otherwise the very first transition into it finds nothing in the
          // window registry and has to hope a list still contains it.
          _rememberWindowedTrack(sanitizedTrack);

          // The head goes into the player on its own. Resolving the rest of
          // the window first would cost first-audio latency (and a slow entry
          // would stop the track starting at all), so the window is completed
          // in the background once this is audible.
          await _audioService.playSources(
            [headSource],
            initialIndex: 0,
            title: effectiveTrack.trackName,
            artist: effectiveTrack.artistName,
            artUri: effectiveTrack.albumArtUrl,
            id: effectiveTrack.id,
          );
          break;
        } catch (e) {
          if (gen != _playbackGeneration) return;
          if (attempt == 3) rethrow;
          if (kDebugMode) {
            debugPrint(
                'MusicProvider: Playback failed ($e). Re-resolving (attempt ${attempt + 1}/3)...');
          }
          _streamResolution.invalidate(playableId);
          final retry = await _streamResolution.resolve(ResolveRequest(
            videoId: playableId,
            title: effectiveTrack.trackName,
            artist: effectiveTrack.artistName,
            durationMs: effectiveTrack.durationMs,
          ));
          if (gen != _playbackGeneration) return;
          if (retry == null || retry.url.isEmpty) rethrow;
          current = retry;
        }
      }

      if (gen != _playbackGeneration) return;

      // Update state - Note: _isPlaying will be updated by the stream listener
      // Don't set _isPlaying = true here to avoid race condition
      // Keep the ORIGINAL track so playlist index lookups (by original id),
      // same-tap toggles and download keys stay valid even after Spotify→YT
      // conversion. The playable YT variant only lives in the audio source.
      _currentTrack = sanitizedTrack;
      _updateRecentlyPlayed(sanitizedTrack);
      _recordSearchFollowup(sanitizedTrack);
      _updateCurrentIndex();
      notifyListeners();

      // Window is filled in the background; the head is already playing.
      unawaited(_fillWindowAround(sanitizedTrack));

      // Start fetching lyrics in PARALLEL (don't wait)
      if (!_isOfflineMode) {
        unawaited(fetchLyrics());
      }

      // Preload next track (Audio + Lyrics)
      _prefetchNextTrack();

      // Asynchronously enrich metadata (album & clean artist) if needed
      if (!_isOfflineMode &&
          effectiveTrack.id.length == 11 &&
          effectiveTrack.source != 'local' &&
          (_currentTrack!.albumName.isEmpty ||
              _currentTrack!.albumName.toLowerCase().contains('unknown'))) {
        unawaited(_enrichCurrentTrackMetadata(_currentTrack!));
      }

      // Top up the station right after the head starts.
      //
      // This used to be gated on `!_suppressAutoplayOnce && _queue.length < 5`,
      // which made the fill unpredictable - the station was regularly still
      // empty tens of seconds into the track, and the empty state was the whole
      // reason the queue ran dry at the end of it. `_autoFillQueue` already
      // makes the decisions that matter (is the station full, is this seed
      // already latched, is a request already in flight), so the trigger does
      // not need to second-guess it. `_queue` is the listener's own picks and
      // says nothing about how much the station holds.
      if (kDebugMode) {
        debugPrint('MusicProvider: playTrack state-update reached '
            '(gen=$gen current=${_playbackGeneration})');
      }
      unawaited(_autoFillQueue(effectiveTrack, generation: gen));

      // Prefetch Metadata (Artist & Album) for Instant Navigation (suppressed in Explore to save battery/data)
      if (prefetchMetadata) {
        this.prefetchMetadata(effectiveTrack);
      }

      // Lyrics prefetch for upcoming tracks
      _prefetchUpcomingLyrics();

      // Palette updated earlier in parallel

      if (kDebugMode) {
        debugPrint(
            'MusicProvider: Successfully started playback of ${effectiveTrack.trackName}');
      }
      _consecutiveErrors = 0; // Reset error count on success
      _failedTrackIds.remove(effectiveTrack.id);
    } catch (e, s) {
      if (gen != _playbackGeneration) {
        if (kDebugMode) {
          debugPrint(
              'MusicProvider: Discarding error from superseded playback request (gen $gen vs $_playbackGeneration)');
        }
        return;
      }
      if (kDebugMode) {
        debugPrint('MusicProvider: ERROR PLAYING TRACK');
        debugPrint('Track: ${track.trackName}');
        debugPrint('Error: $e');
        debugPrint('Stack trace: $s');
      }
      final message = 'Failed to play ${track.trackName}: ${e.toString()}';
      if (isQueueRowPlayback) {
        _errorMessage =
            message.length > 150 ? '${message.substring(0, 147)}...' : message;
        notifyListeners();
        rethrow;
      }
      await _handlePlaybackError(message);
    }
  }

  Future<void> playOfflineTrack(Track track,
      {bool setContext = true,
      bool clearQueue = true,
      List<Track>? contextList,
      bool recordHistory = true}) async {
    bool knownOffline =
        track.source == 'local' || _downloads.metadata.containsKey(track.id);

    if (!knownOffline) {
      await playTrack(track,
          playlistTracks: contextList ?? _currentPlayingTracks,
          playlistId: _currentPlaylistId,
          setContext: setContext,
          clearQueue: clearQueue,
          recordHistory: recordHistory);
      return;
    }

    if (_currentTrack?.id == track.id && _isPlaying) {
      await pauseTrack();
      return;
    }

    if (_currentTrack?.id == track.id && !_isPlaying && _currentTrack != null) {
      await resumeTrack();
      return;
    }

    _isOfflineContext = true; // Set explicit offline flag
    await _playOfflineTrackInternal(track,
        setContext: setContext,
        clearQueue: clearQueue,
        contextList: contextList,
        recordHistory: recordHistory);

    if (setContext && contextList != null) {
      _setPlaybackContext(contextList, clearQueue: clearQueue);
    }
  }

  Future<void> _playOfflineTrackInternal(Track track,
      {bool setContext = true,
      bool clearQueue = true,
      List<Track>? contextList,
      bool recordHistory = true}) async {
    _clearError();

    // Record playback history before changing track
    if (recordHistory && _currentTrack != null && _currentTrack!.id != track.id) {
      _playbackHistory.add(_currentTrack!);
      if (_playbackHistory.length > _maxPlaybackHistory) {
        _playbackHistory.removeAt(0);
      }
    }

    // Sync current track metadata immediately for UI consistency
    _currentTrack = track;
    _paletteService.clear();
    _isOfflineTrack = true;
    _updateCurrentIndex();

    // FIX 1: Immediately clear previous lyrics for offline tracks
    _currentLyrics = null;
    _lyricsTrackId = track.id;
    _isLoadingLyrics = false;
    _lyricsError = null;
    notifyListeners();

    // Start palette generation in parallel
    updatePalette();

    try {
      if (_isPlaying) await _audioService.stop();

      String filePath;
      bool isDownloaded = _downloads.metadata.containsKey(track.id);

      if (track.source == 'local') {
        filePath = track.previewUrl;
      } else if (isDownloaded) {
        final meta = _downloads.metadata[track.id];
        filePath = meta?['filePath'] as String? ?? '';
      } else {
        throw Exception('Track is not local or downloaded.');
      }

      if (filePath.isEmpty) {
        throw Exception('File path is empty.');
      }

      final file = File(filePath);
      // Validate Existence AND Size
      bool fileExists = await file.exists();
      int fileSize = fileExists ? await file.length() : 0;

      if (!fileExists || fileSize < 50 * 1024) {
        // Check for validity (< 50KB assumed corrupt)
        if (fileExists) {
          debugPrint(
              "MusicProvider: File exists but too small ($fileSize bytes). Deleting: $filePath");
          try {
            await file.delete();
          } catch (_) {}
        }
        await _downloads.handleMissingFile(track.id, filePath);

        // Fallback to online if possible
        if (!_isOfflineMode && _networkService.isConnected) {
          if (kDebugMode)
            debugPrint(
                "MusicProvider: Local file missing, falling back to online for ${track.trackName}");
          // Recursive call to playTrack will now see it as NOT downloaded (since we removed metadata)
          // and attempt online playback. Preserve the caller's original context list
          // so skips stay inside what the user tapped from.
          await playTrack(track,
              playlistTracks: setContext
                  ? (contextList ??
                      _currentPlayingTracks ??
                      (isDownloaded
                          ? await getDownloadedTracks()
                          : _localTracks))
                  : null,
              playlistId: _currentPlaylistId,
              setContext: setContext,
              clearQueue: clearQueue);
          return;
        }

        throw Exception('File not found and cannot play online: $filePath');
      }

      _currentTrack = track;
      _paletteService.clear(); // Reset palette immediately
      _isOfflineTrack = true;

      if (setContext) {
        List<Track> contextTracks;
        String contextDesc;
        if (isDownloaded) {
          contextTracks = await getDownloadedTracks();
          contextDesc = "Downloads";
        } else {
          contextTracks = _localTracks;
          contextDesc = "Local Tracks";
        }

        _setPlaybackContext(contextTracks, clearQueue: clearQueue);
        if (kDebugMode) {
          debugPrint("MusicProvider: Set playback context to $contextDesc");
        }
      } else {
        _updateCurrentIndex();
      }

      if (kDebugMode) {
        debugPrint('MusicProvider: Playing offline file: $filePath');
      }

      await _audioService.playLocalFile(
        filePath,
        title: track.trackName,
        artist: track.artistName,
        artUri: track.albumArtUrl,
        id: track.id,
        hasNext: _hasNext(),
        hasPrevious: _hasPrevious(),
      );

      _updateRecentlyPlayed(track);
      notifyListeners();
    } catch (e, s) {
      if (kDebugMode) {
        debugPrint('MusicProvider: ERROR PLAYING OFFLINE TRACK');
        debugPrint('Track: ${track.trackName}');
        debugPrint('Error: $e');
        debugPrint('Stack trace: $s');
      }
      await _handlePlaybackError(
          'Failed to play offline track: ${e.toString()}');
    }
  }

  // --- Player Controls ---
  Future<void> pauseTrack() async {
    if (_isCasting) {
      await _castService.pause();
      _isPlaying = false;
      notifyListeners();
      return;
    }
    await _audioService.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> resumeTrack() async {
    if (_isCasting) {
      await _castService.play();
      _isPlaying = true;
      notifyListeners();
      return;
    }
    // Stopped-but-loaded (error-stop or natural stop with autoplay off):
    // resume means replay from the top through the full pipeline — the
    // audio service has no loaded source anymore.
    if (_currentTrack != null && !_audioService.hasLoadedSource) {
      final t = _currentTrack!;
      _currentTrack = null; // force playTrack full path
      await playTrack(t,
          playlistTracks: _currentPlayingTracks,
          playlistId: _currentPlaylistId);
      return;
    }
    await _audioService.resume();
    _isPlaying = true;
    notifyListeners();
  }

  // --- Volume & Speed (v5.2: player controls; speed reused by Lofi later) ---
  double _volume = 1.0;
  double _playbackSpeed = 1.0;

  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;

  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped == _volume) return;
    _volume = clamped;
    await _audioService.setVolume(_volume);
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double value) async {
    final clamped = value.clamp(0.5, 2.0);
    if (clamped == _playbackSpeed) return;
    _playbackSpeed = clamped;
    await _audioService.setSpeed(_playbackSpeed);
    notifyListeners();
  }

  // --- Autoplay & Canvas ---
  void toggleAutoplay() {
    // If autoplay is already enabled but queue is empty, a tap should force-fill
    // the queue immediately (BitChord 1-tap UX parity) instead of turning off.
    if (_autoplayEnabled && _queue.isEmpty && _currentTrack != null) {
      unawaited(_autoFillQueue(_currentTrack!, generation: _playbackGeneration));
      notifyListeners();
      return;
    }

    final next = !_autoplayEnabled;
    _autoplayEnabled = next;
    notifyListeners();
    SharedPreferences.getInstance().then((p) {
      p.setBool('autoQueueEnabled', next);
      p.setBool('autoplayEnabled', next);
    });
    if (!next) {
      // Switching the station off means taking back what it queued and has not
      // played yet, not merely stopping new suggestions.
      _autoplayQueue.clear();
      _autoplayTrackIds.clear();
      _rearmAutoplay();
    } else if (_currentTrack != null) {
      unawaited(_autoFillQueue(_currentTrack!, generation: _playbackGeneration));
    }
  }

  bool _isCanvasActive = false;
  bool get isCanvasActive => _isCanvasActive;
  void toggleCanvas() {
    _isCanvasActive = !_isCanvasActive;
    notifyListeners();
  }

  // --- BitChord Settings Parity ---
  bool _animatedCanvasEnabled = false;
  bool get animatedCanvasEnabled => _animatedCanvasEnabled;
  Future<void> setAnimatedCanvasEnabled(bool value) async {
    _animatedCanvasEnabled = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('animated_canvas', value);
  }

  bool _canvasOverCellular = false;
  bool get canvasOverCellular => _canvasOverCellular;
  Future<void> setCanvasOverCellular(bool value) async {
    _canvasOverCellular = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('canvas_over_cellular', value);
  }

  bool _fullBleedArtwork = true;
  bool get fullBleedArtwork => _fullBleedArtwork;
  Future<void> setFullBleedArtwork(bool value) async {
    _fullBleedArtwork = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('full_bleed_artwork', value);
  }

  bool _syncedLyricsEnabled = true;
  bool get syncedLyricsEnabled => _syncedLyricsEnabled;
  Future<void> setSyncedLyricsEnabled(bool value) async {
    _syncedLyricsEnabled = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('synced_lyrics', value);
  }

  bool _prioritizeSyllableSync = true;
  bool get prioritizeSyllableSync => _prioritizeSyllableSync;
  Future<void> setPrioritizeSyllableSync(bool value) async {
    _prioritizeSyllableSync = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('prioritize_syllable_sync', value);
  }

  Future<void> seekTo(Duration position) async {
    if (_isCasting) {
      await _castService.seek(position.inSeconds.toDouble());
      return;
    }
    if (_currentTrack == null) return;
    final dur = _duration;
    final clamped = position.isNegative
        ? Duration.zero
        : (dur > Duration.zero && position > dur ? dur : position);
    try {
      await _audioService.seekTo(clamped);
      _position = clamped;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error seeking.';
      notifyListeners();
    }
  }

  Future<void> stopTrack() async {
    if (_isStopping) return;
    _isStopping = true;

    if (_isCasting) {
      await _castService.stop();
      _isPlaying = false;
      _isStopping = false;
      notifyListeners();
      return;
    }

    try {
      await _audioService.stop();
    } catch (e) {
      debugPrint('Error stopping service: $e');
    } finally {
      _isPlaying = false;
      // Keep _currentTrack: the pill mini player keys off it, so nulling
      // here made the pill vanish after error-stop cascades ("mini player
      // goes off when I change songs"). A stopped-but-loaded track is the
      // honest state — user taps play on the pill to restart.
      _isOfflineTrack = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _currentIndex = -1;
      _currentPlayingTracks = null;
      _currentPlaylistId = null;
      _shuffledPlaylist = [];
      _queue.clear();
      _autoplayQueue.clear();

      // FIX: Ensure UI is minimized when track stops
      _isPlayerExpanded = false;

      _isStopping = false;
      notifyListeners();
    }
  }

  /// Full reset — only for logout/account switches and user-initiated
  /// "close player" flows. Clears the pill too.
  Future<void> stopAndClearTrack() async {
    await stopTrack();
    _currentTrack = null;
    notifyListeners();
  }

  // --- Casting Methods ---
  StreamSubscription? _castDevicesSub;

  void startCastingDiscovery() {
    _isSearchingDevices = true;
    notifyListeners();
    _castService.startDiscovery();
    // Keep exactly ONE devices subscription; re-invocations must not stack
    // duplicate listeners on the broadcast stream.
    _castDevicesSub ??= _castService.devicesStream.listen((devices) {
      _castDevices = devices;
      notifyListeners();
    });
  }

  void stopCastingDiscovery() {
    _isSearchingDevices = false;
    _castDevicesSub?.cancel();
    _castDevicesSub = null;
    _castService.stopDiscovery();
    notifyListeners();
  }

  Future<void> connectToCastDevice(CastDevice device) async {
    final success = await _castService.connect(device);
    if (success) {
      // If we are currently playing something, transfer it
      if (_currentTrack != null) {
        // Build high quality URL
        String? streamUrl;
        if (_currentTrack!.source == 'youtube' ||
            _currentTrack!.source == 'piped') {
          final castResolved = await _streamResolution.resolve(ResolveRequest(
            videoId: _currentTrack!.id,
            title: _currentTrack!.trackName,
            artist: _currentTrack!.artistName,
            durationMs: _currentTrack!.durationMs,
          ));
          streamUrl = castResolved?.url;
        } else {
          // Local file casting might require a local HTTP server, omitting for simple scope
          // For now, assume remote URLs only or just remote tracks
          streamUrl = null;
        }

        if (streamUrl != null) {
          _isCasting = true;
          unawaited(_audioService.pause()); // Pause local playback
          await _castService.loadMedia(
            url: streamUrl,
            title: _currentTrack!.trackName,
            artist: _currentTrack!.artistName,
            imageUrl: _currentTrack!.albumArtUrl,
          );
        } else {
          _errorMessage = 'Casting unavailable for this track.';
        }
      } else {
        _isCasting = true;
      }
    }
    notifyListeners();
  }

  Future<void> disconnectCastDevice() async {
    await _castService.disconnect();
    _isCasting = false;
    notifyListeners();
  }

  // --- Error Handling ---
  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  Future<void> _handlePlaybackError(String message) async {
    debugPrint("Playback Error: $message");

    // Dummy padding sources (silent WAV) must never count as track failures —
    // they exist only so notification buttons stay clickable.
    final id = _currentTrack?.id ?? '';
    if (id == 'prev_dummy' || id == 'next_dummy') {
      if (kDebugMode) debugPrint('MusicProvider: Ignoring dummy source error.');
      return;
    }

    // Same track already failed recently: do not loop on it.
    if (_failedTrackIds.contains(id)) {
      await stopTrack();
      return;
    }
    _failedTrackIds.add(id);
    if (_failedTrackIds.length > 20)
      _failedTrackIds.remove(_failedTrackIds.first);

    _errorMessage =
        message.length > 150 ? '${message.substring(0, 147)}...' : message;

    // Automatic Failover: If it's an online track and we have a next one, try skipping
    if (!_isOfflineTrack && !_isOfflineMode && _networkService.isConnected) {
      _consecutiveErrors++;
      if (_consecutiveErrors <= 1) {
        if (kDebugMode)
          debugPrint("MusicProvider: Attempting auto-skip after error...");
        skipToNext();
        return;
      }
    }

    await stopTrack();
    _consecutiveErrors = 0; // Reset
  }

  // --- Queue Management ---
  void addToQueue(Track track) {
    _queue.add(track);
    debugPrint("Added to queue: ${track.trackName}. Size: ${_queue.length}");
    notifyListeners();
  }

  void addListToQueue(List<Track> tracks) {
    _queue.addAll(tracks);
    debugPrint("Added ${tracks.length} to queue. Size: ${_queue.length}");
    notifyListeners();
  }

  void playNext(Track track) {
    _queue.insert(0, track);
    debugPrint("Play next: ${track.trackName}. Size: ${_queue.length}");
    notifyListeners();
  }

  void reorderQueueItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length || newIndex < 0) return;
    final int iIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final tr = _queue.removeAt(oldIndex);
    _queue.insert(iIdx.clamp(0, _queue.length), tr);
    notifyListeners();
  }

  /// Reorders the station within itself. A drag never leaves its section, and
  /// the new order feeds [_peekNextAfter] and the window top-up, so what the
  /// listener puts first is genuinely what plays next.
  void reorderAutoplayItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _autoplayQueue.length ||
        newIndex < 0) {
      return;
    }
    final int iIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final tr = _autoplayQueue.removeAt(oldIndex);
    _autoplayQueue.insert(iIdx.clamp(0, _autoplayQueue.length), tr);
    notifyListeners();
  }

  /// Reorders the collection (context) section within itself.
  ///
  /// [upcomingCollection] hands out `sublist(currentIndex + 1)` - a copy - so
  /// reordering that list would reorder a throwaway and the row would snap
  /// straight back. The order that actually plays lives in the active playlist,
  /// so the move is applied to the *upcoming window* of that list and written
  /// back in place.
  ///
  /// Bounded like every other reorder: the already-played prefix never moves,
  /// so the current track keeps its index and a drag cannot jump the head.
  void reorderCollectionItem(int oldIndex, int newIndex) {
    final list = _getActivePlaylist();
    final current = _currentTrack;
    if (current == null || list.isEmpty || !_isRealCuratedPlaylist) return;

    // Same anchor the getter uses, so row N here is row N there.
    final base = list.indexWhere((t) => t.id == current.id);
    if (base < 0) return;
    final start = base + 1;
    final windowLength = list.length - start;
    if (windowLength <= 1) return;
    if (oldIndex < 0 || oldIndex >= windowLength || newIndex < 0) return;

    final int iIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final int target = iIdx.clamp(0, windowLength - 1);
    if (oldIndex == target) return;

    final window = list.sublist(start);
    final moved = window.removeAt(oldIndex);
    window.insert(target, moved);
    final rebuilt = <Track>[...list.sublist(0, start), ...window];

    // Write back into whichever list is driving playback right now.
    if (_shuffleEnabled) {
      _shuffledPlaylist
        ..clear()
        ..addAll(rebuilt);
    } else if (_currentPlayingTracks != null) {
      _currentPlayingTracks!
        ..clear()
        ..addAll(rebuilt);
    } else {
      return;
    }

    // _currentIndex still points at the current track: nothing before `start`
    // moved. Only the id -> position map is now stale.
    _rebuildTrackIndex();
    notifyListeners();
  }

  // Updated to accept Track object or index
  void removeFromQueue(dynamic item) {
    bool removed = false;
    if (item is int && item >= 0 && item < _queue.length) {
      final rTr = _queue.removeAt(item);
      debugPrint(
          "Removed from queue by index: ${rTr.trackName}. Size: ${_queue.length}");
      removed = true;
    } else if (item is Track) {
      final initialLength = _queue.length;
      _queue.removeWhere((t) => t.id == item.id);
      if (_queue.length < initialLength) {
        debugPrint(
            "Removed from queue by track: ${item.trackName}. Size: ${_queue.length}");
        removed = true;
      } else {
        // Not a manual pick - it may be a station entry, which lives in its
        // own tier. Dismissing it there (rather than silently doing nothing)
        // is what makes the sheet's swipe actually work on radio tracks.
        final stationLength = _autoplayQueue.length;
        _autoplayQueue.removeWhere((t) => t.id == item.id);
        if (_autoplayQueue.length < stationLength) {
          debugPrint("Removed station track: ${item.trackName}.");
          removed = true;
        }
      }
    } else if (item is String) {
      // Remove by track ID
      final initialLength = _queue.length;
      _queue.removeWhere((t) => t.id == item);
      if (_queue.length < initialLength) {
        debugPrint(
            "Removed from queue by track ID: $item. Size: ${_queue.length}");
        removed = true;
      } else {
        final stationLength = _autoplayQueue.length;
        _autoplayQueue.removeWhere((t) => t.id == item);
        if (_autoplayQueue.length < stationLength) {
          debugPrint("Removed station track by ID: $item.");
          removed = true;
        }
      }
    }

    if (removed) {
      notifyListeners();
      // Also call after removing from queue
    }
  }

  void clearQueue() {
    if (_queue.isEmpty && !_isAutoQueueContext) return;
    _queue.clear();
    _autoplayQueue.clear();
    _autoplayTrackIds.clear();
    _rearmAutoplay();
    // v5.2 semantics: clearing during an autoplay (autoqueue) context also
    // empties the upcoming autoqueue — the context shrinks to just the
    // active song, and the player stops after it.
    if (_isAutoQueueContext) {
      _isAutoQueueContext = false;
      _suppressAutoplayOnce = true;
      final tracks = _currentPlayingTracks;
      final idx = _currentIndex;
      if (tracks != null && idx >= 0 && idx < tracks.length) {
        _currentPlayingTracks = [tracks[idx]];
        if (_shuffleEnabled) {
          _shuffledPlaylist = List.from(_currentPlayingTracks!);
        }
        _currentIndex = 0;
      }
    }
    debugPrint(
        "Queue cleared (autoqueue upcoming ${_isAutoQueueContext ? 'kept' : 'emptied'}).");
    notifyListeners();
  }

  /// v5.2: clear affordance enabled only while something is actually
  /// upcoming (user queue entries or autoqueue tracks).
  bool get canClearQueue {
    if (_queue.isNotEmpty) return true;
    if (!_isAutoQueueContext) return false;
    final list = _getActivePlaylist();
    return _currentIndex >= 0 && _currentIndex < list.length - 1;
  }

  // Lyrics prefetch for upcoming tracks
  void _prefetchUpcomingLyrics() {
    if (_currentIndex < 0) return;

    final playlist = _getActivePlaylist();
    if (playlist.isEmpty) return;

    final upcoming = <Map<String, String>>[];

    // Add next 3 tracks from playlist
    for (int i = 1; i <= 3; i++) {
      final nextIndex = _currentIndex + i;
      if (nextIndex < playlist.length) {
        final track = playlist[nextIndex];
        upcoming.add({
          'title': track.trackName,
          'artist': track.artistName,
          'videoId': track.source == 'youtube' ? track.id : null,
        }.map((key, value) => MapEntry(key, value ?? '')));
      }
    }

    // Also add queue items
    for (int i = 0; i < 3 && i < _queue.length; i++) {
      final track = _queue[i];
      upcoming.add({
        'title': track.trackName,
        'artist': track.artistName,
        'videoId': track.source == 'youtube' ? track.id : null,
      }.map((key, value) => MapEntry(key, value ?? '')));
    }

    if (upcoming.isNotEmpty) {
      _lyricsService.prefetchLyrics(upcoming);
    }
  }

  // --- Internal Metadata Fetchers (with Caching) ---
  final Map<String, Artist> _artistCache = {};
  final Map<String, Album> _albumCache = {};

  /// Keeps insertion-ordered caches bounded (FIFO eviction).
  static void _capCache<K, V>(Map<K, V> cache, int max) {
    while (cache.length > max) {
      cache.remove(cache.keys.first);
    }
  }

  Future<Artist?> _fetchArtistInternal(String artistName) async {
    // 1. Check Cache
    if (_artistCache.containsKey(artistName)) {
      if (kDebugMode)
        debugPrint("MusicProvider: Cache hit for artist $artistName");
      return _artistCache[artistName];
    }

    try {
      // 2. Fetch Logic
      final searchResults =
          await _innerTubeService.searchArtists(artistName, limit: 1);
      if (searchResults.isEmpty) return null;

      final artistInfo = searchResults.first;
      final detailsMap =
          await _innerTubeService.getArtistDetails(artistInfo.id);

      // FIX: For artist search results, the artist's name is in trackName, not artistName
      final artist = Artist(
        id: artistInfo.id,
        name:
            artistInfo.trackName.isNotEmpty ? artistInfo.trackName : artistName,
        imageUrl: artistInfo.albumArtUrl,
        topTracks: (detailsMap['tracks'] as List?)?.cast<Track>(),
        topAlbums: (detailsMap['albums'] as List?)?.cast<Album>(),
      );

      // 3. Cache Result
      _artistCache[artistName] = artist;
      _capCache(_artistCache, 100);
      return artist;
    } catch (e) {
      if (kDebugMode)
        debugPrint("MusicProvider: Internal artist fetch error: $e");
      return null;
    }
  }

  Future<Album?> _fetchAlbumInternal(
      String albumName, String artistName) async {
    final key = '$albumName|$artistName';

    // 1. Check Cache
    if (_albumCache.containsKey(key)) {
      if (kDebugMode)
        debugPrint("MusicProvider: Cache hit for album $albumName");
      return _albumCache[key];
    }

    try {
      // 2. Fetch Logic (Legacy implementation for valid tracks)
      final tracks = await _innerTubeService
          .searchSongs('$albumName $artistName', limit: 30);

      if (tracks.isNotEmpty) {
        final first = tracks.first;
        final album = Album(
          id: 'album_${first.artistName}_${first.albumName}'
              .replaceAll(' ', '_'),
          name: first.albumName.isNotEmpty ? first.albumName : albumName,
          artistName:
              first.artistName.isNotEmpty ? first.artistName : artistName,
          imageUrl: first.albumArtUrl,
          tracks: tracks,
        );

        // 3. Cache Result
        _albumCache[key] = album;
        _capCache(_albumCache, 100);
        return album;
      }
      return null;
    } catch (e) {
      if (kDebugMode)
        debugPrint("MusicProvider: Internal album fetch error: $e");
      return null;
    }
  }

  // --- Public Prefetcher ---
  Future<void> prefetchMetadata(Track track) async {
    if (track.artistName.isEmpty) return;

    // Fire and forget - don't await in UI thread
    _fetchArtistInternal(track.artistName);

    if (track.albumName.isNotEmpty) {
      _fetchAlbumInternal(track.albumName, track.artistName);
    }
  }

  // --- Optimized Navigation Methods ---
  Future<void> navigateToArtist(String artistName) async {
    if (kDebugMode)
      debugPrint("PROVIDER ACTION: Navigate to Artist: $artistName");
    _isLoadingArtist = true;
    _currentArtistDetails = null; // Clear old
    _errorMessage = null;
    notifyListeners();

    try {
      final artist = await _fetchArtistInternal(artistName);
      if (artist != null) {
        _currentArtistDetails = artist;
      } else {
        throw Exception("Artist not found");
      }
    } catch (e) {
      _errorMessage = "Could not load artist details.";
      _currentArtistDetails = null;
    } finally {
      _isLoadingArtist = false;
      notifyListeners();
    }
  }

  /// Robust navigation using an existing Artist/Track object from search results
  /// Deep-link helper: resolve a videoId to a playable track and play it.
  Future<void> playTrackById(String id) async {
    try {
      final results = await _innerTubeService.searchSongs(id, limit: 3);
      final resolved = results.where((t) => t.id == id).toList();
      final track = resolved.isNotEmpty
          ? resolved.first
          : Track(
              id: id,
              trackName: 'Shared track',
              artistName: '',
              albumName: '',
              previewUrl: '',
              source: 'youtube',
            );
      await playTrack(track);
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: playTrackById failed: $e');
    }
  }

  /// Deep-link helper: load artist details by browse ID (no name needed).
  Future<void> navigateToArtistById(String id) async {
    _isLoadingArtist = true;
    _currentArtistDetails = null;
    notifyListeners();
    try {
      final detailsMap = await _innerTubeService.getArtistDetails(id);
      final tracks = (detailsMap['tracks'] as List?)?.cast<Track>();
      final albums = (detailsMap['albums'] as List?)?.cast<Album>();
      final name = (detailsMap['name'] as String?) ??
          (tracks?.isNotEmpty == true ? tracks!.first.artistName : '');
      _currentArtistDetails = Artist(
        id: id,
        name: name,
        imageUrl: '',
        topTracks: tracks,
        topAlbums: albums,
      );
    } catch (e) {
      _errorMessage = 'Could not load artist details.';
      _currentArtistDetails = null;
    } finally {
      _isLoadingArtist = false;
      notifyListeners();
    }
  }

  Future<void> navigateToArtistObject(Track artistTrack) async {
    if (kDebugMode)
      debugPrint(
          "PROVIDER ACTION: Navigate to Artist Object: ${artistTrack.trackName} (${artistTrack.id})");
    _isLoadingArtist = true;
    _currentArtistDetails = null;
    _errorMessage = null;
    notifyListeners();

    try {
      // Check cache first using name
      if (_artistCache.containsKey(artistTrack.trackName)) {
        _currentArtistDetails = _artistCache[artistTrack.trackName];
        if (kDebugMode)
          debugPrint(
              "MusicProvider: Cache hit for artist object ${artistTrack.trackName}");
        return;
      }

      // 1. Use ID directly
      final browseId = artistTrack.id;

      // 2. Fetch full details
      final detailsMap = await _innerTubeService.getArtistDetails(browseId);

      // 3. Construct Artist
      _currentArtistDetails = Artist(
        id: browseId,
        name: artistTrack.trackName,
        imageUrl: artistTrack.albumArtUrl,
        topTracks: (detailsMap['tracks'] as List?)?.cast<Track>(),
        topAlbums: (detailsMap['albums'] as List?)?.cast<Album>(),
      );

      // Cache it
      _artistCache[artistTrack.trackName] = _currentArtistDetails!;
      _capCache(_artistCache, 100);

      debugPrint(
          "PROVIDER: Artist info loaded for ${_currentArtistDetails?.name}");
    } catch (e) {
      _errorMessage = "Could not load artist details.";
      if (kDebugMode) debugPrint("PROVIDER ERROR: $e");
      _currentArtistDetails = null;
    } finally {
      _isLoadingArtist = false;
      notifyListeners();
    }
  }

  Future<void> navigateToAlbum(String albumName, String artistName) async {
    if (kDebugMode)
      debugPrint(
          "PROVIDER ACTION: Navigate to Album: $albumName by $artistName");
    _isLoadingAlbum = true;
    _currentAlbumDetails = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final album = await _fetchAlbumInternal(albumName, artistName);
      if (album != null) {
        _currentAlbumDetails = album;
      } else {
        throw Exception("Album not found");
      }
    } catch (e) {
      _errorMessage = "Could not load album details.";
      _currentAlbumDetails = null;
    } finally {
      _isLoadingAlbum = false;
      notifyListeners();
    }
  }

  // --- Network & Mode Management ---
  void _setupConnectivityMonitoring() {
    _networkQualitySubscription = _networkService.onNetworkQualityChanged
        .listen((q) => _handleNetworkQualityChange(q),
            onError: (e) => debugPrint("NetQual stream error: $e"));
    _connectivityStatusSubscription = _networkService.onConnectivityChanged
        .listen((c) => _handleConnectivityChange(c),
            onError: (e) => debugPrint("Connect stream error: $e"));
    _networkService.checkNetworkQualityNow().then((q) {
      _handleNetworkQualityChange(q);
      _handleConnectivityChange(q != NetworkQuality.offline);
    });
  }

  void _handleNetworkQualityChange(NetworkQuality quality) {
    // Adjust bitrates based on network quality (existing logic)
    // Adjust bitrates based on network quality ONLY if Auto Mode is enabled
    if (!_isLowDataMode && _isAutoBitrate) {
      int nW = _wifiBitrate, nC = _cellularBitrate;
      switch (quality) {
        case NetworkQuality.poor:
          nW = nC = NetworkConfig.poorNetworkBitrate;
          break;
        case NetworkQuality.moderate:
          nW = NetworkConfig.moderateNetworkBitrate;
          nC = NetworkConfig.poorNetworkBitrate;
          break;
        case NetworkQuality.good:
          nW = NetworkConfig.goodNetworkBitrate;
          nC = NetworkConfig.moderateNetworkBitrate;
          break;
        case NetworkQuality.excellent:
          nW = NetworkConfig.excellentNetworkBitrate;
          nC = NetworkConfig.goodNetworkBitrate;
          break;
        default:
          break;
      }
      if (nW != _wifiBitrate || nC != _cellularBitrate) {
        _wifiBitrate = nW;
        _cellularBitrate = nC;
        _saveSettings(); // Save bitrate settings
        if (kDebugMode)
          debugPrint(
              "MusicProvider: Auto-adjusted bitrate to Wifi:$_wifiBitrate, Cell:$_cellularBitrate");
      }
    }

    // The following lines related to calling _audioService.configureBufferSettings are now removed
    // as that method in AudioService is commented out.
    // // Only configure if playing online content
    // if (currentTrack != null && !_isOfflineTrack) {
    //     _audioService.configureBufferSettings(
    //         bufferDuration: const Duration(seconds: 30),
    //         minBufferDuration: const Duration(seconds: 5),
    //         maxBufferDuration: const Duration(seconds: 60)
    //     );
    // }
    // No need to notifyListeners() here as this primarily affects background player behavior
  }

  void _handleConnectivityChange(bool isConnected) {
    if (!isConnected && !_isOfflineMode) {
      _isOfflineMode = true;
      _userManuallySetOffline = false;
      _saveSettings();
      _showOfflineModeNotification('Connection lost.');
      _switchToOfflineVersionIfAvailable();
      pauseAllDownloads();
      notifyListeners();
    } else if (isConnected && _isOfflineMode && !_userManuallySetOffline) {
      goOnline();
    } else if (isConnected && _isOfflineMode && _userManuallySetOffline) {
      if (!_isReconnecting) _showReconnectionPrompt();
      _processRetryQueue();
      _downloads.processQueue();
    } else if (isConnected && !_isOfflineMode) {
      if (_isReconnecting) {
        _isReconnecting = false;
        _errorMessage = null;
        notifyListeners();
      }
      _processRetryQueue();
      _downloads.processQueue();
    }
  }

  void goOnline() {
    if (_isOfflineMode) {
      bool wasOffline = _isOfflineMode;
      _isOfflineMode = false;
      _userManuallySetOffline = false;
      _isReconnecting = false;
      _saveSettings();
      _errorMessage = 'You are now online.';
      notifyListeners();
      if (wasOffline) _refreshDataOnReconnect();
      _processRetryQueue();
      _downloads.processQueue();
    }
  }

  void goOffline() {
    if (!_isOfflineMode) {
      _isOfflineMode = true;
      _userManuallySetOffline = true;
      _isReconnecting = false;
      _saveSettings();
      _showOfflineModeNotification('Offline mode enabled.');
      _switchToOfflineVersionIfAvailable();
      pauseAllDownloads();
      notifyListeners();
    }
  }

  void toggleOfflineMode() => _isOfflineMode ? goOnline() : goOffline();
  void toggleLowDataMode() {
    _isLowDataMode = !_isLowDataMode;
    if (_isLowDataMode) {
      _wifiBitrate = NetworkConfig.moderateNetworkBitrate;
      _cellularBitrate = NetworkConfig.poorNetworkBitrate;
      _errorMessage = "Low data mode enabled.";
    } else {
      _handleNetworkQualityChange(_networkService.networkQuality);
      _errorMessage = "Low data mode disabled.";
    }
    _saveSettings();
    notifyListeners();
  }

  void _showReconnectionPrompt() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    _errorMessage = 'Internet available. Tap to go online.';
    notifyListeners();
  }

  void _showOfflineModeNotification(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  Future<void> _refreshDataOnReconnect() async {
    try {
      await fetchTracks(forceRefresh: true);
    } catch (_) {}
    try {
      await fetchTrendingTracks(forceRefresh: true);
    } catch (_) {}
  }

  Future<bool> _switchToOfflineVersionIfAvailable() async {
    if (_currentTrack == null || _isOfflineTrack) return false;
    final downloadedPath = await getDownloadedTrackPath(_currentTrack!.id);
    final isLocalSource = _currentTrack!.source == 'local';
    final String? offlinePath =
        isLocalSource ? _currentTrack!.previewUrl : downloadedPath;
    if (offlinePath != null && offlinePath.isNotEmpty) {
      try {
        final currentPosition = _position;
        await _audioService.stop();
        await _audioService.playLocalFile(offlinePath);
        _isOfflineTrack = true;
        _isPlaying = true;
        if (currentPosition > Duration.zero &&
            _duration > Duration.zero &&
            currentPosition < _duration)
          await _audioService.seekTo(currentPosition);
        notifyListeners();
        return true;
      } catch (e) {
        await _handlePlaybackError("Error playing offline file.");
        return true;
      }
    } else {
      await pauseTrack();
      _errorMessage = "Playback paused: Offline & not downloaded.";
      notifyListeners();
      return true;
    }
  }

  // --- Liked Songs ---
  bool isSongLiked(String trackId) => _likedSongs.any((t) => t.id == trackId);
  void likeSong(Track track) {
    if (!isSongLiked(track.id)) {
      _likedSongs.insert(0, track);
      _saveLikedSongs();
      notifyListeners();
    }
  }

  void unlikeSong(String trackId) {
    int count = _likedSongs.length;
    _likedSongs.removeWhere((t) => t.id == trackId);
    if (_likedSongs.length < count) {
      _saveLikedSongs();
      notifyListeners();
    }
  }

  void toggleLike(Track track) =>
      isSongLiked(track.id) ? unlikeSong(track.id) : likeSong(track);
  Future<void> _loadLikedSongs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('likedSongs');
      if (s != null)
        _likedSongs = (await compute(_jsonDecode, s))
            .map((j) => Track.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
    } catch (_) {
      _likedSongs = [];
    }
  }

  Future<void> _saveLikedSongs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          'likedSongs',
          await compute(
              _jsonEncode, _likedSongs.map((t) => t.toJson()).toList()));
    } catch (e) {
      _addToRetryQueue(_RetryOperation('Save liked', _saveLikedSongs));
    }
  }

  // --- Recently Played ---
  void _recordSearchFollowup(Track track) {
    // Spec #7: attribute plays to search queries within the window.
    final query = _pendingSearchQuery;
    final at = _searchQueryAt;
    if (query == null || query.isEmpty || at == null) return;
    if (DateTime.now().difference(at) > _searchFollowupWindow) {
      _pendingSearchQuery = null;
      return;
    }
    _searchGraph.recordTransition(query, track.id, track.artistName);
    if (kDebugMode) {
      debugPrint(
          'SEARCH_FOLLOWUP: query="$query" → track="${track.trackName}" (${track.id})');
    }
  }

  void _updateRecentlyPlayed(Track track) async {
    _recentlyPlayed.removeWhere((t) => t.id == track.id);
    _recentlyPlayed.insert(0, track);
    if (_recentlyPlayed.length > 20)
      _recentlyPlayed = _recentlyPlayed.take(20).toList();
    await _saveRecentlyPlayed();
    _bumpHomeContent();
  }

  void removeFromRecentlyPlayed(String trackId) {
    int count = _recentlyPlayed.length;
    _recentlyPlayed.removeWhere((t) => t.id == trackId);
    if (_recentlyPlayed.length < count) {
      _saveRecentlyPlayed();
      notifyListeners();
    }
  }

  Future<void> _loadRecentlyPlayed() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('recentlyPlayed');
      if (s != null)
        _recentlyPlayed = (await compute(_jsonDecode, s))
            .map((j) => Track.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
    } catch (_) {
      _recentlyPlayed = [];
    }
  }

  Future<void> _saveRecentlyPlayed() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          'recentlyPlayed',
          await compute(
              _jsonEncode, _recentlyPlayed.map((t) => t.toJson()).toList()));
    } catch (e) {
      _addToRetryQueue(_RetryOperation('Save recent', _saveRecentlyPlayed));
    }
  }

  // --- Bitrate Settings ---
  // --- Bitrate Settings ---
  void setWifiBitrate(int bitrate) {
    if (_wifiBitrate != bitrate || _isAutoBitrate) {
      _wifiBitrate = bitrate;
      _isAutoBitrate = false; // Manual override disables Auto
      _saveSettings();
      notifyListeners();
    }
  }

  void setCellularBitrate(int bitrate) {
    if (_cellularBitrate != bitrate || _isAutoBitrate) {
      _cellularBitrate = bitrate;
      _isAutoBitrate = false; // Manual override disables Auto
      _saveSettings();
      notifyListeners();
    }
  }

  void setAutoBitrate(bool enable) {
    if (_isAutoBitrate != enable) {
      _isAutoBitrate = enable;
      if (enable) {
        // Trigger immediate check to apply auto settings
        _handleNetworkQualityChange(_networkService.networkQuality);
      }
      _saveSettings();
      notifyListeners();
    }
  }

  void setMusicSource(MusicSource source) {
    if (_currentMusicSource != source) {
      if (kDebugMode) {
        debugPrint(
            'MusicProvider: Switching music source from ${_currentMusicSource.displayName} to ${source.displayName}');
      }
      _currentMusicSource = source;
      _saveSettings();

      // Clear caches when switching sources
      _cachedTracks.clear();
      _tracks = [];
      _trendingTracks = [];
      _fullTrendingTracks = [];

      notifyListeners(); // Immediate update for UI switch

      // OPTIMIZED RELOAD LOGIC
      if (source == MusicSource.local) {
        // Immediately load local files if empty
        if (_localTracks.isEmpty) {
          loadLocalMusicFiles();
        }
      } else if (_networkService.isConnected && !_isOfflineMode) {
        // Only fetch if online
        fetchTracks(forceRefresh: true);
        fetchTrendingTracks(forceRefresh: true);
      }
    }
  }

  Future<int> _getBitrate() async {
    if (_isOfflineMode || !_networkService.isConnected) return 0;
    if (_isLowDataMode) return min(_cellularBitrate, _wifiBitrate);
    final type = await _networkService.getConnectionType();
    return (type == ConnectivityResult.wifi) ? _wifiBitrate : _cellularBitrate;
  }

  // --- Local Music ---
  Future<void> loadLocalMusicFiles({bool forceRescan = false}) async {
    if (_isLoadingLocal && !forceRescan) return;
    _isLoadingLocal = true;
    notifyListeners();
    try {
      _localTracks = await _localMusicService.fetchLocalMusicFromMediaStore();
      _localTracks =
          LocalMusicService.sortTracks(_localTracks, _localTracksSortCriteria);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load local files: ${e.toString()}';
      _localTracks = [];
    } finally {
      _isLoadingLocal = false;
      notifyListeners();
    }
  }

  void sortLocalTracks(SortCriteria criteria) {
    if (_localTracksSortCriteria == criteria && _localTracks.isNotEmpty) return;
    _localTracksSortCriteria = criteria;
    _localTracks = LocalMusicService.sortTracks(_localTracks, criteria);
    _saveSettings();
    notifyListeners();
  }

  Future<void> addLocalMusicFolder() async {
    String? iMsg = "Adding folder...";
    _errorMessage = iMsg;
    notifyListeners();
    try {
      final String? p = await _localMusicService.pickDirectory();
      if (p != null) {
        await loadLocalMusicFiles(forceRescan: true);
        if (_errorMessage == iMsg) _errorMessage = "Local music refreshed.";
      } else if (_errorMessage == iMsg) _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to add folder: ${e.toString()}';
    } finally {
      notifyListeners();
    }
  }

  // --- Playlist Management ---
  Future<void> loadUserPlaylists() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('userPlaylists');
      if (s != null)
        _userPlaylists = (await compute(_jsonDecode, s))
            .map((j) => Playlist.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
      _bumpHomeContent();
    } catch (_) {
      _userPlaylists = [];
    }
  }

  Future<void> saveUserPlaylists() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          'userPlaylists',
          await compute(
              _jsonEncode, _userPlaylists.map((pl) => pl.toJson()).toList()));
    } catch (e) {
      _addToRetryQueue(_RetryOperation('Save playlists', saveUserPlaylists));
    }
  }

  Future<void> createPlaylist(String name,
      {List<Track>? initialTracks, String? imageUrl}) async {
    if (name.trim().isEmpty) {
      _errorMessage = "Name empty.";
      notifyListeners();
      return;
    }
    try {
      final pl = Playlist(
          id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
          name: name.trim(),
          imageUrl: imageUrl ?? '',
          tracks: initialTracks ?? []);
      _userPlaylists.add(pl);
      await saveUserPlaylists();
      _errorMessage = "Playlist created.";
      notifyListeners();
    } catch (e, stack) {
      debugPrint("Error creating playlist: $e\n$stack");
      // PROACTIVE FIX: Showing runtimeType to identify "Instance of" errors
      _errorMessage = 'Failed to create (${e.runtimeType}): $e';
      notifyListeners();
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    final i = _userPlaylists.indexWhere((p) => p.id == playlistId);
    if (i < 0) return;
    try {
      _userPlaylists.removeAt(i);
      await saveUserPlaylists();
      if (_currentPlaylistId == playlistId) await stopTrack();
      _errorMessage = "Playlist deleted.";
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete (${e.runtimeType}): $e';
      notifyListeners();
    }
  }

  Future<void> renamePlaylist(String playlistId, String newName) async {
    if (newName.trim().isEmpty) {
      _errorMessage = "Name empty.";
      notifyListeners();
      return;
    }
    final i = _userPlaylists.indexWhere((p) => p.id == playlistId);
    if (i < 0) return;
    try {
      _userPlaylists[i] = _userPlaylists[i].copyWith(name: newName.trim());
      await saveUserPlaylists();
      _errorMessage = "Renamed.";
      notifyListeners();
    } catch (e) {
      _errorMessage = "Failed to rename (${e.runtimeType}): $e";
      notifyListeners();
    }
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    final i = _userPlaylists.indexWhere((p) => p.id == playlistId);
    if (i < 0) {
      _errorMessage = "Playlist not found.";
      notifyListeners();
      return;
    }
    final pl = _userPlaylists[i];
    if (pl.tracks.any((t) => t.id == track.id)) {
      _errorMessage = "Already in playlist.";
      notifyListeners();
      return;
    }
    try {
      // Create a clean copy of the track to ensure no transient fields cause issues
      final cleanTrack = track.copyWith();
      _userPlaylists[i] = pl.copyWith(tracks: [...pl.tracks, cleanTrack]);
      await saveUserPlaylists();
      _errorMessage = "Added to ${pl.name}.";
      notifyListeners();
    } catch (e, stack) {
      debugPrint("Error adding to playlist: $e\n$stack");
      _errorMessage = 'Failed to add track (${e.runtimeType}): $e';
      notifyListeners();
    }
  }

  Future<void> removeTrackFromPlaylist(
      String playlistId, String trackId) async {
    final i = _userPlaylists.indexWhere((p) => p.id == playlistId);
    if (i < 0) return;
    final pl = _userPlaylists[i];
    final tN =
        pl.tracks.firstWhereOrNull((t) => t.id == trackId)?.trackName ?? '?';
    try {
      final uT = pl.tracks.where((t) => t.id != trackId).toList();
      if (uT.length < pl.tracks.length) {
        _userPlaylists[i] = pl.copyWith(tracks: uT);
        await saveUserPlaylists();
        _errorMessage = "Removed '$tN'.";
        if (_currentPlaylistId == playlistId && _currentTrack?.id == trackId)
          await skipToNext();
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to remove track: $e';
      notifyListeners();
    }
  }

  Future<void> importPlaylist(Playlist playlist) async {
    try {
      final i = _userPlaylists.indexWhere((p) => p.id == playlist.id);
      if (i >= 0) {
        _userPlaylists[i] = playlist;
      } else {
        _userPlaylists.add(playlist);
      }
      await saveUserPlaylists();
      _errorMessage = "Imported '${playlist.name}'.";
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to import playlist.';
      _addToRetryQueue(_RetryOperation(
          'Import: ${playlist.name}', () => importPlaylist(playlist)));
      notifyListeners();
    }
  }

  // --- Downloading (delegates to DownloadManager) ---
  Future<void> downloadTrack(Track track) => _downloads.downloadTrack(track);
  void cancelDownload(String trackId) => _downloads.cancelDownload(trackId);
  Future<void> deleteDownloadedTrack(String trackId) =>
      _downloads.deleteDownloadedTrack(trackId);
  Future<bool> isTrackDownloaded(String trackId) =>
      _downloads.isTrackDownloaded(trackId);
  Future<String?> getDownloadedTrackPath(String trackId) =>
      _downloads.getDownloadedTrackPath(trackId);
  Future<List<Track>> getDownloadedTracks() => _downloads.getDownloadedTracks();
  Future<void> saveDownloadedTracksMetadata() => _downloads.saveMetadata();
  void pauseAllDownloads({bool clearQueue = false}) =>
      _downloads.pauseAllDownloads(clearQueue: clearQueue);
  Future<Directory> getDownloadsDirectory() =>
      _downloads.getDownloadsDirectory();

  /// Palette engine recovers legacy artwork from the download store.
  Future<String?> recoverDownloadedArtPath(String trackId) async {
    final meta = _downloads.metadata[trackId];
    if (meta == null) return null;
    final ap = meta['artPath'] as String?;
    if (ap != null && ap.isNotEmpty && await File(ap).exists()) return ap;
    final fp = meta['filePath'] as String?;
    if (fp == null) return null;
    final legacy = fp.replaceAll('.mp3', '.jpg');
    return await File(legacy).exists() ? legacy : null;
  }

  /// Batch download multiple tracks - adds to queue efficiently
  Future<void> downloadTracks(List<Track> tracks,
      {bool skipDownloaded = true}) async {
    int added = 0;
    for (final track in tracks) {
      if (skipDownloaded && await isTrackDownloaded(track.id)) continue;
      if (_downloads.isDownloadingSync(track.id)) continue;
      if (_downloads.downloadQueue.any((t) => t.id == track.id)) continue;
      if (track.source == 'local') continue;
      unawaited(_downloads
          .downloadTrack(track)); // manager enforces concurrency + queue
      added++;
    }
    if (added > 0) {
      _errorMessage = 'Queued $added tracks for download';
      notifyListeners();
    }
  }
  // --- Spotify Integration ---

  // --- API Content Fetching ---

  // Recently shown track IDs for diversity (persisted)
  final List<String> _recentlyShownTrackIds = [];
  static const int _maxRecentlyShown = 200;

  Future<List<Track>> fetchTracks({bool forceRefresh = false}) async {
    const k = 'popular_music';
    final now = DateTime.now();

    if (!forceRefresh && _cachedTracks.containsKey(k)) {
      final cachedTime = _discoveryCacheTimes[k];
      if (cachedTime != null &&
          now.difference(cachedTime) < _discoveryCacheTTL) {
        return _cachedTracks[k]!;
      }
    }

    if (_isOfflineMode || _currentMusicSource == MusicSource.local) {
      _errorMessage = "Offline: No new tracks.";
      notifyListeners();
      return _tracks;
    }
    try {
      // ENHANCED: Fetch personalized content based on recently played seeds
      final personalized = await _fetchPersonalizedForYou();

      // PHASE 2 FIX: Filter and apply diversity + AI ranking
      final processed = _processForYouTracks(personalized, 20);

      _tracks = processed;
      _recommendedTracks = processed;
      _bumpHomeContent();
      _cachedTracks[k] = _tracks;
      _capCache(_cachedTracks, 60);
      _discoveryCacheTimes[k] = now;
      notifyListeners();
      return _tracks;
    } catch (e) {
      _errorMessage = 'Failed to load tracks.';
      _addToRetryQueue(_RetryOperation(
          'Fetch tracks', () => fetchTracks(forceRefresh: true)));
      notifyListeners();
      return _tracks;
    }
  }

  /// Fetch personalized For You content using recently played as seeds
  Future<List<Track>> _fetchPersonalizedForYou() async {
    final allTracks = <Track>[];
    final seenIds = <String>{};

    // Get recently played tracks as seeds (up to 5)
    final seeds = _recentlyPlayed.take(5).toList();

    if (seeds.isNotEmpty) {
      // Fetch related tracks from multiple seeds for variety
      for (final seed in seeds.take(3)) {
        try {
          String? seedId = (seed.source == 'youtube' && seed.id.length == 11) ? seed.id : null;
          if (seedId == null) {
            final results = await _innerTubeService.searchSongs(
                '${seed.trackName} ${seed.artistName}',
                limit: 1);
            if (results.isNotEmpty && results.first.id.length == 11) {
              seedId = results.first.id;
            }
          }
          if (seedId != null) {
            final related =
                await _innerTubeService.getSuggestions(seedId, limit: 15);
            for (final track in related) {
              if (!seenIds.contains(track.id)) {
                seenIds.add(track.id);
                allTracks.add(track);
              }
            }
          }
        } catch (e) {
          if (kDebugMode)
            debugPrint(
                'MusicProvider: Error fetching related for ${seed.trackName}: $e');
        }
      }

      // Also fetch from liked songs if available
      final likedSeeds = _likedSongs.take(2).where((t) =>
          t.source == 'youtube' &&
          t.id.length == 11 &&
          !seenIds.contains(t.id));

      for (final seed in likedSeeds) {
        try {
          final related =
              await _innerTubeService.getSuggestions(seed.id, limit: 10);
          for (final track in related) {
            if (!seenIds.contains(track.id)) {
              seenIds.add(track.id);
              allTracks.add(track);
            }
          }
        } catch (e) {
          if (kDebugMode)
            debugPrint(
                'MusicProvider: Error fetching related for liked ${seed.trackName}: $e');
        }
      }
    }

    // Discovery seed: reuse the structured Home feed's parsed items when
    // available — one Home pipeline (spec #50) instead of a second
    // flattened getHomeTracks call. Falls back to the legacy flattened
    // call only when no feed exists yet.
    try {
      final feed = _homeFeed;
      final List<Track> discoveryTracks;
      if (feed != null) {
        discoveryTracks = feed.sections
            .expand((s) => s.items)
            .where((i) => i.videoId != null)
            .map((i) => Track(
                  id: i.videoId!,
                  trackName: i.title,
                  artistName:
                      i.artists.isNotEmpty ? i.artists.join(', ') : i.subtitle,
                  albumName: '',
                  previewUrl: '',
                  albumArt: i.artworkUrl,
                  source: 'youtube',
                ))
            .toList();
      } else {
        discoveryTracks = await _innerTubeService.getHomeTracks(limit: 20);
      }
      for (final track in discoveryTracks) {
        if (!seenIds.contains(track.id)) {
          seenIds.add(track.id);
          allTracks.add(track);
        }
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('MusicProvider: Error fetching home tracks: $e');
    }

    // If no seeds available, just use home tracks
    if (allTracks.isEmpty) {
      return await _innerTubeService.getHomeTracks(limit: 50);
    }

    return allTracks;
  }

  /// Process For You tracks: filter, diversify, and rank with AI
  List<Track> _processForYouTracks(List<Track> raw, int limit) {
    // 0. DEDUPLICATE: Remove duplicate track IDs (keep first occurrence)
    final seenIds = <String>{};
    final deduped = <Track>[];
    for (final track in raw) {
      if (!seenIds.contains(track.id)) {
        seenIds.add(track.id);
        deduped.add(track);
      }
    }

    // 1. FILTER: Only tracks (not albums/playlists)
    // Valid YouTube video IDs are 11 characters and don't start with PL/VL/UC
    final tracks = deduped.where((t) {
      final id = t.id;
      if (id.length != 11) return false;
      if (id.startsWith('PL') || id.startsWith('VL') || id.startsWith('UC'))
        return false;
      if (t.trackName.isEmpty || t.artistName.isEmpty) return false;
      return true;
    }).toList();

    if (tracks.isEmpty) return raw.take(limit).toList();

    // 2. DIVERSITY: Filter out recently shown tracks first
    final recentSet = _recentlyShownTrackIds.toSet();
    final notRecentlyShown =
        tracks.where((t) => !recentSet.contains(t.id)).toList();
    final recentlyShown =
        tracks.where((t) => recentSet.contains(t.id)).toList();

    // 3. AI RANKING: Apply hybrid recommendation scoring
    final rankedFresh =
        _recommendationService.rankTracks(notRecentlyShown, limit: limit);

    // 4. If we don't have enough fresh tracks, add from recently shown
    List<Track> result;
    if (rankedFresh.length >= limit) {
      result = rankedFresh.take(limit).toList();
    } else {
      final remaining = limit - rankedFresh.length;
      final rankedRecent =
          _recommendationService.rankTracks(recentlyShown, limit: remaining);
      result = [...rankedFresh, ...rankedRecent];
    }

    // 5. Record shown and ensure absolute uniqueness
    final finalResult = <Track>[];
    final finalSeen = <String>{};

    for (final track in result) {
      if (!finalSeen.contains(track.id)) {
        finalSeen.add(track.id);
        finalResult.add(track);
      }
    }

    _recordShownTracks(finalResult);

    return finalResult;
  }

  /// Record shown tracks for diversity penalty
  void _recordShownTracks(List<Track> tracks) {
    for (final track in tracks) {
      if (!_recentlyShownTrackIds.contains(track.id)) {
        _recentlyShownTrackIds.add(track.id);
      }
    }

    // Trim to max size (LRU-style)
    while (_recentlyShownTrackIds.length > _maxRecentlyShown) {
      _recentlyShownTrackIds.removeAt(0);
    }

    // Persist asynchronously
    _saveRecentlyShownIds();
  }

  /// Load recently shown IDs from SharedPreferences
  Future<void> _loadRecentlyShownIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList('recently_shown_track_ids') ?? [];
      _recentlyShownTrackIds.clear();
      _recentlyShownTrackIds.addAll(ids);
    } catch (e) {
      if (kDebugMode)
        debugPrint('MusicProvider: Error loading recently shown IDs: $e');
    }
  }

  /// Save recently shown IDs to SharedPreferences
  Future<void> _saveRecentlyShownIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          'recently_shown_track_ids', _recentlyShownTrackIds);
    } catch (e) {
      if (kDebugMode)
        debugPrint('MusicProvider: Error saving recently shown IDs: $e');
    }
  }

  Future<List<Track>> fetchTrendingTracks({bool forceRefresh = false}) async {
    const k = 'trending_music';
    final now = DateTime.now();

    if (!forceRefresh && _cachedTracks.containsKey(k)) {
      final cachedTime = _discoveryCacheTimes[k];
      if (cachedTime != null &&
          now.difference(cachedTime) < _discoveryCacheTTL) {
        _fullTrendingTracks = _cachedTracks[k]!;
        _trendingTracks = _fullTrendingTracks.take(5).toList();
        return _fullTrendingTracks;
      }
    }
    if (_isOfflineMode || _currentMusicSource == MusicSource.local) {
      _errorMessage = "Offline: No trending.";
      notifyListeners();
      return _fullTrendingTracks;
    }
    try {
      // Use InnerTube for trending tracks (trusted chart source). The
      // v2 engine validates + dedupes; NO taste profile involved (spec
      // #48: personal favorites never become Trending).
      final chart = await _innerTubeService.getTrendingTracks(limit: 20);
      final picked = const TrendingEngineV2().generate(
        regionalChart: chart,
        globalChart: const [],
        limit: 20,
      );
      _fullTrendingTracks = picked.map((c) => c.track).toList();
      _cachedTracks[k] = _fullTrendingTracks;
      _capCache(_cachedTracks, 60);
      _discoveryCacheTimes[k] = now;
      _trendingTracks = _fullTrendingTracks.take(5).toList();
      _bumpHomeContent();
      // Chart arrival → recompute picks so the popularity prior is real
      // (spec #36/#19) instead of leaving native-only filler.
      if (_homeFeed != null) _generateQuickPicks(_homeFeed!);
      notifyListeners();
      return _fullTrendingTracks;
    } catch (e) {
      _errorMessage = 'Failed to load trending.';
      _addToRetryQueue(_RetryOperation(
          'Fetch trending', () => fetchTrendingTracks(forceRefresh: true)));
      notifyListeners();
      return _fullTrendingTracks;
    }
  }

  // Method for generic track search, used by SearchTabContent
  Future<List<Track>> searchTracks(String query,
      {bool forceRefresh = false}) async {
    // Spec #7: remember the query for play-followup attribution.
    _pendingSearchQuery = query.trim();
    _searchQueryAt = DateTime.now();
    // Spec #61: search intent feeds Quick Picks ranking.
    _rememberSearchQuery(query);
    // Search using the appropriate service based on current music source
    if (_isOfflineMode && !_networkService.isConnected) {
      _beginSearchSession(query, kind: SearchKind.songs);
      final gen = _searchGeneration;
      _errorMessage = "Offline: Cannot perform search.";
      _searchedTracks = [];
      _finishSearchSession(gen, hasResults: false, error: _errorMessage);
      return []; // Return empty list in offline mode
    }

    if (query.trim().isEmpty) {
      _searchedTracks = [];
      _resetSearchSession();
      notifyListeners();
      return [];
    }

    // Open the session BEFORE the cache check so even a synchronous cache
    // hit invalidates any still-in-flight older request.
    _beginSearchSession(query, kind: SearchKind.songs);
    final gen = _searchGeneration;
    final cacheKey = query.trim().toLowerCase();

    // Check Search Cache for speed
    if (!forceRefresh && _searchCache.containsKey(cacheKey)) {
      if (kDebugMode)
        debugPrint('MusicProvider: Search Cache HIT for "$query"');
      _searchedTracks = _searchCache[cacheKey]!;
      _finishSearchSession(gen, hasResults: _searchedTracks.isNotEmpty);
      return _searchedTracks;
    }

    try {
      _clearError(); // Clear previous errors before a new search

      if (kDebugMode) {
        debugPrint(
            'MusicProvider: Searching for "$query" using ${_currentMusicSource.displayName}');
      }

      // Use InnerTube service for YouTube Music search or local search

      // Always search local tracks first
      final searchLower = query.toLowerCase();
      List<Track> localResults = _localTracks.where((track) {
        return track.trackName.toLowerCase().contains(searchLower) ||
            track.artistName.toLowerCase().contains(searchLower) ||
            track.albumName.toLowerCase().contains(searchLower);
      }).toList();

      List<Track> onlineResults = [];
      bool onlineFailed = false;

      if (_currentMusicSource != MusicSource.local && !_isOfflineMode) {
        // Use InnerTube/YouTube Music API if allowed
        try {
          onlineResults = await _innerTubeService.searchSongs(query, limit: 50);
        } catch (e) {
          onlineFailed = true;
          if (kDebugMode) debugPrint("Online search failed: $e");
        }
      }

      // Stale guard: a newer query superseded this request.
      if (!_isCurrentSearchSession(gen)) return _searchedTracks;

      // Online failed with nothing local to show: honest error, not a
      // fake empty result (BitChord Error(no_results/network) parity).
      if (onlineFailed && localResults.isEmpty) {
        _errorMessage = 'Search failed for "$query". Check your connection.';
        _searchedTracks = [];
        _addToRetryQueue(_RetryOperation('Search tracks: $query',
            () => searchTracks(query, forceRefresh: true)));
        _finishSearchSession(gen, hasResults: false, error: _errorMessage);
        return [];
      }

      // Combine results (Local first)
      _searchedTracks = [...localResults, ...onlineResults];

      // Update Search Cache (limit size to 10 entries)
      if (_searchCache.length >= 10) {
        _searchCache.remove(_searchCache.keys.first);
      }
      _searchCache[cacheKey] = _searchedTracks;

      if (kDebugMode) {
        debugPrint(
            'MusicProvider: Found ${_searchedTracks.length} results (Local: ${localResults.length}, Online: ${onlineResults.length}) for "$query"');
      }

      _finishSearchSession(gen, hasResults: _searchedTracks.isNotEmpty);
      return _searchedTracks;
    } catch (e) {
      if (!_isCurrentSearchSession(gen)) return _searchedTracks;
      _errorMessage = 'Search failed for "$query": ${e.toString()}';
      _searchedTracks = []; // Clear results on error
      _addToRetryQueue(_RetryOperation('Search tracks: $query',
          () => searchTracks(query, forceRefresh: true)));
      _finishSearchSession(gen, hasResults: false, error: _errorMessage);
      return []; // Return empty list on error
    }
  }

  // Helper for direct local search (used by Library screen)
  Future<void> searchPlaylists(String query) async {
    if (query.trim().isEmpty) {
      _playlistSearchResults = [];
      _resetSearchSession();
      notifyListeners();
      return;
    }

    if (_isOfflineMode) {
      _beginSearchSession(query, kind: SearchKind.playlists);
      final gen = _searchGeneration;
      _errorMessage = "Offline: Cannot search playlists.";
      _playlistSearchResults = [];
      _finishSearchSession(gen, hasResults: false, error: _errorMessage);
      return;
    }

    _beginSearchSession(query, kind: SearchKind.playlists);
    final gen = _searchGeneration;
    _playlistSearchResults = [];
    try {
      final playlists =
          await _innerTubeService.searchPlaylists(query, limit: 20);
      if (!_isCurrentSearchSession(gen)) return;
      _playlistSearchResults = playlists;
      _finishSearchSession(gen, hasResults: playlists.isNotEmpty);
    } catch (e) {
      if (!_isCurrentSearchSession(gen)) return;
      debugPrint("Playlist Search Error: $e");
      _playlistSearchResults = [];
      _finishSearchSession(gen, hasResults: false, error: e.toString());
    }
  }

  Future<void> fetchArtistTracks(String artistName,
      {bool forceRefresh = false}) async {
    final k = 'artist_$artistName';
    _beginSearchSession(artistName, kind: SearchKind.artists);
    final gen = _searchGeneration;

    if (!forceRefresh && _cachedTracks.containsKey(k)) {
      _artistTracks = _cachedTracks[k]!;
      _finishSearchSession(gen, hasResults: _artistTracks.isNotEmpty);
      return;
    }
    if (_isOfflineMode) {
      _errorMessage = "Offline: No artist tracks.";
      _finishSearchSession(gen, hasResults: false, error: _errorMessage);
      return;
    }
    _artistTracks = [];
    try {
      if (kDebugMode) {
        debugPrint(
            'MusicProvider: Fetching artist tracks for "$artistName" using ${_currentMusicSource.displayName}');
      }

      // Use appropriate service based on current music source
      if (_currentMusicSource == MusicSource.local) {
        // Search local tracks by artist
        _artistTracks = _localTracks
            .where((track) => track.artistName
                .toLowerCase()
                .contains(artistName.toLowerCase()))
            .toList();
      } else {
        // SearchScreen tab 2 iterates unique artists over these hits,
        // so searchArtists (artist results as Track objects) is correct here.
        _artistTracks =
            await _innerTubeService.searchArtists(artistName, limit: 30);
      }

      if (!_isCurrentSearchSession(gen)) return;
      _cachedTracks[k] = _artistTracks;
      _capCache(_cachedTracks, 60);
      _finishSearchSession(gen, hasResults: _artistTracks.isNotEmpty);
    } catch (e) {
      if (!_isCurrentSearchSession(gen)) return;
      _errorMessage = 'Failed for $artistName.';
      _addToRetryQueue(_RetryOperation('Fetch artist: $artistName',
          () => fetchArtistTracks(artistName, forceRefresh: true)));
      _finishSearchSession(gen, hasResults: false, error: _errorMessage);
    }
  }

  /// Videos filter chip (BitChord SearchFilter.VIDEOS parity).
  Future<void> searchVideos(String query) async {
    if (query.trim().isEmpty) {
      _videoSearchResults = [];
      _resetSearchSession();
      notifyListeners();
      return;
    }
    if (_isOfflineMode || _currentMusicSource == MusicSource.local) {
      _beginSearchSession(query, kind: SearchKind.videos);
      final gen = _searchGeneration;
      _errorMessage = "Offline: Cannot search videos.";
      _videoSearchResults = [];
      _finishSearchSession(gen, hasResults: false, error: _errorMessage);
      return;
    }
    _beginSearchSession(query, kind: SearchKind.videos);
    final gen = _searchGeneration;
    _videoSearchResults = [];
    try {
      final videos =
          await _innerTubeService.searchVideos(query, limit: 25, strict: true);
      if (!_isCurrentSearchSession(gen)) return;
      _videoSearchResults = videos;
      _finishSearchSession(gen, hasResults: videos.isNotEmpty);
    } catch (e) {
      if (!_isCurrentSearchSession(gen)) return;
      debugPrint("Video Search Error: $e");
      _videoSearchResults = [];
      _finishSearchSession(gen, hasResults: false, error: e.toString());
    }
  }

  /// Albums filter chip (BitChord SearchFilter.ALBUMS parity). Result ids are
  /// browse ids (MPREb/OLAK) preserved by the parser for detail navigation.
  Future<void> searchAlbums(String query) async {
    if (query.trim().isEmpty) {
      _albumSearchResults = [];
      _resetSearchSession();
      notifyListeners();
      return;
    }
    if (_isOfflineMode || _currentMusicSource == MusicSource.local) {
      _beginSearchSession(query, kind: SearchKind.albums);
      final gen = _searchGeneration;
      _errorMessage = "Offline: Cannot search albums.";
      _albumSearchResults = [];
      _finishSearchSession(gen, hasResults: false, error: _errorMessage);
      return;
    }
    _beginSearchSession(query, kind: SearchKind.albums);
    final gen = _searchGeneration;
    _albumSearchResults = [];
    try {
      final albums =
          await _innerTubeService.searchAlbums(query, limit: 25);
      if (!_isCurrentSearchSession(gen)) return;
      _albumSearchResults = albums;
      _finishSearchSession(gen, hasResults: albums.isNotEmpty);
    } catch (e) {
      if (!_isCurrentSearchSession(gen)) return;
      debugPrint("Album Search Error: $e");
      _albumSearchResults = [];
      _finishSearchSession(gen, hasResults: false, error: e.toString());
    }
  }

  /// Typeahead suggestions for [query] (BitChord 180ms suggest parity).
  /// Cheap endpoint; failures stay empty — the UI echoes typed text instead.
  Future<void> fetchSearchSuggestions(String query) async {
    final trimmed = query.trim();
    final gen = _searchGeneration;
    if (trimmed.isEmpty || _isOfflineMode) {
      if (_isCurrentSearchSession(gen)) {
        _searchSuggestions = const [];
        notifyListeners();
      }
      return;
    }
    try {
      final out =
          await _innerTubeService.getSearchSuggestions(trimmed, limit: 8);
      if (!_isCurrentSearchSession(gen)) return;
      _searchSuggestions = out;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentSearchSession(gen)) return;
      _searchSuggestions = const [];
      notifyListeners();
    }
  }

  /// Re-runs the active kind for [query] (default: current session query).
  /// Used by explicit commits (keyboard submit, nav-pill submit) so the
  /// submit honors the visible filter instead of always forcing tracks.
  Future<void> resubmitActiveSearch([String? query]) {
    final q = (query ?? _activeSearchQuery).trim();
    if (q.isEmpty) return Future.value();
    switch (_activeSearchKind) {
      case SearchKind.songs:
        return searchTracks(q, forceRefresh: true);
      case SearchKind.videos:
        return searchVideos(q);
      case SearchKind.albums:
        return searchAlbums(q);
      case SearchKind.artists:
        return fetchArtistTracks(q, forceRefresh: true);
      case SearchKind.playlists:
        return searchPlaylists(q);
    }
  }

  /// Explicit commit entry point: dispatches [query] to [kind].
  Future<void> commitSearch(String query, SearchKind kind,
      {bool forceRefresh = false}) {
    switch (kind) {
      case SearchKind.songs:
        return searchTracks(query, forceRefresh: forceRefresh);
      case SearchKind.videos:
        return searchVideos(query);
      case SearchKind.albums:
        return searchAlbums(query);
      case SearchKind.artists:
        return fetchArtistTracks(query, forceRefresh: forceRefresh);
      case SearchKind.playlists:
        return searchPlaylists(query);
    }
  }

  // --- Artist & Playlist Details (BitChord parity) ---
  Future<ArtistDetailData> fetchArtistPageData(String browseId) async {
    return _innerTubeService.getArtistPageData(browseId);
  }

  Future<AlbumDetailData> fetchAlbumPageData(String browseId) async {
    return _innerTubeService.getAlbumPageData(browseId);
  }

  Future<PlaylistDetailData> fetchPlaylistPageData(String browseId) async {
    return _innerTubeService.getPlaylistPageData(browseId);
  }

  Future<Map<String, dynamic>> fetchArtistDetails(String browseId) async {
    return _innerTubeService.getArtistDetails(browseId);
  }

  Future<List<Track>> fetchPlaylistDetails(String browseId) async {
    return _innerTubeService.getPlaylistDetails(browseId);
  }

  /// Fetch album tracks for displaying album contents
  Future<List<Track>> fetchAlbumTracks(String albumBrowseId) async {
    return _innerTubeService.getAlbumTracks(albumBrowseId);
  }

  Future<void> fetchGenreTracks(String genre,
      {bool forceRefresh = false}) async {
    final k = 'genre_$genre';
    if (!forceRefresh && _cachedTracks.containsKey(k)) {
      _genreTracks = _cachedTracks[k]!;
      notifyListeners();
      return;
    }
    if (_isOfflineMode) {
      _errorMessage = "Offline: No genre tracks.";
      notifyListeners();
      return;
    }
    try {
      if (kDebugMode) {
        debugPrint(
            'MusicProvider: Fetching genre tracks for "$genre" using ${_currentMusicSource.displayName}');
      }

      // Use appropriate service based on current music source
      if (_currentMusicSource == MusicSource.local) {
        // For local, we don't have genre metadata, so search in album/track names
        _genreTracks = _localTracks.where((track) {
          final searchLower = genre.toLowerCase();
          return track.trackName.toLowerCase().contains(searchLower) ||
              track.albumName.toLowerCase().contains(searchLower);
        }).toList();
      } else {
        // Use InnerTube for genre tracks
        _genreTracks =
            await _innerTubeService.searchSongs('$genre music', limit: 30);
      }

      _cachedTracks[k] = _genreTracks;
      _capCache(_cachedTracks, 60);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed for $genre.';
      _addToRetryQueue(_RetryOperation('Fetch genre: $genre',
          () => fetchGenreTracks(genre, forceRefresh: true)));
      notifyListeners();
    }
  }

  // --- Retry Queue ---
  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 45), (t) {
      if (_networkService.isConnected &&
          !_isOfflineMode &&
          _retryQueue.isNotEmpty) _processRetryQueue();
    });
  }

  void _addToRetryQueue(_RetryOperation operation) {
    if (!_retryQueue.any((op) => op.description == operation.description)) {
      _retryQueue.add(operation);
      if (_networkService.isConnected && !_isOfflineMode) _processRetryQueue();
    }
  }

  /// Re-entrancy guard for [_processRetryQueue].
  ///
  /// There are three independent ways into the queue: the 45s poller, an
  /// immediate call from [_addToRetryQueue], and the self-scheduling
  /// `Future.delayed` chain. Without this flag they interleave, so several
  /// chains drain the queue concurrently and each schedules the next link —
  /// which is how the chain used to grow without bound. A caller that arrives
  /// while a pass is already running simply joins the existing pass.
  bool _processingRetryQueue = false;

  Future<void> _processRetryQueue() async {
    if (_processingRetryQueue) return;
    _processingRetryQueue = true;
    try {
      while (_retryQueue.isNotEmpty &&
          !_isOfflineMode &&
          _networkService.isConnected) {
        final op = _retryQueue.removeAt(0);
        try {
          await op.execute();
        } catch (e) {
          if (op.attempts < _maxRetryAttempts) {
            op.attempts++;
            _retryQueue.add(op);
          } else {
            _errorMessage = "Failed ${op.description}.";
            notifyListeners();
          }
          // Stop this pass on failure. The 45s poller is the backoff; keeping
          // the loop going would immediately re-run the operation that just
          // failed, turning a failed request into a hot retry loop.
          break;
        }
        // Keep the old pacing between successful items so a long queue does
        // not become a burst of back-to-back requests.
        if (_retryQueue.isNotEmpty) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    } finally {
      _processingRetryQueue = false;
    }
  }

  void clearSearchResults() {
    _searchedTracks.clear();
    _artistTracks.clear();
    _playlistSearchResults.clear();
    _videoSearchResults.clear();
    _albumSearchResults.clear();
    _searchSuggestions = const [];
    _resetSearchSession();
    notifyListeners();
  }

  // --- Utility & Diagnostics ---
  Future<void> clearAllCaches() async {
    try {
      _cachedTracks.clear();
      _tracks = [];
      _trendingTracks = [];
      _fullTrendingTracks = [];
      _artistTracks = [];
      _genreTracks = [];
      _retryQueue.clear();
      _lyricsService.clearCache();
      _errorMessage = 'Caches cleared.';
      notifyListeners();
      if (_networkService.isConnected && !_isOfflineMode) {
        await fetchTracks();
        await fetchTrendingTracks();
      }
    } catch (_) {
      _errorMessage = 'Failed cache clear.';
      notifyListeners();
    }
  }

  // --- Sleep Timer ---
  Timer? _sleepTimer;

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        stopTrack();
        notifyListeners();
      });
      _errorMessage = "Sleep timer set for $minutes minutes.";
    } else if (minutes == 0) {
      // Logic for "End of Track" could be handled in _onTrackComplete
      // For now, we'll just treat 0 as "cancel" if passed explicitly, or handle "End of Track" differently if needed.
      // If the UI sends 0 for "End of Track", we might need a flag.
      // Let's assume 0 means cancel for now based on typical UI, or we can add a specific flag.
      // If the UI meant "End of Track", we'd need a bool flag _stopAfterCurrentTrack.
      // Let's implement _stopAfterCurrentTrack logic.
      _stopAfterCurrentTrack = true;
      _errorMessage = "Playback will stop after this track.";
    } else {
      _errorMessage = "Sleep timer cancelled.";
    }
    notifyListeners();
  }

  bool _stopAfterCurrentTrack = false;

  // --- Palette (delegates to PaletteService) ---
  /// Feed the dominant palette color to the app accent when album-adaptive
  /// mode is on. No-op otherwise (zero cost when the feature is off).
  void _feedAlbumAccent(PaletteGenerator palette) {
    final controller = _accentController;
    if (controller == null || !controller.isAlbumAdaptive) return;
    Color? color = palette.dominantColor?.color;
    color ??= palette.vibrantColor?.color;
    if (color == null && palette.colors.isNotEmpty) {
      color = palette.colors.first;
    }
    controller.setAlbumAccent(color);
  }

  Future<void> updatePalette() {
    final track = _currentTrack;
    if (track == null) {
      _paletteService.clear();
      return Future.value();
    }
    return _paletteService.updateForTrack(track);
  }

  /// Palette service forwarded to the provider's own notifier.
  ///
  /// The service is not owned by this provider, so it can outlive it. Routing
  /// through a method (rather than passing [notifyListeners] directly) gives
  /// dispose() something to detach by identity, instead of leaving a listener
  /// on a long-lived service that keeps waking a dead provider.
  void _paletteNotified() {
    if (_disposed) return;
    notifyListeners();
  }

  // --- Dispose ---
  bool _disposed = false;

  @override
  void dispose() {
    debugPrint('MusicProvider: Disposing...');
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this); // Stop lifecycle updates
    _authSessionReset.dispose();
    _paletteService.removeListener(_paletteNotified);

    // FIX: Cancel all audio subscriptions to prevent memory leaks
    for (final sub in _audioSubscriptions) {
      sub.cancel();
    }
    _audioSubscriptions.clear();
    _notifyDebouncer?.cancel();

    _audioService.dispose();
    _lyricsService.dispose();
    unawaited(_recommendationService.close());
    stopCastingDiscovery();
    _retryTimer?.cancel();
    _networkQualitySubscription?.cancel();
    _connectivityStatusSubscription?.cancel();
    _sleepTimer?.cancel();
    _downloads.dispose();
    _playback.dispose();
    debugPrint('MusicProvider: Disposed.');
    super.dispose();
  }

  // --- Playback projection sync ---
  // Single sync point: every provider notification re-projects queue,
  // context, and track identity into the immutable PlaybackState consumed
  // by shell/player/queue/lyrics surfaces. Position/duration/buffering
  // ticks stream directly into PlaybackController without going through
  // here.
  @override
  void notifyListeners() {
    // Unawaited async paths (init, local-music scan) can outlive dispose;
    // notifying a dead controller crashes. Drop late notifications.
    if (_disposed) return;
    _playback.projectFromProvider(this);
    super.notifyListeners();
  }

  // --- Preloading Logic ---
  Future<void> _prefetchNextTrack() async {
    Track? nextTrack;

    // Determine Next Track based on Shuffle/Repeat/Queue
    if (_queue.isNotEmpty) {
      nextTrack = _queue.first;
    } else {
      final list = _getActivePlaylist();
      if (list.isNotEmpty) {
        int nextIndex = _currentIndex + 1;
        if (nextIndex >= list.length) {
          nextIndex = (_repeatMode == RepeatMode.all) ? 0 : -1;
        }
        if (nextIndex >= 0 && nextIndex < list.length) {
          nextTrack = list[nextIndex];
        }
      }
    }

    if (nextTrack == null) return;
    if (nextTrack.id == _currentTrack?.id) return;

    if (kDebugMode)
      debugPrint(
          'MusicProvider: Prefetching next track: ${nextTrack.trackName}');

    if (!_isOfflineMode && !_isOfflineTrack && nextTrack.source != 'spotify') {
      // Audio prefetch — warms the StreamResolutionService cache so the
      // next track starts without a network round-trip.
      _streamResolution
          .resolve(ResolveRequest(
        videoId: nextTrack.id,
        title: nextTrack.trackName,
        artist: nextTrack.artistName,
        durationMs: nextTrack.durationMs,
      ))
          .then((resolved) {
        if (kDebugMode && resolved != null) {
          debugPrint(
              'MusicProvider: Stream URL prefetched for ${nextTrack!.trackName}');
        }
      }).catchError((e) {
        if (kDebugMode) debugPrint('MusicProvider: Stream prefetch failed: $e');
      });

      // Lyrics Prefetch
      _lyricsService
          .getParsedLyrics(
              title: nextTrack.trackName,
              artist: nextTrack.artistName,
              durationMs: nextTrack.durationMs,
              videoId: nextTrack.id)
          .then((_) {
        if (kDebugMode)
          debugPrint(
              'MusicProvider: Lyrics prefetch complete for ${nextTrack!.trackName}');
      }).catchError((e) {
        if (kDebugMode) debugPrint('MusicProvider: Lyrics prefetch failed: $e');
      });
    }
  }

  // --- Smart Artist Recommendations ---
  Future<List<dynamic>> getSmartLibraryArtists() async {
    final Set<String> uniqueArtistNames = {};
    final List<dynamic> smartArtists = [];

    // 1. Get AI Recommended Artists
    // Find metadata for these names from recent history/cache if possible

    // 2. Get Artists from Liked Songs (High priority)
    for (final track in _likedSongs) {
      if (!uniqueArtistNames.contains(track.artistName)) {
        uniqueArtistNames.add(track.artistName);
        smartArtists.add(track); // Using Track as artist placeholder
      }
    }

    // 3. Get Artists from Recently Played
    for (final track in _recentlyPlayed) {
      if (!uniqueArtistNames.contains(track.artistName)) {
        uniqueArtistNames.add(track.artistName);
        smartArtists.add(track);
      }
    }

    // Sort by name or relevance? For now, leave mixed (Recommendation priority order)
    return smartArtists;
  }

  // --- Smart Album Recommendations ---
  Future<List<Track>> getSmartLibraryAlbums() async {
    final Set<String> uniqueAlbumKeys = {};
    final List<Track> smartAlbums = [];

    // Extract unique albums from Liked Songs, Recently Played, and Local tracks
    for (final track in [..._likedSongs, ..._recentlyPlayed, ..._localTracks]) {
      if (track.albumName.isNotEmpty &&
          !track.albumName.toLowerCase().contains('unknown') &&
          track.albumArtUrl.isNotEmpty) {
        final key = '${track.albumName.toLowerCase()}_${track.artistName.toLowerCase()}';
        if (uniqueAlbumKeys.add(key)) {
          smartAlbums.add(track);
        }
      }
    }
    return smartAlbums;
  }
} // End of MusicProvider class

// Helper class for retry operations (Keep as is)
class _RetryOperation {
  final String description;
  final Future<dynamic> Function() execute;
  int attempts = 1;
  _RetryOperation(this.description, this.execute);
}

/// Owns the YouTube-identity flip side effect: login/logout changes the
/// session, and the player pipeline binds visitorData + signed stream URLs
/// to one session. Without a reset, /player receives login cookies with a
/// stale anonymous visitorData (or vice versa) and rejects playback while
/// browse — which needs only cookies — keeps working.
///
/// Extracted from MusicProvider (not nested in it) so the behavior is
/// unit-testable without constructing the provider and its init storm.
/// The provider owns one instance and detaches it in dispose().
class AuthSessionReset {
  AuthSessionReset({required this.onIdentityFlipped})
      : _wasLoggedIn = AuthService().isLoggedIn {
    AuthService().addListener(_onAuthChanged);
  }

  final Future<void> Function() onIdentityFlipped;
  bool _wasLoggedIn;

  void _onAuthChanged() {
    final loggedIn = AuthService().isLoggedIn;
    if (loggedIn == _wasLoggedIn) return;
    _wasLoggedIn = loggedIn;
    InnerTubeService.instance.resetSession();
    StreamResolutionService.instance.clearCache();
    unawaited(onIdentityFlipped());
  }

  void dispose() => AuthService().removeListener(_onAuthChanged);
}

/// Bridges RecommendationService's read-only signal view to the
/// QuickPicksEngine's expected TrackSignal shape (spec #15: engine must not
/// reach into the service's private cache).
class _QuickPicksSignalAdapter implements QuickPicksSignalProvider {
  _QuickPicksSignalAdapter(this._service);

  final RecommendationService _service;

  @override
  QuickPicksTrackSignal? signalFor(String trackId) {
    final view = _service.signalFor(trackId);
    if (view == null) return null;
    return QuickPicksTrackSignal(
      trackId: view.trackId,
      artistName: view.artistName,
      playCount: view.playCount,
      skipCount: view.skipCount,
      replayCount: view.replayCount,
      completionRate: view.completionRate,
    );
  }

  @override
  List<String> topArtists({int limit = 10}) =>
      _service.topArtistsForPicks(limit: limit);

  @override
  List<String> topGenres({int limit = 5}) => _service.topGenres(limit: limit);
}
