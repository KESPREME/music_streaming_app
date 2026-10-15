// lib/widgets/replay/replay_card.dart
//
// THE REPLAY CARD - a membership card for your listening.
//
// Four faces, swiped like cards in a wallet: minutes listened, top song, top
// artist, top album. Each is a slab of graphite glass: a brushed-metal gradient,
// a hairline edge, and a specular highlight that SLIDES as the card is dragged -
// the light stays put while the card moves under it, which is what makes glass
// read as glass rather than as a grey rectangle. Neighbouring cards sit back
// (scaled and dimmed) and come forward as they are swiped in.
//
// Everything on a card is a measured fact from the local play log
// (ListeningStats -> ReplaySummary). A face with nothing true to say is not
// shown: a new listener sees the minutes card alone, with an honest empty state.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../services/replay/replay_summary.dart';
import '../home_sections.dart' show PressableScale;

/// Design tokens shared by every Replay surface.
abstract final class ReplayStyle {
  static const Color graphiteHi = Color(0xFF424246);
  static const Color graphiteMid = Color(0xFF2E2E32);
  static const Color graphiteLo = Color(0xFF1C1C1F);
  static const Color canvasTop = Color(0xFF2A2A2D);
  static const Color canvasBottom = Color(0xFF0E0E10);
  static const Color rankOne = Color(0xFFFF3B5C);
  static const Color tile = Color(0x1AFFFFFF);
  static const double cardRadius = 26;
  static const double cardAspect = 0.63; // height / width

  static TextStyle eyebrow() => GoogleFonts.plusJakartaSans(
        color: Colors.white.withValues(alpha: 0.72),
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.8,
      );

  static TextStyle display(double size) => GoogleFonts.plusJakartaSans(
        color: Colors.white,
        fontSize: size,
        height: 1.02,
        fontWeight: FontWeight.w800,
        letterSpacing: -size * 0.03,
        fontFeatures: const [FontFeature.tabularFigures()],
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.45),
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      );

  static TextStyle caps() => GoogleFonts.plusJakartaSans(
        color: Colors.white.withValues(alpha: 0.72),
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      );

  static TextStyle title(double size, {FontWeight weight = FontWeight.w800}) =>
      GoogleFonts.plusJakartaSans(
        color: Colors.white,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -size * 0.02,
      );

  static TextStyle meta({double size = 13.5, double alpha = 0.55}) =>
      GoogleFonts.plusJakartaSans(
        color: Colors.white.withValues(alpha: alpha),
        fontSize: size,
        fontWeight: FontWeight.w500,
      );
}

/// What one face of the card says.
class ReplayFace {
  const ReplayFace({
    required this.headline,
    required this.label,
    required this.meta,
    this.isNumber = false,
  });

  final String headline;
  final String label;
  final String meta;
  final bool isNumber;

  /// The faces a summary can honestly show, in order.
  static List<ReplayFace> of(ReplaySummary s) {
    final year = s.period == ReplayPeriod.allTime ? 'All time' : s.label;
    String plays(int n) => n == 1 ? '1 Play' : '$n Plays';
    final faces = <ReplayFace>[
      ReplayFace(
        headline: groupThousands(s.minutes),
        label: 'MINUTES LISTENED',
        meta: '${plays(s.plays)} · $year',
        isNumber: true,
      ),
    ];
    final song = s.topSongs.firstOrNull;
    if (song != null) {
      faces.add(ReplayFace(
        headline: song.title,
        label: 'TOP SONG',
        meta: '${song.subtitle} · ${plays(song.plays)}',
      ));
    }
    final artist = s.topArtists.firstOrNull;
    if (artist != null) {
      faces.add(ReplayFace(
        headline: artist.title,
        label: 'TOP ARTIST',
        meta: '${formatListenTime(artist.ms)} · ${plays(artist.plays)}',
      ));
    }
    final album = s.topAlbums.firstOrNull;
    if (album != null) {
      faces.add(ReplayFace(
        headline: album.title,
        label: 'TOP ALBUM',
        meta: '${album.subtitle} · ${formatListenTime(album.ms)}',
      ));
    }
    return faces;
  }
}

/// The listener's name for the card, upper-cased; empty when unknown.
String replayHolderName() {
  try {
    final name = AuthService().activeAccount?.name.trim() ?? '';
    return name.toUpperCase();
  } catch (_) {
    return '';
  }
}

/// "09/26" from the first play.
String memberSinceLabel(DateTime? since) {
  if (since == null) return '';
  final mm = since.month.toString().padLeft(2, '0');
  final yy = (since.year % 100).toString().padLeft(2, '0');
  return '$mm/$yy';
}

class ReplayCard extends StatelessWidget {
  const ReplayCard({
    super.key,
    required this.face,
    required this.holder,
    required this.memberSince,
    this.light = 0,
    this.empty = false,
  });

  final ReplayFace face;
  final String holder;
  final String memberSince;

  /// -1..1: where the highlight sits, driven by the carousel's drag.
  final double light;

  /// Nothing listened yet: the minutes face says so instead of "0".
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final headlineSize = (w * 0.115).clamp(28.0, 44.0);
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ReplayStyle.cardRadius),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ReplayStyle.graphiteHi,
              ReplayStyle.graphiteMid,
              ReplayStyle.graphiteLo,
            ],
            stops: [0.0, 0.55, 1.0],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The specular highlight: fixed in space, so it slides across the
            // card as the card moves.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.6 - light * 0.9, -1.1),
                    radius: 1.25,
                    colors: [
                      Colors.white.withValues(alpha: 0.16),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // A lit top edge.
            Positioned(
              top: 0,
              left: 18,
              right: 18,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.28),
                    Colors.white.withValues(alpha: 0),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(w * 0.06, w * 0.055, w * 0.06, w * 0.05),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('YOUR LISTENING EXPERIENCE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ReplayStyle.eyebrow()),
                      ),
                      const SizedBox(width: 10),
                      Image.asset(
                        'assets/images/mine_music_mark.png',
                        height: 24,
                        color: Colors.white,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.graphic_eq_rounded,
                            color: Colors.white,
                            size: 24),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (empty) ...[
                    Text('Your Replay starts here',
                        maxLines: 2, style: ReplayStyle.display(headlineSize * 0.66)),
                    const SizedBox(height: 6),
                    Text('EVERY MINUTE YOU PLAY COUNTS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ReplayStyle.caps().copyWith(fontSize: 11.5)),
                  ] else ...[
                    if (face.isNumber)
                      _CountUp(
                        text: face.headline,
                        style: ReplayStyle.display(headlineSize),
                        animate: !reduceMotion,
                      )
                    else
                      // Long names step down a size before they wrap, and wrap
                      // before they are cut: "Stereo Hearts (feat. Adam Levine)"
                      // must still be readable.
                      Text(face.headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ReplayStyle.display(headlineSize *
                              (face.headline.length > 20
                                  ? 0.66
                                  : face.headline.length > 12
                                      ? 0.82
                                      : 1.0))),
                    const SizedBox(height: 4),
                    Text(face.label, maxLines: 1, style: ReplayStyle.caps()),
                  ],
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(holder.isEmpty ? 'MINE MUSIC' : holder,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ReplayStyle.title(16, weight: FontWeight.w600)
                                    .copyWith(letterSpacing: 1.4)),
                            const SizedBox(height: 2),
                            Text(empty ? 'Built privately on this device' : face.meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ReplayStyle.meta(size: 13, alpha: 0.62)),
                          ],
                        ),
                      ),
                      if (memberSince.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('MEMBER SINCE',
                                style: ReplayStyle.meta(size: 9.5, alpha: 0.6)
                                    .copyWith(letterSpacing: 1, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(memberSince,
                                style: ReplayStyle.title(17, weight: FontWeight.w600)
                                    .copyWith(letterSpacing: 1.6)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// A grouped number that counts up to itself once, when it first appears.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.text, required this.style, required this.animate});

  final String text;
  final TextStyle style;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final target = int.tryParse(text.replaceAll(',', '')) ?? 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target.toDouble()),
      duration: animate ? const Duration(milliseconds: 1100) : Duration.zero,
      curve: Curves.easeOutExpo,
      builder: (_, v, __) => Text(groupThousands(v.round()), maxLines: 1, style: style),
    );
  }
}

/// The swipeable wallet of faces.
class ReplayCardCarousel extends StatefulWidget {
  const ReplayCardCarousel({
    super.key,
    required this.summary,
    this.onTap,
    this.horizontalPadding = 20,
  });

  final ReplaySummary summary;
  final VoidCallback? onTap;
  final double horizontalPadding;

  @override
  State<ReplayCardCarousel> createState() => _ReplayCardCarouselState();
}

class _ReplayCardCarouselState extends State<ReplayCardCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.88);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final faces = ReplayFace.of(widget.summary);
    final empty = widget.summary.isEmpty;
    final holder = replayHolderName();
    final since = memberSinceLabel(widget.summary.memberSince);
    final width = MediaQuery.sizeOf(context).width * 0.88;
    final height = width * ReplayStyle.cardAspect;

    return SizedBox(
      height: height + 24,
      child: PageView.builder(
        controller: _controller,
        padEnds: false,
        itemCount: faces.length,
        onPageChanged: (_) => HapticFeedback.selectionClick(),
        itemBuilder: (context, i) {
          final card = Semantics(
            button: widget.onTap != null,
            label: empty
                ? 'Replay. Nothing listened yet'
                : 'Replay. ${faces[i].label.toLowerCase()}: ${faces[i].headline}. ${faces[i].meta}',
            excludeSemantics: true,
            child: PressableScale(
              onTap: widget.onTap,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final page = _controller.hasClients &&
                          _controller.position.haveDimensions
                      ? (_controller.page ?? 0)
                      : 0.0;
                  final delta = (i - page).clamp(-1.0, 1.0);
                  final t = delta.abs();
                  return Opacity(
                    opacity: 1 - t * 0.35,
                    child: Transform.scale(
                      scale: 1 - t * 0.06,
                      child: ReplayCard(
                        face: faces[i],
                        holder: holder,
                        memberSince: since,
                        light: delta,
                        empty: empty && i == 0,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          return Padding(
            padding: EdgeInsets.only(
              left: i == 0 ? widget.horizontalPadding : 6,
              right: i == faces.length - 1 ? widget.horizontalPadding * 0.5 : 6,
              top: 4,
              bottom: 20,
            ),
            child: card,
          );
        },
      ),
    );
  }
}
