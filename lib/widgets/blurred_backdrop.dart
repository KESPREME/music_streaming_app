// lib/widgets/blurred_backdrop.dart
//
// The player's blurred artwork wash, computed once per track instead of once
// per frame.
//
// WHY
//
// The backdrop was `ImageFiltered(blur 60)` over a full-screen, 1.6x-scaled
// image. A blur that large is a multi-pass GPU operation, and on Impeller there
// is no raster cache to remember its result: wrapping it in a RepaintBoundary
// saves the Dart side of repainting but not the GPU's. So the wash was
// re-blurred in full for EVERY frame the player drew - at display rate while a
// word-synced lyric sweeps - to produce the same picture.
//
// WHAT
//
// The picture never changes within a track, and it is so heavily blurred that it
// holds almost no detail: one pixel per 4 logical px on screen is far more than
// a sigma of 96 can resolve. So it is rendered ONCE into a small image
// (~1/16 of a screen's logical pixels), and each frame draws that image as a
// single textured quad.
//
// The bake replays the SAME operations the live widget did - same cover fit,
// same blur in the same coordinate space, same scale about the same origin -
// only at a smaller scale, so it is the same picture, not an approximation of
// its look. test/blurred_backdrop_test.dart compares the two pixel for pixel.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/image_quality_utils.dart';

/// How many logical pixels one baked pixel covers (per axis).
///
/// The wash is blurred with an effective sigma of ~100 logical px, so its
/// finest feature is hundreds of pixels wide; 4 is a safety factor of ~25 over
/// what the blur can show. A larger cell would still be indistinguishable, but
/// the saving past this point is small and the margin is free.
const double kBackdropBakeCell = 4.0;

/// The source decoded for the wash. The blur removes everything finer than
/// ~100 logical px, so a 256px thumbnail carries all the information the result
/// has - and is a third of the memory of the hero's 800px decode.
const int kBackdropSourcePx = 256;

/// Renders [source] as the player renders its backdrop - cover-fitted into
/// [size], blurred with [sigma], then scaled by [scale] about [alignment] - into
/// an image of `size / cell`.
///
/// The returned image is owned by the caller.
Future<ui.Image> bakeBlurredBackdrop({
  required ui.Image source,
  required Size size,
  required double sigma,
  required double scale,
  Alignment alignment = Alignment.center,
  double cell = kBackdropBakeCell,
}) async {
  final bw = (size.width / cell).ceil().clamp(1, 4096);
  final bh = (size.height / cell).ceil().clamp(1, 4096);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, bw.toDouble(), bh.toDouble()),
  );

  // Logical -> baked pixels. Each axis maps the box exactly onto the image, so
  // the result stretches back over the box with no residual scale.
  canvas.scale(bw / size.width, bh / size.height);

  // Transform.scale(scale, alignment): scale about the alignment point.
  final origin = alignment.alongSize(size);
  canvas.translate(origin.dx, origin.dy);
  canvas.scale(scale);
  canvas.translate(-origin.dx, -origin.dy);

  // ImageFiltered(blur) over SizedBox.expand(image, cover). The sigma lives in
  // the coordinate space of the layer, which the transform above scales - the
  // same way it scaled the live blur.
  final local = Offset.zero & size;
  canvas.saveLayer(
    local,
    Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
  );
  paintImage(
    canvas: canvas,
    rect: local,
    image: source,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
  );
  canvas.restore();

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(bw, bh);
  } finally {
    picture.dispose();
  }
}

/// The artwork provider the wash is made from, or null when there is none.
///
/// Decoded small ([kBackdropSourcePx]) - and for a local file too, which used to
/// be decoded at its full resolution only to be blurred beyond recognition.
ImageProvider? backdropArtProvider(String albumArtUrl) {
  final art = ImageQualityUtils.getHighResArtwork(albumArtUrl);
  if (art.isEmpty) return null;
  if (!art.contains('://')) {
    final file = File(art);
    if (file.existsSync()) {
      return ResizeImage(
        FileImage(file),
        width: kBackdropSourcePx,
        height: kBackdropSourcePx,
        policy: ResizeImagePolicy.fit,
      );
    }
  }
  return ResizeImage(
    CachedNetworkImageProvider(art),
    width: kBackdropSourcePx,
    height: kBackdropSourcePx,
    policy: ResizeImagePolicy.fit,
  );
}

/// A blurred, scaled wash of [image], baked once and drawn as one image.
///
/// Fills its parent. Changing [image] cross-fades to the new wash; the previous
/// one stays on screen until it is ready, so there is never an empty frame
/// between tracks.
class BlurredBackdrop extends StatefulWidget {
  const BlurredBackdrop({
    super.key,
    required this.image,
    required this.sigma,
    required this.scale,
    this.alignment = Alignment.center,
    this.fade = const Duration(milliseconds: 450),
    this.errorColor,
  });

  /// What to wash. Compared by value, so rebuilding with an equal provider is
  /// free.
  final ImageProvider image;
  final double sigma;
  final double scale;
  final Alignment alignment;
  final Duration fade;

  /// Shown when the image cannot be loaded.
  final Color? errorColor;

  @override
  State<BlurredBackdrop> createState() => _BlurredBackdropState();
}

class _BlurredBackdropState extends State<BlurredBackdrop> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// The decoded source, cloned so it outlives the image cache's entry. Kept
  /// for as long as the provider is the same, because a change of size needs to
  /// bake again.
  ui.Image? _source;
  Size? _size;
  Size? _bakedFor;

  ui.Image? _baked;

  /// Changes when the picture is a NEW wash (a new track), not on a re-bake of
  /// the same one at a new size - so only the former cross-fades.
  int _washId = 0;

  /// Bumped to abandon an in-flight bake.
  int _generation = 0;
  bool _failed = false;

  /// Images that were replaced while their fade-out may still be painting.
  final List<ui.Image> _retired = <ui.Image>[];
  Timer? _retireTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant BlurredBackdrop old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) {
      _resolve();
    } else if (old.sigma != widget.sigma ||
        old.scale != widget.scale ||
        old.alignment != widget.alignment) {
      _bakedFor = null;
      _maybeBake();
    }
  }

  @override
  void dispose() {
    _detach();
    _generation++;
    _retireTimer?.cancel();
    _source?.dispose();
    _baked?.dispose();
    for (final i in _retired) {
      i.dispose();
    }
    super.dispose();
  }

  void _detach() {
    final l = _listener;
    if (l != null) _stream?.removeListener(l);
    _listener = null;
    _stream = null;
  }

  ImageProvider? _resolved;

  void _resolve() {
    if (_resolved == widget.image) return;
    _resolved = widget.image;
    _detach();
    _source?.dispose();
    _source = null;
    _bakedFor = null;
    _failed = false;
    _washPending = true;
    _generation++;

    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        // One image is all this needs; letting go of the stream also lets go
        // of the cache's hold on the full-size decode.
        _source?.dispose();
        _source = info.image.clone();
        stream.removeListener(listener);
        if (identical(_stream, stream)) {
          _stream = null;
          _listener = null;
        }
        _maybeBake();
      },
      onError: (Object error, StackTrace? stack) {
        if (!mounted) return;
        setState(() => _failed = true);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _maybeBake() {
    final source = _source;
    final size = _size;
    if (source == null || size == null || size.isEmpty) return;
    final done = _bakedFor;
    if (done != null &&
        (done.width - size.width).abs() < 1 &&
        (done.height - size.height).abs() < 1) {
      return;
    }
    _bakedFor = size;
    final generation = ++_generation;
    final newWash = _baked == null || _washPending;
    bakeBlurredBackdrop(
      source: source,
      size: size,
      sigma: widget.sigma,
      scale: widget.scale,
      alignment: widget.alignment,
    ).then((image) {
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() {
        final old = _baked;
        if (old != null) _retire(old);
        _baked = image;
        if (newWash) _washId++;
        _washPending = false;
      });
    }, onError: (Object _, StackTrace __) {
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
    });
  }

  /// True from a change of image until its first bake lands.
  bool _washPending = true;

  void _retire(ui.Image image) {
    _retired.add(image);
    _retireTimer?.cancel();
    _retireTimer = Timer(widget.fade + const Duration(milliseconds: 250), () {
      for (final i in _retired) {
        i.dispose();
      }
      _retired.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (_size != size) {
          _size = size;
          // After this frame: baking starts a future, which must not run
          // inside layout.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeBake();
          });
        }
        final baked = _baked;
        final Widget child;
        if (_failed) {
          child = ColoredBox(
            key: const ValueKey<int>(-2),
            color: widget.errorColor ?? Colors.grey.shade900,
          );
        } else if (baked == null) {
          child = const SizedBox.expand(key: ValueKey<int>(-1));
        } else {
          child = RawImage(
            key: ValueKey<int>(_washId),
            image: baked,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          );
        }
        return AnimatedSwitcher(
          duration: widget.fade,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: <Widget>[...previous, if (current != null) current],
          ),
          child: child,
        );
      },
    );
  }
}
