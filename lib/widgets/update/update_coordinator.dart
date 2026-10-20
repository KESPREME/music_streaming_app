// lib/widgets/update/update_coordinator.dart
//
// WHEN THE APP TALKS ABOUT UPDATES BY ITSELF.
//
// Sits above the Navigator, owns the "check on launch" and decides when a sheet
// may appear. Its rules are the polite ones:
//
//   * check once the first frame is out, never during start-up;
//   * what's new (you just updated) comes before update available;
//   * never over the full player or another open screen - try again a moment
//     later, a few times, then let it go (Settings will still show the dot);
//   * once per version: markPrompted() is called as the sheet opens.
//
// It adds no UI of its own and never throws: a missing provider (a test, a
// preview) makes it a pass-through.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/root_navigator.dart';
import '../../providers/music_provider.dart';
import '../../services/update/update_service.dart';
import 'update_sheets.dart';

class UpdateCoordinator extends StatefulWidget {
  const UpdateCoordinator({
    super.key,
    required this.child,
    this.service,
    this.settleDelay = const Duration(milliseconds: 2500),
    this.retryDelay = const Duration(seconds: 4),
    this.maxRetries = 6,
  });

  final Widget child;

  /// The updater; defaults to the one in Provider.
  final UpdateService? service;
  final Duration settleDelay;
  final Duration retryDelay;
  final int maxRetries;

  @override
  State<UpdateCoordinator> createState() => _UpdateCoordinatorState();
}

class _UpdateCoordinatorState extends State<UpdateCoordinator>
    with WidgetsBindingObserver {
  UpdateService? _service;
  Timer? _timer;
  bool _showing = false;
  int _retries = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || _started) return;
    _started = true;
    try {
      _service = widget.service ?? context.read<UpdateService>();
    } catch (_) {
      return; // no updater in this tree
    }
    final s = _service!;
    await s.initialize();
    if (!mounted) return;
    s.addListener(_onChanged);
    unawaited(s.check());
    _schedule(widget.settleDelay);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = _service;
    if (s == null || state != AppLifecycleState.resumed) return;
    // Back from the installer or from "install unknown apps" settings.
    unawaited(s.refreshAfterResume());
    unawaited(s.check());
  }

  void _onChanged() {
    final s = _service;
    if (s == null) return;
    if (s.whatsNew != null || s.shouldPrompt) _schedule(widget.retryDelay ~/ 2);
  }

  void _schedule(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, _maybeShow);
  }

  bool get _somethingElseIsOpen {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return true;
    if (nav.canPop()) return true;
    try {
      return context.read<MusicProvider>().isPlayerExpanded;
    } catch (_) {
      return false;
    }
  }

  Future<void> _maybeShow() async {
    final s = _service;
    if (!mounted || s == null || _showing) return;
    final wantsWhatsNew = s.whatsNew != null;
    final wantsPrompt = !wantsWhatsNew && s.shouldPrompt;
    if (!wantsWhatsNew && !wantsPrompt) return;

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || _somethingElseIsOpen) {
      if (_retries++ < widget.maxRetries) _schedule(widget.retryDelay);
      return;
    }
    _retries = 0;
    _showing = true;
    try {
      if (wantsWhatsNew) {
        await showWhatsNewSheet(ctx, s);
      } else {
        await showUpdatePromptSheet(ctx, s);
      }
    } finally {
      _showing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _service?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
