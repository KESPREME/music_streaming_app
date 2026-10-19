// lib/screens/playlist_import_screen.dart
//
// IMPORT FROM SPOTIFY (glass). Plan: docs/PLAN-local-import-youtube.md §2.
//
// Two routes in, one result out:
//   * Paste a playlist link -> any public playlist, read without an account
//     or build credentials (spotify_public.dart). Always available.
//   * Connect Spotify -> your own Spotify playlists, tick any, "Import N".
//     Only when this build carries Spotify credentials.
// Each playlist is read in full and every song is matched to YouTube Music
// (best title/artist/length match, a few at a time), with progress you can
// watch and cancel. The result says how many matched; a song with no match is
// kept and looked up when it is played. Re-importing updates the copy you
// already have.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../providers/music_provider.dart';
import '../services/spotify_public.dart' show SpotifyPublicException;
import '../services/spotify_service.dart';
import '../theme/amoled_theme.dart';
import '../widgets/collection/collection_kit.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/home_sections.dart' show PressableScale;
import '../widgets/playlist/open_playlist.dart';

const Color _spotifyGreen = Color(0xFF1DB954);

/// One finished import, for the results list.
class ImportResult {
  const ImportResult({
    required this.playlist,
    required this.matched,
    required this.total,
    this.updated = false,
    this.spotifyTotal,
  });

  final Playlist playlist;
  final int matched;
  final int total;

  /// It replaced a copy imported before.
  final bool updated;

  /// How many songs the playlist has on Spotify, when more than could be read.
  final int? spotifyTotal;

  int get unmatched => total - matched;
}

/// "118 of 120 songs matched" and the rest explained.
String importSummary(ImportResult r) {
  final base = r.total == 0
      ? 'No songs in this playlist'
      : r.unmatched == 0
          ? (r.total == 1 ? '1 song matched' : 'All ${r.total} songs matched')
          : '${r.matched} of ${r.total} matched · ${r.unmatched} will be looked up when played';
  final all = r.spotifyTotal;
  return all != null && all > r.total ? '$base · Spotify shared ${r.total} of its $all songs' : base;
}

/// One playlist to import: how to read and match it.
class _ImportJob {
  const _ImportJob({required this.id, required this.name, required this.load});

  final String id;
  final String name;
  final Future<({Playlist playlist, int? total})> Function(
      void Function(int done, int total) onProgress, bool Function() isCancelled) load;
}

class PlaylistImportScreen extends StatefulWidget {
  const PlaylistImportScreen({super.key, this.service, this.configured});

  /// For tests.
  final SpotifyService? service;
  final bool? configured;

  @override
  State<PlaylistImportScreen> createState() => _PlaylistImportScreenState();
}

class _PlaylistImportScreenState extends State<PlaylistImportScreen> {
  late final SpotifyService _spotify = widget.service ?? SpotifyService();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _link = TextEditingController();

  bool get _configured => widget.configured ?? SpotifyService.isConfigured;

  bool _connecting = false;
  String? _connectError;
  List<Map<String, dynamic>>? _spotifyPlaylists;
  final Set<String> _picked = {};

  // The running import.
  bool _importing = false;
  bool _cancel = false;
  String _currentName = '';
  int _done = 0;
  int _total = 0;
  int _queueIndex = 0;
  int _queueLength = 0;
  bool _reading = false;
  String? _importError;
  final List<ImportResult> _results = [];

  @override
  void dispose() {
    _scroll.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    HapticFeedback.lightImpact();
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    try {
      final list = await _spotify.getUserPlaylists();
      if (!mounted) return;
      setState(() {
        _spotifyPlaylists = list;
        _connecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = _friendly(e);
      });
    }
  }

  static String _friendly(Object e) {
    final s = e.toString();
    if (e is SpotifyPublicException) return s;
    if (s.contains('cancel')) return 'Spotify sign-in was cancelled.';
    if (s.contains('Network') || s.contains('Socket') || s.contains('Timeout')) {
      return 'No connection. Check your network and try again.';
    }
    if (s.contains('credentials missing')) return 'Spotify import is not set up in this build.';
    return 'Spotify didn\'t answer. Try again in a moment.';
  }

  static String _imageOf(Map<String, dynamic> m) {
    final images = m['images'];
    if (images is List && images.isNotEmpty && images.first is Map) {
      return (images.first['url'] as String?) ?? '';
    }
    return '';
  }

  static int? _countOf(Map<String, dynamic> m) {
    final t = m['tracks'];
    return t is Map && t['total'] is int ? t['total'] as int : null;
  }

  Future<void> _run(List<_ImportJob> jobs) async {
    if (jobs.isEmpty || _importing) return;
    HapticFeedback.mediumImpact();
    final provider = context.read<MusicProvider>();
    setState(() {
      _importing = true;
      _cancel = false;
      _importError = null;
      _queueLength = jobs.length;
    });
    for (var i = 0; i < jobs.length; i++) {
      if (_cancel || !mounted) break;
      final job = jobs[i];
      setState(() {
        _queueIndex = i;
        _currentName = job.name;
        _done = 0;
        _total = 0;
        _reading = false;
      });
      try {
        final existed = provider.playlistById(job.id) != null;
        final loaded = await job.load(
          (d, t) {
            if (!mounted) return;
            setState(() {
              _reading = false;
              _done = d;
              _total = t;
            });
          },
          () => _cancel || !mounted,
        );
        final pl = loaded.playlist;
        await provider.importPlaylist(pl);
        final matched = pl.tracks.where((t) => t.source == 'youtube').length;
        if (!mounted) return;
        setState(() => _results.insert(
            0,
            ImportResult(
              playlist: pl,
              matched: matched,
              total: pl.tracks.length,
              updated: existed,
              spotifyTotal: loaded.total,
            )));
      } on ImportCancelled {
        break;
      } catch (e) {
        if (!mounted) return;
        setState(() => _importError = 'Couldn\'t import "$_currentName". ${_friendly(e)}');
      }
    }
    if (!mounted) return;
    final cancelled = _cancel;
    setState(() {
      _importing = false;
      _picked.clear();
    });
    if (cancelled) {
      showCollectionToast(context, 'Import stopped', icon: Icons.stop_circle_outlined);
    } else if (_results.isNotEmpty) {
      HapticFeedback.mediumImpact();
    }
  }

  _ImportJob _accountJob(String id, String name, String image) => _ImportJob(
        id: id,
        name: name,
        load: (onProgress, isCancelled) => _spotify
            .getPlaylistWithTracks(id, name, image, onProgress: onProgress, isCancelled: isCancelled)
            .then((pl) => (playlist: pl, total: null)),
      );

  /// A pasted link. Read publicly first (no account, no build credentials);
  /// the signed-in API only if that fails and this build has credentials.
  Future<void> _importLink() async {
    final id = spotifyPlaylistIdFrom(_link.text);
    if (id == null) {
      setState(() => _importError = 'That doesn\'t look like a Spotify playlist link.');
      return;
    }
    FocusScope.of(context).unfocus();
    await _run([
      _ImportJob(
        id: id,
        name: 'Spotify playlist',
        load: (onProgress, isCancelled) async {
          try {
            return await _spotify.getPublicPlaylistWithTracks(
              id,
              onName: (name) {
                if (mounted) setState(() => _currentName = name);
              },
              onReading: (read, total) {
                if (!mounted) return;
                setState(() {
                  _reading = true;
                  _done = read;
                  _total = total;
                });
              },
              onProgress: onProgress,
              isCancelled: isCancelled,
            );
          } on ImportCancelled {
            rethrow;
          } catch (e) {
            if (!_configured) rethrow;
            final meta = await _spotify.getPlaylistMetadata(id);
            final name = (meta['name'] as String?) ?? 'Spotify playlist';
            if (mounted) setState(() => _currentName = name);
            final pl = await _spotify.getPlaylistWithTracks(id, name, _imageOf(meta),
                onProgress: onProgress, isCancelled: isCancelled);
            return (playlist: pl, total: null);
          }
        },
      ),
    ]);
    if (mounted && _importError == null && !_cancel) _link.clear();
  }

  /// The link field, its paste button and Import. Pasting a Spotify link
  /// starts the import straight away: that is what the listener came to do.
  Widget _linkField() => Padding(
        padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 0),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, color: Colors.white.withValues(alpha: 0.6)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _link,
                        enabled: !_importing,
                        cursorColor: _spotifyGreen,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _importLink(),
                        style: CollectionStyle.meta(size: 15, alpha: 0.95),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: 'open.spotify.com/playlist/…',
                          hintStyle: CollectionStyle.meta(size: 15, alpha: 0.4),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Paste',
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      icon: Icon(Icons.content_paste_rounded, color: Colors.white.withValues(alpha: 0.7), size: 20),
                      onPressed: _importing
                          ? null
                          : () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              final text = data?.text?.trim();
                              if (text == null || text.isEmpty || !mounted) return;
                              _link.text = text;
                              if (spotifyPlaylistIdFrom(text) != null) {
                                HapticFeedback.selectionClick();
                                _importLink();
                              } else {
                                setState(() => _importError = 'That doesn\'t look like a Spotify playlist link.');
                              }
                            },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            ListenableBuilder(
              listenable: _link,
              builder: (context, _) => Opacity(
                opacity: _link.text.trim().isEmpty || _importing ? 0.4 : 1,
                child: SizedBox(
                  width: 108,
                  child: CollectionPill(
                    label: 'Import',
                    icon: Icons.download_rounded,
                    filled: true,
                    onTap: () {
                      if (_link.text.trim().isNotEmpty && !_importing) _importLink();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final clearance = collectionBottomClearance(context);
    final amoled = AmoledTheme.isOn(context);
    final provider = context.watch<MusicProvider>();
    final lists = _spotifyPlaylists;

    return PlayerAwarePopScope(
      child: PopScope(
        // Leaving mid-import stops it cleanly between songs.
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _cancel = true;
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (!amoled)
                const Positioned(
                  top: -140,
                  left: -100,
                  right: -100,
                  height: 440,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-0.4, -0.3),
                          radius: 0.9,
                          colors: [Color(0x401DB954), Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                ),
              CustomScrollView(
                controller: _scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: top + 64)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 4, CollectionStyle.gutter, 18),
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: _spotifyGreen,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [BoxShadow(color: _spotifyGreen.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 10))],
                            ),
                            child: const Icon(Icons.graphic_eq_rounded, color: Colors.black, size: 34),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(header: true, child: Text('Import from Spotify', style: CollectionStyle.title(28))),
                                const SizedBox(height: 4),
                                Text('Bring your playlists over. Every song is matched on YouTube Music.',
                                    style: CollectionStyle.meta(size: 14, alpha: 0.6).copyWith(height: 1.35)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_importing)
                    SliverToBoxAdapter(
                      child: _Progress(
                        name: _currentName,
                        done: _done,
                        total: _total,
                        reading: _reading,
                        index: _queueIndex,
                        count: _queueLength,
                        onCancel: () => setState(() => _cancel = true),
                        cancelling: _cancel,
                      ),
                    ),
                  if (_importError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(_importError!,
                              style: CollectionStyle.meta(size: 14, alpha: 0.9).copyWith(color: const Color(0xFFFF8A8A))),
                        ),
                      ),
                    ),
                  if (_results.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _Results(
                        results: _results,
                        onOpen: (r) {
                          final pl = provider.playlistById(r.playlist.id) ?? r.playlist;
                          openUserPlaylist(context, pl);
                        },
                      ),
                    ),
                  // 1. Paste a link: works for any public playlist, no account.
                  const SliverToBoxAdapter(child: _SectionTitle('Paste a playlist link')),
                  SliverToBoxAdapter(child: _linkField()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter + 4, 10, CollectionStyle.gutter, 0),
                      child: Text('In Spotify: ··· → Share → Copy link. Any public playlist works, no sign-in needed.',
                          style: CollectionStyle.meta(size: 13, alpha: 0.5).copyWith(height: 1.35)),
                    ),
                  ),
                  // 2. Your own library, when this build can sign in to Spotify.
                  const SliverToBoxAdapter(child: _SectionTitle('Your Spotify playlists')),
                  if (!_configured)
                    const SliverToBoxAdapter(child: _NotConfigured())
                  else ...[
                    if (lists == null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Sign in to Spotify to see the playlists you made and follow.',
                                  style: CollectionStyle.meta(size: 14.5, alpha: 0.6)),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: _SpotifyButton(
                                  label: _connecting ? 'Connecting…' : 'Connect Spotify',
                                  busy: _connecting,
                                  onTap: _connecting || _importing ? null : _connect,
                                ),
                              ),
                              if (_connectError != null) ...[
                                const SizedBox(height: 10),
                                Text(_connectError!,
                                    style: CollectionStyle.meta(size: 14, alpha: 0.9).copyWith(color: const Color(0xFFFF8A8A))),
                              ],
                            ],
                          ),
                        ),
                      )
                    else if (lists.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: CollectionStyle.gutter, vertical: 8),
                          child: Text('No playlists on this Spotify account.', style: CollectionStyle.meta(size: 14.5, alpha: 0.6)),
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter - 8, 0, CollectionStyle.gutter - 8, 4),
                          child: Row(
                            children: [
                              TextButton(
                                onPressed: _importing
                                    ? null
                                    : () => setState(() {
                                          if (_picked.length == lists.length) {
                                            _picked.clear();
                                          } else {
                                            _picked.addAll(lists.map((m) => m['id'] as String));
                                          }
                                        }),
                                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                                child: Text(_picked.length == lists.length ? 'Deselect all' : 'Select all',
                                    style: CollectionStyle.meta(size: 14.5, alpha: 0.9, w: FontWeight.w700)),
                              ),
                              const Spacer(),
                              Text('${lists.length} playlists', style: CollectionStyle.meta(size: 13, alpha: 0.5)),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final m = lists[i];
                            final id = m['id'] as String;
                            return _SpotifyRow(
                              name: (m['name'] as String?) ?? 'Untitled',
                              image: _imageOf(m),
                              count: _countOf(m),
                              owner: (m['owner'] is Map ? m['owner']['display_name'] as String? : null),
                              picked: _picked.contains(id),
                              alreadyImported: provider.playlistById(id) != null,
                              onTap: _importing
                                  ? null
                                  : () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));
                                    },
                            );
                          },
                          childCount: lists.length,
                        ),
                      ),
                    ],
                  ],
                  SliverToBoxAdapter(child: SizedBox(height: clearance + (_picked.isNotEmpty ? 84 : 20))),
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: CollectionNavBar(
                  scroll: _scroll,
                  topInset: top,
                  title: 'Import from Spotify',
                  titleAppearsAt: 40,
                  onBack: () => Navigator.maybePop(context),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: clearance - 6,
                child: IgnorePointer(
                  ignoring: _picked.isEmpty || _importing,
                  child: AnimatedSlide(
                    offset: _picked.isEmpty || _importing ? const Offset(0, 0.6) : Offset.zero,
                    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _picked.isEmpty || _importing ? 0 : 1,
                      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
                      child: _SpotifyButton(
                        label: _picked.length == 1 ? 'Import 1 playlist' : 'Import ${_picked.length} playlists',
                        onTap: () {
                          final chosen = [
                            for (final m in lists ?? const <Map<String, dynamic>>[])
                              if (_picked.contains(m['id']))
                                _accountJob(m['id'] as String, (m['name'] as String?) ?? 'Untitled', _imageOf(m)),
                          ];
                          _run(chosen);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 22, CollectionStyle.gutter, 10),
        child: Semantics(header: true, child: Text(text, style: CollectionStyle.title(20))),
      );
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: CollectionStyle.gutter),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Signing in to see your own Spotify library isn\'t available in this build. '
                'Public playlist links above work without it.',
                style: CollectionStyle.meta(size: 14.5, alpha: 0.75).copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      );
}

class _SpotifyButton extends StatelessWidget {
  const _SpotifyButton({required this.label, required this.onTap, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null && !busy ? 0.5 : 1,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _spotifyGreen,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [BoxShadow(color: _spotifyGreen.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                else
                  const Icon(Icons.graphic_eq_rounded, color: Colors.black),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CollectionStyle.title(16).copyWith(color: Colors.black)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpotifyRow extends StatelessWidget {
  const _SpotifyRow({
    required this.name,
    required this.image,
    required this.count,
    required this.owner,
    required this.picked,
    required this.alreadyImported,
    required this.onTap,
  });

  final String name;
  final String image;
  final int? count;
  final String? owner;
  final bool picked;
  final bool alreadyImported;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (count != null) count == 1 ? '1 song' : '$count songs',
      if (owner != null && owner!.isNotEmpty) 'by $owner',
      if (alreadyImported) 'Imported · importing again updates it',
    ].join(' · ');
    final ph = Container(color: Colors.white.withValues(alpha: 0.06), child: const Icon(Icons.queue_music_rounded, color: Colors.white24));
    return Semantics(
      button: true,
      selected: picked,
      label: '$name${meta.isEmpty ? '' : ', $meta'}',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 8, CollectionStyle.gutter, 8),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: image.isEmpty
                      ? ph
                      : CachedNetworkImage(imageUrl: image, fit: BoxFit.cover, placeholder: (_, __) => ph, errorWidget: (_, __, ___) => ph),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(16, w: FontWeight.w700)),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta(size: 13)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: Icon(
                  picked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(picked),
                  color: picked ? _spotifyGreen : Colors.white38,
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.name,
    required this.done,
    required this.total,
    required this.index,
    required this.count,
    required this.onCancel,
    required this.cancelling,
    this.reading = false,
  });

  final String name;
  final int done;
  final int total;
  final int index;
  final int count;
  final VoidCallback onCancel;
  final bool cancelling;

  /// Reading the songs past the first 100, before matching starts.
  final bool reading;

  @override
  Widget build(BuildContext context) {
    final line = total == 0
        ? 'Reading the playlist…'
        : reading
            ? 'Reading songs $done of $total'
            : 'Matching $done of $total songs';
    return Container(
      margin: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _spotifyGreen.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(count > 1 ? 'Importing ${index + 1} of $count · $name' : 'Importing $name',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(15.5, w: FontWeight.w700)),
                const SizedBox(height: 4),
                Semantics(liveRegion: true, child: Text(cancelling ? 'Stopping…' : line, style: CollectionStyle.meta(size: 13))),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: total == 0 ? null : done / total,
                    color: _spotifyGreen,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: cancelling ? null : onCancel,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text('Cancel', style: CollectionStyle.meta(size: 14.5, alpha: 0.9, w: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.results, required this.onOpen});

  final List<ImportResult> results;
  final ValueChanged<ImportResult> onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Imported', style: CollectionStyle.title(20)),
          const SizedBox(height: 6),
          for (final r in results)
            Semantics(
              button: true,
              label: '${r.updated ? 'Updated' : 'Imported'} ${r.playlist.name}. ${importSummary(r)}',
              excludeSemantics: true,
              child: PressableScale(
                onTap: () => onOpen(r),
                child: Container(
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: _spotifyGreen),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${r.updated ? 'Updated' : 'Imported'} "${r.playlist.name}"',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(15.5, w: FontWeight.w700)),
                            Text(importSummary(r), maxLines: 2, style: CollectionStyle.meta(size: 13)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.45)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
