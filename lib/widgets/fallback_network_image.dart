// lib/widgets/fallback_network_image.dart
//
// A network picture that does not give up at the first bad link.
//
// The app upgrades artwork links to a higher resolution (ImageQualityUtils). An
// upgrade is a guess - the resolution may not exist, the signature may not
// survive - and the old widgets answered a failed guess with a flat colour, so a
// cover that the SOURCE would have served went blank. This tries the candidates
// in order (the upgraded link, then the original) and only then shows the
// placeholder. The placeholder is also what shows while the first one loads, so
// nothing flashes between attempts.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../utils/image_quality_utils.dart';

class FallbackNetworkImage extends StatefulWidget {
  /// Candidates are tried in order; empty and duplicate entries are ignored.
  const FallbackNetworkImage({
    super.key,
    required this.urls,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.fadeInDuration = const Duration(milliseconds: 180),
    this.debugLoader,
  });

  /// One picture from the link a source gave: the upgraded link first, the original
  /// as the fallback.
  FallbackNetworkImage.forUrl(
    String? url, {
    super.key,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.fadeInDuration = const Duration(milliseconds: 180),
    this.debugLoader,
  }) : urls = ImageQualityUtils.candidates(url);

  final List<String> urls;
  final Widget placeholder;
  final BoxFit fit;
  final Alignment alignment;
  final int? memCacheWidth;
  final Duration fadeInDuration;

  /// Test seam: replaces the network image so a test can fail chosen links
  /// deterministically (the test binding's own failure timing is not something to
  /// build an assertion on). Call onError the way an image's error builder would.
  @visibleForTesting
  final Widget Function(BuildContext context, String url, VoidCallback onError)? debugLoader;

  @override
  State<FallbackNetworkImage> createState() => _FallbackNetworkImageState();
}

class _FallbackNetworkImageState extends State<FallbackNetworkImage> {
  int _index = 0;
  bool _advancing = false;

  List<String> get _urls => [
        for (final u in widget.urls)
          if (u.trim().isNotEmpty) u,
      ];

  @override
  void didUpdateWidget(FallbackNetworkImage old) {
    super.didUpdateWidget(old);
    // A different picture starts again from its best candidate.
    if (old.urls.join('|') != widget.urls.join('|')) _index = 0;
  }

  void _next() {
    if (_advancing) return;
    _advancing = true;
    // The error builder runs during build: step on after the frame.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _advancing = false;
      if (mounted) setState(() => _index++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final urls = _urls;
    if (_index >= urls.length) return widget.placeholder;
    final loader = widget.debugLoader;
    if (loader != null) {
      return loader(context, urls[_index], () {
        if (_index + 1 < urls.length) _next();
      });
    }
    return CachedNetworkImage(
      key: ValueKey('${_index}_${urls[_index]}'),
      imageUrl: urls[_index],
      fit: widget.fit,
      alignment: widget.alignment,
      // Width only: a height as well decodes to an exact box and squashes any
      // picture that is not square (a 16:9 thumbnail) before it is cropped.
      memCacheWidth: widget.memCacheWidth,
      fadeInDuration: widget.fadeInDuration,
      placeholder: (_, __) => widget.placeholder,
      errorWidget: (_, __, ___) {
        if (_index + 1 < urls.length) {
          _next();
        }
        return widget.placeholder;
      },
    );
  }
}
