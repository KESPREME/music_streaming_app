// lib/widgets/update/update_copy.dart
//
// WHAT THE SOFTWARE UPDATE SCREEN SAYS, for every state the updater can be in.
//
// One pure function maps (state, installed version, now) to the words and the
// shape of the main button. The screen, the "update available" sheet and the
// Settings banner all speak through it, so they can never disagree, and every
// sentence is covered by a table test instead of being found on a phone.

import '../../services/app_platform.dart';
import '../../services/update/update_models.dart';
import '../../utils/update_format.dart';

/// What the main button does and how it looks.
enum UpdateAction {
  /// Ask GitHub.
  check,

  /// Start the download.
  download,

  /// Stop the download.
  cancel,

  /// Hand the file to the installer.
  install,

  /// Open the "install unknown apps" page.
  allow,

  /// Retry the step that failed.
  retry,

  /// Nothing to press right now (busy).
  none,
}

class UpdateCopy {
  const UpdateCopy({
    required this.title,
    required this.subtitle,
    this.detail,
    required this.action,
    required this.actionLabel,
    this.busy = false,
    this.tone = UpdateTone.neutral,
  });

  final String title;
  final String subtitle;

  /// A third, quieter line (speed and time left, last checked, the reason).
  final String? detail;
  final UpdateAction action;
  final String actionLabel;

  /// The button is a spinner / disabled.
  final bool busy;
  final UpdateTone tone;
}

enum UpdateTone { neutral, good, attention, bad }

UpdateCopy describeUpdate(UpdateState s, AppInfo installed, DateTime now) {
  final r = s.release;
  final size = formatBytes(r?.asset?.size ?? 0);
  final installedLabel = installed.isKnown
      ? 'Version ${versionLabel(installed.versionName, installed.versionCode)}'
      : 'Version unknown';

  switch (s.status) {
    case UpdateStatus.idle:
    case UpdateStatus.upToDate:
      final needsNewer = s.error != null && s.error!.startsWith('Needs Android');
      if (needsNewer) {
        return UpdateCopy(
          title: 'A newer version is out',
          subtitle: 'It ${s.error!.replaceFirst('Needs', 'needs')} or later.',
          detail: 'Mine Music will keep working as it is. $installedLabel',
          action: UpdateAction.check,
          actionLabel: 'Check again',
          tone: UpdateTone.attention,
        );
      }
      return UpdateCopy(
        title: s.status == UpdateStatus.idle && s.checkedAt == null
            ? 'Software Update'
            : 'Mine Music is up to date',
        subtitle: installedLabel,
        detail: s.checkedAt == null
            ? 'Not checked yet'
            : 'Last checked ${formatAgo(s.checkedAt, now)}',
        action: UpdateAction.check,
        actionLabel: 'Check for updates',
        tone: s.status == UpdateStatus.upToDate ? UpdateTone.good : UpdateTone.neutral,
      );

    case UpdateStatus.checking:
      return UpdateCopy(
        title: 'Checking for updates\u2026',
        subtitle: installedLabel,
        action: UpdateAction.none,
        actionLabel: 'Checking',
        busy: true,
      );

    case UpdateStatus.available:
      return UpdateCopy(
        title: r == null ? 'Update available' : 'Mine Music ${r.version}',
        subtitle: _releaseLine(r),
        detail: s.error ?? r?.notes.summary,
        action: UpdateAction.download,
        actionLabel: size.isEmpty ? 'Download' : 'Download \u00b7 $size',
        tone: UpdateTone.attention,
      );

    case UpdateStatus.downloading:
      final pct = (s.progress * 100).clamp(0, 100).round();
      final got = formatBytes(s.receivedBytes);
      final total = formatBytes(s.totalBytes);
      final speed = formatSpeed(s.bytesPerSecond);
      final eta = formatEta(s.etaSeconds);
      return UpdateCopy(
        title: r == null ? 'Downloading\u2026' : 'Downloading ${r.version}',
        subtitle: total.isEmpty
            ? (got.isEmpty ? 'Starting\u2026' : got)
            : '$pct% \u00b7 ${got.isEmpty ? '0 B' : got} of $total',
        detail: [speed, eta].where((e) => e.isNotEmpty).join(' \u00b7 '),
        action: UpdateAction.cancel,
        actionLabel: 'Cancel',
        tone: UpdateTone.attention,
      );

    case UpdateStatus.verifying:
      return const UpdateCopy(
        title: 'Verifying\u2026',
        subtitle: 'Checking the file is exactly what was published',
        action: UpdateAction.none,
        actionLabel: 'Verifying',
        busy: true,
        tone: UpdateTone.attention,
      );

    case UpdateStatus.ready:
      return UpdateCopy(
        title: 'Ready to install',
        subtitle: r == null
            ? 'The update is downloaded and verified'
            : 'Mine Music ${r.version} is downloaded and verified',
        detail: s.error,
        action: UpdateAction.install,
        actionLabel: 'Install',
        tone: UpdateTone.good,
      );

    case UpdateStatus.installing:
      return const UpdateCopy(
        title: 'Installing\u2026',
        subtitle: 'Confirm in the system installer. Mine Music reopens when it finishes',
        action: UpdateAction.none,
        actionLabel: 'Installing',
        busy: true,
        tone: UpdateTone.good,
      );

    case UpdateStatus.needsPermission:
      return const UpdateCopy(
        title: 'One more step',
        subtitle: 'Allow Mine Music to install updates, then come back and tap Install',
        action: UpdateAction.allow,
        actionLabel: 'Open settings',
        tone: UpdateTone.attention,
      );

    case UpdateStatus.failed:
      final during = s.failedDuring;
      final (title, label) = switch (during) {
        UpdateStatus.checking => ('Couldn\u2019t check for updates', 'Try again'),
        UpdateStatus.downloading => ('The download stopped', 'Resume download'),
        UpdateStatus.verifying => ('The download was damaged', 'Download again'),
        UpdateStatus.installing => ('Couldn\u2019t start the installer', 'Try again'),
        _ => ('Something went wrong', 'Try again'),
      };
      return UpdateCopy(
        title: title,
        subtitle: s.error ?? 'Please try again in a moment.',
        detail: installedLabel,
        action: during == UpdateStatus.checking ? UpdateAction.check : UpdateAction.retry,
        actionLabel: label,
        tone: UpdateTone.bad,
      );
  }
}

String _releaseLine(ReleaseInfo? r) {
  if (r == null) return '';
  final parts = <String>[
    'Build ${r.build}',
    if ((r.asset?.size ?? 0) > 0) formatBytes(r.asset!.size),
    if (r.publishedAt != null) formatDate(r.publishedAt),
  ];
  return parts.join(' \u00b7 ');
}
