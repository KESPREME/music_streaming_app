// lib/services/eq/eq_presets.dart
//
// The built-in curves. Each is ten gains against [kIsoHz]
// (31 Hz .. 16 kHz), so one definition fits a 5-band phone and a 10-band one.
//
// They are tuned to be useful, not dramatic: nothing exceeds +/-7 dB, because a
// preset that needs more than that is compensating for the speaker, not
// shaping the music, and a bigger swing is what costs headroom and clips.

import 'eq_curves.dart';

class EqPresetDef {
  const EqPresetDef(this.id, this.name, this.blurb, this.tenBand);

  final String id;
  final String name;

  /// One line on what it is for.
  final String blurb;

  /// Gains in dB at 31 62 125 250 500 1k 2k 4k 8k 16k.
  final List<double> tenBand;

  List<double> gainsFor(List<double> centersHz) =>
      resampleTenBand(tenBand, centersHz);
}

const String kFlatPreset = 'flat';

const List<EqPresetDef> kEqPresets = [
  EqPresetDef('flat', 'Flat', 'No change. The recording as it was mastered',
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  EqPresetDef('bass_boost', 'Bass Booster', 'More weight in the low end',
      [6, 5.5, 4.5, 2.5, 0.5, 0, 0, 0, 0, 0]),
  EqPresetDef('bass_reducer', 'Bass Reducer', 'Tames boomy rooms and speakers',
      [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0]),
  EqPresetDef('treble_boost', 'Treble Booster', 'Sparkle and air',
      [0, 0, 0, 0, 0, 1, 2.5, 4, 5.5, 6]),
  EqPresetDef('treble_reducer', 'Treble Reducer', 'Softens harsh, bright tracks',
      [0, 0, 0, 0, 0, -1, -2.5, -4, -5.5, -6]),
  EqPresetDef('vocal', 'Vocal Booster', 'Voices forward, rumble back',
      [-3, -3, -2, 0, 2.5, 4, 4, 2.5, 0, -1.5]),
  EqPresetDef('acoustic', 'Acoustic', 'Warm strings, natural air',
      [4, 4, 3, 1.5, 2, 1.5, 2.5, 3.5, 3, 2]),
  EqPresetDef('classical', 'Classical', 'Gentle width, nothing forced',
      [3, 2.5, 2, 1.5, 0, 0, 0, 1, 2, 2.5]),
  EqPresetDef('dance', 'Dance', 'Punchy low end, lively highs',
      [6, 5, 3.5, 0, 1.5, 3, 4, 3.5, 1.5, 0]),
  EqPresetDef('deep', 'Deep', 'Warm and dark',
      [5, 4.5, 3.5, 2, 1, 0, -1.5, -3, -4, -5]),
  EqPresetDef('electronic', 'Electronic', 'Sub weight, crisp top',
      [4.5, 4, 1.5, 0, -2, 2, 1.5, 1.5, 4, 4.5]),
  EqPresetDef('hip_hop', 'Hip-Hop', 'Heavy kicks, clear vocals',
      [5, 4.5, 2, 3, -1, -1, 1.5, -0.5, 2, 3]),
  EqPresetDef('jazz', 'Jazz', 'Smooth mids, open top',
      [3, 2.5, 1, 2, -2, -2, 0, 1, 2.5, 3.5]),
  EqPresetDef('latin', 'Latin', 'Bright percussion, rounded bass',
      [3, 2, 0, 0, -1, -1, -1, 0, 2.5, 4]),
  EqPresetDef('loudness', 'Loudness', 'Fuller sound at low volume',
      [6, 4.5, 2, 0, -1, -1, 0, 2, 4, 5]),
  EqPresetDef('lounge', 'Lounge', 'Relaxed, mid-focused',
      [-3, -1.5, 0, 1.5, 2.5, 1.5, 0, -1.5, 2, 1]),
  EqPresetDef('piano', 'Piano', 'Clear attack, natural decay',
      [2, 1.5, 0, 2.5, 3, 1.5, 3, 4, 3, 3.5]),
  EqPresetDef('pop', 'Pop', 'Present vocals, tight bass',
      [-1.5, -0.5, 1.5, 3, 3.5, 2.5, 0.5, -1, -1.5, -1.5]),
  EqPresetDef('rnb', 'R&B', 'Deep, round low end',
      [5, 7, 5.5, 1.5, -2, -1.5, 2.5, 3, 3.5, 4]),
  EqPresetDef('rock', 'Rock', 'Driving lows, bright guitars',
      [5, 4, 3, 1.5, -0.5, -1, 0.5, 2.5, 3.5, 4.5]),
  EqPresetDef('small_speakers', 'Small Speakers', 'Makes up for a tiny driver',
      [5.5, 5, 4, 3, 1.5, 0, -1.5, -2.5, -3.5, -4.5]),
  EqPresetDef('spoken_word', 'Spoken Word', 'Podcasts and audiobooks',
      [-4, -3, -1, 1, 3.5, 4.5, 4, 2.5, 0.5, -1]),
  EqPresetDef('late_night', 'Late Night', 'Clear at a whisper',
      [-2, -1, 0, 0.5, 1.5, 2.5, 2.5, 2, 1, 0]),
];

/// Ids older builds stored, mapped to today's.
const Map<String, String> kLegacyPresetIds = {
  'hiphop': 'hip_hop',
  'podcast': 'spoken_word',
};

EqPresetDef? presetById(String id) {
  final real = kLegacyPresetIds[id] ?? id;
  for (final p in kEqPresets) {
    if (p.id == real) return p;
  }
  return null;
}
