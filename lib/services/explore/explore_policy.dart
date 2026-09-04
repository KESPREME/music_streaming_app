import 'package:music_streaming_app/services/recommendation/candidate.dart';
import 'package:music_streaming_app/services/recommendation/ranker.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';

/// Explore policy: constants + the discovery-tilted ranking configuration.
/// One shared recommendation stack, one config variant (spec #96/#97).
abstract class ExplorePolicy {
  /// Initial session batch (spec #24: bounded startup, 6–12).
  static const int initialBatch = 12;

  /// Refill batch size.
  static const int refillBatch = 14;

  /// Refill when this many items remain ahead of the user (spec #25).
  static const int refillThreshold = 5;

  /// How many upcoming artworks to prefetch (spec #88).
  static const int prefetchAhead = 3;

  /// Related-songs fetch size for the seed chain.
  static const int relatedLimit = 25;

  /// Max consecutive pages from one artist (session-level soft cap).
  static const int maxArtistRun = 2;

  /// Minimum dwell (seconds) before a swipe-away counts as neutral
  /// rather than a skip signal.
  static const int skipDwellSeconds = 8;

  /// Discovery tilt: cap the personal blend well below Quick Picks'
  /// warm confidence so popularity/freshness still shape the stream
  /// (spec #11/#18). Cold profiles stay popularity-heavy (#58).
  static RankingConfig ranking(TasteProfile profile) {
    final confidence =
        (profile.personalizationConfidence * 0.75).clamp(0.15, 0.60);
    return RankingConfig.forConfidence(confidence);
  }

  static const Map<String, CandidateReason> _reasonMap = {
    'seed': CandidateReason.relatedToListening,
    'native_home': CandidateReason.nativeRecommendation,
    'quick_picks': CandidateReason.recentlyPlayed,
    'local_favorites': CandidateReason.favoriteArtist,
    'local_history': CandidateReason.recentlyPlayed,
    'chart_regional': CandidateReason.regionalTrending,
    'chart_global': CandidateReason.globalTrending,
    'new_release': CandidateReason.newReleaseArtist,
  };

  static CandidateReason reasonFor(String source) =>
      _reasonMap[source] ?? CandidateReason.exploration;

  /// Short user-facing explanation (spec #71).
  static String reasonLabel(CandidateReason reason) => switch (reason) {
        CandidateReason.relatedToListening => 'Related to current',
        CandidateReason.nativeRecommendation => 'Recommended',
        CandidateReason.recentlyPlayed => 'From your listening',
        CandidateReason.favoriteArtist => 'Artist you like',
        CandidateReason.searchFollowup => 'From your search',
        CandidateReason.regionalTrending => 'Trending near you',
        CandidateReason.globalTrending => 'Trending worldwide',
        CandidateReason.newReleaseArtist => 'New release',
        CandidateReason.genreAffinity => 'Your genres',
        CandidateReason.exploration => 'Discovery',
        CandidateReason.frequentArtist => 'Often played',
      };
}
