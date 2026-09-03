import '../../models/track.dart';
import 'candidate.dart' show CandidateReason;
import 'candidate_metadata.dart';
import 'quick_picks_engine.dart' show QuickPickCandidate;
import 'taste_profile.dart';

/// New Releases engine v2 (spec #40-46): actual recent releases from a
/// trusted source, freshness-banded, affinity-ranked, soft-capped.
/// Deterministic — no Random.
class NewReleasesEngineV2 {
  NewReleasesEngineV2({this.now});

  final DateTime? now;

  /// Freshness bands (spec #44): veryRecent ≤1y, recent ≤2y, aging ≤3y.
  /// Older than 3y leaves the section; missing year on a trusted source
  /// is kept as veryRecent-by-construction (the source IS the new
  /// releases shelf) — never fabricated onto untrusted items.
  static FreshnessBand bandFor(int? releaseYear, DateTime now) {
    if (releaseYear == null) return FreshnessBand.veryRecent;
    final age = now.year - releaseYear;
    if (age <= 1) return FreshnessBand.veryRecent;
    if (age <= 2) return FreshnessBand.recent;
    if (age <= 3) return FreshnessBand.aging;
    return FreshnessBand.stale;
  }

  List<QuickPickCandidate> generate({
    required List<RichCandidate> releases,
    required TasteProfile profile,
    int limit = 10,
  }) {
    final clock = now ?? DateTime.now();
    final scored = <(RichCandidate, double, FreshnessBand, double)>[];

    for (final release in releases) {
      // Validation (spec #41): identity sanity is upstream; here staleness
      // and trust decide. Stale leaves; untrusted + unknown year leaves.
      final band = bandFor(release.releaseYear, clock);
      if (band == FreshnessBand.stale) continue;
      if (release.releaseYear == null &&
          release.sourceTrust == SourceTrust.low) {
        continue;
      }

      // Ranking (spec #42): artist affinity dominates, then genre, then
      // freshness band, then chart popularity when known.
      var artistAffinity = 0.0;
      for (final artistName in release.artists) {
        final value = profile.artistAffinity(artistName);
        if (value > artistAffinity) artistAffinity = value;
      }
      var genreAffinity = 0.0;
      for (final genre in release.genres) {
        final value = profile.genreAffinity(genre);
        if (value > genreAffinity) genreAffinity = value;
      }
      final freshness = switch (band) {
        FreshnessBand.veryRecent => 1.0,
        FreshnessBand.recent => 0.6,
        FreshnessBand.aging => 0.3,
        FreshnessBand.stale => 0.0,
      };
      final popularity = release.popularity ?? 0.0;

      final score = 0.40 * artistAffinity +
          0.15 * genreAffinity +
          0.25 * freshness +
          0.20 * popularity;

      scored.add((release, score, band, artistAffinity));
    }

    // Deterministic sort: score DESC → freshness band → id ASC.
    scored.sort((a, b) {
      final cmp = b.$2.compareTo(a.$2);
      if (cmp != 0) return cmp;
      final bandCmp = a.$3.index.compareTo(b.$3.index);
      if (bandCmp != 0) return bandCmp;
      return a.$1.id.compareTo(b.$1.id);
    });

    // Soft caps (spec #45): artist ≤3, album ≤2. Unknown artist pool gets
    // no special treatment — popularity carries cold start (spec #46).
    final artistCounts = <String, int>{};
    final albumCounts = <String, int>{};
    final output = <QuickPickCandidate>[];
    for (final (release, score, band, artistAffinity) in scored) {
      if (output.length >= limit) break;
      final artistKey = release.primaryArtist.toLowerCase().trim();
      if (artistKey.isNotEmpty) {
        final count = artistCounts[artistKey] ?? 0;
        if (count >= 3) continue;
        artistCounts[artistKey] = count + 1;
      }
      final albumKey = release.albumName?.toLowerCase().trim();
      if (albumKey != null && albumKey.isNotEmpty) {
        final count = albumCounts[albumKey] ?? 0;
        if (count >= 2) continue;
        albumCounts[albumKey] = count + 1;
      }

      final secondary = <CandidateReason>[];
      if (artistAffinity > 0.05) secondary.add(CandidateReason.frequentArtist);
      if (release.popularity != null && release.popularity! > 0.3) {
        secondary.add(CandidateReason.regionalTrending);
      }
      final reason = artistAffinity > 0.05
          ? CandidateReason.newReleaseArtist
          : (release.releaseYear == null
              ? CandidateReason.newReleaseArtist
              : CandidateReason.exploration);

      output.add(QuickPickCandidate(
        track: _toTrack(release),
        reason: reason,
        score: score,
        secondaryReasons: secondary,
        source: 'new_release',
        confidence:
            (artistAffinity * 0.6 + genreAffinityOf(release, profile) * 0.4)
                .clamp(0.0, 1.0),
        features: {
          'artistAffinity': artistAffinity,
          'popularity': release.popularity ?? 0.0,
          'freshness': switch (band) {
            FreshnessBand.veryRecent => 1.0,
            FreshnessBand.recent => 0.6,
            FreshnessBand.aging => 0.3,
            FreshnessBand.stale => 0.0,
          },
        },
        trackId: release.id,
      ));
    }
    return output;
  }

  static double genreAffinityOf(RichCandidate release, TasteProfile profile) {
    var best = 0.0;
    for (final genre in release.genres) {
      final value = profile.genreAffinity(genre);
      if (value > best) best = value;
    }
    return best;
  }

  static Track _toTrack(RichCandidate release) => Track(
        id: release.id,
        trackName: release.title,
        artistName: release.artists.join(', '),
        albumName: release.albumName ?? '',
        previewUrl: '',
        albumArt: '',
        source: 'youtube',
      );
}

/// Freshness bands (spec #44).
enum FreshnessBand { veryRecent, recent, aging, stale }

/// Trending engine v2 (spec #47-50): current popularity ONLY. The user's
/// taste profile is deliberately NOT consulted — a personal favorite must
/// never become "Trending" (spec #48/#77).
class TrendingEngineV2 {
  const TrendingEngineV2();

  List<QuickPickCandidate> generate({
    required List<Track> regionalChart,
    required List<Track> globalChart,
    List<Track> nativeTrending = const [],
    List<Track> userFavorite = const [],
    int limit = 8,
  }) {
    final picked = <Track>[];
    final pickedSources = <String, String>{};
    final seen = <String>{};

    void addFrom(List<Track> source, String sourceTag) {
      for (final track in source) {
        if (!isValid(track)) continue;
        if (!seen.add(track.id)) continue;
        picked.add(track);
        pickedSources[track.id] = sourceTag;
        if (picked.length >= limit) return;
      }
    }

    // Priority (spec #49/#50): regional and global charts round-robin at
    // equal rank — coverage variety, regional wins ties. Trusted native
    // trending fills the remainder. userFavorite is accepted for API
    // symmetry and deliberately NEVER consumed (#48).
    final regional = regionalChart.where(isValid).toList();
    final global = globalChart.where(isValid).toList();
    final sourceOf = <String, String>{
      for (final t in regional) t.id: 'regional',
      for (final t in global) t.id: 'global',
    };
    var a = 0, b = 0;
    while (
        picked.length < limit && (a < regional.length || b < global.length)) {
      if (a < regional.length) {
        final track = regional[a++];
        if (seen.add(track.id)) {
          picked.add(track);
          pickedSources[track.id] = sourceOf[track.id]!;
        }
      }
      if (picked.length >= limit) break;
      if (b < global.length) {
        final track = global[b++];
        if (seen.add(track.id)) {
          picked.add(track);
          pickedSources[track.id] = sourceOf[track.id]!;
        }
      }
    }
    if (picked.length < limit) addFrom(nativeTrending, 'native');

    return [
      for (final track in picked)
        QuickPickCandidate(
          track: Track(
            id: track.id,
            trackName: track.trackName,
            artistName: track.artistName,
            albumName: '',
            previewUrl: '',
            albumArt: track.albumArt,
            source: 'youtube',
          ),
          reason: pickedSources[track.id] == 'regional'
              ? CandidateReason.regionalTrending
              : pickedSources[track.id] == 'global'
                  ? CandidateReason.globalTrending
                  : CandidateReason.regionalTrending,
          score: 1.0 - picked.indexOf(track) / (limit + 1),
          source: 'trending',
          trackId: track.id,
        ),
    ];
  }

  /// Validity gate (spec #85): 11-char video id, non-empty title, no
  /// album/playlist/artist browse prefixes.
  static bool isValid(Track track) =>
      track.id.length == 11 &&
      track.trackName.isNotEmpty &&
      !track.id.startsWith(RegExp(r'(MPREb|OLAK|VL|PL|UC)'));
}
