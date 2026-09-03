import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/presentation/home/home_presentation.dart';
import 'package:music_streaming_app/services/home/home_models.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart';

HomeItem _item(String id, HomeContentType type) => HomeItem(
      id: id,
      videoId: type == HomeContentType.song ? id : null,
      browseId: type == HomeContentType.song ? null : id,
      title: 'T-$id',
      subtitle: 'Sub',
      artworkUrl: 'https://example.com/$id.jpg',
      contentType: type,
    );

HomeSection _section(
  String title,
  List<HomeItem> items, {
  String? provenance,
  HomePresentation presentation = HomePresentation.artworkRail,
}) =>
    HomeSection(
      id: 'id_$title',
      title: title,
      items: items,
      presentation: presentation,
      provenance: provenance,
    );

void main() {
  group('HomeSemanticClassifier (spec #42)', () {
    test('top picks → hero carousel 4:5 with overlay + 2-line title', () {
      final section = _section(
        'Top picks for you',
        List.generate(5, (i) => _item('s$i', HomeContentType.song)),
      );
      final plan = planPresentation(section);
      expect(plan.semanticType, HomeSemanticType.topPicks);
      expect(plan.layoutKind, HomeLayoutKind.heroCarousel);
      expect(plan.aspectRatio, closeTo(0.8, 0.01)); // 4:5
      expect(plan.showOverlay, isTrue);
      expect(plan.maxLines, 2);
    });

    test('recently played → square grid', () {
      final section = _section(
        'Listen again',
        List.generate(6, (i) => _item('r$i', HomeContentType.song)),
      );
      final plan = planPresentation(section);
      expect(plan.semanticType, HomeSemanticType.recentlyPlayed);
      expect(plan.layoutKind, HomeLayoutKind.squareGrid);
      expect(plan.aspectRatio, 1.0);
    });

    test('new releases → square grid', () {
      final section = _section(
        'New releases',
        List.generate(4, (i) => _item('n$i', HomeContentType.album)),
      );
      final plan = planPresentation(section);
      expect(plan.semanticType, HomeSemanticType.newReleases);
      expect(plan.layoutKind, HomeLayoutKind.squareRail);
    });

    test('music videos → 16:9 landscape rail', () {
      final section = _section(
        'New music videos',
        List.generate(4, (i) => _item('v$i', HomeContentType.video)),
      );
      final plan = planPresentation(section);
      expect(plan.semanticType, HomeSemanticType.musicVideos);
      expect(plan.layoutKind, HomeLayoutKind.landscapeRail16x9);
      expect(plan.aspectRatio, closeTo(16 / 9, 0.01));
    });

    test('trending → compact list (spec #12 editorial density)', () {
      final section = _section(
        'Trending',
        List.generate(8, (i) => _item('t$i', HomeContentType.song)),
      );
      final plan = planPresentation(section);
      expect(plan.semanticType, HomeSemanticType.trending);
      expect(plan.layoutKind, HomeLayoutKind.compactList);
    });

    test('episodes → 16:9', () {
      final section = _section(
        'Popular episodes',
        List.generate(3, (i) => _item('e$i', HomeContentType.video)),
      );
      final plan = planPresentation(section);
      expect(plan.semanticType, HomeSemanticType.episodes);
      expect(plan.layoutKind, HomeLayoutKind.landscapeRail16x9);
    });

    test('moods (Rain Therapy) → playlist rail, semantic type moods', () {
      final section = _section(
        'Rain Therapy',
        List.generate(4, (i) => _item('m$i', HomeContentType.playlist)),
      );
      final plan = planPresentation(section);
      expect(plan.semanticType, HomeSemanticType.moods);
      expect(plan.layoutKind, HomeLayoutKind.playlistRail);
    });

    test('provenance fallback: chart → trending compact list', () {
      final section = _section(
        'Top Weekly Charts',
        List.generate(6, (i) => _item('c$i', HomeContentType.song)),
        provenance: 'chart',
      );
      final plan = planPresentation(section);
      expect(plan.semanticType, HomeSemanticType.trending);
      expect(plan.layoutKind, HomeLayoutKind.compactList);
    });

    test('provenance fallback: new_release → new releases grid', () {
      final section = _section(
        'Fresh finds',
        List.generate(4, (i) => _item('f$i', HomeContentType.song)),
        provenance: 'new_release',
      );
      final plan = planPresentation(section);
      expect(plan.semanticType, HomeSemanticType.newReleases);
      expect(plan.layoutKind, HomeLayoutKind.squareRail);
    });

    test('unknown title → UNKNOWN with safe square rail (never crash)', () {
      final section = _section(
        'Some new editorial shelf',
        List.generate(3, (i) => _item('u$i', HomeContentType.song)),
      );
      final plan = planPresentation(section);
      expect(plan.semanticType, HomeSemanticType.unknown);
      expect(plan.layoutKind, HomeLayoutKind.squareRail);
    });

    test('semantic integrity: "Picked for you" only from source title', () {
      // A mood shelf titled by the source must NOT become 'Picked for you'.
      final mood = classifySection(_section(
        'Rain Therapy',
        List.generate(3, (i) => _item('m$i', HomeContentType.playlist)),
      ));
      expect(mood, isNot(HomeSemanticType.topPicks));
      expect(mood, HomeSemanticType.moods);
    });

    test('adaptive: single-item recent section does not reserve a grid', () {
      final single = _section(
        'Listen again',
        [_item('only1', HomeContentType.song)],
      );
      final plan = planPresentation(single);
      // 1 item → squareRail (compact, no empty second column) per spec #8.
      expect(plan.layoutKind, HomeLayoutKind.squareRail);
    });

    group('quickPickReasonLabel (explanation UI)', () {
      test('every CandidateReason has a non-empty label', () {
        for (final reason in CandidateReason.values) {
          final label = quickPickReasonLabel(reason);
          expect(label, isNotEmpty, reason: 'missing label for ' + reason.name);
        }
      });

      test('known reasons get their documented label', () {
        expect(quickPickReasonLabel(CandidateReason.favoriteArtist),
            'From your favorites');
        expect(quickPickReasonLabel(CandidateReason.recentlyPlayed),
            'Recently played');
        expect(quickPickReasonLabel(CandidateReason.searchFollowup),
            'From your searches');
        expect(quickPickReasonLabel(CandidateReason.genreAffinity),
            'Matches your taste');
      });
    });
  });
}
