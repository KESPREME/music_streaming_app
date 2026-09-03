// lib/services/recommendation_service.dart
// Advanced Autonomous Recommendation Agent
// Maximizes long-term user satisfaction through adaptive recommendations

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import 'recommendation/user_taste_model.dart';
import 'recommendation/sequence_planner.dart';
import 'recommendation/discovery_controller.dart';
import 'recommendation/taste_profile.dart';

/// Enhanced track signal with completion rate and context
class TrackSignal {
  final String trackId;
  final String artistName;
  String? genre; // Mutable: first evidence wins, later evidence may refine.
  int playCount;
  int skipCount;
  int replayCount;
  int likeCount;
  double completionRate; // 0-1 average
  int totalListenTimeMs;
  DateTime lastPlayed;
  int? lastSkipTimingMs; // When user skipped (null if completed)

  TrackSignal({
    required this.trackId,
    required this.artistName,
    this.genre,
    this.playCount = 0,
    this.skipCount = 0,
    this.replayCount = 0,
    this.likeCount = 0,
    this.completionRate = 0.0,
    this.totalListenTimeMs = 0,
    required this.lastPlayed,
    this.lastSkipTimingMs,
  });

  Map<String, dynamic> toMap() => {
        'track_id': trackId,
        'artist_name': artistName,
        'genre': genre,
        'play_count': playCount,
        'skip_count': skipCount,
        'replay_count': replayCount,
        'like_count': likeCount,
        'completion_rate': completionRate,
        'total_listen_time_ms': totalListenTimeMs,
        'last_played': lastPlayed.millisecondsSinceEpoch,
        'last_skip_timing_ms': lastSkipTimingMs,
      };

  factory TrackSignal.fromMap(Map<String, dynamic> map) => TrackSignal(
        trackId: map['track_id'] as String,
        artistName: map['artist_name'] as String,
        genre: map['genre'] as String?,
        playCount: map['play_count'] as int? ?? 0,
        skipCount: map['skip_count'] as int? ?? 0,
        replayCount: map['replay_count'] as int? ?? 0,
        likeCount: map['like_count'] as int? ?? 0,
        completionRate: (map['completion_rate'] as num?)?.toDouble() ?? 0.0,
        totalListenTimeMs: map['total_listen_time_ms'] as int? ?? 0,
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(
            map['last_played'] as int? ?? 0),
        lastSkipTimingMs: map['last_skip_timing_ms'] as int?,
      );

  /// Calculate weighted engagement score
  /// Uses signal weighting rules from specification
  double get engagementScore {
    // PRIMARY SIGNALS (high weight)
    final completionScore = completionRate * 1.0; // Weight: 1.0
    final replayScore = min(replayCount, 5) * 0.16; // Weight: 0.8, capped

    // MEDIUM SIGNALS
    final playScore = min(playCount, 10) * 0.05; // Weight: 0.5, capped

    // LOW WEIGHT SIGNALS
    final likeScore = likeCount * 0.2; // Weight: 0.2

    // NEGATIVE SIGNALS
    double skipPenalty = 0;
    if (skipCount > 0) {
      // Earlier skip = stronger penalty
      if (lastSkipTimingMs != null && lastSkipTimingMs! < 30000) {
        skipPenalty = 0.6; // Skipped within 30 seconds
      } else {
        skipPenalty = 0.3;
      }
    }

    // Recency boost (exponential decay over 7 days)
    final daysSincePlay = DateTime.now().difference(lastPlayed).inHours / 24;
    final recencyBoost = exp(-daysSincePlay / 7) * 0.3;

    return (completionScore +
            replayScore +
            playScore +
            likeScore +
            recencyBoost -
            skipPenalty)
        .clamp(0.0, 2.0);
  }
}

/// Context snapshot for context-aware ranking
class PlaybackContext {
  final int hour;
  final int dayOfWeek; // 1-7, Monday = 1
  final bool isWeekend;

  PlaybackContext({
    required this.hour,
    required this.dayOfWeek,
  }) : isWeekend = dayOfWeek >= 6;

  factory PlaybackContext.now() {
    final now = DateTime.now();
    return PlaybackContext(
      hour: now.hour,
      dayOfWeek: now.weekday,
    );
  }

  /// Get energy bias based on time (-0.2 to +0.2)
  double get energyBias {
    if (hour >= 6 && hour < 10) return 0.1; // Morning: slight energy boost
    if (hour >= 10 && hour < 14) return 0.15; // Late morning: more energy
    if (hour >= 14 && hour < 18) return 0.05; // Afternoon: neutral
    if (hour >= 18 && hour < 22) return -0.1; // Evening: chill
    return -0.2; // Late night: ambient
  }

  /// Get exploration bias (weekends = more exploration)
  double get explorationBias {
    return isWeekend ? 0.1 : 0.0;
  }
}

/// Main Recommendation Agent
class RecommendationService {
  static const String _dbName = 'recommendations_v2.db';
  static const String _signalsTable = 'track_signals_v2';
  static const String _profileKey = 'recommendation_profile';
  static const int _dbVersion = 2;

  Database? _database;
  bool _isInitialized = false;

  // Signal cache
  final Map<String, TrackSignal> _signalCache = {};

  // User models
  final LongTermTasteModel _longTermModel = LongTermTasteModel();
  final ShortTermIntentModel _shortTermModel = ShortTermIntentModel();
  late final UserTasteBlender _tasteBlender;

  // Sequence planning
  final SequencePlanner _sequencePlanner = SequencePlanner();

  // Discovery management
  final DiscoveryController _discoveryController = DiscoveryController();

  // Recently played (for repetition prevention)
  final List<String> _recentlyPlayedIds = [];
  static const int _maxRecentlyPlayed = 50;

  // Noise filtering: require consistent evidence
  final Map<String, int> _signalConsistency =
      {}; // trackId -> consistent signal count
  static const int _minConsistentSignals = 2;

  // RL-style policy parameters
  double _explorationEpsilon = 0.15; // 15% exploration

  // Session tracking

  // Batched updates for battery efficiency
  final List<TrackSignal> _pendingUpdates = [];
  Timer? _batchSaveTimer;

  RecommendationService() {
    _tasteBlender = UserTasteBlender(_longTermModel, _shortTermModel);
  }

  /// Initialize the recommendation agent
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);

      _database = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _createDb,
        onUpgrade: _upgradeDb,
      );

      await _loadSignalsFromDb();
      await _loadProfile();
      _buildModelsFromSignals();

      _isInitialized = true;
      if (kDebugMode)
        debugPrint(
            'RecommendationAgent: Initialized with ${_signalCache.length} signals');
    } catch (e) {
      if (kDebugMode) debugPrint('RecommendationAgent: Init error: $e');
    }
  }

  /// Signal access for the Quick Picks engine (read-only facade).
  RecommendationSignalView? signalFor(String trackId) {
    final s = _signalCache[trackId];
    if (s == null) return null;
    return RecommendationSignalView(
      trackId: s.trackId,
      artistName: s.artistName,
      playCount: s.playCount,
      skipCount: s.skipCount,
      replayCount: s.replayCount,
      completionRate: s.completionRate,
    );
  }

  /// Top artist names by aggregate play weight (spec #22).
  List<String> topArtistsForPicks({int limit = 10}) =>
      _longTermModel.getTopArtists(limit: limit);

  /// Read-only view of stored signals as profile events (spec #9) —
  /// feeds TasteProfile.build without leaking the internal cache.
  List<TrackEvent> eventViews() => [
        for (final signal in _signalCache.values)
          TrackEvent(
            trackId: signal.trackId,
            artistName: signal.artistName,
            genre: signal.genre,
            completionRate: signal.completionRate,
            playCount: signal.playCount,
            skipCount: signal.skipCount,
            replayCount: signal.replayCount,
            likeCount: signal.likeCount,
            lastPlayed: signal.lastPlayed,
          ),
      ];

  /// Explicit favorite artist names (spec #60).
  List<String> favoriteArtists() => [
        for (final signal in _signalCache.values)
          if (signal.likeCount > 0) signal.artistName,
      ];

  /// Preferred genres by aggregate engagement across signals (spec: genre
  /// affinity). Deterministic: engagement DESC, then genre name ASC.
  List<String> topGenres({int limit = 5}) {
    if (_signalCache.isEmpty) return const [];
    final weight = <String, double>{};
    for (final signal in _signalCache.values) {
      final genre = signal.genre;
      if (genre == null || genre.trim().isEmpty) continue;
      final key = genre.trim().toLowerCase();
      weight[key] = (weight[key] ?? 0) + signal.engagementScore;
    }
    final entries = weight.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      });
    return entries.take(limit).map((e) => e.key).toList();
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_signalsTable (
        track_id TEXT PRIMARY KEY,
        artist_name TEXT NOT NULL,
        genre TEXT,
        play_count INTEGER DEFAULT 0,
        skip_count INTEGER DEFAULT 0,
        replay_count INTEGER DEFAULT 0,
        like_count INTEGER DEFAULT 0,
        completion_rate REAL DEFAULT 0,
        total_listen_time_ms INTEGER DEFAULT 0,
        last_played INTEGER,
        last_skip_timing_ms INTEGER
      )
    ''');

    await db
        .execute('CREATE INDEX idx_artist_v2 ON $_signalsTable(artist_name)');
    await db.execute(
        'CREATE INDEX idx_last_played_v2 ON $_signalsTable(last_played DESC)');
    await db.execute(
        'CREATE INDEX idx_engagement ON $_signalsTable(completion_rate DESC)');
  }

  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    // Migration logic - preserve data where possible
    if (oldVersion < 2) {
      // Back up v1 table instead of dropping it, then best-effort copy
      // any overlapping columns into the new schema.
      const backupTable = '${_signalsTable}_v1_backup';
      final hasOld = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [_signalsTable],
      );
      if (hasOld.isNotEmpty) {
        await db.execute('ALTER TABLE $_signalsTable RENAME TO $backupTable');
      }
      await _createDb(db, newVersion);
      try {
        if (hasOld.isNotEmpty) {
          final cols = (await db.rawQuery('PRAGMA table_info($backupTable)'))
              .map((r) => r['name'] as String)
              .toSet();
          final shared = [
            'track_id',
            'artist_name',
            'play_count',
            'skip_count',
            'replay_count',
            'like_count',
            'completion_rate',
            'total_listen_time_ms',
            'last_played',
            'last_skip_timing_ms',
          ].where(cols.contains).toList();
          if (shared.isNotEmpty) {
            await db.execute(
              'INSERT OR REPLACE INTO $_signalsTable (${shared.join(',')}) '
              'SELECT ${shared.join(',')} FROM $backupTable',
            );
          }
          await db.execute('DROP TABLE IF EXISTS $backupTable');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('RecommendationAgent: Migration error: $e');
      }
    }
  }

  /// Explicit swipe feedback from the discovery deck — feeds the discovery
  /// controller's accept/reject learning directly.
  void recordSwipeOutcome(
      {required String artistName, required bool wasAccepted}) {
    if (!_isInitialized) return;
    _discoveryController.recordDiscoveryOutcome(
      artistName: artistName,
      wasAccepted: wasAccepted,
    );
  }

  /// Record a track play with detailed signals
  Future<void> recordPlay(
    Track track, {
    required double completionRate, // 0-1
    required int listenTimeMs,
    int? skipTimingMs, // When skipped, null if completed
  }) async {
    if (!_isInitialized) return;
    final isSkip = completionRate < 0.5;
    final isReplay = _recentlyPlayedIds.contains(track.id) &&
        _recentlyPlayedIds.indexOf(track.id) < 3;

    // Get or create signal
    final signal = _signalCache[track.id] ??
        TrackSignal(
          trackId: track.id,
          artistName: track.artistName,
          genre: track.genre,
          lastPlayed: DateTime.now(),
        );
    // First evidence wins; a later non-null tag may refine it.
    if (track.genre != null && track.genre!.isNotEmpty) {
      signal.genre ??= track.genre;
    }

    // Update signal with new data
    signal.playCount++;
    if (isSkip) {
      signal.skipCount++;
      signal.lastSkipTimingMs = skipTimingMs;
    }
    if (isReplay) {
      signal.replayCount++;
    }
    signal.totalListenTimeMs += listenTimeMs;
    signal.lastPlayed = DateTime.now();

    // Update completion rate (exponential moving average)
    signal.completionRate = signal.completionRate * 0.7 + completionRate * 0.3;

    _signalCache[track.id] = signal;

    // Update models (with noise filtering)
    final consistencyCount = (_signalConsistency[track.id] ?? 0) + 1;
    _signalConsistency[track.id] = consistencyCount;

    if (consistencyCount >= _minConsistentSignals) {
      // Enough evidence to update long-term model
      _longTermModel.updateArtistAffinity(
        track.artistName,
        signal.engagementScore / 2,
        signal.playCount,
      );
    }

    // Always update short-term model
    _shortTermModel.recordListen(
      trackId: track.id,
      artistName: track.artistName,
      completionRate: completionRate,
    );

    // Track discovery outcomes
    if (_discoveryController.isDiscoveryTrack(track)) {
      _discoveryController.recordDiscoveryOutcome(
        artistName: track.artistName,
        wasAccepted: completionRate >= 0.5,
      );
    }

    // Session tracking

    // Update recently played
    _updateRecentlyPlayed(track.id);

    // Batch save for battery efficiency
    _pendingUpdates.add(signal);
    _scheduleBatchSave();
  }

  /// Rank tracks for For You section
  /// Uses multi-objective scoring with context awareness
  List<Track> rankTracks(List<Track> candidates, {int limit = 20}) {
    if (candidates.isEmpty) return [];

    final context = PlaybackContext.now();
    final shouldExploit = _tasteBlender.shouldExploit();

    // Score each candidate
    final scored = <_ScoredTrack>[];

    for (final track in candidates) {
      final score =
          _calculateMultiObjectiveScore(track, context, shouldExploit);
      scored.add(_ScoredTrack(track, score));
    }

    // Sort by score
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Take top results
    var result = scored.take(limit).map((s) => s.track).toList();

    // Inject discoveries if appropriate
    if (!shouldExploit && _discoveryController.getDiscoveryBudget(limit) > 0) {
      final discoveries = _discoveryController.selectDiscoveries(
        candidates: candidates,
        knownFavorites: _longTermModel.getTopArtists(limit: 5),
        maxCount: _discoveryController.getDiscoveryBudget(limit),
      );

      if (discoveries.isNotEmpty) {
        result = _discoveryController.injectDiscoveries(
          rankedTracks: result,
          discoveries: discoveries,
        );
      }
    }

    return result.take(limit).toList();
  }

  /// Get recommended artists from long-term model
  List<String> getRecommendedArtists({int limit = 20}) {
    return _longTermModel.getTopArtists(limit: limit);
  }

  /// Calculate multi-objective score for a track
  double _calculateMultiObjectiveScore(
    Track track,
    PlaybackContext context,
    bool safeMode,
  ) {
    double score = 0;

    // 1. Track engagement history
    final signal = _signalCache[track.id];
    if (signal != null) {
      score += signal.engagementScore * 0.3;
    }

    // 2. Artist affinity (blended short/long term)
    final artistAffinity =
        _tasteBlender.getBlendedArtistAffinity(track.artistName);
    score += artistAffinity * 0.25;

    // 3. Context alignment
    final contextScore = context.energyBias * 0.5 + 0.5; // Normalize to 0-1
    score += contextScore * 0.15;

    // 4. Repetition penalty
    final recencyPenalty = _getRecencyPenalty(track.id);
    score -= recencyPenalty * 0.2;

    // 5. Fatigue penalty (same artist too often)
    final artistFatigue = _getArtistFatigue(track.artistName);
    score -= artistFatigue * 0.1;

    // 6. Safe mode adjustment
    if (safeMode) {
      // Boost known tracks when user is frustrated
      if (signal != null && signal.playCount >= 2) {
        score += 0.2;
      }
    }

    return score.clamp(0.0, 2.0);
  }

  /// Get autoplay recommendations with sequence planning
  List<Track> getAutoplayRecommendations(
    Track currentTrack,
    List<Track> candidates, {
    int limit = 15,
  }) {
    if (candidates.isEmpty) return [];

    final context = PlaybackContext.now();
    final targetEnergy =
        _tasteBlender.getBlendedEnergyPreference() + context.energyBias;

    // First, rank by relevance
    final ranked = rankTracks(candidates, limit: limit * 2);

    // Then, plan sequence for energy continuity
    final sequenced = _sequencePlanner.planSequence(
      currentTrack: currentTrack,
      candidates: ranked,
      targetEnergy: targetEnergy.clamp(0.0, 1.0),
      maintainMomentum: true,
    );

    return sequenced
        .where((t) =>
            !_recentlyPlayedIds.take(5).contains(t.id) &&
            t.id != currentTrack.id)
        .take(limit)
        .toList();
  }

  // --- Internal Helpers ---

  double _getRecencyPenalty(String trackId) {
    final index = _recentlyPlayedIds.indexOf(trackId);
    if (index == -1) return 0;

    // Higher penalty for very recent plays
    if (index < 5) return 0.8;
    if (index < 10) return 0.5;
    return (1 - (index / _maxRecentlyPlayed)) * 0.3;
  }

  double _getArtistFatigue(String artistName) {
    // Count recent plays of this artist
    int count = 0;
    for (final id in _recentlyPlayedIds.take(10)) {
      final signal = _signalCache[id];
      if (signal?.artistName == artistName) {
        count++;
      }
    }

    return (count / 5.0).clamp(0.0, 1.0);
  }

  void _updateRecentlyPlayed(String trackId) {
    _recentlyPlayedIds.remove(trackId);
    _recentlyPlayedIds.insert(0, trackId);

    while (_recentlyPlayedIds.length > _maxRecentlyPlayed) {
      _recentlyPlayedIds.removeLast();
    }

    // Update known artists
    _discoveryController.updateKnownArtists(
        _signalCache.values.map((s) => s.artistName).toSet());
  }

  void _buildModelsFromSignals() {
    for (final signal in _signalCache.values) {
      if (signal.playCount >= _minConsistentSignals) {
        _longTermModel.updateArtistAffinity(
          signal.artistName,
          signal.engagementScore / 2,
          signal.playCount,
        );
      }
    }

    _discoveryController.updateKnownArtists(
        _signalCache.values.map((s) => s.artistName).toSet());
  }

  void _scheduleBatchSave() {
    _batchSaveTimer?.cancel();
    _batchSaveTimer = Timer(const Duration(seconds: 5), _flushPendingUpdates);
  }

  Future<void> _flushPendingUpdates() async {
    if (_database == null || _pendingUpdates.isEmpty) return;

    try {
      final batch = _database!.batch();

      for (final signal in _pendingUpdates) {
        batch.insert(
          _signalsTable,
          signal.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      _pendingUpdates.clear();

      // Also save profile periodically
      await _saveProfile();
    } catch (e) {
      if (kDebugMode) debugPrint('RecommendationAgent: Batch save error: $e');
    }
  }

  Future<void> _loadSignalsFromDb() async {
    if (_database == null) return;

    try {
      final results = await _database!.query(_signalsTable);
      _signalCache.clear();

      for (final row in results) {
        final signal = TrackSignal.fromMap(row);
        _signalCache[signal.trackId] = signal;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RecommendationAgent: Load error: $e');
    }
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_profileKey);

      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;

        if (map['longTermModel'] != null) {
          _longTermModel.fromMap(map['longTermModel'] as Map<String, dynamic>);
        }

        if (map['discoveryController'] != null) {
          _discoveryController
              .loadState(map['discoveryController'] as Map<String, dynamic>);
        }

        _explorationEpsilon =
            (map['explorationEpsilon'] as num?)?.toDouble() ?? 0.15;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RecommendationAgent: Profile load error: $e');
    }
  }

  Future<void> _saveProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final map = {
        'longTermModel': _longTermModel.toMap(),
        'discoveryController': _discoveryController.saveState(),
        'explorationEpsilon': _explorationEpsilon,
      };

      await prefs.setString(_profileKey, jsonEncode(map));
    } catch (e) {
      if (kDebugMode) debugPrint('RecommendationAgent: Profile save error: $e');
    }
  }

  Future<void> close() async {
    _batchSaveTimer?.cancel();
    await _flushPendingUpdates();

    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}

class _ScoredTrack {
  final Track track;
  final double score;

  _ScoredTrack(this.track, this.score);
}

/// Read-only signal view for the Quick Picks engine (decoupled facade —
/// the engine must not reach into the service's private cache).
class RecommendationSignalView {
  const RecommendationSignalView({
    required this.trackId,
    required this.artistName,
    required this.playCount,
    required this.skipCount,
    required this.replayCount,
    required this.completionRate,
  });

  final String trackId;
  final String artistName;
  final int playCount;
  final int skipCount;
  final int replayCount;
  final double completionRate;
}
