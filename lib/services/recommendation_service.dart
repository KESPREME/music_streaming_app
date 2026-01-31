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

/// Enhanced track signal with completion rate and context
class TrackSignal {
  final String trackId;
  final String artistName;
  final String? genre;
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
    lastPlayed: DateTime.fromMillisecondsSinceEpoch(map['last_played'] as int? ?? 0),
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
    
    return (completionScore + replayScore + playScore + likeScore + recencyBoost - skipPenalty).clamp(0.0, 2.0);
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
  final Map<String, int> _signalConsistency = {}; // trackId -> consistent signal count
  static const int _minConsistentSignals = 2;
  
  // RL-style policy parameters
  double _explorationEpsilon = 0.15; // 15% exploration
  double _explorationDecay = 0.995; // Decay per session
  
  // Session tracking
  DateTime _sessionStart = DateTime.now();
  int _sessionTrackCount = 0;
  double _sessionTotalCompletion = 0;
  
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
      if (kDebugMode) print('RecommendationAgent: Initialized with ${_signalCache.length} signals');
    } catch (e) {
      if (kDebugMode) print('RecommendationAgent: Init error: $e');
    }
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
    
    await db.execute('CREATE INDEX idx_artist_v2 ON $_signalsTable(artist_name)');
    await db.execute('CREATE INDEX idx_last_played_v2 ON $_signalsTable(last_played DESC)');
    await db.execute('CREATE INDEX idx_engagement ON $_signalsTable(completion_rate DESC)');
  }
  
  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    // Migration logic - preserve data where possible
    if (oldVersion < 2) {
      // Create new table and migrate
      try {
        await db.execute('DROP TABLE IF EXISTS $_signalsTable');
        await _createDb(db, newVersion);
      } catch (e) {
        if (kDebugMode) print('RecommendationAgent: Migration error: $e');
      }
    }
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
    final signal = _signalCache[track.id] ?? TrackSignal(
      trackId: track.id,
      artistName: track.artistName,
      lastPlayed: DateTime.now(),
    );
    
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
    _sessionTrackCount++;
    _sessionTotalCompletion += completionRate;
    
    // Update recently played
    _updateRecentlyPlayed(track.id);
    
    // Batch save for battery efficiency
    _pendingUpdates.add(signal);
    _scheduleBatchSave();
  }
  
  /// Record a like/heart event (low weight signal)
  Future<void> recordLike(Track track, {bool isLiked = true}) async {
    if (!_isInitialized) return;
    
    final signal = _signalCache[track.id] ?? TrackSignal(
      trackId: track.id,
      artistName: track.artistName,
      lastPlayed: DateTime.now(),
    );
    
    signal.likeCount = isLiked ? 1 : 0;
    _signalCache[track.id] = signal;
    
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
      final score = _calculateMultiObjectiveScore(track, context, shouldExploit);
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
    final artistAffinity = _tasteBlender.getBlendedArtistAffinity(track.artistName);
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
    final targetEnergy = _tasteBlender.getBlendedEnergyPreference() + context.energyBias;
    
    // First, rank by relevance
    final ranked = rankTracks(candidates, limit: limit * 2);
    
    // Then, plan sequence for energy continuity
    final sequenced = _sequencePlanner.planSequence(
      currentTrack: currentTrack,
      candidates: ranked,
      targetEnergy: targetEnergy.clamp(0.0, 1.0),
      maintainMomentum: true,
    );
    
    return sequenced.where((t) => 
      !_recentlyPlayedIds.take(5).contains(t.id) && t.id != currentTrack.id
    ).take(limit).toList();
  }
  
  /// Record a transition for sequence learning
  void recordTransition(Track from, Track to) {
    _sequencePlanner.recordTransition(from, to);
  }
  
  /// Record a search query for intent modeling
  void recordSearch(String query) {
    _shortTermModel.recordSearch(query);
  }
  
  /// Start a new session
  void startNewSession() {
    _shortTermModel.startNewSession();
    _sequencePlanner.resetSession();
    _discoveryController.resetSession();
    
    // Update exploration epsilon with decay
    _explorationEpsilon = (_explorationEpsilon * _explorationDecay).clamp(0.05, 0.2);
    
    _sessionStart = DateTime.now();
    _sessionTrackCount = 0;
    _sessionTotalCompletion = 0;
  }
  
  /// Check if session is stale and needs refresh
  bool isSessionStale() {
    final sessionAge = DateTime.now().difference(_sessionStart);
    return sessionAge > const Duration(hours: 4) || _shortTermModel.isSessionStale();
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
      _signalCache.values.map((s) => s.artistName).toSet()
    );
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
      _signalCache.values.map((s) => s.artistName).toSet()
    );
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
      if (kDebugMode) print('RecommendationAgent: Batch save error: $e');
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
      if (kDebugMode) print('RecommendationAgent: Load error: $e');
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
          _discoveryController.loadState(map['discoveryController'] as Map<String, dynamic>);
        }
        
        _explorationEpsilon = (map['explorationEpsilon'] as num?)?.toDouble() ?? 0.15;
      }
    } catch (e) {
      if (kDebugMode) print('RecommendationAgent: Profile load error: $e');
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
      if (kDebugMode) print('RecommendationAgent: Profile save error: $e');
    }
  }
  
  /// Get agent statistics
  Map<String, dynamic> getStats() => {
    'totalSignals': _signalCache.length,
    'longTermConfidence': _longTermModel.confidence,
    'sessionQuality': _shortTermModel.getSessionQuality(),
    'skipMomentum': _shortTermModel.skipMomentum,
    'explorationEpsilon': _explorationEpsilon,
    'sessionTrackCount': _sessionTrackCount,
    'discoveryStats': _discoveryController.getStats(),
  };
  
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
