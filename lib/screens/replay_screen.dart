// lib/screens/replay_screen.dart
//
// REPLAY - your listening, this month, this year, or all time.
//
// Flow: Library card -> this screen -> "Play your Replay" (the story) or any row
// (play a song, open an artist or album). The period switch is a liquid-glass
// segmented capsule; switching it cross-fades the whole summary below, because
// every number on the page changes together.
//
// Every figure comes from the local play log (ListeningStats) through the pure
// ReplaySummary. Nothing here is estimated, and nothing leaves the device unless
// the listener taps Share.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/music_provider.dart';
import '../services/auth_service.dart';
import '../services/listening_stats.dart';
import '../services/replay/replay_summary.dart';
import '../theme/glass_tokens.dart';
import '../utils/app_image_cache.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/glass_circle_button.dart';
import '../widgets/home_sections.dart' show PressableScale;
import '../widgets/collection/collection_kit.dart' show showCollectionToast;
import '../widgets/liquid_glass_pill.dart';
import '../widgets/playlist/playlist_edit_sheet.dart';
import '../widgets/replay/replay_card.dart';
import '../widgets/themed_album_detail_screen.dart';
import '../widgets/themed_artist_detail_screen.dart';
import 'replay_story_screen.dart';

/// The text a listener shares. Facts only.
String replayShareText(ReplaySummary s) {
  final b = StringBuffer('My Replay ${s.label} on Mine Music\n')
    ..write('${groupThousands(s.minutes)} minutes · ')
    ..write(s.plays == 1 ? '1 play' : '${s.plays} plays');
  final song = s.topSongs.firstOrNull;
  final artist = s.topArtists.firstOrNull;
  final album = s.topAlbums.firstOrNull;
  if (song != null) b.write('\nTop song: ${song.title} - ${song.subtitle}');
  if (artist != null) b.write('\nTop artist: ${artist.title}');
  if (album != null) b.write('\nTop album: ${album.title} - ${album.subtitle}');
  return b.toString();
}

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key, this.initialPeriod = ReplayPeriod.year, this.now});

  final ReplayPeriod initialPeriod;

  /// Fixed clock for tests.
  final DateTime? now;

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => const ReplayScreen(),
          transitionsBuilder: (context, animation, _, child) {
            final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                    .animate(curved),
                child: child,
              ),
            );
          },
        ),
      );

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  late ReplayPeriod _period = widget.initialPeriod;

  void _setPeriod(ReplayPeriod p) {
    if (p == _period) return;
    HapticFeedback.selectionClick();
    setState(() => _period = p);
  }

  /// Turns the period's top songs into a playlist the listener can keep.
  Future<void> _saveTopSongs(ReplaySummary s) async {
    final tracks = [for (final e in s.topSongs) if (e.track != null) e.track!];
    if (tracks.isEmpty) return;
    final made = await showPlaylistEditSheet(
      context,
      initialTracks: tracks,
      initialName: 'Replay ${s.label}',
    );
    if (made != null && mounted) {
      showCollectionToast(context, 'Saved "${made.name}" with ${tracks.length} songs',
          icon: Icons.playlist_add_check_rounded);
    }
  }

  Future<void> _confirmClear(ListeningStats stats) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear listening history?'),
        content: const Text(
            'Replay forgets every play on this device. Your playlists, likes and downloads are not touched. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear', style: TextStyle(color: ReplayStyle.rankOne)),
          ),
        ],
      ),
    );
    if (ok == true) await stats.clear();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicProvider>();
    final stats = provider.listeningStats;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final avatar = AuthService().activeAccount?.avatarUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ReplayStyle.canvasTop, ReplayStyle.canvasBottom, Colors.black],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            ListenableBuilder(
              listenable: stats,
              builder: (context, _) {
                final s = ReplaySummary.of(stats, _period, now: widget.now);
                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: top + 76)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text('Replay', style: ReplayStyle.title(44)),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(s.label,
                                  key: ValueKey(s.label),
                                  style: ReplayStyle.meta(size: 20, alpha: 0.5)
                                      .copyWith(fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: 330,
                              child: LiquidGlassSegmented(
                                height: 46,
                                segments: [
                                  for (final p in ReplayPeriod.values)
                                    GlassSegment(
                                      semanticLabel: p.label,
                                      isActive: p == _period,
                                      onTap: () => _setPeriod(p),
                                      icon: Text(
                                        p.label,
                                        maxLines: 1,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: p == _period
                                              ? Colors.black
                                              : Colors.white.withValues(alpha: 0.8),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.015), end: Offset.zero)
                                .animate(a),
                            child: child,
                          ),
                        ),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          children: [...previous, if (current != null) current],
                        ),
                        child: _ReplayBody(
                          key: ValueKey(_period),
                          summary: s,
                          onPlayStory: () => ReplayStoryScreen.open(context, s),
                          onSave: () => _saveTopSongs(s),
                          onShare: () => SharePlus.instance
                              .share(ShareParams(text: replayShareText(s))),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(22, 8, 22,
                            GlassTokens.playerBottomInset + GlassTokens.playerPillHeight + 40 + bottom),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Built privately from your listening on this device.',
                                style: ReplayStyle.meta(size: 12.5, alpha: 0.42)),
                            if (stats.records.isNotEmpty)
                              TextButton(
                                style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(44, 44)),
                                onPressed: () => _confirmClear(stats),
                                child: Text('Clear listening history',
                                    style: ReplayStyle.meta(size: 13, alpha: 0.6)
                                        .copyWith(fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            // Floating glass controls over the content.
            Positioned(
              top: top + 10,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  GlassCircleButton(
                    icon: Icons.arrow_back_rounded,
                    size: 48,
                    iconSize: 22,
                    semanticLabel: 'Back',
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const Spacer(),
                  if (avatar != null && avatar.isNotEmpty)
                    Semantics(
                      image: true,
                      label: 'Your account',
                      child: Container(
                        width: 48,
                        height: 48,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                        ),
                        child: ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: avatar,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayBody extends StatelessWidget {
  const _ReplayBody({
    super.key,
    required this.summary,
    required this.onPlayStory,
    required this.onShare,
    required this.onSave,
  });

  final ReplaySummary summary;
  final VoidCallback onPlayStory;
  final VoidCallback onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final songs = s.topSongs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReplayCardCarousel(summary: s, horizontalPadding: 22),
        if (s.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Text(
              switch (s.period) {
                ReplayPeriod.month => 'Nothing played this month yet. Play something and come back.',
                ReplayPeriod.year => 'Nothing played this year yet. Play something and come back.',
                ReplayPeriod.allTime => 'Replay fills in as you listen. Every song you play is counted here.',
              },
              style: ReplayStyle.meta(size: 15, alpha: 0.62).copyWith(height: 1.4),
            ),
          )
        else ...[
          _ActionRow(
            icon: Icons.play_arrow_rounded,
            label: 'Play your Replay',
            onTap: onPlayStory,
          ),
          if (songs.isNotEmpty)
            _Section(
              title: 'Top songs',
              trailing: _PlayAll(onTap: () {
                context.read<MusicProvider>().playTrackList(
                      [for (final e in songs) e.track!],
                      initialIndex: 0,
                    );
              }),
              children: [
                for (var i = 0; i < songs.length; i++)
                  _RankRow(
                    rank: i + 1,
                    entry: songs[i],
                    subtitle: '${songs[i].subtitle} · ${formatListenTime(songs[i].ms)}',
                    onTap: () => context.read<MusicProvider>().playTrack(
                          songs[i].track!,
                          playlistTracks: [for (final e in songs) e.track!],
                          playlistId: 'replay_top_songs',
                        ),
                  ),
              ],
            ),
          if (s.topArtists.isNotEmpty)
            _Section(
              title: 'Top artists',
              children: [
                for (var i = 0; i < s.topArtists.length; i++)
                  _RankRow(
                    rank: i + 1,
                    entry: s.topArtists[i],
                    circle: true,
                    subtitle: formatListenTime(s.topArtists[i].ms),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ThemedArtistDetailScreen(
                          artistId: '',
                          artistName: s.topArtists[i].title,
                          artistImage: s.topArtists[i].artUrl,
                          searchByName: true,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          if (s.topAlbums.isNotEmpty)
            _Section(
              title: 'Top albums',
              children: [
                for (var i = 0; i < s.topAlbums.length; i++)
                  _RankRow(
                    rank: i + 1,
                    entry: s.topAlbums[i],
                    subtitle:
                        '${s.topAlbums[i].subtitle} · ${formatListenTime(s.topAlbums[i].ms)}',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ThemedAlbumDetailScreen(
                          albumId: '',
                          albumName: s.topAlbums[i].title,
                          artistName: s.topAlbums[i].subtitle,
                          albumImage: s.topAlbums[i].artUrl,
                          searchByName: true,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          if (s.topGenres.isNotEmpty)
            _Section(
              title: 'Top genres',
              children: [
                for (var i = 0; i < s.topGenres.length; i++)
                  _RankRow(
                    rank: i + 1,
                    entry: s.topGenres[i],
                    letter: true,
                    subtitle: formatListenTime(s.topGenres[i].ms),
                  ),
              ],
            ),
          _Section(
            title: 'Your listening pattern',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    _StatTile(value: s.distinctSongs, label: 'Songs'),
                    const SizedBox(width: 10),
                    _StatTile(value: s.distinctArtists, label: 'Artists'),
                    const SizedBox(width: 10),
                    _StatTile(value: s.distinctAlbums, label: 'Albums'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (s.peakHour != null)
                _Sentence('You listen most around ${formatHour(s.peakHour!)}.'),
              if (s.biggestDay != null && s.biggestDayMs >= Duration.millisecondsPerMinute)
                _Sentence('Your biggest day was ${s.biggestDay!.day} '
                    '${ReplaySummary.monthName(s.biggestDay!.month)} with '
                    '${formatListenTime(s.biggestDayMs)} of listening.'),
            ],
          ),
          const SizedBox(height: 18),
          if (songs.isNotEmpty) ...[
            _ActionRow(icon: Icons.playlist_add_rounded, label: 'Save top songs as a playlist', onTap: onSave),
            const SizedBox(height: 10),
          ],
          _ActionRow(icon: Icons.ios_share_rounded, label: 'Share my Replay', onTap: onShare),
        ],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: PressableScale(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: ReplayStyle.tile,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(width: 14),
                Expanded(child: Text(label, style: ReplayStyle.title(18, weight: FontWeight.w700))),
                Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.45)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayAll extends StatelessWidget {
  const _PlayAll({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Play top songs',
      excludeSemantics: true,
      child: PressableScale(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
              const SizedBox(width: 4),
              Text('Play',
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.black, fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 34, 22, 10),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: ReplayStyle.title(26)),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.entry,
    required this.subtitle,
    this.onTap,
    this.circle = false,
    this.letter = false,
  });

  final int rank;
  final ReplayEntry entry;
  final String subtitle;
  final VoidCallback? onTap;
  final bool circle;
  final bool letter;

  static const _hues = [Color(0xFF9C8A2E), Color(0xFF2E9C6A), Color(0xFF2E8A3C),
      Color(0xFF2E5E9C), Color(0xFF6A2E9C), Color(0xFF9C2E5E)];

  @override
  Widget build(BuildContext context) {
    const size = 60.0;
    Widget art;
    if (letter) {
      final hue = _hues[entry.title.toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b) % _hues.length];
      art = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(hue, Colors.white, 0.12)!, hue],
          ),
        ),
        child: Text(entry.title.characters.first.toUpperCase(),
            style: ReplayStyle.title(24)),
      );
    } else {
      final placeholder = Container(
        color: Colors.white.withValues(alpha: 0.06),
        child: Icon(circle ? Icons.person_rounded : Icons.music_note_rounded,
            color: Colors.white24),
      );
      final img = entry.artUrl.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: ImageQualityUtils.getHighResArtwork(entry.artUrl),
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: AppImageCache.thumbnailMemCache,
              placeholder: (_, __) => placeholder,
              errorWidget: (_, __, ___) => placeholder,
            );
      art = SizedBox(
        width: size,
        height: size,
        child: circle
            ? ClipOval(child: img)
            : ClipRRect(borderRadius: BorderRadius.circular(10), child: img),
      );
    }

    final plays = entry.plays;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('$rank',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: rank == 1 ? ReplayStyle.rankOne : Colors.white.withValues(alpha: 0.45),
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
          const SizedBox(width: 6),
          art,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ReplayStyle.title(17.5, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ReplayStyle.meta(size: 14.5)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('$plays',
              style: ReplayStyle.meta(size: 14, alpha: 0.45).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: 'Number $rank, ${entry.title}, $subtitle, ${plays == 1 ? '1 play' : '$plays plays'}',
      excludeSemantics: true,
      child: onTap == null
          ? row
          : PressableScale(
              onTap: () {
                HapticFeedback.lightImpact();
                onTap!();
              },
              child: row,
            ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: ReplayStyle.tile,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(groupThousands(value), style: ReplayStyle.display(30)),
            ),
            const SizedBox(height: 2),
            Text(label, style: ReplayStyle.meta(size: 13, alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _Sentence extends StatelessWidget {
  const _Sentence(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
        child: Text(text,
            style: ReplayStyle.meta(size: 15.5, alpha: 0.62).copyWith(height: 1.4)),
      );
}
