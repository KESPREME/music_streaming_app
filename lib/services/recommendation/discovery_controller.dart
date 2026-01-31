// lib/services/recommendation/discovery_controller.dart
// Discovery and exploration management for the recommendation agent

import 'dart:math';
import '../../models/track.dart';

/// Controls exploration vs exploitation balance
/// Manages novelty injection and discovery validation
class DiscoveryController {
  // Personalized exploration tolerance (0-1, learned over time)
  double _explorationTolerance = 0.3;
  
  // Session novelty budget (max % of new artists per session)
  double _noveltyBudget = 0.2; // 20% max
  
  // Tracks introduced as discoveries this session
  final Set<String> _sessionDiscoveries = {};
  
  // Known/familiar artists
  final Set<String> _knownArtists = {};
  
  // Discovery success rate (validated discoveries)
  double _discoverySuccessRate = 0.5;
  
  // Consecutive discovery rejections
  int _consecutiveRejections = 0;
  
  /// Update known artists from user history
  void updateKnownArtists(Set<String> artists) {
    _knownArtists.addAll(artists);
  }
  
  /// Calculate current exploration budget
  /// Returns recommended discovery count for a batch of N tracks
  int getDiscoveryBudget(int batchSize) {
    // Base budget from tolerance
    double budget = batchSize * _noveltyBudget * _explorationTolerance;
    
    // Reduce if recent discoveries were rejected
    if (_consecutiveRejections >= 2) {
      budget *= 0.5;
    }
    
    // Increase if discoveries are going well
    if (_discoverySuccessRate > 0.7) {
      budget *= 1.2;
    }
    
    // Never exceed 30% of batch
    return budget.clamp(0, batchSize * 0.3).round();
  }
  
  /// Check if a track qualifies as a discovery
  bool isDiscoveryTrack(Track track) {
    return !_knownArtists.contains(track.artistName);
  }
  
  /// Validate a discovery candidate
  /// Uses heuristics for "adjacent to known favorites"
  double validateDiscovery(Track discovery, List<String> knownFavorites) {
    double score = 0.5;
    
    // Check for name similarity with known artists (collaboration potential)
    for (final favorite in knownFavorites) {
      final favLower = favorite.toLowerCase();
      final discLower = discovery.artistName.toLowerCase();
      
      // Shared words (collaboration, same label, etc.)
      final favWords = favLower.split(RegExp(r'\s+'));
      final discWords = discLower.split(RegExp(r'\s+'));
      
      for (final word in discWords) {
        if (word.length > 3 && favWords.contains(word)) {
          score += 0.2;
        }
      }
    }
    
    // Check track name for featuring known artists
    final trackLower = discovery.trackName.toLowerCase();
    for (final favorite in knownFavorites) {
      if (trackLower.contains(favorite.toLowerCase())) {
        score += 0.3; // Known artist featured
      }
    }
    
    return score.clamp(0.0, 1.0);
  }
  
  /// Record discovery outcome
  void recordDiscoveryOutcome({
    required String artistName,
    required bool wasAccepted, // Completion rate > 50%
  }) {
    if (wasAccepted) {
      _consecutiveRejections = 0;
      _discoverySuccessRate = _discoverySuccessRate * 0.8 + 0.2;
      
      // Successful discovery becomes known
      _knownArtists.add(artistName);
      
      // Increase exploration tolerance
      _explorationTolerance = (_explorationTolerance * 0.95 + 0.05).clamp(0.1, 0.5);
    } else {
      _consecutiveRejections++;
      _discoverySuccessRate = _discoverySuccessRate * 0.8;
      
      // Decrease exploration tolerance
      _explorationTolerance = (_explorationTolerance * 0.95 - 0.02).clamp(0.1, 0.5);
    }
    
    _sessionDiscoveries.add(artistName);
  }
  
  /// Filter and rank discovery candidates
  List<Track> selectDiscoveries({
    required List<Track> candidates,
    required List<String> knownFavorites,
    int maxCount = 3,
  }) {
    // Filter to actual discoveries
    final discoveries = candidates.where(isDiscoveryTrack).toList();
    
    if (discoveries.isEmpty) return [];
    
    // Score each discovery
    final scored = <_ScoredDiscovery>[];
    for (final d in discoveries) {
      final score = validateDiscovery(d, knownFavorites);
      scored.add(_ScoredDiscovery(d, score));
    }
    
    // Sort by score and take top N
    scored.sort((a, b) => b.score.compareTo(a.score));
    
    // Only include high-quality discoveries
    return scored
        .where((s) => s.score >= 0.4)
        .take(maxCount)
        .map((s) => s.track)
        .toList();
  }
  
  /// Inject discoveries into a ranked list
  List<Track> injectDiscoveries({
    required List<Track> rankedTracks,
    required List<Track> discoveries,
  }) {
    if (discoveries.isEmpty || rankedTracks.isEmpty) return rankedTracks;
    
    final result = List<Track>.from(rankedTracks);
    final rng = Random();
    
    // Inject discoveries at strategic positions (not at start)
    final positions = <int>[];
    for (int i = 0; i < discoveries.length && i < 3; i++) {
      // Position between 30-70% of list
      final minPos = (result.length * 0.3).round();
      final maxPos = (result.length * 0.7).round();
      final pos = minPos + rng.nextInt(max(1, maxPos - minPos));
      
      if (!positions.contains(pos)) {
        positions.add(pos);
      }
    }
    
    positions.sort();
    
    // Insert in reverse order to maintain positions
    for (int i = min(discoveries.length, positions.length) - 1; i >= 0; i--) {
      if (positions[i] < result.length) {
        result.insert(positions[i], discoveries[i]);
      }
    }
    
    return result;
  }
  
  /// Reset session state
  void resetSession() {
    _sessionDiscoveries.clear();
    _consecutiveRejections = 0;
  }
  
  /// Get exploration stats
  Map<String, dynamic> getStats() => {
    'explorationTolerance': _explorationTolerance,
    'noveltyBudget': _noveltyBudget,
    'discoverySuccessRate': _discoverySuccessRate,
    'knownArtistsCount': _knownArtists.length,
    'sessionDiscoveriesCount': _sessionDiscoveries.length,
  };
  
  /// Load saved state
  void loadState(Map<String, dynamic> state) {
    _explorationTolerance = (state['explorationTolerance'] as num?)?.toDouble() ?? 0.3;
    _noveltyBudget = (state['noveltyBudget'] as num?)?.toDouble() ?? 0.2;
    _discoverySuccessRate = (state['discoverySuccessRate'] as num?)?.toDouble() ?? 0.5;
    
    final known = state['knownArtists'] as List<dynamic>?;
    if (known != null) {
      _knownArtists.addAll(known.cast<String>());
    }
  }
  
  /// Save state
  Map<String, dynamic> saveState() => {
    'explorationTolerance': _explorationTolerance,
    'noveltyBudget': _noveltyBudget,
    'discoverySuccessRate': _discoverySuccessRate,
    'knownArtists': _knownArtists.toList(),
  };
}

class _ScoredDiscovery {
  final Track track;
  final double score;
  
  _ScoredDiscovery(this.track, this.score);
}
