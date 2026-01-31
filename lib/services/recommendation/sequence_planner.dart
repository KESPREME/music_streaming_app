// lib/services/recommendation/sequence_planner.dart
// Autoplay sequence planning with energy continuity and flow optimization

import 'dart:math';
import '../../models/track.dart';

/// Plans optimal track sequences for autoplay
/// Focuses on energy continuity, smooth transitions, and session momentum
class SequencePlanner {
  // Maximum energy change per transition (±15% recommended)
  static const double _maxEnergyDelta = 0.15;
  
  // Session momentum (positive = user engaged, negative = declining)
  double _sessionMomentum = 0.0;
  
  // Last played track's estimated energy
  double? _lastEnergy;
  
  // Transition history for variety
  final List<String> _recentTransitions = [];
  static const int _maxTransitionHistory = 10;
  
  /// Plan the next track from candidates
  /// Returns ranked candidates optimized for sequence continuity
  List<Track> planSequence({
    required Track currentTrack,
    required List<Track> candidates,
    double targetEnergy = 0.5,
    bool maintainMomentum = true,
  }) {
    if (candidates.isEmpty) return [];
    
    final currentEnergy = _estimateTrackEnergy(currentTrack);
    _lastEnergy = currentEnergy;
    
    // Score each candidate for sequence fit
    final scored = <_SequenceScore>[];
    
    for (final candidate in candidates) {
      final score = _scoreForSequence(
        candidate: candidate,
        currentEnergy: currentEnergy,
        targetEnergy: targetEnergy,
        maintainMomentum: maintainMomentum,
      );
      scored.add(_SequenceScore(candidate, score));
    }
    
    // Sort by sequence score (higher = better fit)
    scored.sort((a, b) => b.score.compareTo(a.score));
    
    return scored.map((s) => s.track).toList();
  }
  
  /// Score a track for sequence placement
  double _scoreForSequence({
    required Track candidate,
    required double currentEnergy,
    required double targetEnergy,
    required bool maintainMomentum,
  }) {
    double score = 0.5; // Base score
    
    final candidateEnergy = _estimateTrackEnergy(candidate);
    
    // 1. Energy continuity (penalize large jumps)
    final energyDelta = (candidateEnergy - currentEnergy).abs();
    if (energyDelta <= _maxEnergyDelta) {
      score += 0.3; // Smooth transition bonus
    } else {
      // Penalty proportional to delta
      score -= (energyDelta - _maxEnergyDelta) * 2;
    }
    
    // 2. Target energy alignment
    final targetAlignment = 1 - (candidateEnergy - targetEnergy).abs();
    score += targetAlignment * 0.2;
    
    // 3. Session momentum alignment
    if (maintainMomentum && _sessionMomentum != 0) {
      final momentumDirection = _sessionMomentum > 0 ? 1 : -1;
      final energyDirection = (candidateEnergy - currentEnergy).sign;
      
      if (energyDirection == momentumDirection) {
        score += 0.15; // Matches momentum
      }
    }
    
    // 4. Transition variety (penalize repeating same artist)
    final transitionKey = '${candidate.artistName}';
    if (_recentTransitions.contains(transitionKey)) {
      score -= 0.1;
    }
    
    // 5. Artist variety bonus
    if (_recentTransitions.isNotEmpty) {
      final lastTransition = _recentTransitions.first;
      if (!lastTransition.contains(candidate.artistName)) {
        score += 0.05;
      }
    }
    
    return score.clamp(0.0, 1.0);
  }
  
  /// Estimate track energy (0-1) from metadata
  /// Uses heuristics when actual audio features unavailable
  double _estimateTrackEnergy(Track track) {
    // Use cached/stored energy if available
    // For now, use heuristic based on track name patterns
    
    final name = track.trackName.toLowerCase();
    final artist = track.artistName.toLowerCase();
    
    // High energy indicators
    final highEnergyPatterns = [
      'remix', 'club', 'dance', 'party', 'hype', 'live', 'rock', 
      'metal', 'punk', 'edm', 'bass', 'drop', 'fire', 'lit'
    ];
    
    // Low energy indicators  
    final lowEnergyPatterns = [
      'acoustic', 'piano', 'ballad', 'slow', 'sleep', 'relax',
      'calm', 'chill', 'ambient', 'lofi', 'lo-fi', 'soft', 'night'
    ];
    
    double energy = 0.5; // Default neutral
    
    for (final pattern in highEnergyPatterns) {
      if (name.contains(pattern) || artist.contains(pattern)) {
        energy += 0.1;
      }
    }
    
    for (final pattern in lowEnergyPatterns) {
      if (name.contains(pattern) || artist.contains(pattern)) {
        energy -= 0.1;
      }
    }
    
    return energy.clamp(0.0, 1.0);
  }
  
  /// Record a transition for variety tracking
  void recordTransition(Track from, Track to) {
    final key = '${from.artistName}->${to.artistName}';
    _recentTransitions.insert(0, key);
    
    while (_recentTransitions.length > _maxTransitionHistory) {
      _recentTransitions.removeLast();
    }
    
    // Update session momentum
    final fromEnergy = _estimateTrackEnergy(from);
    final toEnergy = _estimateTrackEnergy(to);
    final delta = toEnergy - fromEnergy;
    
    // Exponential moving average
    _sessionMomentum = _sessionMomentum * 0.7 + delta * 0.3;
  }
  
  /// Get current session energy trajectory
  double get sessionMomentum => _sessionMomentum;
  
  /// Reset for new session
  void resetSession() {
    _sessionMomentum = 0.0;
    _lastEnergy = null;
    _recentTransitions.clear();
  }
  
  /// Check if sequence is getting stale (too many same-artist transitions)
  bool isSequenceStale() {
    if (_recentTransitions.length < 3) return false;
    
    // Count unique artists in recent transitions
    final artists = <String>{};
    for (final t in _recentTransitions.take(5)) {
      final parts = t.split('->');
      if (parts.length == 2) {
        artists.add(parts[1]);
      }
    }
    
    return artists.length <= 2; // Too few unique artists
  }
  
  /// Get recommended energy shift for variety
  double getRecommendedEnergyShift() {
    // If momentum has been consistent, suggest opposite direction
    if (_sessionMomentum.abs() > 0.1) {
      return -_sessionMomentum.sign * 0.1;
    }
    return 0;
  }
}

/// Internal scoring class
class _SequenceScore {
  final Track track;
  final double score;
  
  _SequenceScore(this.track, this.score);
}

/// Transition smoothness evaluator
class TransitionEvaluator {
  /// Evaluate smoothness of a transition (0-1)
  static double evaluateTransition(Track from, Track to) {
    double smoothness = 0.5;
    
    // Same artist = smooth but potentially boring
    if (from.artistName == to.artistName) {
      smoothness += 0.2;
    }
    
    // Different artist in same "sonic space" = ideal
    // (Would use audio features if available)
    
    return smoothness.clamp(0.0, 1.0);
  }
}
