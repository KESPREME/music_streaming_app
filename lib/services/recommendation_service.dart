// lib/services/recommendation_service.dart
// Hybrid recommendation engine with local signal tracking

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/track.dart';

/// User interaction signals for recommendation
class TrackSignal {
  final String trackId;
  final String artistName;
  final String? genre;
  int playCount;
  int skipCount; // Plays < 30 seconds
  int likeCount;
  DateTime lastPlayed;
  int totalListenTimeMs;
  
  TrackSignal({
    required this.trackId,
    required this.artistName,
    this.genre,
    this.playCount = 0,
    this.skipCount = 0,
    this.likeCount = 0,
    required this.lastPlayed,
    this.totalListenTimeMs = 0,
  });
  
  Map<String, dynamic> toMap() => {
    'track_id': trackId,
    'artist_name': artistName,
    'genre': genre,
    'play_count': playCount,
    'skip_count': skipCount,
    'like_count': likeCount,
    'last_played': lastPlayed.millisecondsSinceEpoch,
    'total_listen_time_ms': totalListenTimeMs,
  };
  
  factory TrackSignal.fromMap(Map<String, dynamic> map) => TrackSignal(
    trackId: map['track_id'] as String,
    artistName: map['artist_name'] as String,
    genre: map['genre'] as String?,
    playCount: map['play_count'] as int? ?? 0,
    skipCount: map['skip_count'] as int? ?? 0,
    likeCount: map['like_count'] as int? ?? 0,
    lastPlayed: DateTime.fromMillisecondsSinceEpoch(map['last_played'] as int? ?? 0),
    totalListenTimeMs: map['total_listen_time_ms'] as int? ?? 0,
  );
  
  /// Calculate engagement score (higher = more engaged)
  double get engagementScore {
    // Positive signals
    final playScore = playCount * 1.0;
    final likeScore = likeCount * 3.0;
    final listenTimeScore = (totalListenTimeMs / 60000) * 0.5; // Per minute
    
    // Negative signals
    final skipPenalty = skipCount * 2.0;
    
    // Recency boost (exponential decay over 7 days)
    final daysSincePlay = DateTime.now().difference(lastPlayed).inHours / 24;
    final recencyBoost = exp(-daysSincePlay / 7) * 2;
    
    return (playScore + likeScore + listenTimeScore + recencyBoost - skipPenalty).clamp(0, 100);
  }
}

/// Artist preference profile
class ArtistPreference {
  final String artistName;
  double affinityScore;
  int totalPlays;
  DateTime lastPlayed;
  
  ArtistPreference({
    required this.artistName,
    this.affinityScore = 0,
    this.totalPlays = 0,
    required this.lastPlayed,
  });
}

/// Recommendation service with local signal storage
class RecommendationService {
  static const String _dbName = 'recommendations.db';
  static const String _signalsTable = 'track_signals';
  static const int _dbVersion = 1;
  
  Database? _database;
  bool _isInitialized = false;
  
  // In-memory caches for fast access
  final Map<String, TrackSignal> _signalCache = {};
  final Map<String, ArtistPreference> _artistPreferences = {};
  final List<String> _recentlyPlayedIds = []; // Last 50
  static const int _maxRecentlyPlayed = 50;
  
  // Recommendation weights
  static const double _weightCollaborative = 0.4;
  static const double _weightContent = 0.3;
  static const double _weightContext = 0.3;
  static const double _explorationRate = 0.1; // 10% random exploration
  
  /// Initialize the recommendation system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);
      
      _database = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_signalsTable (
              track_id TEXT PRIMARY KEY,
              artist_name TEXT NOT NULL,
              genre TEXT,
              play_count INTEGER DEFAULT 0,
              skip_count INTEGER DEFAULT 0,
              like_count INTEGER DEFAULT 0,
              last_played INTEGER,
              total_listen_time_ms INTEGER DEFAULT 0
            )
          ''');
          
          await db.execute('CREATE INDEX idx_artist ON $_signalsTable(artist_name)');
          await db.execute('CREATE INDEX idx_last_played ON $_signalsTable(last_played DESC)');
        },
      );
      
      await _loadSignalsFromDb();
      _buildArtistPreferences();
      
      _isInitialized = true;
      if (kDebugMode) print('RecommendationService: Initialized with ${_signalCache.length} signals');
    } catch (e) {
      if (kDebugMode) print('RecommendationService: Init error: $e');
    }
  }
  
  /// Record a track play event
  Future<void> recordPlay(Track track, {bool isSkip = false, int listenTimeMs = 0}) async {
    if (!_isInitialized) return;
    
    final signal = _signalCache[track.id] ?? TrackSignal(
      trackId: track.id,
      artistName: track.artistName,
      lastPlayed: DateTime.now(),
    );
    
    if (isSkip) {
      signal.skipCount++;
    } else {
      signal.playCount++;
      signal.totalListenTimeMs += listenTimeMs;
    }
    signal.lastPlayed = DateTime.now();
    
    _signalCache[track.id] = signal;
    _updateRecentlyPlayed(track.id);
    _updateArtistPreference(track.artistName);
    
    // Persist asynchronously
    unawaited(_saveSignal(signal));
  }
  
  /// Record a like/heart event
  Future<void> recordLike(Track track, {bool isLiked = true}) async {
    if (!_isInitialized) return;
    
    final signal = _signalCache[track.id] ?? TrackSignal(
      trackId: track.id,
      artistName: track.artistName,
      lastPlayed: DateTime.now(),
    );
    
    signal.likeCount = isLiked ? 1 : 0;
    _signalCache[track.id] = signal;
    
    unawaited(_saveSignal(signal));
  }
  
  /// Rank tracks for recommendations
  List<Track> rankTracks(List<Track> candidates, {int limit = 20}) {
    if (candidates.isEmpty || _signalCache.isEmpty) {
      // No signals yet, return shuffled
      return (List<Track>.from(candidates)..shuffle()).take(limit).toList();
    }
    
    final scored = <_ScoredTrack>[];
    
    for (final track in candidates) {
      final score = _calculateScore(track);
      scored.add(_ScoredTrack(track, score));
    }
    
    // Sort by score descending
    scored.sort((a, b) => b.score.compareTo(a.score));
    
    // Apply exploration: swap 10% with random tracks
    final result = scored.take(limit).map((s) => s.track).toList();
    _applyExploration(result, candidates);
    
    return result;
  }
  
  /// Calculate recommendation score for a track
  double _calculateScore(Track track) {
    double score = 0;
    
    // 1. Collaborative filtering (based on similar tracks played)
    final signal = _signalCache[track.id];
    if (signal != null) {
      score += signal.engagementScore * _weightCollaborative;
    }
    
    // 2. Content-based (artist affinity)
    final artistPref = _artistPreferences[track.artistName];
    if (artistPref != null) {
      score += artistPref.affinityScore * _weightContent;
    }
    
    // 3. Context (recently played penalty, time of day boost)
    final recencyPenalty = _getRecencyPenalty(track.id);
    final timeBoost = _getTimeOfDayBoost();
    score += (timeBoost - recencyPenalty) * _weightContext;
    
    return score;
  }
  
  /// Penalize recently played tracks
  double _getRecencyPenalty(String trackId) {
    final index = _recentlyPlayedIds.indexOf(trackId);
    if (index == -1) return 0;
    
    // Higher penalty for more recently played
    return (1 - (index / _maxRecentlyPlayed)) * 5;
  }
  
  /// Boost based on time of day (evening = more chill, morning = upbeat)
  double _getTimeOfDayBoost() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) return 1.0; // Morning
    if (hour >= 12 && hour < 18) return 0.8; // Afternoon
    if (hour >= 18 && hour < 22) return 1.2; // Evening
    return 0.5; // Night
  }
  
  /// Apply exploration by injecting random tracks
  void _applyExploration(List<Track> result, List<Track> allCandidates) {
    final rng = Random();
    final explorationCount = (result.length * _explorationRate).round();
    
    final resultIds = result.map((t) => t.id).toSet();
    final unexplored = allCandidates.where((t) => !resultIds.contains(t.id)).toList();
    
    if (unexplored.isEmpty) return;
    
    for (int i = 0; i < explorationCount && unexplored.isNotEmpty; i++) {
      final randomIndex = rng.nextInt(unexplored.length);
      final insertIndex = rng.nextInt(result.length);
      
      result[insertIndex] = unexplored.removeAt(randomIndex);
    }
  }
  
  /// Get autoplay recommendations (context-aware, no recent repeats)
  List<Track> getAutoplayRecommendations(
    String currentTrackId,
    List<Track> candidates, {
    int limit = 10,
  }) {
    // Filter out recently played
    final filtered = candidates.where((t) => 
      !_recentlyPlayedIds.contains(t.id) && t.id != currentTrackId
    ).toList();
    
    if (filtered.isEmpty) return candidates.take(limit).toList();
    
    return rankTracks(filtered, limit: limit);
  }
  
  // --- Internal Helpers ---
  
  void _updateRecentlyPlayed(String trackId) {
    _recentlyPlayedIds.remove(trackId);
    _recentlyPlayedIds.insert(0, trackId);
    
    while (_recentlyPlayedIds.length > _maxRecentlyPlayed) {
      _recentlyPlayedIds.removeLast();
    }
  }
  
  void _updateArtistPreference(String artistName) {
    final pref = _artistPreferences[artistName] ?? ArtistPreference(
      artistName: artistName,
      lastPlayed: DateTime.now(),
    );
    
    pref.totalPlays++;
    pref.affinityScore = min(100, pref.affinityScore + 1);
    pref.lastPlayed = DateTime.now();
    
    _artistPreferences[artistName] = pref;
  }
  
  void _buildArtistPreferences() {
    _artistPreferences.clear();
    
    for (final signal in _signalCache.values) {
      final pref = _artistPreferences[signal.artistName] ?? ArtistPreference(
        artistName: signal.artistName,
        lastPlayed: signal.lastPlayed,
      );
      
      pref.totalPlays += signal.playCount;
      pref.affinityScore += signal.engagementScore;
      if (signal.lastPlayed.isAfter(pref.lastPlayed)) {
        pref.lastPlayed = signal.lastPlayed;
      }
      
      _artistPreferences[signal.artistName] = pref;
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
      if (kDebugMode) print('RecommendationService: Load error: $e');
    }
  }
  
  Future<void> _saveSignal(TrackSignal signal) async {
    if (_database == null) return;
    
    try {
      await _database!.insert(
        _signalsTable,
        signal.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      if (kDebugMode) print('RecommendationService: Save error: $e');
    }
  }
  
  /// Get statistics
  Map<String, dynamic> getStats() => {
    'totalSignals': _signalCache.length,
    'totalArtistPreferences': _artistPreferences.length,
    'recentlyPlayedCount': _recentlyPlayedIds.length,
  };
  
  Future<void> close() async {
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
