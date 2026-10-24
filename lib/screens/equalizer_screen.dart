// lib/screens/equalizer_screen.dart
//
// THE EQUALIZER SCREEN.
//
// What a careful listener expects from a serious player, in the order they reach
// for it:
//
//   1. a switch, and proof that it is doing something (the live curve);
//   2. a way to hear the difference (hold to compare);
//   3. good starting points (a carousel of preset SHAPES), and a place to keep
//      their own;
//   4. the controls the pros use: pre-amp, headroom so boosts do not clip,
//      loudness, bass, spatial width;
//   5. separate settings for speaker, wired and Bluetooth;
//   6. honesty about the hardware: the real bands and range, and a plain
//      explanation (never a dead switch) when the phone has no equalizer.
//
// Touching anything while it is off switches it on - the instrument answers to
// being played.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/navigation/root_navigator.dart';
import '../services/eq/eq_curves.dart';
import '../services/eq/eq_models.dart';
import '../services/eq/eq_presets.dart';
import '../services/equalizer_service.dart';
import '../theme/amoled_theme.dart';
import '../theme/app_font.dart';
import '../widgets/eq/eq_graph.dart';
import '../widgets/eq/eq_preset_strip.dart';
import '../widgets/jelly_icon_button.dart';
import '../widgets/jelly_press.dart';
import '../widgets/liquid_switch.dart';
import '../widgets/settings/glass_settings_group.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key, this.service});

  /// The engine to drive (the app's singleton unless a test passes its own).
  final EqualizerService? service;

  static Future<void> open(BuildContext context) =>
      pushAboveShell<void>(context, const EqualizerScreen());

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen>
    with SingleTickerProviderStateMixin {
  late final EqualizerService _eq = widget.service ?? EqualizerService();
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _eq.setBypass(false);
    _intro.dispose();
    super.dispose();
  }

  /// Any edit while off switches the equalizer on.
  void _ensureOn() {
    if (_eq.isPlatformAvailable && !_eq.profile.enabled) {
      _eq.setEnabled(true);
    }
  }

  Future<void> _savePreset() async {
    final name = await _askName(context, title: 'Save preset', initial: '');
    if (name == null || !mounted) return;
    HapticFeedback.mediumImpact();
    final saved = _eq.saveUserPreset(name);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Saved \u201c${saved.name}\u201d'),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _userPresetMenu(UserEqPreset preset) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AmoledTheme.surfaceOf(context, const Color(0xFF161616)),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(preset.name,
                    style: AppFont.style(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Colors.white70),
              title: Text('Rename', style: AppFont.style(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B6B)),
              title: Text('Delete',
                  style: AppFont.style(color: const Color(0xFFFF6B6B))),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'delete') {
      _eq.deleteUserPreset(preset.id);
    } else if (action == 'rename') {
      final name = await _askName(context, title: 'Rename preset', initial: preset.name);
      if (name != null) _eq.renameUserPreset(preset.id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AmoledTheme.gradient(context, const [
              Color(0xFF121214),
              Color(0xFF0A0A0B),
              Color(0xFF000000),
            ]),
          ),
        ),
        child: Stack(
          children: [
            // A bloom of the accent behind the graph: the instrument glows in the
            // colour of what is playing.
            Positioned(
              top: -120,
              left: -80,
              right: -80,
              height: 460,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: ListenableBuilder(
                listenable: _eq,
                builder: (context, _) => _content(context, accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, Color accent) {
    final eq = _eq;
    final caps = eq.capabilities;
    final p = eq.profile;
    final available = eq.isPlatformAvailable;
    final on = eq.isEnabled;
    final bands = eq.bands;
    final range = (min: available ? caps.minDb : -12.0, max: available ? caps.maxDb : 12.0);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 20, 0),
              child: Row(
                children: [
                  JellyIconButton(
                    onPressed: () => Navigator.maybePop(context),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Equalizer',
                            style: AppFont.style(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8)),
                        const SizedBox(height: 2),
                        Text(
                          available ? caps.summary : 'Not available on this phone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.style(
                              color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    label: 'Equalizer',
                    toggled: on,
                    child: LiquidSwitch(
                      value: on,
                      enabled: available,
                      onChanged: (v) {
                        HapticFeedback.lightImpact();
                        eq.setEnabled(v);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _GraphCard(
                eq: eq,
                accent: accent,
                available: available,
                on: on,
                range: range,
                bands: bands,
                onEdit: _ensureOn,
                onSave: _savePreset,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('PRESETS', style: _sectionStyle(accent)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _blurb(eq),
                        key: ValueKey(eq.currentPresetId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppFont.style(
                            color: Colors.white.withValues(alpha: 0.45), fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 3,
            child: IgnorePointer(
              ignoring: !available,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 240),
                opacity: available ? 1 : 0.4,
                child: EqPresetStrip(
                  bands: bands,
                  minDb: range.min,
                  maxDb: range.max,
                  selectedId: p.presetId,
                  currentGains: p.gains,
                  userPresets: eq.userPresets,
                  enabled: on,
                  accent: accent,
                  onSelect: (id) {
                    _ensureOn();
                    eq.selectPreset(id);
                  },
                  onUserLongPress: _userPresetMenu,
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 12),
              child: Text('SOUND SHAPING', style: _sectionStyle(accent)),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: IgnorePointer(
                ignoring: !available,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 240),
                  opacity: available ? 1 : 0.4,
                  child: _ShapingGroup(eq: eq, accent: accent, onEdit: _ensureOn),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 12),
              child: Text('OUTPUT', style: _sectionStyle(accent)),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 7,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _OutputGroup(eq: eq, accent: accent, enabled: available),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 140),
              child: Text(
                available
                    ? 'The equalizer runs in your phone\u2019s audio system, so it '
                        'works on everything you play. Some phones limit bass '
                        'boost or spatial widening; those controls say so. While '
                        'it is on, the phone cannot use its low-power audio path, '
                        'so battery use is slightly higher.'
                    : 'Your phone\u2019s audio system does not offer an equalizer '
                        'to apps (some manufacturers restrict it). Playback is '
                        'unaffected; this screen will light up on a phone that '
                        'supports it.',
                style: AppFont.style(
                    color: Colors.white.withValues(alpha: 0.38), fontSize: 12, height: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _blurb(EqualizerService eq) {
    final id = eq.currentPresetId;
    if (id == 'custom') return 'Your own curve';
    if (id.startsWith('user:')) return 'Saved by you';
    return presetById(id)?.blurb ?? '';
  }
}

TextStyle _sectionStyle(Color accent) => AppFont.style(
      color: accent.withValues(alpha: 0.9),
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.6,
    );

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
    final start = (index * 0.07).clamp(0.0, 0.7);
    final anim = CurvedAnimation(
      parent: intro,
      curve: Interval(start, (start + 0.35).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, 22 * (1 - anim.value)), child: child),
      ),
      child: child,
    );
  }
}

// ── The graph and its toolbar ───────────────────────────────────────────────

class _GraphCard extends StatelessWidget {
  const _GraphCard({
    required this.eq,
    required this.accent,
    required this.available,
    required this.on,
    required this.range,
    required this.bands,
    required this.onEdit,
    required this.onSave,
  });

  final EqualizerService eq;
  final Color accent;
  final bool available;
  final bool on;
  final ({double min, double max}) range;
  final List<EqBand> bands;
  final VoidCallback onEdit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final p = eq.profile;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withValues(alpha: 0.045),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 12),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              EqGraph(
                bands: bands,
                gains: p.gains,
                minDb: range.min,
                maxDb: range.max,
                enabled: available && on,
                interactive: available,
                bypass: eq.bypass,
                accent: accent,
                onChanged: (g) {
                  onEdit();
                  eq.setGains(g);
                },
              ),
              if (!available)
                const Positioned.fill(child: _UnavailableVeil())
              else if (!on)
                Positioned(
                  bottom: 40,
                  child: _Pill(
                    icon: Icons.touch_app_rounded,
                    label: 'Touch the curve to switch on',
                    accent: accent,
                  ),
                ),
              if (available && on && !eq.engineHealthy)
                const Positioned(
                  top: 0,
                  child: _Pill(
                    icon: Icons.warning_amber_rounded,
                    label: 'Couldn\u2019t reach the audio effect',
                    accent: Color(0xFFFFB74D),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Row(
              children: [
                Expanded(child: _CompareButton(eq: eq, accent: accent, enabled: available && on)),
                const SizedBox(width: 8),
                _ToolButton(
                  icon: Icons.restart_alt_rounded,
                  label: 'Reset',
                  enabled: available && !p.isNeutral,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    eq.reset();
                  },
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  icon: Icons.bookmark_add_outlined,
                  label: 'Save',
                  enabled: available && !p.gains.every((g) => g == 0),
                  onTap: onSave,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableVeil extends StatelessWidget {
  const _UnavailableVeil();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.black.withValues(alpha: 0.55),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.speaker_group_outlined,
                  size: 34, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(height: 10),
              Text('No equalizer on this phone',
                  textAlign: TextAlign.center,
                  style: AppFont.style(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Your phone\u2019s audio system doesn\u2019t offer one to apps.',
                  textAlign: TextAlign.center,
                  style: AppFont.style(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.accent});

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(label,
              style: AppFont.style(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Hold to hear the original. The effects stay attached; only the curve is
/// taken out, so letting go is instant and click-free.
class _CompareButton extends StatelessWidget {
  const _CompareButton({required this.eq, required this.accent, required this.enabled});

  final EqualizerService eq;
  final Color accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final held = eq.bypass;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Hold to compare with the original sound',
      onTap: enabled
          ? () async {
              eq.setBypass(true);
              await Future<void>.delayed(const Duration(milliseconds: 1600));
              eq.setBypass(false);
            }
          : null,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: enabled
            ? (_) {
                HapticFeedback.lightImpact();
                eq.setBypass(true);
              }
            : null,
        onPointerUp: (_) => eq.setBypass(false),
        onPointerCancel: (_) => eq.setBypass(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: held ? accent.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.07),
            border: Border.all(
              color: held ? accent : Colors.white.withValues(alpha: 0.1),
              width: held ? 1.5 : 1,
            ),
            boxShadow: held
                ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 16)]
                : const [],
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          // Shares the row with Reset + Save. FittedBox + ConstrainedBox keeps
          // the longer "Hearing…" from spilling into its neighbour on 320dp.
          child: LayoutBuilder(
            builder: (context, c) => ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hearing_rounded,
                      size: 18,
                      color: enabled ? Colors.white : Colors.white30),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        held ? 'Hearing the original' : 'Hold to compare',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                          color: enabled ? Colors.white : Colors.white30,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: JellyPress(
        enabled: enabled,
        onTap: onTap,
        haptic: JellyHaptic.none,
        borderRadius: 22,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withValues(alpha: enabled ? 0.07 : 0.03),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: enabled ? Colors.white : Colors.white24),
              const SizedBox(width: 6),
              Text(label,
                  style: AppFont.style(
                      color: enabled ? Colors.white : Colors.white24,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sound shaping ───────────────────────────────────────────────────────────

class _ShapingGroup extends StatelessWidget {
  const _ShapingGroup({required this.eq, required this.accent, required this.onEdit});

  final EqualizerService eq;
  final Color accent;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = eq.profile;
    final caps = eq.capabilities;
    final headroom = eq.headroomDb;
    return GlassSettingsGroup(
      children: [
        _SliderRow(
          icon: Icons.tune_rounded,
          title: 'Pre-amp',
          valueLabel: formatDb(p.preampDb),
          subtitle: 'Overall level before the bands. Cut it if a boost sounds harsh',
          value: p.preampDb,
          min: -EqProfile.maxPreamp,
          max: EqProfile.maxPreamp,
          divisions: (EqProfile.maxPreamp * 4).round(),
          accent: accent,
          detent: 0,
          onChanged: (v) {
            onEdit();
            eq.setPreamp(v);
          },
        ),
        GlassSettingsRow.toggle(
          icon: Icons.shield_outlined,
          title: 'Prevent clipping',
          subtitle: p.autoHeadroom
              ? (headroom > 0
                  ? 'Lowering everything by ${headroom.toStringAsFixed(headroom == headroom.roundToDouble() ? 0 : 1)} dB so boosts can\u2019t distort'
                  : 'On. Nothing needs lowering right now')
              : 'Off. Large boosts can distort',
          value: p.autoHeadroom,
          onChanged: (v) {
            onEdit();
            eq.setAutoHeadroom(v);
          },
        ),
        _SliderRow(
          icon: Icons.volume_up_rounded,
          title: 'Loudness boost',
          valueLabel: p.loudnessDb == 0 ? 'Off' : '+${p.loudnessDb.toStringAsFixed(p.loudnessDb == p.loudnessDb.roundToDouble() ? 0 : 1)} dB',
          subtitle: 'Brings quiet music up with a soft limiter',
          value: p.loudnessDb,
          min: 0,
          max: EqProfile.maxLoudness,
          divisions: (EqProfile.maxLoudness * 2).round(),
          accent: accent,
          supported: caps.loudness,
          onChanged: (v) {
            onEdit();
            eq.setLoudness(v);
          },
        ),
        _SliderRow(
          icon: Icons.graphic_eq_rounded,
          title: 'Bass boost',
          valueLabel: p.bassBoost == 0 ? 'Off' : '${(p.bassBoost * 100).round()}%',
          subtitle: 'Extra low end from the phone\u2019s own bass engine',
          value: p.bassBoost,
          min: 0,
          max: 1,
          divisions: 20,
          accent: accent,
          supported: caps.bassBoost,
          onChanged: (v) {
            onEdit();
            eq.setBassBoost(v);
          },
        ),
        _SliderRow(
          icon: Icons.surround_sound_rounded,
          title: 'Spatial widening',
          valueLabel: p.virtualizer == 0 ? 'Off' : '${(p.virtualizer * 100).round()}%',
          subtitle: 'Opens up the stereo image. Best on headphones',
          value: p.virtualizer,
          min: 0,
          max: 1,
          divisions: 20,
          accent: accent,
          supported: caps.virtualizer,
          onChanged: (v) {
            onEdit();
            eq.setVirtualizer(v);
          },
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.accent,
    required this.onChanged,
    this.supported = true,
    this.detent,
  });

  final IconData icon;
  final String title;
  final String valueLabel;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color accent;
  final bool supported;
  final double? detent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final dim = !supported;
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
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
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(title,
                      style: AppFont.style(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Text(
                  dim ? 'Not supported' : valueLabel,
                  style: AppFont.style(
                      color: dim ? Colors.white54 : accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 13),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 2),
              child: Text(subtitle,
                  style: AppFont.style(color: Colors.white54, fontSize: 12)),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                thumbColor: Colors.white,
                overlayColor: accent.withValues(alpha: 0.16),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                tickMarkShape: SliderTickMarkShape.noTickMark,
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                label: valueLabel,
                semanticFormatterCallback: (_) => '$title $valueLabel',
                onChanged: dim
                    ? null
                    : (v) {
                        if (detent != null &&
                            (v - detent!).abs() < (max - min) / divisions / 2 &&
                            (value - detent!).abs() >= (max - min) / divisions / 2) {
                          HapticFeedback.selectionClick();
                        }
                        onChanged(v);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Output ──────────────────────────────────────────────────────────────────

class _OutputGroup extends StatelessWidget {
  const _OutputGroup({required this.eq, required this.accent, required this.enabled});

  final EqualizerService eq;
  final Color accent;
  final bool enabled;

  static IconData _icon(String key) => switch (key) {
        'bluetooth' => Icons.bluetooth_audio_rounded,
        'wired' => Icons.headphones_rounded,
        _ => Icons.speaker_phone_rounded,
      };

  static String _label(String key) => switch (key) {
        'bluetooth' => 'Bluetooth',
        'wired' => 'Wired',
        _ => 'Speaker',
      };

  @override
  Widget build(BuildContext context) {
    final key = eq.outputKey;
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GlassSettingsGroup(
          children: [
            GlassSettingsRow(
              icon: _icon(key),
              title: 'Playing through',
              subtitle: eq.outputName,
              trailing: const SizedBox.shrink(),
            ),
            GlassSettingsRow.toggle(
              icon: Icons.splitscreen_rounded,
              title: 'Separate settings per output',
              subtitle: eq.perOutput
                  ? 'Speaker, wired and Bluetooth each keep their own curve'
                  : 'One curve for every output',
              value: eq.perOutput,
              onChanged: (v) => eq.setPerOutput(v),
            ),
            if (eq.perOutput)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Row(
                  children: [
                    for (final k in const ['speaker', 'wired', 'bluetooth']) ...[
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: k == key
                                ? accent.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.04),
                            border: Border.all(
                              color: k == key
                                  ? accent.withValues(alpha: 0.7)
                                  : Colors.white.withValues(alpha: 0.07),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(_icon(k),
                                  size: 20,
                                  color: k == key ? accent : Colors.white54),
                              const SizedBox(height: 4),
                              Text(_label(k),
                                  style: AppFont.style(
                                      color: k == key ? Colors.white : Colors.white54,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                      if (k != 'bluetooth') const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Name dialog ─────────────────────────────────────────────────────────────

Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AmoledTheme.surfaceOf(context, const Color(0xFF1A1A1C)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      title: Text(title,
          style: AppFont.style(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.sentences,
        style: AppFont.style(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Name',
          hintStyle: AppFont.style(color: Colors.white38),
          counterStyle: AppFont.style(color: Colors.white38),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
