import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as lg;
import 'package:provider/provider.dart';

import '../core/navigation/root_navigator.dart';
import '../design/tokens/motion.dart';
import '../design/tokens/space.dart';
import '../design/tokens/type.dart' as type;
import '../services/auth_models.dart';
import '../services/auth_service.dart';
import '../widgets/themed_settings_screen.dart';
import 'login_screen.dart';

/// The account quick-switch, opened from the header avatar.
///
/// Everything is driven from [AuthService], so the sheet holds no account state
/// of its own and cannot drift from what will actually be sent.
///
/// Three rules this file follows because the glass underneath punishes
/// violations:
///
///  * **No `Opacity` anywhere.** A translucent layer isolates the backdrop the
///    lens samples, so the glass behind it goes flat. Every reveal here is a
///    scale or a slide instead. (The package's own dialog transition is
///    scale-only for the same reason.)
///  * **No stretch overscroll.** A backdrop-filter lens inside a scrollable with
///    overscroll renders BLACK at both scroll edges on Android.
///  * **Rows are tappable, not decorative.** A modal you cannot act on is worse
///    than no modal.
class AccountSwitcherSheet extends StatefulWidget {
  const AccountSwitcherSheet({super.key});

  /// Present the sheet above the shell.
  ///
  /// `useRootNavigator` defaults to false, which would put this inside the
  /// nested detail navigator and leave the tab bar floating over it.
  static Future<void> show(BuildContext context) {
    return lg.showLiquidGlassSheet<void>(
      context: context,
      useRootNavigator: true,
      anchor: lg.LiquidGlassSheetAnchor.floating,
      // The sheet carries its own title row, so the grabber would be a second
      // title bar.
      grabber: false,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      constraints: const BoxConstraints(maxWidth: 420),
      builder: (_) => const AccountSwitcherSheet(),
    );
  }

  @override
  State<AccountSwitcherSheet> createState() => _AccountSwitcherSheetState();
}

class _AccountSwitcherSheetState extends State<AccountSwitcherSheet> {
  /// In manage mode a row tap removes that Google account instead of switching.
  bool _managing = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final accounts = auth.accounts;

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + Spacing.lg,
        bottom: MediaQuery.of(context).padding.bottom + Spacing.sm,
        left: Spacing.screenX,
        right: Spacing.screenX,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Switch account', style: type.Type.title(context)),
              ),
              if (_managing)
                TextButton(
                  onPressed: () => setState(() => _managing = false),
                  child: const Text('Done'),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),

          // A short list, deliberately not a scroll view: this is the only
          // place in the app where overscroll would meet a lens, and refusing
          // to scroll removes the question rather than mitigating it.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                for (final account in accounts) ...[
                  _GroupLabel(account),
                  for (final profile in _rowsOf(account))
                    _ProfileRow(
                      accountId: account.accountId,
                      profile: profile,
                      avatarUrl: profile.avatarUrl ??
                          (account.activeProfile?.profileId == profile.profileId
                              ? account.avatarUrl
                              : null),
                      selected: _isSelected(auth, account, profile),
                      managing: _managing,
                      onTap: () => _onRowTap(auth, account, profile),
                    ),
                ],
                const SizedBox(height: Spacing.sm),
                _ActionRow(
                  icon: Icons.add_rounded,
                  label: 'Add account',
                  onTap: () {
                    Navigator.of(context).pop();
                    LoginScreen.open(context, addAnotherAccount: true);
                  },
                ),
                _ActionRow(
                  icon: Icons.manage_accounts_rounded,
                  label: 'Manage accounts',
                  selected: _managing,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _managing = !_managing);
                  },
                ),
                _ActionRow(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onTap: () {
                    Navigator.of(context).pop();
                    // Above the shell, same reason the sheet is: this route
                    // would otherwise land inside the nested navigator and the
                    // tab bar would float over Settings.
                    pushAboveShell<void>(context, const ThemedSettingsScreen());
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<YouTubeProfile> _rowsOf(GoogleAccountSession account) {
    // A channel we can actually act as. A profile with neither token would be
    // a row that silently does nothing when tapped.
    final usable =
        account.profiles.where((p) => p.hasRealIdentity).toList();
    if (usable.isNotEmpty) return usable;

    // One channel still deserves a row - the account itself.
    final active = account.activeProfile;
    if (active != null) return [active];
    return [
      YouTubeProfile(
        profileId: 'page_${account.accountId}',
        name: account.displayName,
        handle: account.email,
        avatarUrl: account.avatarUrl,
      ),
    ];
  }

  bool _isSelected(
    AuthService auth,
    GoogleAccountSession account,
    YouTubeProfile profile,
  ) {
    if (auth.activeAccountId != account.accountId) return false;
    final active = account.activeProfile;
    if (active == null) return false;
    return active.profileId == profile.profileId;
  }

  Future<void> _onRowTap(
    AuthService auth,
    GoogleAccountSession account,
    YouTubeProfile profile,
  ) async {
    HapticFeedback.lightImpact();
    if (_managing) {
      final messenger = ScaffoldMessenger.of(context);
      final confirmed = await _confirmRemove(context, account);
      if (!confirmed) return;
      await auth.removeAccount(account.accountId);
      messenger.showSnackBar(const SnackBar(content: Text('Account removed')));
      return;
    }
    Navigator.of(context).pop();
    await auth.selectIdentity(account.accountId, profile.profileId);
  }

  Future<bool> _confirmRemove(
      BuildContext context, GoogleAccountSession account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this account?'),
        content: Text(
          'Its saved session and cached recommendations are deleted from this '
          'device. You can add ${account.displayName} again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.account);

  final GoogleAccountSession account;

  @override
  Widget build(BuildContext context) {
    // Falls back through email, name, then a generic word. A blank group header
    // reads as a rendering bug rather than as "unnamed account".
    final label = account.email.trim().isNotEmpty
        ? account.email.trim()
        : (account.name.trim().isNotEmpty
            ? account.name.trim()
            : 'Accounts');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.xs, Spacing.md, 0, Spacing.xs),
      child: Text(label, style: type.Type.caption(context)),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.accountId,
    required this.profile,
    required this.avatarUrl,
    required this.selected,
    required this.managing,
    required this.onTap,
  });

  final String accountId;
  final YouTubeProfile profile;
  final String? avatarUrl;
  final bool selected;
  final bool managing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Semantics(
        button: true,
        selected: selected,
        label: profile.name,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm, vertical: Spacing.sm),
          child: Row(
            children: [
              _Avatar(url: avatarUrl, name: profile.name),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name.trim().isEmpty
                          ? 'Channel'
                          : profile.name.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.Type.body(context).copyWith(
                        color: selected && !managing
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.Type.metadata(context)
                          .copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              // Scale rather than fade: a cross-fade needs an Opacity, which
              // would flatten the lens behind the whole row.
              _Trailing(managing: managing, selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing({required this.managing, required this.selected});

  final bool managing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (managing) {
      return Text(
        'Sign out',
        style: type.Type.body(context).copyWith(color: theme.colorScheme.error),
      );
    }

    return AnimatedScale(
      scale: selected ? 1 : 0,
      duration: Motion.normal,
      curve: Motion.springCurve,
      child: Icon(Icons.check_rounded, color: theme.colorScheme.primary, size: 22),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.md),
        child: Row(
          children: [
            Icon(icon,
                size: 22,
                color: selected ? theme.colorScheme.primary : null),
            const SizedBox(width: Spacing.md),
            Text(label, style: type.Type.body(context)),
          ],
        ),
      ),
    );
  }
}

/// Circular account picture with an honest fallback.
///
/// No placeholder image URL: a broken network image in an account row reads as
/// a loading state that will never resolve.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    final fallback = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: type.Type.body(context).copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        trimmed,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        // Same glyph as the fallback, so a 404 and an absent URL look alike
        // instead of one reading as an error and the other as intent.
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}