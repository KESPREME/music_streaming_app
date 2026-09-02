// lib/services/recommendation/sequence_planner.dart
// Autoplay sequence planning with energy continuity

import '../../models/track.dart';

/// Plans optimal track sequences for autoplay
/// Focuses on energy continuity and smooth transitions
class SequencePlanner {
  // Maximum energy change per transition (±15% recommended)
  static const double _maxEnergyDelta = 0.15;

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

    // Score each candidate for sequence fit
    final scored = <_SequenceScore>[];

    for (final candidate in candidates) {
      final score = _scoreForSequence(
        candidate: candidate,
        currentEnergy: currentEnergy,
        targetEnergy: targetEnergy,
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

    return score.clamp(0.0, 1.0);
  }

  /// Estimate track energy (0-1) from metadata
  /// Uses heuristics when actual audio features unavailable
  double _estimateTrackEnergy(Track track) {
    final name = track.trackName.toLowerCase();
    final artist = track.artistName.toLowerCase();

    // High energy indicators
    final highEnergyPatterns = [
      'remix',
      'club',
      'dance',
      'party',
      'hype',
      'live',
      'rock',
      'metal',
      'punk',
      'edm',
      'bass',
      'drop',
      'fire',
      'lit'
    ];

    // Low energy indicators
    final lowEnergyPatterns = [
      'acoustic',
      'piano',
      'ballad',
      'slow',
      'sleep',
      'relax',
      'calm',
      'chill',
      'ambient',
      'lofi',
      'lo-fi',
      'soft',
      'night'
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
}

/// Internal scoring class
class _SequenceScore {
  final Track track;
  final double score;

  _SequenceScore(this.track, this.score);
}
