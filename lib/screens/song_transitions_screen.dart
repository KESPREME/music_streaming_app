import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import '../services/transition/transition_settings.dart';
import '../widgets/settings/glass_settings_group.dart';
import '../widgets/thin_slider.dart';
import '../widgets/transition_diagram.dart';
import '../widgets/transition_glyph.dart';

/// Song Transitions: how one song joins the next.
///
/// Modelled on Apple Music (Settings > Music > Song Transitions: a switch, a
/// Transition Style of Crossfade or AutoMix, a 1-12 second slider) with the
/// options BitChord adds. The picture at the top is live: it redraws as the
/// slider moves, over the same gain curves the player uses.
class SongTransitionsScreen extends StatelessWidget {
  const SongTransitionsScreen({super.key, this.settings});

  /// Overrides the app's settings (tests).
  final TransitionSettings? settings;

  /// A one-line summary for a settings row.
  static String summary(TransitionSettings s) {
    if (!s.enabled) return 'Off';
    return s.style == TransitionStyle.automix
        ? 'AutoMix'
        : 'Crossfade · ${s.crossfadeSeconds} s';
  }

  @override
  Widget build(BuildContext context) {
    final s = settings ?? context.read<MusicProvider>().transitionSettings;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF121212), Color(0xFF1E1E1E), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: s,
            builder: (context, _) => _Body(settings: s),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.settings});

  final TransitionSettings settings;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final s = settings;
    final automix = s.style == TransitionStyle.automix;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 20, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white70, size: 20),
                ),
                Expanded(
                  child: Text(
                    'Song Transitions',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // The live picture.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
            child: TransitionDiagram(
              seconds: s.crossfadeSeconds,
              style: s.style,
              enabled: s.enabled,
            ),
          ),
        ),

        // Master switch.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GlassSettingsGroup(
              children: [
                GlassSettingsRow.toggle(
                  icon: Icons.blur_linear_rounded,
                  title: 'Song Transitions',
                  subtitle: s.enabled
                      ? 'Songs blend into each other'
                      : 'Songs play one after another',
                  value: s.enabled,
                  onChanged: s.setEnabled,
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),

        // Everything below is visible but asleep while transitions are off, so
        // the screen shows what turning them on gives.
        SliverToBoxAdapter(
          child: _Dimmed(
            dimmed: !s.enabled,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('TRANSITION STYLE'),
                  const SizedBox(height: 10),
                  _StyleChooser(
                    style: s.style,
                    accent: accent,
                    onChanged: s.setStyle,
                  ),
                  const SizedBox(height: 18),
                  _LengthCard(settings: s, automix: automix),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: automix
                        ? Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _SectionLabel('AUTOMIX'),
                                const SizedBox(height: 10),
                                GlassSettingsGroup(
                                  children: [
                                    GlassSettingsRow.toggle(
                                      icon: Icons.speed_rounded,
                                      title: 'Match tempo',
                                      badge: 'BETA',
                                      subtitle:
                                          'Speed the next song up or down by a few percent so its beat lines up with the one leaving. Only when both songs have a clear beat.',
                                      value: s.matchTempo,
                                      onChanged: s.setMatchTempo,
                                    ),
                                    GlassSettingsRow.toggle(
                                      icon: Icons.signal_cellular_alt_rounded,
                                      title: 'Analyse on mobile data',
                                      subtitle:
                                          'AutoMix reads each upcoming song once to plan the join. Off keeps that to Wi-Fi.',
                                      value: s.analyzeOnCellular,
                                      onChanged: s.setAnalyzeOnCellular,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('PLAYBACK'),
                  const SizedBox(height: 10),
                  GlassSettingsGroup(
                    children: [
                      GlassSettingsRow.toggle(
                        icon: Icons.album_rounded,
                        title: 'Transition between album tracks',
                        subtitle:
                            'Off keeps albums gapless, the way they were made.',
                        value: s.crossfadeAlbums,
                        onChanged: s.setCrossfadeAlbums,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // These do not depend on transitions being on.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('ALSO'),
                const SizedBox(height: 10),
                GlassSettingsGroup(
                  children: [
                    GlassSettingsRow.toggle(
                      icon: Icons.bedtime_rounded,
                      title: 'Fade out for the sleep timer',
                      subtitle:
                          'Let the music fade away instead of cutting off.',
                      value: s.sleepFade,
                      onChanged: s.setSleepFade,
                    ),
                    GlassSettingsRow.toggle(
                      icon: Icons.content_cut_rounded,
                      title: 'Skip silence',
                      subtitle: 'Jump over silent passages inside a song.',
                      value: s.skipSilence,
                      onChanged: s.setSkipSilence,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 48),
            child: Text(
              'Transitions happen when a song runs out. Tapping next or '
              'previous, seeking, or starting a new song never blends.',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white38, fontSize: 12, height: 1.45),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
      );
}

/// Fades and locks its child while [dimmed].
class _Dimmed extends StatelessWidget {
  const _Dimmed({required this.dimmed, required this.child});
  final bool dimmed;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: dimmed ? 0.38 : 1.0,
        child: IgnorePointer(ignoring: dimmed, child: child),
      );
}

/// Crossfade | AutoMix as two cards that explain themselves.
class _StyleChooser extends StatelessWidget {
  const _StyleChooser({
    required this.style,
    required this.accent,
    required this.onChanged,
  });

  final TransitionStyle style;
  final Color accent;
  final ValueChanged<TransitionStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    // Equal-height cards: stretch needs a bounded height, which a scrolling
    // column does not have, so the row measures its tallest card first.
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _StyleCard(
            selected: style == TransitionStyle.crossfade,
            accent: accent,
            icon: const Icon(Icons.blur_linear_rounded),
            title: 'Crossfade',
            blurb: 'One song fades out as the next fades in, over a length you choose.',
            onTap: () => onChanged(TransitionStyle.crossfade),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StyleCard(
            selected: style == TransitionStyle.automix,
            accent: accent,
            glyph: true,
            title: 'AutoMix',
            blurb:
                "Each pair of songs is analysed. The fade is placed over the song's own ending, silence is skipped, and joins land on the beat when they can.",
            onTap: () => onChanged(TransitionStyle.automix),
          ),
        ),
      ],
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.selected,
    required this.accent,
    required this.title,
    required this.blurb,
    required this.onTap,
    this.icon,
    this.glyph = false,
  });

  final bool selected;
  final Color accent;
  final String title;
  final String blurb;
  final VoidCallback onTap;
  final Widget? icon;
  final bool glyph;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? accent : Colors.white70;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $blurb',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: selected
                ? RadialGradient(
                    center: Alignment.topLeft,
                    radius: 1.6,
                    colors: [
                      accent.withValues(alpha: 0.26),
                      accent.withValues(alpha: 0.07),
                    ],
                  )
                : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.07),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: accent.withValues(alpha: 0.16), blurRadius: 16)]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTheme(
                    data: IconThemeData(color: fg, size: 22),
                    child: glyph
                        ? TransitionGlyph(size: 22, color: fg)
                        : icon!,
                  ),
                  const Spacer(),
                  AnimatedScale(
                    scale: selected ? 1 : 0.6,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(Icons.check_circle_rounded,
                          size: 18, color: accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                blurb,
                style: GoogleFonts.plusJakartaSans(
                    color: Colors.white54, fontSize: 12, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 1-12 second slider with a live value.
class _LengthCard extends StatefulWidget {
  const _LengthCard({required this.settings, required this.automix});

  final TransitionSettings settings;
  final bool automix;

  @override
  State<_LengthCard> createState() => _LengthCardState();
}

class _LengthCardState extends State<_LengthCard> {
  double? _drag;

  int _secondsOf(double v) =>
      (TransitionSettings.minSeconds +
              v * (TransitionSettings.maxSeconds - TransitionSettings.minSeconds))
          .round();

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    const span = TransitionSettings.maxSeconds - TransitionSettings.minSeconds;
    final shown = _drag == null ? s.crossfadeSeconds : _secondsOf(_drag!);
    final value = (s.crossfadeSeconds - TransitionSettings.minSeconds) / span;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.automix ? 'Fallback length' : 'Crossfade length',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.automix
                          ? "Used when a song just stops, or hasn't been analysed yet"
                          : 'How long the two songs overlap',
                      style: GoogleFonts.plusJakartaSans(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Text(
                  '$shown s',
                  key: ValueKey<int>(shown),
                  style: GoogleFonts.plusJakartaSans(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ThinSlider(
            value: _drag ?? value,
            semanticLabel: 'Crossfade length, $shown seconds',
            idleHeight: 8,
            activeHeight: 12,
            activeColor: Theme.of(context).colorScheme.primary,
            inactiveColor: Colors.white.withValues(alpha: 0.18),
            onValueChangeStart: () => setState(() => _drag = value),
            onValueChange: (v) {
              final before = _secondsOf(_drag ?? value);
              final after = _secondsOf(v);
              setState(() => _drag = v);
              if (after != before) {
                HapticFeedback.selectionClick();
                s.setCrossfadeSeconds(after);
              }
            },
            onValueChangeFinished: () => setState(() => _drag = null),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in const ['1 s', '12 s'])
                  Text(
                    t,
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
