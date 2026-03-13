// lib/services/recommendation/taste_vector.dart
// User Music DNA — persistent representation of musical identity

import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/track.dart';
import '../recommendation_service.dart';

/// Genre mapping heuristics — maps artist names to genres
/// Uses keyword-based heuristics since we don't have a genre API
class GenreMapper {
  static const Map<String, List<String>> _genreKeywords = {
    'pop': ['pop', 'taylor swift', 'ariana grande', 'dua lipa', 'billie eilish', 'olivia rodrigo', 'harry styles', 'the weeknd', 'bruno mars', 'ed sheeran', 'justin bieber', 'selena gomez', 'shawn mendes', 'camila cabello', 'doja cat', 'bad bunny'],
    'rock': ['rock', 'arctic monkeys', 'imagine dragons', 'linkin park', 'foo fighters', 'green day', 'nirvana', 'radiohead', 'muse', 'coldplay', 'the killers', 'red hot chili peppers', 'pearl jam', 'queens of the stone age'],
    'hip-hop': ['hip-hop', 'rap', 'drake', 'kendrick lamar', 'travis scott', 'kanye', 'j. cole', 'eminem', '21 savage', 'lil', 'migos', 'future', 'post malone', 'juice wrld', 'xxxtentacion', 'nf', 'logic'],
    'r&b': ['r&b', 'sza', 'frank ocean', 'daniel caesar', 'brent faiyaz', 'h.e.r.', 'khalid', 'summer walker', 'jhene aiko', 'chris brown', 'usher', 'alicia keys'],
    'indie': ['indie', 'tame impala', 'mac demarco', 'clairo', 'mitski', 'phoebe bridgers', 'beach house', 'bon iver', 'fleet foxes', 'sufjan stevens', 'arcade fire', 'the national', 'glass animals'],
    'electronic': ['electronic', 'edm', 'dj', 'marshmello', 'deadmau5', 'skrillex', 'avicii', 'zedd', 'flume', 'calvin harris', 'tiesto', 'david guetta', 'kygo', 'illenium', 'alan walker'],
    'classical': ['classical', 'beethoven', 'mozart', 'bach', 'chopin', 'vivaldi', 'debussy', 'tchaikovsky', 'liszt', 'brahms', 'orchestra', 'symphony', 'concerto'],
    'jazz': ['jazz', 'miles davis', 'john coltrane', 'duke ellington', 'louis armstrong', 'herbie hancock', 'charlie parker', 'thelonious monk'],
    'metal': ['metal', 'metallica', 'iron maiden', 'megadeth', 'slayer', 'pantera', 'black sabbath', 'judas priest', 'avenged sevenfold', 'slipknot', 'disturbed', 'system of a down'],
    'country': ['country', 'morgan wallen', 'luke combs', 'chris stapleton', 'zach bryan', 'luke bryan', 'blake shelton', 'dolly parton', 'johnny cash', 'carrie underwood'],
    'latin': ['latin', 'reggaeton', 'bad bunny', 'j balvin', 'ozuna', 'daddy yankee', 'maluma', 'anuel', 'karol g', 'shakira', 'rosalia'],
    'k-pop': ['k-pop', 'kpop', 'bts', 'blackpink', 'stray kids', 'twice', 'aespa', 'newjeans', 'le sserafim', 'seventeen', 'txt', 'ateez', 'itzy', 'red velvet', 'exo'],
    'bollywood': ['bollywood', 'arijit singh', 'shreya ghoshal', 'atif aslam', 'neha kakkar', 'armaan malik', 'jubin nautiyal', 'a.r. rahman', 'vishal-shekhar', 'pritam', 'amit trivedi', 'badshah', 'yo yo honey singh'],
    'lo-fi': ['lo-fi', 'lofi', 'chillhop', 'chilled cow', 'nujabes', 'j dilla'],
    'punk': ['punk', 'blink-182', 'green day', 'sum 41', 'my chemical romance', 'paramore', 'the offspring', 'bad religion'],
    'soul': ['soul', 'motown', 'aretha franklin', 'stevie wonder', 'marvin gaye', 'ray charles', 'sam cooke', 'otis redding'],
    'ambient': ['ambient', 'brian eno', 'sigur ros', 'boards of canada', 'aphex twin'],
  };

  /// Infer genres from artist name using keyword matching
  static Map<String, double> inferGenres(String artistName) {
    final lower = artistName.toLowerCase().trim();
    final result = <String, double>{};
    
    for (final entry in _genreKeywords.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword) || keyword.contains(lower)) {
          result[entry.key] = (result[entry.key] ?? 0) + 1.0;
          break; // Only match once per genre
        }
      }
    }
    
    // Normalize
    if (result.isNotEmpty) {
      final total = result.values.reduce((a, b) => a + b);
      for (final key in result.keys.toList()) {
        result[key] = result[key]! / total;
      }
    }
    
    return result;
  }

  /// Infer genres from track name heuristics (e.g. "(Lo-Fi Mix)")
  static Map<String, double> inferFromTrackName(String trackName) {
    final lower = trackName.toLowerCase();
    final result = <String, double>{};
    
    if (lower.contains('remix') || lower.contains('mix')) {
      result['electronic'] = 0.3;
    }
    if (lower.contains('acoustic')) {
      result['indie'] = 0.3;
    }
    if (lower.contains('lo-fi') || lower.contains('lofi')) {
      result['lo-fi'] = 0.5;
    }
    if (lower.contains('unplugged')) {
      result['rock'] = 0.2;
    }
    
    return result;
  }
}

/// The user's musical DNA — a persistent taste fingerprint
class TasteVector {
  /// Genre affinities (genre -> 0.0-1.0)
  final Map<String, double> genres;
  
  /// Preferred energy level (0.0=calm, 1.0=high)
  final double energyPreference;
  
  /// Preferred tempo feel (0.0=slow, 1.0=fast)
  final double tempoPreference;
  
  /// How adventurous the user is (newArtists / totalArtists)
  final double discoveryRate;
  
  /// How much the user replays old favorites
  final double nostalgiaScore;
  
  /// Top 3 genres for quick access
  final List<String> topGenres;
  
  /// Confidence (0-1, based on data volume)
  final double confidence;
  
  const TasteVector({
    required this.genres,
    required this.energyPreference,
    required this.tempoPreference,
    required this.discoveryRate,
    required this.nostalgiaScore,
    required this.topGenres,
    required this.confidence,
  });
  
  /// Empty taste vector (new user)
  factory TasteVector.empty() => const TasteVector(
    genres: {},
    energyPreference: 0.5,
    tempoPreference: 0.5,
    discoveryRate: 0.0,
    nostalgiaScore: 0.0,
    topGenres: [],
    confidence: 0.0,
  );
  
  /// Calculate genre affinity for a track
  double genreAffinityFor(String artistName, {String? trackName}) {
    if (genres.isEmpty) return 0.5; // Neutral if no data
    
    final trackGenres = GenreMapper.inferGenres(artistName);
    if (trackName != null) {
      final nameGenres = GenreMapper.inferFromTrackName(trackName);
      for (final entry in nameGenres.entries) {
        trackGenres[entry.key] = (trackGenres[entry.key] ?? 0) + entry.value * 0.3;
      }
    }
    
    if (trackGenres.isEmpty) return 0.5; // Unknown genre
    
    // Cosine-like similarity between user genres and track genres
    double dotProduct = 0;
    for (final entry in trackGenres.entries) {
      dotProduct += (genres[entry.key] ?? 0) * entry.value;
    }
    
    return dotProduct.clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
    'genres': genres,
    'energyPreference': energyPreference,
    'tempoPreference': tempoPreference,
    'discoveryRate': discoveryRate,
    'nostalgiaScore': nostalgiaScore,
    'topGenres': topGenres,
    'confidence': confidence,
  };
  
  factory TasteVector.fromJson(Map<String, dynamic> json) => TasteVector(
    genres: Map<String, double>.from((json['genres'] as Map?)?.map(
      (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
    ) ?? {}),
    energyPreference: (json['energyPreference'] as num?)?.toDouble() ?? 0.5,
    tempoPreference: (json['tempoPreference'] as num?)?.toDouble() ?? 0.5,
    discoveryRate: (json['discoveryRate'] as num?)?.toDouble() ?? 0.0,
    nostalgiaScore: (json['nostalgiaScore'] as num?)?.toDouble() ?? 0.0,
    topGenres: List<String>.from(json['topGenres'] as List? ?? []),
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
  );
}

/// Builds a TasteVector from accumulated signal data
class TasteVectorBuilder {
  /// Build taste vector from signal cache and long-term model
  static TasteVector build({
    required Map<String, TrackSignal> signalCache,
    required List<double> energyDistribution,
    required Set<String> knownArtists,
    required int totalUniqueArtists,
  }) {
    if (signalCache.isEmpty) return TasteVector.empty();
    
    // 1. Build genre distribution from all signals
    final genreAccum = <String, double>{};
    double totalWeight = 0;
    
    for (final signal in signalCache.values) {
      final weight = _signalWeight(signal);
      final artistGenres = GenreMapper.inferGenres(signal.artistName);
      
      for (final entry in artistGenres.entries) {
        genreAccum[entry.key] = (genreAccum[entry.key] ?? 0) + entry.value * weight;
      }
      totalWeight += weight;
    }
    
    // Normalize genres
    final genres = <String, double>{};
    if (totalWeight > 0) {
      for (final entry in genreAccum.entries) {
        genres[entry.key] = (entry.value / totalWeight).clamp(0.0, 1.0);
      }
    }
    
    // 2. Top 3 genres
    final sortedGenres = genres.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topGenres = sortedGenres.take(3).map((e) => e.key).toList();
    
    // 3. Energy preference from distribution
    double energyPref = 0.5;
    if (energyDistribution.isNotEmpty) {
      double weightedSum = 0;
      double distSum = 0;
      for (int i = 0; i < energyDistribution.length && i <= 10; i++) {
        weightedSum += (i / 10.0) * energyDistribution[i];
        distSum += energyDistribution[i];
      }
      if (distSum > 0) energyPref = (weightedSum / distSum).clamp(0.0, 1.0);
    }
    
    // 4. Discovery rate
    double discoveryRate = 0.0;
    if (totalUniqueArtists > 0 && knownArtists.isNotEmpty) {
      // Approximate: new artists = total unique - established (playCount >= 3)
      final established = signalCache.values
          .map((s) => s.artistName)
          .toSet()
          .where((a) => signalCache.values
              .where((s) => s.artistName == a)
              .fold<int>(0, (sum, s) => sum + s.playCount) >= 3)
          .length;
      discoveryRate = ((totalUniqueArtists - established) / totalUniqueArtists).clamp(0.0, 1.0);
    }
    
    // 5. Nostalgia score (ratio of replayed old tracks)
    double nostalgiaScore = 0.0;
    final now = DateTime.now();
    int oldReplays = 0;
    int totalReplays = 0;
    for (final signal in signalCache.values) {
      if (signal.replayCount > 0) {
        totalReplays += signal.replayCount;
        final daysSinceFirst = now.difference(signal.lastPlayed).inDays;
        if (daysSinceFirst > 30) {
          oldReplays += signal.replayCount;
        }
      }
    }
    if (totalReplays > 0) {
      nostalgiaScore = (oldReplays / totalReplays).clamp(0.0, 1.0);
    }
    
    // 6. Confidence
    final dataPoints = signalCache.length;
    final confidence = (dataPoints / 50.0).clamp(0.0, 1.0); // Full confidence at 50+ signals
    
    return TasteVector(
      genres: genres,
      energyPreference: energyPref,
      tempoPreference: energyPref * 0.8 + 0.1, // Correlate with energy
      discoveryRate: discoveryRate,
      nostalgiaScore: nostalgiaScore,
      topGenres: topGenres,
      confidence: confidence,
    );
  }
  
  /// Calculate signal weight (engagement-based)
  static double _signalWeight(TrackSignal signal) {
    double w = 0;
    w += signal.playCount * 0.3;
    w += signal.completionRate * 0.4;
    w += signal.likeCount * 0.5;
    w -= signal.skipCount * 0.2;
    return max(0.1, w);
  }
}
