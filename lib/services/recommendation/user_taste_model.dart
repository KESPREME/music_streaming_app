// lib/services/recommendation/user_taste_model.dart
// Long-term and short-term user taste modeling for the recommendation agent

import 'dart:math';
import 'package:flutter/foundation.dart';

/// Long-term stable taste preferences (artist clusters, genre, energy)
/// Updated slowly, requires consistent evidence
class LongTermTasteModel {
  // Artist affinity clusters (artist -> affinity score 0-1)
  final Map<String, double> artistAffinities = {};
  
  // Energy preference distribution (0-10 bins)
  final List<double> energyDistribution = List.filled(11, 0.0);
  
  // Era preference (decade -> weight)
  final Map<String, double> eraPreferences = {};
  
  // Confidence in the model (0-1, based on data volume)
  double confidence = 0.0;
  
  // Last update time
  DateTime lastUpdated = DateTime.now();
  
  /// Update artist affinity (requires 3+ plays for significant update)
  void updateArtistAffinity(String artist, double delta, int playCount) {
    if (playCount < 3) {
      // Require consistent evidence - minor update only
      delta *= 0.1;
    }
    
    final current = artistAffinities[artist] ?? 0.5;
    // Slow exponential moving average
    artistAffinities[artist] = (current * 0.9 + delta.clamp(0, 1) * 0.1).clamp(0.0, 1.0);
    _updateConfidence();
  }
  
  /// Update energy preference based on completed tracks
  void updateEnergyPreference(double energy, double weight) {
    final bin = (energy * 10).clamp(0, 10).round();
    // Slow update to energy distribution
    for (int i = 0; i <= 10; i++) {
      if (i == bin) {
        energyDistribution[i] = (energyDistribution[i] * 0.95 + weight * 0.05).clamp(0, 1);
      } else {
        // Slight decay for other bins
        energyDistribution[i] *= 0.999;
      }
    }
    _updateConfidence();
  }
  
  /// Get preferred energy range (returns center and range)
  (double center, double range) getPreferredEnergyRange() {
    if (confidence < 0.1) return (0.5, 0.5); // No preference yet
    
    double sum = 0;
    double weightedSum = 0;
    for (int i = 0; i <= 10; i++) {
      final energy = i / 10.0;
      sum += energyDistribution[i];
      weightedSum += energy * energyDistribution[i];
    }
    
    if (sum == 0) return (0.5, 0.5);
    
    final center = weightedSum / sum;
    // Calculate standard deviation as range
    double variance = 0;
    for (int i = 0; i <= 10; i++) {
      final energy = i / 10.0;
      final diff = energy - center;
      variance += energyDistribution[i] * diff * diff;
    }
    final range = sqrt(variance / sum).clamp(0.1, 0.5);
    
    return (center, range);
  }
  
  /// Get top N preferred artists
  List<String> getTopArtists({int limit = 10}) {
    final sorted = artistAffinities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }
  
  /// Get artist affinity score (0-1)
  double getArtistAffinity(String artist) {
    return artistAffinities[artist] ?? 0.5; // Neutral default
  }
  
  void _updateConfidence() {
    // Confidence based on data volume
    final artistCount = artistAffinities.length;
    final energySum = energyDistribution.reduce((a, b) => a + b);
    
    confidence = ((artistCount / 50.0) * 0.6 + (energySum / 10.0) * 0.4).clamp(0.0, 1.0);
    lastUpdated = DateTime.now();
  }
  
  Map<String, dynamic> toMap() => {
    'artist_affinities': artistAffinities,
    'energy_distribution': energyDistribution,
    'era_preferences': eraPreferences,
    'confidence': confidence,
    'last_updated': lastUpdated.millisecondsSinceEpoch,
  };
  
  void fromMap(Map<String, dynamic> map) {
    artistAffinities.clear();
    (map['artist_affinities'] as Map<String, dynamic>?)?.forEach((k, v) {
      artistAffinities[k] = (v as num).toDouble();
    });
    
    final energyList = map['energy_distribution'] as List<dynamic>?;
    if (energyList != null) {
      for (int i = 0; i < min(11, energyList.length); i++) {
        energyDistribution[i] = (energyList[i] as num).toDouble();
      }
    }
    
    eraPreferences.clear();
    (map['era_preferences'] as Map<String, dynamic>?)?.forEach((k, v) {
      eraPreferences[k] = (v as num).toDouble();
    });
    
    confidence = (map['confidence'] as num?)?.toDouble() ?? 0.0;
    lastUpdated = DateTime.fromMillisecondsSinceEpoch(
      map['last_updated'] as int? ?? DateTime.now().millisecondsSinceEpoch
    );
  }
}

/// Short-term session intent (last 7 plays, current mood, skip momentum)
/// Updated frequently, decays rapidly
class ShortTermIntentModel {
  // Sliding window of recent tracks (max 7)
  final List<_RecentListen> recentListens = [];
  static const int _maxRecent = 7;
  
  // Skip momentum (consecutive skips, resets on completion)
  int skipMomentum = 0;
  
  // Current session energy trajectory (positive = increasing, negative = decreasing)
  double energyTrajectory = 0.0;
  
  // Session start time
  DateTime sessionStart = DateTime.now();
  
  // Recent search queries (for intent detection)
  final List<String> recentSearches = [];
  static const int _maxSearches = 5;
  
  /// Record a track listen
  void recordListen({
    required String trackId,
    required String artistName,
    required double completionRate,
    double? energy,
  }) {
    // Update skip momentum
    if (completionRate < 0.3) {
      skipMomentum = min(5, skipMomentum + 1); // Cap at 5
    } else {
      skipMomentum = max(0, skipMomentum - 1); // Decay on completion
    }
    
    // Update energy trajectory
    if (energy != null && recentListens.isNotEmpty) {
      final lastEnergy = recentListens.first.energy;
      if (lastEnergy != null) {
        final delta = energy - lastEnergy;
        // Exponential moving average
        energyTrajectory = energyTrajectory * 0.7 + delta * 0.3;
      }
    }
    
    // Add to recent listens (most recent first)
    recentListens.insert(0, _RecentListen(
      trackId: trackId,
      artistName: artistName,
      completionRate: completionRate,
      energy: energy,
      timestamp: DateTime.now(),
    ));
    
    // Trim to max size
    while (recentListens.length > _maxRecent) {
      recentListens.removeLast();
    }
  }
  
  /// Record a search query
  void recordSearch(String query) {
    recentSearches.insert(0, query.toLowerCase().trim());
    while (recentSearches.length > _maxSearches) {
      recentSearches.removeLast();
    }
  }
  
  /// Get recently listened artists (for short-term affinity)
  Set<String> getRecentArtists() {
    return recentListens.map((l) => l.artistName).toSet();
  }
  
  /// Get current energy preference (based on trajectory)
  double getCurrentEnergyPreference() {
    if (recentListens.isEmpty) return 0.5;
    
    // Average recent energy + trajectory
    double sum = 0;
    int count = 0;
    for (final listen in recentListens) {
      if (listen.energy != null) {
        sum += listen.energy!;
        count++;
      }
    }
    
    if (count == 0) return 0.5;
    
    final avgEnergy = sum / count;
    // Apply trajectory to predict desired energy
    return (avgEnergy + energyTrajectory * 0.2).clamp(0.0, 1.0);
  }
  
  /// Check if user is in "skip mode" (high momentum)
  bool isInSkipMode() => skipMomentum >= 3;
  
  /// Check if session is stale (needs refresh)
  bool isSessionStale() {
    return DateTime.now().difference(sessionStart) > const Duration(hours: 4);
  }
  
  /// Reset for new session
  void startNewSession() {
    recentListens.clear();
    skipMomentum = 0;
    energyTrajectory = 0;
    sessionStart = DateTime.now();
  }
  
  /// Get average completion rate (session quality indicator)
  double getSessionQuality() {
    if (recentListens.isEmpty) return 0.5;
    final sum = recentListens.fold(0.0, (s, l) => s + l.completionRate);
    return sum / recentListens.length;
  }
}

class _RecentListen {
  final String trackId;
  final String artistName;
  final double completionRate;
  final double? energy;
  final DateTime timestamp;
  
  _RecentListen({
    required this.trackId,
    required this.artistName,
    required this.completionRate,
    this.energy,
    required this.timestamp,
  });
}

/// Blends long-term and short-term models based on context
class UserTasteBlender {
  final LongTermTasteModel longTerm;
  final ShortTermIntentModel shortTerm;
  
  UserTasteBlender(this.longTerm, this.shortTerm);
  
  /// Get blended artist affinity
  /// Short-term has higher weight when session is active
  double getBlendedArtistAffinity(String artist) {
    final ltAffinity = longTerm.getArtistAffinity(artist);
    final isRecentArtist = shortTerm.getRecentArtists().contains(artist);
    
    // Blend based on long-term confidence and session activity
    final shortTermWeight = _calculateShortTermWeight();
    
    if (isRecentArtist) {
      // Boost for recently played artists
      return (ltAffinity * (1 - shortTermWeight) + 0.8 * shortTermWeight).clamp(0.0, 1.0);
    } else {
      return ltAffinity;
    }
  }
  
  /// Get blended energy preference
  double getBlendedEnergyPreference() {
    final (ltCenter, _) = longTerm.getPreferredEnergyRange();
    final stEnergy = shortTerm.getCurrentEnergyPreference();
    
    final shortTermWeight = _calculateShortTermWeight();
    
    return ltCenter * (1 - shortTermWeight) + stEnergy * shortTermWeight;
  }
  
  /// Calculate short-term weight (0-0.6)
  /// Higher when session is active and long-term confidence is low
  double _calculateShortTermWeight() {
    // Base weight from session activity
    final sessionAge = DateTime.now().difference(shortTerm.sessionStart).inMinutes;
    final activityWeight = sessionAge < 30 ? 0.5 : (sessionAge < 60 ? 0.4 : 0.3);
    
    // Reduce short-term weight if user is in skip mode (erratic behavior)
    final skipPenalty = shortTerm.isInSkipMode() ? 0.2 : 0.0;
    
    // Increase short-term weight if long-term confidence is low
    final confidenceBoost = (1 - longTerm.confidence) * 0.2;
    
    return (activityWeight - skipPenalty + confidenceBoost).clamp(0.2, 0.6);
  }
  
  /// Check if we should heavily favor exploitation vs exploration
  bool shouldExploit() {
    // Exploit (safe recommendations) when:
    // - Skip momentum is high (user is frustrated)
    // - Session quality is low
    return shortTerm.isInSkipMode() || shortTerm.getSessionQuality() < 0.4;
  }
}
