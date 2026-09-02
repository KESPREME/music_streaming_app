/// Candidate model for the recommendation engine (spec #4/#42/#80).
/// Every candidate carries: identity, provenance, and an explainable reason.
library;

/// Why this candidate was considered.
enum CandidateReason {
  favoriteArtist,
  recentlyPlayed,
  frequentArtist,
  searchFollowup,
  relatedToListening,
  regionalTrending,
  globalTrending,
  newReleaseArtist,
  nativeRecommendation,
  exploration,
}

/// One ranked candidate for a recommendation section.
class Candidate<T> {
  const Candidate({
    required this.item,
    required this.reason,
    required this.score,
    this.secondaryReasons = const [],
    this.source,
  });

  final T item;
  final CandidateReason reason;
  final double score;
  final List<CandidateReason> secondaryReasons;

  /// Which pool generated this candidate (spec #17).
  final String? source;

  @override
  String toString() =>
      'Candidate(reason=$reason score=${score.toStringAsFixed(2)} source=$source)';
}
