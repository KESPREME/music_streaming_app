// lib/screens/software_update_screen.dart
//
// SOFTWARE UPDATE, the way a phone does it.
//
// The shape follows system updates (Settings > System > Software update): a big
// statement of where you stand at the top, the one thing you can do right now
// under it, then what is in the update, then the few settings that govern it.
//
//   * The ring around the app mark IS the progress (see update_hero.dart).
//   * The main button morphs through Check -> Download -> Cancel -> Install, so
//     there is never a second button to wonder about.
//   * The notes are the release's own: headline, grouped changes, screenshots.
//   * Nothing here can fail loudly. Offline, rate-limited or mid-download it says
//     what happened, in a sentence, and keeps whatever it already knew.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/navigation/root_navigator.dart';
import '../services/update/update_models.dart';
import '../services/update/update_service.dart';
import '../theme/amoled_theme.dart';
import '../theme/app_font.dart';
import '../utils/update_format.dart';
import '../widgets/jelly_icon_button.dart';
import '../widgets/liquid_switch.dart';
import '../widgets/settings/glass_settings_group.dart';
import '../widgets/update/release_notes_view.dart';
import '../widgets/update/update_actions.dart';
import '../widgets/update/update_copy.dart';
import '../widgets/update/update_hero.dart';

class SoftwareUpdateScreen extends StatefulWidget {
  const SoftwareUpdateScreen({super.key, this.service, this.now});

  /// The updater (the app's, from Provider, unless a test passes one).
  final UpdateService? service;

  /// The clock for "last checked" (tests).
  final DateTime Function()? now;

  static Future<void> open(BuildContext context) =>
      pushAboveShell<void>(context, const SoftwareUpdateScreen());

  @override
  State<SoftwareUpdateScreen> createState() => _SoftwareUpdateScreenState();
}

class _SoftwareUpdateScreenState extends State<SoftwareUpdateScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..forward();

  UpdateService? _service;
  UpdateService get service => _service!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service == null) {
      _service = widget.service ?? context.read<UpdateService>();
      // Opening the screen is a reason to look, but a recent look is enough.
      service.initialize().then((_) => service.check());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) service.refreshAfterResume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intro.dispose();
    super.dispose();
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
        child: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: service,
            builder: (context, _) => _body(context, accent),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Color accent) {
    final state = service.state;
    final now = (widget.now ?? DateTime.now)();
    final copy = describeUpdate(state, service.installed, now);
    final release = state.release;
    final showNotes = release != null && release.notes.isNotEmpty;

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
                  Text('Software Update',
                      style: AppFont.style(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8)),
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
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
              child: Column(
                children: [
                  UpdateHero(
                    status: state.status,
                    progress: state.progress,
                    tone: copy.tone,
                    accent: accent,
                  ),
                  const SizedBox(height: 22),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: Column(
                      key: ValueKey('${state.status}-${copy.title}'),
                      children: [
                        Text(copy.title,
                            textAlign: TextAlign.center,
                            style: AppFont.style(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 6),
                        Text(copy.subtitle,
                            textAlign: TextAlign.center,
                            style: AppFont.style(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 14.5,
                                height: 1.4)),
                        if (copy.detail != null && copy.detail!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(copy.detail!,
                              textAlign: TextAlign.center,
                              style: AppFont.style(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 13,
                                  height: 1.4)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  UpdateActionButton(
                    copy: copy,
                    progress: state.status == UpdateStatus.downloading
                        ? state.progress
                        : null,
                    onPressed: () => runUpdateAction(service, copy.action),
                  ),
                  if (release != null &&
                      (state.status == UpdateStatus.available ||
                          state.status == UpdateStatus.failed)) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () async {
                        HapticFeedback.selectionClick();
                        await service.skipThisVersion();
                        if (context.mounted) Navigator.maybePop(context);
                      },
                      child: Text('Skip this version',
                          style: AppFont.style(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showNotes) ...[
          SliverToBoxAdapter(
            child: _Reveal(
              intro: _intro,
              index: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 12),
                child: Text('WHAT\u2019S NEW', style: _sectionStyle(accent)),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _Reveal(
              intro: _intro,
              index: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ReleaseNotesView(notes: release.notes, accent: accent),
              ),
            ),
          ),
          if (release.releaseUrl.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(release.releaseUrl),
                        mode: LaunchMode.externalApplication),
                    icon: Icon(Icons.open_in_new_rounded, size: 16, color: accent),
                    label: Text('Release page on GitHub',
                        style: AppFont.style(
                            color: accent, fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
        ],
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 12),
              child: Text('SETTINGS', style: _sectionStyle(accent)),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GlassSettingsGroup(
                children: [
                  GlassSettingsRow.toggle(
                    icon: Icons.autorenew_rounded,
                    title: 'Check automatically',
                    subtitle: 'Looks for updates when you open the app, at most every six hours',
                    value: service.autoCheck,
                    onChanged: service.setAutoCheck,
                  ),
                  _ChannelRow(service: service, accent: accent),
                  GlassSettingsRow(
                    icon: Icons.info_outline_rounded,
                    title: 'Installed',
                    subtitle: service.installed.isKnown
                        ? versionLabel(service.installed.versionName, service.installed.versionCode)
                        : 'Unknown',
                    trailing: const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Reveal(
            intro: _intro,
            index: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 140),
              child: Text(
                'Updates are published on GitHub and downloaded over a secure '
                'connection. Every download is checked against its SHA-256 '
                'fingerprint before it can be installed, and Android only accepts '
                'an update signed by the same key as the app you have.',
                style: AppFont.style(
                    color: Colors.white.withValues(alpha: 0.38), fontSize: 12, height: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

TextStyle _sectionStyle(Color accent) => AppFont.style(
      color: accent.withValues(alpha: 0.9),
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.6,
    );

class _Reveal extends StatelessWidget {
  const _Reveal({required this.intro, required this.index, required this.child});

  final Animation<double> intro;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return child;
    final start = (index * 0.08).clamp(0.0, 0.7);
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

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.service, required this.accent});

  final UpdateService service;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final beta = service.channel == UpdateChannel.beta;
    return GlassSettingsRow(
      icon: Icons.science_outlined,
      title: 'Get early builds',
      subtitle: beta
          ? 'You receive beta builds before everyone else. They may be rougher'
          : 'Off. You receive tested releases only',
      trailing: LiquidSwitch(
        value: beta,
        onChanged: (v) => service.setChannel(v ? UpdateChannel.beta : UpdateChannel.stable),
      ),
      onTap: () => service.setChannel(beta ? UpdateChannel.stable : UpdateChannel.beta),
    );
  }
}

/// A button-like row used by Settings to enter this screen (kept here so the
/// banner and the row cannot drift apart).
class UpdateEntryPoint {
  const UpdateEntryPoint._();

  static String subtitle(UpdateService s, DateTime now) {
    final copy = describeUpdate(s.state, s.installed, now);
    return switch (s.status) {
      UpdateStatus.available => '${s.release?.version ?? ''} is available'.trim(),
      UpdateStatus.downloading => 'Downloading\u2026 ${(s.progress * 100).round()}%',
      UpdateStatus.ready => 'Ready to install',
      UpdateStatus.failed => copy.title,
      _ => s.installed.isKnown
          ? 'Version ${s.installed.versionName}'
          : 'Check for updates',
    };
  }
}
