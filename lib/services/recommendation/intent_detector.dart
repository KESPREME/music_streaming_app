// lib/services/recommendation/intent_detector.dart
// Short-term intent detection — what the user wants RIGHT NOW

import 'package:flutter/foundation.dart';
import '../../models/track.dart';
import '../recommendation_service.dart';
import 'taste_vector.dart';

/// Detected listening mood
enum ListeningMood {
  energetic,  // High energy tracks
  relaxed,    // Low energy, calm
  focused,    // Long completion rates, steady energy
  nostalgic,  // Replaying old favorites
  exploring,  // Many different artists
  party,      // High energy + late hours
  melancholy, // Slow, emotional tracks
  neutral,    // No strong pattern
}

/// Represents the user's current listening intent
class ListeningIntent {
  /// Dominant genre right now
  final String? dominantGenre;
  
  /// Current energy level (0.0-1.0)
  final double energy;
  
  /// Detected mood
  final ListeningMood mood;
  
  /// Whether user is on an artist streak (3+ same artist)
  final bool artistStreak;
  
  /// The streak artist name (if any)
  final String? streakArtist;
  
  /// Whether user is on a genre streak (3+ same genre)
  final bool genreStreak;
  
  /// Whether user is in high-energy mode
  final bool highEnergyStreak;
  
  /// Time of day bias
  final TimeOfDayBias timeOfDay;
  
  /// Confidence in the detected intent (0-1)
  final double confidence;
  
  /// Human-readable description
  final String description;
  
  const ListeningIntent({
    this.dominantGenre,
    required this.energy,
    required this.mood,
    this.artistStreak = false,
    this.streakArtist,
    this.genreStreak = false,
    this.highEnergyStreak = false,
    required this.timeOfDay,
    required this.confidence,
    required this.description,
  });
  
  factory ListeningIntent.neutral() => const ListeningIntent(
    energy: 0.5,
    mood: ListeningMood.neutral,
    timeOfDay: TimeOfDayBias.afternoon,
    confidence: 0.0,
    description: 'No strong listening pattern detected',
  );
}

/// Time-of-day context
enum TimeOfDayBias {
  earlyMorning,  // 5-8 AM  → calm, acoustic
  morning,       // 8-12 PM → upbeat, pop
  afternoon,     // 12-5 PM → varied
  evening,       // 5-9 PM  → social, pop, hip-hop
  lateNight,     // 9 PM-12 → chill, r&b, lo-fi
  deepNight,     // 12-5 AM → ambient, electronic, lo-fi
}

/// Detects user's current listening intent from recent tracks
class IntentDetector {
  /// Detect intent from recent tracks and signals
  static ListeningIntent detect({
    required List<Track> recentTracks,
    required Map<String, TrackSignal> signalCache,
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now();
    final timeOfDay = _getTimeOfDay(now);
    
    if (recentTracks.isEmpty) {
      return ListeningIntent(
        energy: _timeBasedEnergy(timeOfDay),
        mood: _timeBasedMood(timeOfDay),
        timeOfDay: timeOfDay,
        confidence: 0.1,
        description: _timeBasedDescription(timeOfDay),
      );
    }
    
    final recent = recentTracks.take(10).toList();
    
    // 1. Detect artist streak
    String? streakArtist;
    bool artistStreak = false;
    if (recent.length >= 2) {
      final firstArtist = recent[0].artistName;
      int streakCount = 0;
      for (final track in recent) {
        if (track.artistName == firstArtist) {
          streakCount++;
        } else {
          break;
        }
      }
      if (streakCount >= 2) {
        artistStreak = true;
        streakArtist = firstArtist;
      }
    }
    
    // 2. Detect genre streak
    bool genreStreak = false;
    String? dominantGenre;
    final genreCounts = <String, int>{};
    for (final track in recent) {
      final genres = GenreMapper.inferGenres(track.artistName);
      for (final genre in genres.keys) {
        genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
      }
    }
    if (genreCounts.isNotEmpty) {
      final sorted = genreCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      dominantGenre = sorted.first.key;
      genreStreak = sorted.first.value >= 3;
    }
    
    // 3. Estimate energy from completion rates and play patterns
    double avgEnergy = 0.5;
    int energySamples = 0;
    for (final track in recent) {
      final signal = signalCache[track.id];
      if (signal != null) {
        // High completion + high play count = probably matching energy preference
        final engagement = signal.completionRate * 0.6 + 
            (signal.playCount > 1 ? 0.4 : 0);
        avgEnergy += engagement * 0.1;
        energySamples++;
      }
    }
    if (energySamples > 0) {
      avgEnergy = (avgEnergy / energySamples).clamp(0.0, 1.0);
    }
    
    // 4. Detect high energy streak
    bool highEnergyStreak = false;
    int highEnergyCount = 0;
    for (final track in recent.take(5)) {
      final signal = signalCache[track.id];
      if (signal != null && signal.completionRate > 0.8) {
        highEnergyCount++;
      }
    }
    highEnergyStreak = highEnergyCount >= 3;
    
    // 5. Detect mood
    final mood = _detectMood(
      recent: recent,
      signalCache: signalCache,
      avgEnergy: avgEnergy,
      timeOfDay: timeOfDay,
      highEnergyStreak: highEnergyStreak,
    );
    
    // 6. Confidence
    final confidence = (recent.length / 10.0).clamp(0.0, 1.0);
    
    // 7. Build description
    final description = _buildDescription(
      mood: mood,
      dominantGenre: dominantGenre,
      artistStreak: artistStreak,
      streakArtist: streakArtist,
      timeOfDay: timeOfDay,
    );
    
    return ListeningIntent(
      dominantGenre: dominantGenre,
      energy: avgEnergy,
      mood: mood,
      artistStreak: artistStreak,
      streakArtist: streakArtist,
      genreStreak: genreStreak,
      highEnergyStreak: highEnergyStreak,
      timeOfDay: timeOfDay,
      confidence: confidence,
      description: description,
    );
  }
  
  static TimeOfDayBias _getTimeOfDay(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 8) return TimeOfDayBias.earlyMorning;
    if (hour >= 8 && hour < 12) return TimeOfDayBias.morning;
    if (hour >= 12 && hour < 17) return TimeOfDayBias.afternoon;
    if (hour >= 17 && hour < 21) return TimeOfDayBias.evening;
    if (hour >= 21 || hour < 1) return TimeOfDayBias.lateNight;
    return TimeOfDayBias.deepNight;
  }
  
  static double _timeBasedEnergy(TimeOfDayBias time) {
    switch (time) {
      case TimeOfDayBias.earlyMorning: return 0.3;
      case TimeOfDayBias.morning: return 0.6;
      case TimeOfDayBias.afternoon: return 0.5;
      case TimeOfDayBias.evening: return 0.7;
      case TimeOfDayBias.lateNight: return 0.4;
      case TimeOfDayBias.deepNight: return 0.25;
    }
  }
  
  static ListeningMood _timeBasedMood(TimeOfDayBias time) {
    switch (time) {
      case TimeOfDayBias.earlyMorning: return ListeningMood.relaxed;
      case TimeOfDayBias.morning: return ListeningMood.energetic;
      case TimeOfDayBias.afternoon: return ListeningMood.neutral;
      case TimeOfDayBias.evening: return ListeningMood.energetic;
      case TimeOfDayBias.lateNight: return ListeningMood.relaxed;
      case TimeOfDayBias.deepNight: return ListeningMood.relaxed;
    }
  }
  
  static String _timeBasedDescription(TimeOfDayBias time) {
    switch (time) {
      case TimeOfDayBias.earlyMorning: return 'Good morning — calm vibes to start your day';
      case TimeOfDayBias.morning: return 'Morning energy — upbeat tracks to power through';
      case TimeOfDayBias.afternoon: return 'Afternoon chill — discover new sounds';
      case TimeOfDayBias.evening: return 'Evening mode — your go-to favorites';
      case TimeOfDayBias.lateNight: return 'Late night — wind down with soothing tracks';
      case TimeOfDayBias.deepNight: return 'Night owl — ambient moods for the quiet hours';
    }
  }
  
  static ListeningMood _detectMood({
    required List<Track> recent,
    required Map<String, TrackSignal> signalCache,
    required double avgEnergy,
    required TimeOfDayBias timeOfDay,
    required bool highEnergyStreak,
  }) {
    // Check for completion-based focus mode
    int highCompletionCount = 0;
    for (final track in recent.take(5)) {
      final signal = signalCache[track.id];
      if (signal != null && signal.completionRate > 0.9) {
        highCompletionCount++;
      }
    }
    if (highCompletionCount >= 4) return ListeningMood.focused;
    
    // Check for nostalgia (replaying old favorites)
    int replayCount = 0;
    for (final track in recent.take(5)) {
      final signal = signalCache[track.id];
      if (signal != null && signal.replayCount > 2) {
        replayCount++;
      }
    }
    if (replayCount >= 3) return ListeningMood.nostalgic;
    
    // Check for exploration (many different artists)
    final uniqueArtists = recent.take(8).map((t) => t.artistName).toSet();
    if (uniqueArtists.length >= 7) return ListeningMood.exploring;
    
    // Energy-based mood
    if (highEnergyStreak) {
      if (timeOfDay == TimeOfDayBias.evening || timeOfDay == TimeOfDayBias.lateNight) {
        return ListeningMood.party;
      }
      return ListeningMood.energetic;
    }
    
    if (avgEnergy < 0.35) {
      if (timeOfDay == TimeOfDayBias.lateNight || timeOfDay == TimeOfDayBias.deepNight) {
        return ListeningMood.melancholy;
      }
      return ListeningMood.relaxed;
    }
    
    return ListeningMood.neutral;
  }
  
  static String _buildDescription({
    required ListeningMood mood,
    required String? dominantGenre,
    required bool artistStreak,
    required String? streakArtist,
    required TimeOfDayBias timeOfDay,
  }) {
    if (artistStreak && streakArtist != null) {
      return 'You\'re on a $streakArtist streak';
    }
    
    switch (mood) {
      case ListeningMood.energetic:
        return 'High energy vibes${dominantGenre != null ? ' — heavy on $dominantGenre' : ''}';
      case ListeningMood.relaxed:
        return 'Chill mode${dominantGenre != null ? ' — $dominantGenre vibes' : ''}';
      case ListeningMood.focused:
        return 'Deep focus — you\'re locked in';
      case ListeningMood.nostalgic:
        return 'Throwback time — revisiting your classics';
      case ListeningMood.exploring:
        return 'Discovery mode — exploring new sounds';
      case ListeningMood.party:
        return 'Party energy — keep it going!';
      case ListeningMood.melancholy:
        return 'Late night feels${dominantGenre != null ? ' — $dominantGenre mood' : ''}';
      case ListeningMood.neutral:
        return dominantGenre != null 
            ? 'Vibing with $dominantGenre' 
            : 'Mixed listening — open to anything';
    }
  }
}
