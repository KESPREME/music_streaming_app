// lib/screens/replay_story_screen.dart
//
// "PLAY YOUR REPLAY" - the summary as a story.
//
// Full screen, one fact per page, advancing on its own like a story: segmented
// progress along the top, tap the right of the screen for next and the left for
// back, hold anywhere to pause, swipe down or tap X to leave. The progress
// controller is the only clock: it drives the bar AND the slow drift of each
// page's artwork, so a page costs one ticker and nothing runs when paused.
//
// Pages are built from what is true: a period with no top album has no album
// page; no genre tags means no genre page.

import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../widgets/jelly_icon_button.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/replay/replay_summary.dart';
import '../utils/app_image_cache.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/replay/replay_card.dart';
import 'replay_screen.dart' show replayShareText;

enum _Page { intro, minutes, song, artists, albums, genres, pattern, outro }

class ReplayStoryScreen extends StatefulWidget {
  const ReplayStoryScreen({super.key, required this.summary, this.pageDuration});

  final ReplaySummary summary;

  /// Per page; 6 s by default.
  final Duration? pageDuration;

  static Future<void> open(BuildContext context, ReplaySummary summary) {
    HapticFeedback.mediumImpact();
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => ReplayStoryScreen(summary: summary),
        transitionsBuilder: (_, a, __, child) {
          final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: c,
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(c),
              child: child,
            ),
          );
        },
      ),
    );
  }

  /// The pages a summary can honestly fill.
  static List<String> pagesFor(ReplaySummary s) => _pages(s).map((p) => p.name).toList();

  static List<_Page> _pages(ReplaySummary s) => [
        _Page.intro,
        _Page.minutes,
        if (s.topSongs.isNotEmpty) _Page.song,
        if (s.topArtists.isNotEmpty) _Page.artists,
        if (s.topAlbums.isNotEmpty) _Page.albums,
        if (s.topGenres.isNotEmpty) _Page.genres,
        if (s.peakHour != null) _Page.pattern,
        _Page.outro,
      ];

  @override
  State<ReplayStoryScreen> createState() => _ReplayStoryScreenState();
}

class _ReplayStoryScreenState extends State<ReplayStoryScreen>
    with SingleTickerProviderStateMixin {
  late final List<_Page> _pages = ReplayStoryScreen._pages(widget.summary);
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.pageDuration ?? const Duration(seconds: 6),
  )..addStatusListener(_onStatus);
  int _index = 0;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _progress.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) _next(auto: true);
  }

  void _go(int i) {
    setState(() => _index = i);
    _progress
      ..reset()
      ..forward();
  }

  void _next({bool auto = false}) {
    if (_index < _pages.length - 1) {
      if (!auto) HapticFeedback.selectionClick();
      _go(_index + 1);
    } else if (!auto) {
      Navigator.maybePop(context);
    }
  }

  void _previous() {
    HapticFeedback.selectionClick();
    if (_index > 0) {
      _go(_index - 1);
    } else {
      _progress
        ..reset()
        ..forward();
    }
  }

  void _share() {
    _progress.stop();
    SharePlus.instance
        .share(ShareParams(text: replayShareText(widget.summary)))
        .whenComplete(() {
      if (mounted) _progress.forward();
    });
  }

  String? _artFor(_Page p) {
    final s = widget.summary;
    return switch (p) {
      _Page.intro || _Page.minutes || _Page.song || _Page.outro => s.topSongs.firstOrNull?.artUrl,
      _Page.artists => s.topArtists.firstOrNull?.artUrl,
      _Page.albums => s.topAlbums.firstOrNull?.artUrl,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final page = _pages[_index];
    final pad = MediaQuery.paddingOf(context);
    final art = _artFor(page);
    final yy = s.period == ReplayPeriod.allTime ? '' : ' ${s.label.split(' ').last.substring(2)}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final w = MediaQuery.sizeOf(context).width;
          d.localPosition.dx < w / 3 ? _previous() : _next();
        },
        onLongPressStart: (_) => _progress.stop(),
        onLongPressEnd: (_) => _progress.forward(),
        onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(0, 400)),
        onVerticalDragEnd: (d) {
          if (_drag > 120 || (d.primaryVelocity ?? 0) > 700) {
            Navigator.maybePop(context);
          } else {
            setState(() => _drag = 0);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: Opacity(
            opacity: (1 - _drag / 600).clamp(0.4, 1.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Graphite canvas, washed with the page's artwork.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF4A4A4E), Color(0xFF2C2C30), Color(0xFF151517)],
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: art == null || art.isEmpty
                      ? const SizedBox.expand(key: ValueKey('none'))
                      : SizedBox.expand(
                          key: ValueKey(art),
                          child: RepaintBoundary(
                            child: Opacity(
                              opacity: 0.28,
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                                child: CachedNetworkImage(
                                  imageUrl: art,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 200,
                                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(22, pad.top + 12, 22, pad.bottom + 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Spacer(),
                          Semantics(
                            button: true,
                            label: 'Close Replay',
                            child: JellyIconButton(
                              onPressed: () => Navigator.maybePop(context),
                              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                            ),
                          ),
                        ],
                      ),
                      _Bars(count: _pages.length, index: _index, progress: _progress),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Flexible(
                            child: Text('Replay$yy',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ReplayStyle.title(18, weight: FontWeight.w700)),
                          ),
                          const Spacer(),
                          Image.asset('assets/images/mine_music_mark.png',
                              height: 20,
                              color: Colors.white,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text('Mine Music',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ReplayStyle.title(18, weight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                          child: KeyedSubtree(
                            key: ValueKey(_index),
                            child: _PageBody(page: page, summary: s, drift: _progress),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Built privately from your listening history on this device.',
                                style: ReplayStyle.meta(size: 13, alpha: 0.55)),
                          ),
                          const SizedBox(width: 16),
                          Semantics(
                            button: true,
                            label: 'Share my Replay',
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.16),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _share,
                                child: const SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: Icon(Icons.ios_share_rounded, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.count, required this.index, required this.progress});

  final int count;
  final int index;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${index + 1} of $count',
      child: AnimatedBuilder(
        animation: progress,
        builder: (_, __) => Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: i < index ? 1 : (i == index ? progress.value : 0),
                    color: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fades and lifts in, [order] beats after the page arrives.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    const base = 520, step = 110;
    final total = base + order * step;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(order * step / total, 1, curve: Curves.easeOutCubic),
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.url, required this.size, this.circle = false});

  final String url;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final ph = Container(color: Colors.white10, width: size, height: size);
    final img = url.isEmpty
        ? ph
        : CachedNetworkImage(
            imageUrl: ImageQualityUtils.getHighResArtwork(url),
            width: size,
            height: size,
            fit: BoxFit.cover,
            memCacheWidth: AppImageCache.cardMemCache,
            placeholder: (_, __) => ph,
            errorWidget: (_, __, ___) => ph,
          );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.04),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 12)),
        ],
      ),
      child: circle
          ? ClipOval(child: img)
          : ClipRRect(borderRadius: BorderRadius.circular(size * 0.04), child: img),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page, required this.summary, required this.drift});

  final _Page page;
  final ReplaySummary summary;
  final Animation<double> drift;

  Widget _heading(String muted, String bold, [String tail = '']) => Text.rich(
        TextSpan(children: [
          TextSpan(text: muted, style: TextStyle(color: Colors.white.withValues(alpha: 0.55))),
          TextSpan(text: bold),
          if (tail.isNotEmpty)
            TextSpan(text: tail, style: TextStyle(color: Colors.white.withValues(alpha: 0.55))),
        ]),
        style: ReplayStyle.title(34),
      );

  Widget _ranked(List<ReplayEntry> list, {bool circle = false, required String Function(ReplayEntry) meta}) {
    return Column(
      children: [
        for (var i = 0; i < list.length; i++)
          _Reveal(
            order: i + 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text('${i + 1}',
                        style: ReplayStyle.title(22).copyWith(
                            color: i == 0 ? ReplayStyle.rankOne : Colors.white54)),
                  ),
                  _Art(url: list[i].artUrl, size: i == 0 ? 72 : 56, circle: circle),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(list[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ReplayStyle.title(i == 0 ? 21 : 17, weight: FontWeight.w700)),
                        Text(meta(list[i]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ReplayStyle.meta(size: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (page == _Page.intro) return _content(context);
    // Every other page is a fixed composition that must fit any screen and any
    // text size: it is laid out at full width and scaled down, never clipped.
    final centred = page == _Page.minutes || page == _Page.pattern || page == _Page.outro;
    return LayoutBuilder(
      builder: (context, c) => Align(
        alignment: centred ? Alignment.centerLeft : Alignment.topLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: centred ? Alignment.centerLeft : Alignment.topLeft,
          child: SizedBox(width: c.maxWidth, child: _content(context)),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final s = summary;
    String plays(int n) => n == 1 ? '1 play' : '${groupThousands(n)} plays';
    switch (page) {
      case _Page.intro:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Reveal(order: 0, child: _heading('Your ', 'Replay', ' is ready.')),
            Expanded(child: _Collage(summary: s, drift: drift)),
          ],
        );
      case _Page.minutes:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Reveal(order: 0, child: _heading('You listened for', '')),
            const SizedBox(height: 10),
            _Reveal(
              order: 1,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: s.minutes.toDouble()),
                duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
                    ? Duration.zero
                    : const Duration(milliseconds: 1600),
                curve: Curves.easeOutExpo,
                builder: (_, v, __) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(groupThousands(v.round()), style: ReplayStyle.display(96)),
                ),
              ),
            ),
            _Reveal(order: 2, child: Text('MINUTES', style: ReplayStyle.caps().copyWith(fontSize: 16))),
            const SizedBox(height: 26),
            _Reveal(
              order: 3,
              child: Text(
                '${plays(s.plays)} across ${groupThousands(s.distinctSongs)} '
                '${s.distinctSongs == 1 ? 'song' : 'songs'}.',
                style: ReplayStyle.meta(size: 18, alpha: 0.7),
              ),
            ),
          ],
        );
      case _Page.song:
        final song = s.topSongs.first;
        return LayoutBuilder(builder: (context, c) {
          final size = (c.maxWidth * 0.78).clamp(160.0, 320.0).toDouble();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Reveal(order: 0, child: _heading('Your top ', 'song')),
              const SizedBox(height: 28),
              Center(child: _Reveal(order: 1, child: _Art(url: song.artUrl, size: size))),
              const SizedBox(height: 22),
              _Reveal(
                order: 2,
                child: Text(song.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: ReplayStyle.title(30)),
              ),
              _Reveal(
                order: 3,
                child: Text('${song.subtitle} · ${plays(song.plays)} · ${formatListenTime(song.ms)}',
                    maxLines: 2, style: ReplayStyle.meta(size: 16, alpha: 0.65)),
              ),
            ],
          );
        });
      case _Page.artists:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Reveal(order: 0, child: _heading('Your top ', 'artists')),
            const SizedBox(height: 20),
            _ranked(s.topArtists, circle: true, meta: (e) => '${formatListenTime(e.ms)} · ${plays(e.plays)}'),
          ],
        );
      case _Page.albums:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Reveal(order: 0, child: _heading('Your top ', 'albums')),
            const SizedBox(height: 20),
            _ranked(s.topAlbums, meta: (e) => '${e.subtitle} · ${formatListenTime(e.ms)}'),
          ],
        );
      case _Page.genres:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Reveal(order: 0, child: _heading('You were into ', s.topGenres.first.title, '.')),
            const SizedBox(height: 20),
            for (var i = 0; i < s.topGenres.length; i++)
              _Reveal(
                order: i + 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('${i + 1}  ${s.topGenres[i].title}  ·  ${formatListenTime(s.topGenres[i].ms)}',
                      style: ReplayStyle.title(i == 0 ? 24 : 18, weight: FontWeight.w700)),
                ),
              ),
          ],
        );
      case _Page.pattern:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Reveal(order: 0, child: _heading('You listen most around', '')),
            _Reveal(
              order: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(formatHour(s.peakHour!), style: ReplayStyle.display(88)),
              ),
            ),
            const SizedBox(height: 24),
            if (s.biggestDay != null)
              _Reveal(
                order: 2,
                child: Text(
                  'Your biggest day was ${s.biggestDay!.day} '
                  '${ReplaySummary.monthName(s.biggestDay!.month)}, with '
                  '${formatListenTime(s.biggestDayMs)} of listening.',
                  style: ReplayStyle.meta(size: 18, alpha: 0.72).copyWith(height: 1.4),
                ),
              ),
            const SizedBox(height: 14),
            _Reveal(
              order: 3,
              child: Text(
                '${groupThousands(s.distinctArtists)} artists · '
                '${groupThousands(s.distinctAlbums)} albums',
                style: ReplayStyle.meta(size: 16, alpha: 0.55),
              ),
            ),
          ],
        );
      case _Page.outro:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Reveal(order: 0, child: _heading("That's your ", 'Replay', '.')),
            const SizedBox(height: 16),
            _Reveal(
              order: 1,
              child: Text(
                '${groupThousands(s.minutes)} minutes, ${plays(s.plays)}. '
                'It keeps filling in as you listen.',
                style: ReplayStyle.meta(size: 18, alpha: 0.7).copyWith(height: 1.4),
              ),
            ),
          ],
        );
    }
  }
}

/// The intro: the year's artwork, scattered, drifting a few pixels with the
/// page clock.
class _Collage extends StatelessWidget {
  const _Collage({required this.summary, required this.drift});

  final ReplaySummary summary;
  final Animation<double> drift;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final items = <({String url, bool circle})>[
      if (s.topSongs.isNotEmpty) (url: s.topSongs[0].artUrl, circle: false),
      for (final a in s.topAlbums.skip(0).take(2)) (url: a.artUrl, circle: false),
      for (final a in s.topArtists.take(3)) (url: a.artUrl, circle: true),
    ].where((e) => e.url.isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    // Positions as fractions of the box: centre piece, then satellites.
    const spots = [
      (0.50, 0.52, 0.56),
      (0.22, 0.28, 0.34),
      (0.78, 0.22, 0.26),
      (0.16, 0.72, 0.24),
      (0.82, 0.48, 0.24),
      (0.56, 0.86, 0.22),
    ];
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      return AnimatedBuilder(
        animation: drift,
        builder: (_, __) {
          final d = drift.value;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = items.length - 1; i >= 0; i--)
                Builder(builder: (_) {
                  final (x, y, f) = spots[i];
                  final size = w * f;
                  final dir = i.isEven ? 1.0 : -1.0;
                  return Positioned(
                    left: x * w - size / 2 + dir * 10 * d,
                    top: y * h - size / 2 - (i + 1) * 3 * d,
                    child: _Reveal(
                      order: i,
                      child: Transform.rotate(
                        angle: i == 0 ? 0 : dir * 0.06,
                        child: _Art(url: items[i].url, size: size, circle: items[i].circle),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      );
    });
  }
}
