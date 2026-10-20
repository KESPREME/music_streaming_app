// lib/widgets/update/update_sheets.dart
//
// The two moments an update speaks up on its own:
//
//   * "Update available"  - once per version, a calm bottom sheet with the
//     picture, the headline, three highlights and the same morphing button as
//     the full screen. Download from here and the sheet becomes the progress.
//   * "What's new"        - the first launch after an update: the notes of the
//     version you are now running, like the screen after a phone's OTA.
//
// Neither is modal in spirit: both dismiss with a swipe, and "Later" costs
// nothing. Skipping a version is one tap and remembered.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/software_update_screen.dart';
import '../../services/update/update_models.dart';
import '../../services/update/update_service.dart';
import '../../theme/amoled_theme.dart';
import '../../theme/app_font.dart';
import '../../utils/update_format.dart';
import 'release_notes_view.dart';
import 'update_actions.dart';
import 'update_copy.dart';
import 'update_hero.dart';

Future<void> showUpdatePromptSheet(BuildContext context, UpdateService service) async {
  await service.markPrompted();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _SheetFrame(child: _PromptBody(service: service)),
  );
}

Future<void> showWhatsNewSheet(BuildContext context, UpdateService service) async {
  // The notes may not be on the phone yet; the sheet opens at once and fills in.
  service.loadWhatsNewNotes();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _SheetFrame(child: _WhatsNewBody(service: service)),
  );
  await service.dismissWhatsNew();
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: h * 0.9),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AmoledTheme.surfaceOf(context, const Color(0xFF111113)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
        child: SafeArea(
          top: false,
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
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptBody extends StatelessWidget {
  const _PromptBody({required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final state = service.state;
        final copy = describeUpdate(state, service.installed, DateTime.now());
        final r = state.release;
        final notes = r?.notes ?? ReleaseNotes.empty;
        final lines = notes.highlights.isNotEmpty
            ? notes.highlights
            : [for (final s in notes.sections) ...s.items].take(3).toList();
        final size = formatBytes(r?.asset?.size ?? 0);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notes.bannerUrl != null)
                ReleaseNotesView(
                  notes: ReleaseNotes(bannerUrl: notes.bannerUrl),
                  accent: accent,
                )
              else
                Center(
                  child: UpdateHero(
                    status: state.status,
                    progress: state.progress,
                    tone: copy.tone,
                    size: 112,
                    accent: accent,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                state.status == UpdateStatus.available || r == null
                    ? 'Update available'
                    : copy.title,
                style: AppFont.style(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 4),
              Text(
                r == null
                    ? copy.subtitle
                    : [
                        'Mine Music ${r.version}',
                        if (size.isNotEmpty) size,
                      ].join(' \u00b7 '),
                style: AppFont.style(
                    color: Colors.white.withValues(alpha: 0.6), fontSize: 14.5),
              ),
              if (state.status == UpdateStatus.downloading ||
                  state.status == UpdateStatus.verifying ||
                  state.status == UpdateStatus.failed) ...[
                const SizedBox(height: 4),
                Text(
                  [copy.subtitle, copy.detail ?? '']
                      .where((e) => e.isNotEmpty)
                      .join(' \u00b7 '),
                  style: AppFont.style(
                      color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
                ),
              ],
              if (lines.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8, right: 10),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration:
                                BoxDecoration(color: accent, shape: BoxShape.circle),
                          ),
                        ),
                        Expanded(
                          child: Text(line,
                              style: AppFont.style(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 14.5,
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 18),
              UpdateActionButton(
                copy: copy,
                progress: state.status == UpdateStatus.downloading ? state.progress : null,
                onPressed: () => runUpdateAction(service, copy.action),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop();
                    },
                    child: Text('Later', style: _quiet),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      SoftwareUpdateScreen.open(context);
                    },
                    child: Text('Details', style: _quiet),
                  ),
                  TextButton(
                    onPressed: () async {
                      await service.skipThisVersion();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Text('Skip this version', style: _quiet),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

final TextStyle _quiet = AppFont.style(
  color: Colors.white.withValues(alpha: 0.55),
  fontSize: 13.5,
  fontWeight: FontWeight.w600,
);

class _WhatsNewBody extends StatelessWidget {
  const _WhatsNewBody({required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final r = service.whatsNew;
        final notes = r?.notes ?? ReleaseNotes.empty;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF63D68D).withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Color(0xFF63D68D), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mine Music was updated',
                            style: AppFont.style(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3)),
                        Text(
                          r == null ? '' : 'Now on version ${versionLabel(r.version, r.build)}',
                          style: AppFont.style(
                              color: Colors.white.withValues(alpha: 0.55), fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (notes.isEmpty)
                Text(
                  'Fixes and polish. The full notes are on the release page.',
                  style: AppFont.style(color: Colors.white.withValues(alpha: 0.7), fontSize: 14.5),
                )
              else
                ReleaseNotesView(notes: notes, accent: accent),
              const SizedBox(height: 22),
              UpdateActionButton(
                copy: const UpdateCopy(
                  title: '',
                  subtitle: '',
                  action: UpdateAction.install,
                  actionLabel: 'Continue',
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
}
