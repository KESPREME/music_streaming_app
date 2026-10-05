import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/navigation/root_navigator.dart';
import '../design/glass/glass_materials.dart' show GlassTier;
import '../design/glass/glass_surface.dart' as design;
import '../design/tokens/motion.dart';
import '../design/tokens/space.dart';
import '../design/tokens/type.dart' as type;
import '../services/auth_models.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

/// Account and channel management.
///
/// Everything here is driven by [AuthService] state, so the screen holds no
/// account state of its own and cannot drift from what will actually be sent.
///
/// Design notes:
///  * Selection is expressed with an animated check + a subtle scale on the
///    active row rather than a colour swap, so it survives the user's colour
///    scheme and reads at a glance.
///  * Rows animate in with a staggered slide-fade on [Motion.settle], and the
///    whole list cross-fades on identity change. The stagger is capped: an
///    account list is short, and an uncapped stagger reads as lag.
///  * Removal is destructive, so it confirms and explains what it costs -
///    signing out of an account removes its cookies and its saved feed.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  /// Pushed above the shell so the tab bar and mini-player do not float over the
  /// account list.
  static Future<void> open(BuildContext context) {
    return pushAboveShell<void>(context, const AccountScreen());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final accounts = auth.accounts;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: AnimatedSwitcher(
        duration: Motion.normal,
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        // Keyed on identity so the list cross-fades when the signed-in account
        // changes, instead of rows silently re-labelling under the user.
        child: accounts.isEmpty
            ? _SignedOut(onSignIn: () => _signIn(context))
            : _SignedIn(
                key: ValueKey(auth.identityKey),
                auth: auth,
                accounts: accounts,
                onSignIn: () => _signIn(context, addAnother: true),
              ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context, {bool addAnother = false}) async {
    // The screen is popped by the login route on success; nothing to do here
    // because AuthService notifies and the watch above rebuilds.
    await LoginScreen.open(context, addAnotherAccount: addAnother);
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
              child: Icon(Icons.person_outline_rounded,
                  size: 34, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: Spacing.lg),
            Text('Not signed in', style: type.Type.title(context)),
            const SizedBox(height: Spacing.sm),
            Text(
              'Sign in to get your own picks, library and listening history.',
              textAlign: TextAlign.center,
              style: type.Type.metadata(context),
            ),
            const SizedBox(height: Spacing.xl),
            FilledButton.icon(
              onPressed: onSignIn,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({
    super.key,
    required this.auth,
    required this.accounts,
    required this.onSignIn,
  });

  final AuthService auth;
  final List<GoogleAccountSession> accounts;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Spacing.screenX, Spacing.lg, Spacing.screenX, Spacing.huge),
      children: [
        for (var i = 0; i < accounts.length; i++)
          _stagger(
            i,
            child: _AccountCard(
              account: accounts[i],
              auth: auth,
            ),
          ),
        const SizedBox(height: Spacing.lg),
        _AddAccountButton(onTap: onSignIn),
        const SizedBox(height: Spacing.xxl),
        _SignOutButton(auth: auth),
      ],
    );
  }
}

/// Entrance stagger.
///
/// The index is clamped so a long list cannot accumulate delay - past a few
/// rows, waiting for the last one to arrive reads as the app being slow rather
/// than as an animation.
Widget _stagger(int index, {required Widget child}) {
  final clamped = index.clamp(0, 4);
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Motion.normal + Duration(milliseconds: 40 * clamped),
    curve: Motion.settle,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - t)),
        child: child,
      ),
    ),
    child: child,
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.auth});

  final GoogleAccountSession account;
  final AuthService auth;

  bool get _isActive => auth.activeAccount?.accountId == account.accountId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = account.profiles;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: design.GlassSurface(
        tier: GlassTier.card,
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.sm, Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(name: account.name, active: _isActive),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label(account),
                        style: type.Type.body(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isActive ? 'Active account' : account.email,
                        style: type.Type.metadata(context)
                            .copyWith(color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _ActiveCheck(active: _isActive),
                IconButton(
                  tooltip: 'Remove account',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => _confirmRemove(context),
                ),
              ],
            ),
            if (profiles.length > 1) ...[
              const SizedBox(height: Spacing.sm),
              // Channels only appear once there is a choice to make. With one
              // channel a list is noise.
              Padding(
                padding: const EdgeInsets.only(left: 52, bottom: Spacing.xs),
                child: Text('Channels', style: type.Type.caption(context)),
              ),
              for (final profile in profiles)
                _ChannelRow(
                  profile: profile,
                  selected: _isActive &&
                      (account.activeProfileId == null ||
                          account.activeProfileId == profile.profileId),
                  onTap: () => auth.selectIdentity(account.accountId, profile.profileId),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Never show a blank row. Google does not give us a display name from the
  /// cookie jar, and an empty line reads as a bug rather than as anonymity.
  String _label(GoogleAccountSession account) {
    final name = account.name.trim();
    if (name.isNotEmpty) return name;
    final email = account.email.trim();
    if (email.isNotEmpty) return email.split('@').first;
    final active = account.activeProfile?.name.trim() ?? '';
    if (active.isNotEmpty) return active;
    return 'YouTube account';
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final auth = this.auth;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this account?'),
        content: const Text(
          'Its saved session and cached recommendations are deleted from this '
          'device. You can add it again later.',
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
    if (ok != true) return;
    await auth.removeAccount(account.accountId);
    messenger.showSnackBar(
      const SnackBar(content: Text('Account removed')),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final YouTubeProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile.name.trim();
    return InkWell(
      onTap: selected ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.sm),
        child: Row(
          children: [
            Icon(
              profile.isBrandAccount
                  ? Icons.business_rounded
                  : Icons.person_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                name.isEmpty ? 'Channel' : name,
                style: type.Type.body(context).copyWith(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(profile.subtitle, style: type.Type.caption(context)),
            const SizedBox(width: Spacing.xs),
            // The check scales in rather than toggling, so a channel switch
            // reads as movement instead of a repaint.
            AnimatedScale(
              scale: selected ? 1 : 0,
              duration: Motion.fast,
              curve: Motion.springCurve,
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: Motion.fast,
                child: Icon(Icons.check_circle_rounded,
                    size: 18, color: theme.colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveCheck extends StatelessWidget {
  const _ActiveCheck({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedScale(
      scale: active ? 1 : 0,
      duration: Motion.normal,
      curve: Motion.springCurve,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: Motion.fast,
        child: Icon(Icons.check_circle_rounded,
            color: theme.colorScheme.primary, size: 22),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.active});

  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return AnimatedContainer(
      duration: Motion.normal,
      curve: Motion.settle,
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? theme.colorScheme.primary.withValues(alpha: 0.18)
            : theme.colorScheme.onSurface.withValues(alpha: 0.08),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: type.Type.body(context).copyWith(
          color: active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AddAccountButton extends StatelessWidget {
  const _AddAccountButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return design.GlassSurface(
      tier: GlassTier.card,
      borderRadius: 20,
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
        title: Text('Add another account', style: type.Type.body(context)),
        subtitle: Text(
          'Switch between Google accounts without losing this one',
          style: type.Type.caption(context),
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final only = auth.accounts.length <= 1;
    return OutlinedButton.icon(
      onPressed: () => _confirmSignOut(context),
      icon: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
      label: Text(
        only ? 'Sign out' : 'Sign out of all accounts',
        style: TextStyle(color: theme.colorScheme.error),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final auth = this.auth;
    final only = auth.accounts.length <= 1;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(only ? 'Sign out?' : 'Sign out of all accounts?'),
        content: Text(
          only
              ? 'Your saved session is deleted from this device and Home goes '
                  'back to the anonymous feed.'
              : 'All ${auth.accounts.length} saved sessions are deleted from '
                  'this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await auth.logout();
    messenger.showSnackBar(const SnackBar(content: Text('Signed out')));
  }
}