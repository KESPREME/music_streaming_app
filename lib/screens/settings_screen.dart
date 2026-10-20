import 'dart:ui';
import 'package:flutter/material.dart';
import '../widgets/jelly_icon_button.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../design/glass/chrome_glass.dart';
import '../theme/app_font.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart';
import '../services/app_platform.dart';
import '../services/auth_service.dart';
import '../services/equalizer_service.dart';
import '../services/session/session_store.dart';
import '../services/update/update_models.dart';
import '../services/update/update_service.dart';
import '../models/music_source.dart';
import '../screens/account_screen.dart';
import '../screens/equalizer_screen.dart';
import '../screens/software_update_screen.dart';
import '../screens/song_transitions_screen.dart';
import '../widgets/eq/eq_curve_glyph.dart';
import '../widgets/themed_downloaded_songs_screen.dart';
import '../widgets/accent_settings_card.dart';
import '../widgets/glass_surface.dart';
import '../widgets/home_sections.dart' show PressableScale;
import '../widgets/jelly_press.dart';
import '../widgets/liquid_switch.dart';
import '../widgets/lyric_providers_sheet.dart';
import '../widgets/settings/font_picker_sheet.dart';
import '../widgets/settings/settings_search.dart';
import '../widgets/settings/settings_segmented.dart';
import '../widgets/update/update_actions.dart';
import '../widgets/update/update_copy.dart';
import '../theme/amoled_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Keywords for every row on this screen.
///
/// Several entries carry words that are deliberately NOT on the row - "mobile
/// data" for Cellular Quality, "sign in" for Account - because those are what
/// somebody actually types.
///
/// PUBLIC because the registry is the thing worth testing. A test that copied
/// this list would keep passing while the screen drifted, which is the opposite
/// of what a test is for: the bug this list actually had was a group gated by
/// ids nobody had registered, and only a test reading the real list can catch
/// the next one.
const List<SettingsEntry> settingsSearchEntries = <SettingsEntry>[
    SettingsEntry('quick.quality', ['Quality', 'bitrate', 'audio']),
    SettingsEntry('quick.eq', [
      'Equalizer', 'EQ', 'sound', 'audio', 'bass', 'treble', 'presets', 'preamp',
      'pre-amp', 'headroom', 'loudness boost', 'spatial', 'virtualizer', 'audiophile',
    ]),
    SettingsEntry('quick.lyrics', ['Lyrics', 'providers']),
    SettingsEntry('quick.downloads', ['Downloads', 'offline']),
    SettingsEntry('account', ['Account', 'sign in', 'google', 'profile', 'channel']),
    SettingsEntry('version', ['Version', 'about', 'build']),
    SettingsEntry('about.update', [
      'Software update', 'update', 'updates', 'upgrade', 'new version', 'release',
      'OTA', 'check for updates', 'early builds', 'beta',
    ]),
    SettingsEntry('source', ['Source', 'innertube', 'powered by']),
    SettingsEntry('prefs.theme', ['Theme', 'appearance', 'dark mode', 'accent', 'colour', 'color']),
    SettingsEntry('prefs.dynamic', ['Dynamic Colors', 'material you', 'wallpaper']),
  SettingsEntry('prefs.font', ['Font', 'typeface', 'typography', 'Inter', 'Manrope']),
  SettingsEntry('prefs.weight', ['Text weight', 'bold', 'bolder', 'lighter', 'font weight']),
  SettingsEntry('prefs.amoled', ['Pure black', 'AMOLED', 'OLED', 'black', 'true black', 'dark', 'battery', 'background']),
    SettingsEntry('prefs.glass', [
      'Glass rendering', 'glass', 'refraction', 'frosted', 'blur', 'bottom bar',
      'navigation bar', 'mini player', 'pixelated', 'artifacts', 'performance',
    ]),
    SettingsEntry('accent.card', ['Accent', 'colour', 'color', 'swatch', 'album art']),
    SettingsEntry('playback.transitions', ['Song Transitions', 'crossfade', 'automix', 'fade', 'gapless', 'blend', 'mix', 'loudness', 'balance', 'beat', 'tempo', 'bpm', 'level', 'transition']),
    SettingsEntry('playback.autoQueue', ['Auto Queue', 'keep playing', 'queue']),
    SettingsEntry('playback.session', [
      'Remember what I was playing', 'resume', 'restore', 'session', 'last played',
      'where I left off', 'continue',
    ]),
    SettingsEntry('playback.cellular', ['Cellular Quality', 'mobile data', 'stream over mobile data']),
    SettingsEntry('data.wifi', ['Wi-Fi Quality', 'wifi', 'wi-fi', 'bitrate', 'kbps', 'streaming quality', 'audio quality']),
    SettingsEntry('playback.lowData', ['Low Data Mode', 'data saver']),
    SettingsEntry('playback.offline', ['Offline Mode', 'local', 'downloaded only']),
    SettingsEntry('playback.canvas', ['Animated Cover Art', 'canvas video']),
    SettingsEntry('playback.blur', ['Animated Cover Art', 'bleed artwork']),
    // These three live in the SAME card as the two above, so they have to be
    // registered AND named in that card's gate. Registering them alone does
    // nothing: the gate asks `matchesAny`, which only ever sees the ids it was
    // given, and failing-open inside a group cannot help a group that was already
    // taken off the screen. That is how searching "lyrics" used to hide the
    // Lyric Providers row outright.
    SettingsEntry('playback.syncedLyrics', [
      'Lyrics',
      'synced lyrics',
      'time-synced',
      'timed lyrics',
      'karaoke',
      'timing',
    ]),
    SettingsEntry('playback.wordSync', [
      'Lyrics',
      'word sync',
      'syllable',
      'prioritize syllable lyrics',
      'apple music timings',
    ]),
    SettingsEntry('playback.lyricProviders', [
      'Lyrics',
      'lyric providers',
      'providers',
      'lrc',
      'source',
      'reorder',
    ]),
    SettingsEntry('data.cache', ['Clear Cache', 'storage', 'free up space']),
  ];

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  /// Current filter. Held here rather than in a search widget so the same query
  /// can decide which groups render and whether the empty state appears.
  String _query = '';

  /// The sections rise in one after another when the screen opens.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  final GlobalKey _qualityKey = GlobalKey();
  bool _remember = SessionStore.instance.restoreEnabled;
  late final Future<AppInfo> _appInfo = AppPlatform.info();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Widget _section(int i, Widget child) => SliverToBoxAdapter(
        child: _Reveal(intro: _intro, index: i, child: child),
      );

  Widget _header(int i, String text, Color accent) => _section(
        i,
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            text,
            style: AppFont.style(
              color: accent.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
        ),
      );

  Widget _card(List<Widget> rows, {Key? key}) => Container(
        key: key,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: rows),
      );

  Widget _gap(double h) => SliverToBoxAdapter(child: SizedBox(height: h));

  @override
  Widget build(BuildContext context) {
    final index = SettingsSearchIndex(_query)
      ..registerAll(settingsSearchEntries);
    final theme = Theme.of(context);
    final musicProvider = context.watch<MusicProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final authService = Provider.of<AuthService>(context, listen: false);
    final updates = maybeUpdateService(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;

    final hasQualityGroup = index.matchesAny(const ['data.wifi', 'playback.cellular', 'data.cache']);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AmoledTheme.gradient(context, isDark
                ? [const Color(0xFF121212), const Color(0xFF1E1E1E), const Color(0xFF000000)]
                : [const Color(0xFFF7F7F7), const Color(0xFFFFFFFF)]),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Large header
              _section(
                0,
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Settings',
                          style: AppFont.style(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      JellyIconButton(
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),

              // Search. Sits directly under the title, before anything it can
              // filter, so what it controls is visible when it is used.
              _section(
                1,
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                  child: SettingsSearchField(
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ),

              // Profile
              if (index.matchesAny(const ['account']))
                _section(
                  2,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _ProfileCard(authService: authService),
                  ),
                ),

              // An update waiting for you. Absent (and zero-height) otherwise, so
              // nothing on this screen moves when there is none.
              if (updates != null && !index.isFiltering)
                _section(
                  3,
                  _UpdateBanner(service: updates, accent: accent),
                ),
              _gap(14),

              // Sound & quick access. Gated as a group rather than per tile: the
              // tiles are a single visual unit, and leaving one stranded on its
              // own row looks like a rendering fault.
              if (index.matchesAny(const [
                'quick.eq',
                'quick.quality',
                'quick.lyrics',
                'quick.downloads',
              ]))
                _section(
                  4,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _EqualizerTile(accent: accent)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _QuickTile(
                                  icon: Icons.high_quality_rounded,
                                  title: 'Quality',
                                  subtitle: musicProvider.isAutoBitrate
                                      ? 'Auto'
                                      : '${musicProvider.wifiBitrate} kbps',
                                  accent: accent,
                                  onTap: () {
                                    final ctx = _qualityKey.currentContext;
                                    if (ctx != null) {
                                      Scrollable.ensureVisible(
                                        ctx,
                                        alignment: 0.1,
                                        duration: const Duration(milliseconds: 520),
                                        curve: Curves.easeOutCubic,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _QuickTile(
                                icon: Icons.lyrics_rounded,
                                title: 'Lyrics',
                                subtitle: 'Providers',
                                accent: accent,
                                onTap: () => LyricProvidersSheet.show(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _QuickTile(
                                icon: Icons.download_rounded,
                                title: 'Downloads',
                                subtitle: 'Offline',
                                accent: accent,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ThemedDownloadedSongsScreen(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              _gap(28),

              // Appearance
              //
              // The header is hidden together with its group, never on its own:
              // a section title above nothing is worse than no section title.
              if (index.matchesAny(const [
                'prefs.theme', 'prefs.dynamic', 'prefs.amoled', 'prefs.glass',
                'prefs.font', 'prefs.weight',
              ]))
                _header(5, 'APPEARANCE', accent),
              if (index.matchesAny(const [
                'prefs.theme', 'prefs.dynamic', 'prefs.amoled', 'prefs.glass',
                'prefs.font', 'prefs.weight',
              ]))
                _section(
                  5,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _card([
                      _GlassRow(
                        icon: Icons.palette_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Theme',
                        subtitle: '${themeProvider.getThemeName()} · ${themeProvider.getThemeDescription()}',
                        trailing: LiquidSwitch(value: themeProvider.isMaterialYou, onChanged: (_) => themeProvider.toggleTheme()),
                      ),
                      _divider(),
                      _GlassRow(
                        icon: Icons.color_lens_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Dynamic Colors',
                        subtitle: themeProvider.isDynamicColorEnabled ? 'Enabled' : 'Disabled',
                        trailing: LiquidSwitch(value: themeProvider.isDynamicColorEnabled, onChanged: (v) => themeProvider.setDynamicColorEnabled(v)),
                      ),
                      _divider(),
                      // Off by default. The backdrop and the full-screen pages
                      // go to #000000 (see AmoledTheme); artwork is untouched.
                      // One switch, one spoken label: the whole row is the
                      // target and a screen reader hears "Pure black (AMOLED),
                      // switch, on" instead of a bare unlabeled toggle.
                      Semantics(
                        container: true,
                        toggled: themeProvider.isAmoled,
                        label: 'Pure black (AMOLED)',
                        hint: 'True black backgrounds, saves power on OLED screens',
                        onTap: () => themeProvider.setAmoled(!themeProvider.isAmoled),
                        excludeSemantics: true,
                        child: _GlassRow(
                          icon: Icons.contrast_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Pure black (AMOLED)',
                          subtitle: themeProvider.isAmoled
                              ? 'On · true black, saves power on OLED screens'
                              : 'Off · backgrounds follow the album art',
                          onTap: () => themeProvider.setAmoled(!themeProvider.isAmoled),
                          trailing: LiquidSwitch(value: themeProvider.isAmoled, onChanged: (v) => themeProvider.setAmoled(v)),
                        ),
                      ),
                      // How the bottom bar, its pills and the mini player are
                      // drawn. An escape hatch as much as a preference: if a
                      // phone's GPU renders the refraction badly, this is one
                      // tap, not a new release.
                      if (themeProvider.isGlassmorphism) ...[
                        _divider(),
                        _GlassRenderingRow(themeProvider: themeProvider, accent: accent),
                      ],
                      _divider(),
                      _GlassRow(
                        key: const ValueKey('settings_font'),
                        icon: Icons.text_fields_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Font',
                        subtitle: themeProvider.fontFamily,
                        onTap: () => FontPickerSheet.show(context),
                        trailing: Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.4)),
                      ),
                      _divider(),
                      _GlassRow(
                        key: const ValueKey('settings_weight'),
                        icon: Icons.format_bold_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Text weight',
                        subtitle: FontPickerSheet.weightLabel(themeProvider.fontWeightDelta),
                        onTap: () => FontPickerSheet.show(context),
                        trailing: Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.4)),
                      ),
                      // The "Album-Art Adaptive" row that used to sit here
                      // is gone: AccentSettingsCard a few lines below already
                      // exposes the same switch, so the screen was offering
                      // one setting twice in two different-looking places.
                    ]),
                  ),
                ),
              _gap(16),

              // Accent swatches (keep existing card but wrap in glass)
              _section(
                6,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GlassSurface(
                    tier: GlassTier.card,
                    borderRadius: 22,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: const AccentSettingsCard(),
                  ),
                ),
              ),
              _gap(28),

              // Playback
              if (index.matchesAny(const [
                'playback.transitions',
                'playback.autoQueue',
                'playback.session',
                'playback.cellular',
                'playback.lowData',
                'playback.offline',
              ])) ...[
                _header(7, 'PLAYBACK', accent),
                _section(
                  7,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _card([
                      if (index.matchesAny(const ['playback.transitions'])) ...[
                        ListenableBuilder(
                          listenable: musicProvider.transitionSettings,
                          builder: (context, _) => _NavTile(
                            icon: Icons.blur_linear_rounded,
                            title: 'Song Transitions',
                            subtitle: SongTransitionsScreen.summary(
                                musicProvider.transitionSettings),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SongTransitionsScreen()),
                            ),
                          ),
                        ),
                        _divider(),
                      ],
                      _GlassRow(
                        icon: Icons.play_circle_filled_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Auto Queue',
                        subtitle: 'Keep music going when queue ends',
                        trailing: LiquidSwitch(value: musicProvider.isAutoQueueEnabled, onChanged: (v) => musicProvider.setAutoQueueEnabled(v)),
                      ),
                      _divider(),
                      _GlassRow(
                        icon: Icons.history_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Remember what I was playing',
                        subtitle: _remember
                            ? 'Reopens on the same song, queue and moment, paused'
                            : 'Starts fresh every time',
                        onTap: () => _setRemember(!_remember),
                        trailing: LiquidSwitch(value: _remember, onChanged: _setRemember),
                      ),
                      _divider(),
                      _GlassRow(
                        icon: Icons.data_saver_on_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Low Data Mode',
                        subtitle: 'Reduces quality to save data',
                        trailing: LiquidSwitch(value: musicProvider.isLowDataMode, onChanged: (_) => musicProvider.toggleLowDataMode()),
                      ),
                      _divider(),
                      _GlassRow(
                        icon: Icons.offline_bolt_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Offline Mode',
                        subtitle: 'Play only downloaded songs',
                        trailing: LiquidSwitch(value: musicProvider.isOfflineMode, onChanged: (_) => musicProvider.toggleOfflineMode()),
                      ),
                    ]),
                  ),
                ),
                _gap(16),
              ],

              // Music source pill
              _section(
                8,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _MusicSourcePill(musicProvider: musicProvider, isDark: isDark),
                ),
              ),
              _gap(28),

              // Streaming quality & storage
              if (hasQualityGroup) ...[
                _header(9, 'QUALITY & STORAGE', accent),
                _section(
                  9,
                  Padding(
                    key: _qualityKey,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _card([
                      _BitrateRow(
                        icon: Icons.wifi_rounded,
                        title: 'Wi-Fi quality',
                        options: const [64, 128, 256, 320],
                        current: musicProvider.wifiBitrate,
                        auto: musicProvider.isAutoBitrate,
                        onAuto: () => musicProvider.setAutoBitrate(true),
                        onPick: musicProvider.setWifiBitrate,
                      ),
                      _divider(),
                      _BitrateRow(
                        icon: Icons.signal_cellular_alt_rounded,
                        title: 'Cellular quality',
                        options: const [32, 64, 128],
                        current: musicProvider.cellularBitrate,
                        auto: musicProvider.isAutoBitrate,
                        onAuto: () => musicProvider.setAutoBitrate(true),
                        onPick: musicProvider.setCellularBitrate,
                      ),
                      _divider(),
                      _GlassRow(
                        icon: Icons.graphic_eq_rounded,
                        iconBg: Colors.white.withValues(alpha: 0.08),
                        iconColor: Colors.white70,
                        title: 'Clear Cache',
                        subtitle: 'Free up storage space',
                        trailing: JellyIconButton(
                          icon: const Icon(Icons.cleaning_services_rounded, size: 20, color: Colors.white70),
                          onPressed: () async {
                            await musicProvider.clearAllCaches();
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cache cleared', style: AppFont.style(color: Colors.white)), backgroundColor: Colors.grey[900]));
                          },
                        ),
                      ),
                    ]),
                  ),
                ),
                _gap(28),
              ],

              // Motion Artwork & Lyrics
              //
              // Gated as a group, so every row in the card has to be named here.
              // The card is a single visual unit - leaving the lyric rows out of
              // this list is not a smaller group, it is the whole card gone the
              // moment somebody searches for lyrics.
              if (index.matchesAny(const [
                'playback.canvas',
                'playback.blur',
                'playback.syncedLyrics',
                'playback.wordSync',
                'playback.lyricProviders',
              ])) ...[
                _header(10, 'MOTION ARTWORK & LYRICS', accent),
                _section(
                  10,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _card([
                      _GlassRow(
                        icon: Icons.movie_filter_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Animated Cover Art',
                        subtitle: 'Play looping canvas video on normal screen',
                        trailing: LiquidSwitch(
                          value: musicProvider.animatedCanvasEnabled,
                          onChanged: (v) => musicProvider.setAnimatedCanvasEnabled(v),
                        ),
                      ),
                      _divider(),
                      _GlassRow(
                        icon: Icons.cell_tower_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Stream Over Mobile Data',
                        subtitle: 'Allow video covers over cellular connections',
                        trailing: LiquidSwitch(
                          value: musicProvider.canvasOverCellular,
                          onChanged: (v) => musicProvider.setCanvasOverCellular(v),
                        ),
                      ),
                      _divider(),
                      _GlassRow(
                        icon: Icons.fullscreen_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Full-Bleed Artwork',
                        subtitle: 'Bleed artwork to screen edges like BitChord',
                        trailing: LiquidSwitch(
                          value: musicProvider.fullBleedArtwork,
                          onChanged: (v) => musicProvider.setFullBleedArtwork(v),
                        ),
                      ),
                      _divider(),
                      _GlassRow(
                        icon: Icons.lyrics_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Synced Lyrics',
                        subtitle: 'Real-time time-synced vocal tracking',
                        trailing: LiquidSwitch(
                          value: musicProvider.syncedLyricsEnabled,
                          onChanged: (v) => musicProvider.setSyncedLyricsEnabled(v),
                        ),
                      ),
                      _divider(),
                      _GlassRow(
                        icon: Icons.text_fields_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Prioritize syllable lyrics',
                        // Says what the switch actually DOES, which the old
                        // wording did not: it keeps searching past a
                        // line-synced hit for one with word timings, and so
                        // can make the first lyric arrive later.
                        subtitle: 'Keep searching past a line-synced match for word-level timings',
                        trailing: LiquidSwitch(
                          value: musicProvider.prioritizeSyllableSync,
                          onChanged: (v) => musicProvider.setPrioritizeSyllableSync(v),
                        ),
                      ),
                      _divider(),
                      _GlassRow(
                        icon: Icons.tune_rounded,
                        iconBg: accent.withValues(alpha: 0.18),
                        iconColor: accent,
                        title: 'Lyric Providers',
                        subtitle: 'Reorder source priority and toggle providers',
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 22,
                        ),
                        onTap: () => LyricProvidersSheet.show(context),
                      ),
                    ]),
                  ),
                ),
                _gap(28),
              ],

              _header(11, 'ABOUT', accent),
              _section(
                11,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _card([
                    _NavTile(icon: Icons.person_outline_rounded, title: 'Account', subtitle: _accountSubtitle(context), onTap: () => AccountScreen.open(context)),
                    _divider(),
                    if (updates != null)
                      ListenableBuilder(
                        listenable: updates,
                        builder: (context, _) => _NavTile(
                          icon: Icons.system_update_rounded,
                          title: 'Software update',
                          subtitle: UpdateEntryPoint.subtitle(updates, DateTime.now()),
                          badge: updates.hasUpdate ? 'NEW' : null,
                          onTap: () => SoftwareUpdateScreen.open(context),
                        ),
                      )
                    else
                      _NavTile(
                        icon: Icons.system_update_rounded,
                        title: 'Software update',
                        subtitle: 'Check for updates',
                        onTap: () => SoftwareUpdateScreen.open(context),
                      ),
                    _divider(),
                    FutureBuilder<AppInfo>(
                      future: _appInfo,
                      builder: (context, snap) {
                        final info = snap.data;
                        return _NavTile(
                          icon: Icons.info_outline_rounded,
                          title: 'Version',
                          subtitle: info != null && info.isKnown
                              ? '${info.versionName} (${info.versionCode})'
                              : 'Mine Music',
                        );
                      },
                    ),
                    _divider(),
                    _NavTile(icon: Icons.code_rounded, title: 'Source', subtitle: 'Powered by InnerTube'),
                  ]),
                ),
              ),
              // Honest empty state, and only when NOTHING matched. An empty
              // screen with no explanation reads as a crash, not as a filter,
              // and the query is echoed back so it is clear what was searched.
              if (index.isFiltering && !index.anyMatch)
                SliverToBoxAdapter(
                  child: SettingsSearchEmpty(query: index.needle),
                ),
              _gap(28),
              SliverToBoxAdapter(child: _MadeByFooter(isDark: isDark)),
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setRemember(bool value) async {
    setState(() => _remember = value);
    await SessionStore.instance.setRestoreEnabled(value);
  }

  Widget _divider() => Divider(height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.06), indent: 62);
}

/// Fades and lifts a section in, one after another.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.intro, required this.index, required this.child});

  final Animation<double> intro;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return child;
    final start = (index * 0.055).clamp(0.0, 0.65);
    final anim = CurvedAnimation(
      parent: intro,
      curve: Interval(start, (start + 0.35).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, 18 * (1 - anim.value)), child: child),
      ),
      child: child,
    );
  }
}

/// The tile that shows the sound you have set, as a picture of its curve.
class _EqualizerTile extends StatelessWidget {
  const _EqualizerTile({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final eq = EqualizerService();
    return ListenableBuilder(
      listenable: eq,
      builder: (context, _) {
        final on = eq.isEnabled;
        final subtitle = on
            ? eq.currentPresetName
            : (eq.isPlatformAvailable ? 'Off' : 'Not on this phone');
        return PressableScale(
          onTap: () {
            HapticFeedback.lightImpact();
            EqualizerScreen.open(context);
          },
          child: Semantics(
            button: true,
            label: 'Equalizer, $subtitle',
            excludeSemantics: true,
            child: GlassSurface(
              tier: GlassTier.card,
              borderRadius: 18,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: accent.withValues(alpha: 0.22)),
                        ),
                        child: Icon(Icons.equalizer_rounded, size: 16, color: accent),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white24),
                    ],
                  ),
                  const SizedBox(height: 12),
                  EqCurveGlyph(
                    bands: eq.bands,
                    gains: eq.profile.gains,
                    color: accent,
                    active: on,
                  ),
                  const SizedBox(height: 8),
                  Text('Equalizer',
                      style: AppFont.style(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.style(color: Colors.white54, fontSize: 11.5)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "Update available" at the top of Settings, with the progress inside it.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.service, required this.accent});

  final UpdateService service;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final show = service.hasUpdate;
        final copy = describeUpdate(service.state, service.installed, DateTime.now());
        final r = service.release;
        final downloading = service.status == UpdateStatus.downloading;
        return AnimatedSize(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !show
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: PressableScale(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      SoftwareUpdateScreen.open(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.26),
                            accent.withValues(alpha: 0.08),
                          ],
                        ),
                        border: Border.all(color: accent.withValues(alpha: 0.45)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.22),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.system_update_rounded, size: 20, color: accent),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      service.status == UpdateStatus.available
                                          ? 'Update available'
                                          : copy.title,
                                      style: AppFont.style(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15.5),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      service.status == UpdateStatus.available && r != null
                                          ? 'Mine Music ${r.version} is ready to download'
                                          : copy.subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFont.style(
                                          color: Colors.white.withValues(alpha: 0.7),
                                          fontSize: 12.5),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                            ],
                          ),
                          if (downloading) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: service.progress <= 0 ? null : service.progress,
                                minHeight: 4,
                                backgroundColor: Colors.white.withValues(alpha: 0.12),
                                valueColor: AlwaysStoppedAnimation(accent),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// How the bottom bar, pills and mini player are drawn, as a three-way choice.
class _GlassRenderingRow extends StatelessWidget {
  const _GlassRenderingRow({required this.themeProvider, required this.accent});

  final ThemeProvider themeProvider;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final chosen = themeProvider.glassRendering;
    final amoled = themeProvider.isAmoled;
    final resolved = ChromeGlassSpec.resolve(amoled: amoled, rendering: chosen);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.blur_on_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Glass rendering',
                        style: AppFont.style(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      chosen == GlassRendering.auto
                          ? 'Auto \u00b7 ${resolved.frosted ? 'frosted' : 'refraction'} right now'
                          : chosen.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.style(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsSegmented<GlassRendering>(
            semanticPrefix: 'Glass rendering',
            selected: chosen,
            options: [for (final r in GlassRendering.values) (r, r.label)],
            onChanged: themeProvider.setGlassRendering,
          ),
        ],
      ),
    );
  }
}

/// A streaming-quality choice: Auto, or one of the bitrates, in one tap.
class _BitrateRow extends StatelessWidget {
  const _BitrateRow({
    required this.icon,
    required this.title,
    required this.options,
    required this.current,
    required this.auto,
    required this.onAuto,
    required this.onPick,
  });

  final IconData icon;
  final String title;
  final List<int> options;
  final int current;
  final bool auto;
  final VoidCallback onAuto;
  final ValueChanged<int> onPick;

  /// `null` stands for Auto.
  static const int _autoKey = -1;

  @override
  Widget build(BuildContext context) {
    final selected = auto ? _autoKey : (options.contains(current) ? current : null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: Colors.white70),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppFont.style(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      auto ? 'Auto \u00b7 adapts to your connection' : '$current kbps',
                      style: AppFont.style(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsSegmented<int>(
            semanticPrefix: title,
            selected: selected,
            options: [
              (_autoKey, 'Auto'),
              for (final b in options) (b, '$b'),
            ],
            onChanged: (v) => v == _autoKey ? onAuto() : onPick(v),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.authService});
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final isLoggedIn = authService.isLoggedIn;
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => AccountScreen.open(context),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Center(child: Text(isLoggedIn ? 'Y' : 'U', style: AppFont.style(color: accent, fontWeight: FontWeight.w900, fontSize: 22))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(isLoggedIn ? 'YouTube Account' : 'User Profile', style: AppFont.style(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8), border: Border.all(color: accent.withValues(alpha: 0.35))),
                        child: Text(isLoggedIn ? 'MANAGE' : 'PROFILE', style: AppFont.style(color: accent, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(isLoggedIn ? _connectedLabel(authService) : 'Mine Music Account & Media', style: AppFont.style(color: Colors.white54, fontSize: 12.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white30),
          ],
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.title, required this.subtitle, required this.accent, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: GlassSurface(
        tier: GlassTier.card,
        borderRadius: 18,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10), border: Border.all(color: accent.withValues(alpha: 0.22))),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white24),
              ],
            ),
            const SizedBox(height: 18),
            Text(title, style: AppFont.style(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Text(subtitle, style: AppFont.style(color: Colors.white54, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _GlassRow extends StatelessWidget {
  const _GlassRow({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 18, color: iconColor)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: AppFont.style(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 2), Text(subtitle, style: AppFont.style(color: Colors.white54, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)])),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap!();
        },
        child: content,
      );
    }
    return content;
  }
}

/// Honest account state for a subtitle.
///
/// A flat "Connected" hid the two things a user actually needs to know: that
/// more than one account is saved, and which one is live. The account name is
/// never invented when Google did not give us one.
String _connectedLabel(AuthService auth) {
  final count = auth.accounts.length;
  if (count > 1) return '$count accounts · switch active';
  final name = auth.activeAccount?.name.trim() ?? '';
  final email = auth.activeAccount?.email.trim() ?? '';
  if (name.isNotEmpty) return 'Signed in as $name';
  if (email.isNotEmpty) return 'Signed in as ${email.split('@').first}';
  return 'Signed in';
}

/// Subtitle for the Account row.
///
/// Says which account is live rather than a flat "Connected", because the row
/// now leads to switching rather than to a single sign-in state.
String _accountSubtitle(BuildContext context) {
  final auth = Provider.of<AuthService>(context, listen: false);
  if (!auth.isLoggedIn) return 'Log in to YouTube';
  return _connectedLabel(auth);
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.title, this.subtitle, this.badge, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap == null ? null : () { HapticFeedback.lightImpact(); onTap!(); },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 18, color: Colors.white70)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: AppFont.style(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)), if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: AppFont.style(color: Colors.white54, fontSize: 12))]])),
            if (badge != null) ...[
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: badge == 'LIVE' ? Colors.blue.withValues(alpha: 0.18) : accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8), border: Border.all(color: badge == 'LIVE' ? Colors.blue.withValues(alpha: 0.4) : accent.withValues(alpha: 0.32))), child: Text(badge!, style: AppFont.style(color: badge == 'LIVE' ? Colors.blue[300] : accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6))),
              const SizedBox(width: 10),
            ],
            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.28), size: 20),
          ],
        ),
      ),
    );
  }
}

class _MusicSourcePill extends StatelessWidget {
  const _MusicSourcePill({required this.musicProvider, required this.isDark});
  final MusicProvider musicProvider;
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    final current = musicProvider.currentMusicSource;
    final accent = Theme.of(context).colorScheme.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        height: 56,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
        child: Stack(children: [
          AnimatedAlign(duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic, alignment: current == MusicSource.youtube ? Alignment.centerLeft : Alignment.centerRight, child: FractionallySizedBox(widthFactor: 0.5, child: Container(margin: const EdgeInsets.all(4), decoration: BoxDecoration(gradient: RadialGradient(center: Alignment.center, radius: 2.5, colors: [accent.withValues(alpha: 0.28), accent.withValues(alpha: 0.10)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: accent.withValues(alpha: 0.38)), boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 12)])))),
          Row(children: [
            Expanded(child: JellyPress(profile: JellyProfile.icon, haptic: JellyHaptic.selection, onTap: () => musicProvider.setMusicSource(MusicSource.youtube), child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cloud_queue_rounded, size: 18, color: current == MusicSource.youtube ? accent : Colors.white54), const SizedBox(width: 8), Text('Stream', style: AppFont.style(fontWeight: FontWeight.w700, fontSize: 15, color: current == MusicSource.youtube ? accent : Colors.white54))])))),
            Expanded(child: JellyPress(profile: JellyProfile.icon, haptic: JellyHaptic.selection, onTap: () => musicProvider.setMusicSource(MusicSource.local), child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.folder_open_rounded, size: 18, color: current == MusicSource.local ? accent : Colors.white54), const SizedBox(width: 8), Text('Local', style: AppFont.style(fontWeight: FontWeight.w700, fontSize: 15, color: current == MusicSource.local ? accent : Colors.white54))])))),
          ]),
        ]),
      ),
      Padding(padding: const EdgeInsets.only(left: 16, top: 10, right: 16), child: Text(current == MusicSource.youtube ? 'Streaming from YouTube Music (InnerTube).' : 'Playing files from your device storage.', style: AppFont.style(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic))),
    ]);
  }
}

class _MadeByFooter extends StatelessWidget {
  const _MadeByFooter({required this.isDark});
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Image.asset('assets/images/app_logo.png', height: 56, width: 56, errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded, color: Colors.white24, size: 40)),
      const SizedBox(height: 14),
      InkWell(
        onTap: () async { final uri = Uri.parse('https://github.com/KESPREME'); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); },
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: RichText(textAlign: TextAlign.center, text: TextSpan(style: AppFont.style(color: Colors.white54, fontSize: 13), children: [const TextSpan(text: 'Made with ❤️ using Flutter by '), TextSpan(text: 'KESPREME', style: AppFont.style(color: const Color(0xFFB388FF), fontWeight: FontWeight.w800, decoration: TextDecoration.underline))]))),
      ),
    ]);
  }
}
