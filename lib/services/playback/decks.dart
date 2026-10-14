// lib/services/playback/decks.dart
//
// Two players that trade roles, and the plumbing that lets everything else go
// on talking to "the player" while they do.
//
// WHY TWO
//
// A crossfade has two songs audible at once. One ExoPlayer (or AVQueuePlayer)
// renders one item at a time, so at a track boundary there is exactly one source
// and the gain it can be given is 1 or 0: fading it out and back in leaves a dip
// of silence at the join, which is a gap, not a blend. just_audio's maintainer
// says as much (ryanheise/just_audio#815): crossfade needs a second decoder.
//
// THE RULE THAT KEEPS IT SIMPLE
//
// The standby deck only ever carries the INCOMING track, started at its cue
// point. The two decks never hold the same audio, so there is nothing to align
// and nothing rendered twice. Finishing a transition is a role swap, not a seek.
//
// WHY RELAYS
//
// Everything in the app listens to one set of streams (position, state, index).
// Those streams belong to a player, and the player they belong to changes at
// every handoff. A [DeckRelay] is a stable stream that follows whichever deck is
// active, so no listener has to know a swap happened.

import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// A stream that follows a changing source.
///
/// With [replay] a new listener first hears the latest value, which is how
/// just_audio's own state streams behave and what late subscribers (a screen
/// opening mid-song) rely on.
class DeckRelay<T> {
  DeckRelay({this.replay = false});

  final bool replay;
  final StreamController<T> _controller = StreamController<T>.broadcast();
  StreamSubscription<T>? _source;
  bool _hasLast = false;
  T? _last;

  Stream<T> get stream {
    if (!replay) return _controller.stream;
    return Stream<T>.multi((sink) {
      if (_hasLast) sink.add(_last as T);
      final sub = _controller.stream.listen(
        sink.add,
        onError: sink.addError,
        onDone: sink.close,
      );
      sink.onCancel = sub.cancel;
    });
  }

  /// The most recent value, if any has arrived.
  T? get latest => _last;

  /// Switches to [source]. The previous source stops being relayed at once.
  void follow(Stream<T> source) {
    _source?.cancel();
    _source = source.listen(
      (value) {
        _hasLast = true;
        _last = value;
        if (!_controller.isClosed) _controller.add(value);
      },
      onError: (Object e, StackTrace s) {
        if (!_controller.isClosed) _controller.addError(e, s);
      },
    );
  }

  Future<void> dispose() async {
    await _source?.cancel();
    _source = null;
    await _controller.close();
  }
}

/// The pair. [active] is the session deck; [standby] is created on first use,
/// so an app that never transitions pays for one player, as before.
class DeckPair {
  DeckPair(this._create) : _decks = <AudioPlayer?>[null, null] {
    _decks[0] = _create();
  }

  final AudioPlayer Function() _create;
  final List<AudioPlayer?> _decks;
  int _active = 0;

  AudioPlayer get active => _decks[_active]!;

  AudioPlayer get standby => _decks[1 - _active] ??= _create();

  bool get hasStandby => _decks[1 - _active] != null;

  /// The standby, without creating it.
  AudioPlayer? get standbyIfAny => _decks[1 - _active];

  /// Trades roles. Callers re-point their relays afterwards.
  void swap() => _active = 1 - _active;

  Future<void> dispose() async {
    for (final deck in _decks) {
      await deck?.dispose();
    }
  }
}
