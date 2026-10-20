import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/audio_output_service.dart';
import 'package:music_streaming_app/services/eq/eq_curves.dart';
import 'package:music_streaming_app/services/eq/eq_models.dart';
import 'package:music_streaming_app/services/eq/eq_platform.dart';
import 'package:music_streaming_app/services/eq/eq_presets.dart';
import 'package:music_streaming_app/services/equalizer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Out extends AudioOutputService {
  void set(String kind, String name) {
    outputs = [AudioOutputDevice(id: 1, kind: kind, name: name, isActive: true)];
    notifyListeners();
  }
}

Future<(EqualizerService, FakeEqPlatform)> boot({
  Map<String, Object> prefs = const {},
  EqCapabilities? caps,
  bool supported = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final fake = caps == null ? FakeEqPlatform() : FakeEqPlatform(capabilities: caps);
  final s = EqualizerService.test(platform: fake, supported: supported);
  await s.initialize();
  return (s, fake);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('interpolation and resampling', () {
    test('flat beyond the ends, exact at a control point', () {
      const f = [100.0, 1000.0];
      const d = [2.0, 8.0];
      expect(interpolateDb(f, d, 20), 2);
      expect(interpolateDb(f, d, 20000), 8);
      expect(interpolateDb(f, d, 100), closeTo(2, 1e-9));
      expect(interpolateDb(f, d, 1000), closeTo(8, 1e-9));
    });

    test('halfway in octaves is halfway in gain', () {
      expect(interpolateDb(const [100.0, 1000.0], const [0.0, 10.0], math.sqrt(100 * 1000)),
          closeTo(5, 1e-6));
    });

    test('resampling onto the ISO centres returns the preset itself', () {
      for (final p in kEqPresets) {
        final back = p.gainsFor(kIsoHz);
        for (var i = 0; i < 10; i++) {
          expect(back[i], closeTo(p.tenBand[i], 0.26),
              reason: '${p.id} band $i (rounded to the 0.5 dB grid)');
        }
      }
    });

    test('a bass preset is bass-heavy on a typical five-band phone', () {
      final g = presetById('bass_boost')!.gainsFor(const [60, 230, 910, 3600, 14000]);
      expect(g.length, 5);
      expect(g.first, greaterThan(4));
      expect(g.last, lessThan(1));
      expect(g.first, greaterThan(g[1]));
    });

    test('every value is on the 0.5 dB grid the sliders move in', () {
      for (final p in kEqPresets) {
        for (final g in p.gainsFor(const [60, 230, 910, 3600, 14000])) {
          expect((g * 2) % 1, 0, reason: p.id);
        }
      }
    });
  });

  group('preset library', () {
    test('ids are unique and each has ten gains within a sane swing', () {
      final ids = <String>{};
      for (final p in kEqPresets) {
        expect(ids.add(p.id), isTrue, reason: 'duplicate ${p.id}');
        expect(p.tenBand.length, 10, reason: p.id);
        expect(p.tenBand.every((g) => g.abs() <= 7), isTrue, reason: p.id);
        expect(p.name, isNotEmpty);
        expect(p.blurb, isNotEmpty);
      }
      expect(kEqPresets.length, greaterThanOrEqualTo(20));
    });

    test('flat is flat, and old ids still resolve', () {
      expect(presetById('flat')!.tenBand.every((g) => g == 0), isTrue);
      expect(presetById('hiphop')!.id, 'hip_hop');
      expect(presetById('podcast')!.id, 'spoken_word');
      expect(presetById('nope'), isNull);
    });
  });

  group('response curve', () {
    const five = EqBand.typicalFive;

    test('at a band centre the response is that band\'s gain', () {
      final g = [0.0, 0.0, 6.0, 0.0, 0.0];
      expect(responseDb(five[2].centerHz, five, g), closeTo(6, 0.05));
    });

    test('far from a lone band the response is flat', () {
      final g = [0.0, 0.0, 6.0, 0.0, 0.0];
      expect(responseDb(20, five, g).abs(), lessThan(0.5));
      expect(responseDb(20000, five, g).abs(), lessThan(0.5));
    });

    test('a cut is a cut', () {
      expect(responseDb(60, five, [-6.0, 0, 0, 0, 0]), lessThan(-5));
    });

    test('the curve is sampled log-spaced from 20 Hz to 20 kHz', () {
      final c = responseCurve(five, [0, 0, 0, 0, 0]);
      expect(c.length, 96);
      expect(c.first.$1, closeTo(20, 1e-6));
      expect(c.last.$1, closeTo(20000, 1e-3));
      expect(c.every((p) => p.$2.abs() < 1e-9), isTrue);
    });
  });

  group('headroom', () {
    test('equals the biggest boost plus the pre-amp, never negative', () {
      expect(headroomDb([6, 2, -3], 0), 6);
      expect(headroomDb([6, 2, -3], -3), 3);
      expect(headroomDb([-6, -2], 0), 0);
      expect(headroomDb([], 4), 4);
      expect(headroomDb([], -4), 0);
    });

    test('the loudest band lands on 0 dB so nothing can clip', () {
      final l = effectiveLevels([6, 2, -3],
          preampDb: 0, autoHeadroom: true, minDb: -15, maxDb: 15);
      expect(l.reduce(math.max), 0);
      expect(l, [0, -4, -9]);
    });

    test('with auto headroom off the gains pass through, clamped to the range',
        () {
      final l = effectiveLevels([10, -10],
          preampDb: 8, autoHeadroom: false, minDb: -15, maxDb: 15);
      expect(l, [15, -2]);
    });
  });

  group('formatting', () {
    test('frequencies', () {
      expect(formatHz(60), '60 Hz');
      expect(formatHz(3600), '3.6 kHz');
      expect(formatHz(14000), '14 kHz');
      expect(formatHz(1000), '1 kHz');
      expect(formatHzShort(230), '230');
      expect(formatHzShort(3600), '3.6k');
      expect(formatHzShort(16000), '16k');
    });

    test('decibels use a real minus and half-dB steps', () {
      expect(formatDb(3.5), '+3.5 dB');
      expect(formatDb(-2), '\u22122 dB');
      expect(formatDb(0), '0 dB');
      expect(formatDb(6, unit: false), '+6');
      expect(formatDb(3.26), '+3.5 dB');
    });

    test('snapping', () {
      expect(snapDb(3.3, -12, 12), 3.5);
      expect(snapDb(40, -12, 12), 12);
      expect(snapDb(-40, -12, 12), -12);
    });
  });

  group('models', () {
    test('a profile survives JSON and clamps hostile values', () {
      const p = EqProfile(
        enabled: true,
        presetId: 'rock',
        gains: [1, 2, 3],
        preampDb: -2.5,
        autoHeadroom: false,
        loudnessDb: 4,
        bassBoost: 0.5,
        virtualizer: 0.25,
      );
      expect(EqProfile.fromJson(jsonDecode(jsonEncode(p.toJson()))), p);

      final bad = EqProfile.fromJson({
        'enabled': true,
        'gains': [999, 'x', -999],
        'preamp': 500,
        'loudness': -4,
        'bass': 7,
        'virt': double.nan,
      });
      expect(bad.gains, [24, 0, -24]);
      expect(bad.preampDb, 12);
      expect(bad.loudnessDb, 0);
      expect(bad.bassBoost, 1);
      expect(bad.virtualizer, 0);
      expect(EqProfile.fromJson('nope'), const EqProfile());
    });

    test('state decoding rejects damage and other versions', () {
      expect(EqState.decode(null), isNull);
      expect(EqState.decode('{oops'), isNull);
      expect(EqState.decode('{"v":1}'), isNull);
      final ok = EqState(
        perOutput: true,
        profiles: {'all': const EqProfile(presetId: 'jazz')},
        userPresets: [
          const UserEqPreset(id: 'a', name: 'Mine', points: [(60, 2), (1000, 0)])
        ],
      );
      final back = EqState.decode(ok.encode())!;
      expect(back.perOutput, isTrue);
      expect(back.profiles['all']!.presetId, 'jazz');
      expect(back.userPresets.single.name, 'Mine');
    });

    test('a saved preset with fewer than two points is dropped', () {
      expect(UserEqPreset.fromJson({'id': 'a', 'name': 'x', 'points': [[1, 2]]}), isNull);
      expect(UserEqPreset.fromJson({'id': '', 'name': 'x', 'points': []}), isNull);
    });

    test('capabilities: no bands means unavailable', () {
      expect(EqCapabilities.fromMap({'available': true, 'bands': []}).available, isFalse);
      final c = EqCapabilities.fromMap({
        'available': true,
        'bands': [
          {'centerHz': 60.0, 'lowHz': 20.0, 'highHz': 120.0}
        ],
        'minDb': -15.0,
        'maxDb': 15.0,
        'bassBoost': true,
      });
      expect(c.available, isTrue);
      expect(c.summary, contains('1 bands'));
      expect(c.summary, contains('±15 dB'));
      expect(c.bassBoost, isTrue);
      expect(c.virtualizer, isFalse);
    });

    test('the sync map speaks millibels', () {
      const s = EqSync(
          sessions: [3], levelsDb: [1.5, -2], bass: 0.5, virtualizer: 1, loudnessDb: 3);
      expect(s.toMap(), {
        'sessions': [3],
        'levelsMb': [150, -200],
        'bass': 500,
        'virt': 1000,
        'loudnessMb': 300,
      });
    });
  });

  group('EqualizerService', () {
    test('learns the device and starts neutral and off', () async {
      final (s, _) = await boot();
      expect(s.isPlatformAvailable, isTrue);
      expect(s.bands.length, 5);
      expect(s.profile.gains, [0, 0, 0, 0, 0]);
      expect(s.isEnabled, isFalse);
      expect(s.currentPresetName, 'Flat');
    });

    test('attaches nothing while off, and nothing is wasted before audio exists',
        () async {
      final (s, fake) = await boot();
      s.reportSession('deck', 11);
      await s.flushPush();
      expect(fake.last!.isOff, isTrue);

      await s.setEnabled(true);
      await s.flushPush();
      expect(fake.last!.sessions, [11]);
    });

    test('on, with no audio session yet, attaches nothing', () async {
      final (s, fake) = await boot();
      await s.setEnabled(true);
      await s.flushPush();
      expect(fake.last!.isOff, isTrue);
      s.reportSession('deck', 7);
      await s.flushPush();
      expect(fake.last!.sessions, [7]);
    });

    test('both decks of a crossfade are processed, and a gone deck is released',
        () async {
      final (s, fake) = await boot();
      await s.setEnabled(true);
      s.reportSession('a', 11);
      s.reportSession('b', 12);
      await s.flushPush();
      expect(fake.last!.sessions, [11, 12]);
      s.reportSession('b', null);
      await s.flushPush();
      expect(fake.last!.sessions, [11]);
      s.reportSession('a', 0);
      await s.flushPush();
      expect(fake.last!.isOff, isTrue);
    });

    test('a preset shapes the levels and the headroom keeps them from clipping',
        () async {
      final (s, fake) = await boot();
      await s.setEnabled(true);
      s.reportSession('d', 5);
      await s.selectPreset('rock');
      await s.flushPush();
      final l = fake.last!.levelsDb;
      expect(l.length, 5);
      expect(l.reduce(math.max), closeTo(0, 1e-9));
      expect(s.headroomDb, greaterThan(3));
      expect(s.currentPresetId, 'rock');
      // The shape is unchanged: rock is scooped in the mids.
      expect(l[2], lessThan(l[0]));
    });

    test('with auto headroom off the gains are sent as set', () async {
      final (s, fake) = await boot();
      await s.setEnabled(true);
      s.reportSession('d', 5);
      s.setAutoHeadroom(false);
      await s.setBandGain(0, 6);
      await s.flushPush();
      expect(fake.last!.levelsDb.first, 6);
      expect(s.headroomDb, 0);
    });

    test('moving a band leaves the preset: it is Custom now', () async {
      final (s, _) = await boot();
      await s.selectPreset('pop');
      await s.setBandGain(2, 4);
      expect(s.currentPresetId, 'custom');
      expect(s.profile.gains[2], 4);
      expect(s.currentPresetName, 'Custom');
    });

    test('gains snap to half a dB and to the device range', () async {
      final (s, _) = await boot();
      await s.setBandGain(1, 3.3);
      expect(s.profile.gains[1], 3.5);
      await s.setBandGain(1, 99);
      expect(s.profile.gains[1], 15);
      await s.setBandGain(1, -99);
      expect(s.profile.gains[1], -15);
      await s.setBandGain(9, 1); // no such band
      expect(s.profile.gains.length, 5);
    });

    test('hold-to-compare passes the signal untouched without detaching',
        () async {
      final (s, fake) = await boot();
      await s.setEnabled(true);
      s.reportSession('d', 5);
      await s.selectPreset('bass_boost');
      s.setBassBoost(0.8);
      await s.flushPush();
      expect(fake.last!.levelsDb.any((l) => l != 0), isTrue);
      expect(fake.last!.bass, 0.8);

      s.setBypass(true);
      await s.flushPush();
      expect(fake.last!.sessions, [5], reason: 'still attached');
      expect(fake.last!.levelsDb.every((l) => l == 0), isTrue);
      expect(fake.last!.bass, 0);

      s.setBypass(false);
      await s.flushPush();
      expect(fake.last!.bass, 0.8);
    });

    test('effects the device cannot do are never requested', () async {
      final (s, fake) = await boot(
          caps: const EqCapabilities(
              available: true, bands: EqBand.typicalFive, minDb: -15, maxDb: 15));
      await s.setEnabled(true);
      s.reportSession('d', 5);
      s.setBassBoost(1);
      s.setVirtualizer(1);
      s.setLoudness(6);
      await s.flushPush();
      expect(fake.last!.bass, 0);
      expect(fake.last!.virtualizer, 0);
      expect(fake.last!.loudnessDb, 0);
    });

    test('switching off releases everything, which also frees the low-power path',
        () async {
      final (s, fake) = await boot();
      await s.setEnabled(true);
      s.reportSession('d', 5);
      await s.flushPush();
      expect(fake.last!.isOff, isFalse);
      await s.setEnabled(false);
      await s.flushPush();
      expect(fake.last!.isOff, isTrue);
    });

    test('identical consecutive states are not re-sent', () async {
      final (s, fake) = await boot();
      await s.setEnabled(true);
      s.reportSession('d', 5);
      await s.flushPush();
      final n = fake.syncs.length;
      await s.flushPush();
      s.reportSession('d', 5);
      await s.flushPush();
      expect(fake.syncs.length, n);
    });

    test('refuses to switch on when the device has no equalizer', () async {
      final (s, fake) =
          await boot(caps: EqCapabilities.unavailable, supported: true);
      await s.setEnabled(true);
      expect(s.isEnabled, isFalse);
      expect(s.isPlatformAvailable, isFalse);
      s.reportSession('d', 5);
      await s.flushPush();
      expect(fake.last!.isOff, isTrue);
      // The screen can still draw something coherent.
      expect(s.bands.length, 5);
    });

    test('a host that is not Android never talks to the platform', () async {
      final (s, fake) = await boot(supported: false);
      await s.setEnabled(true);
      s.reportSession('d', 5);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fake.syncs, isEmpty);
      expect(s.isEnabled, isFalse);
    });

    test('a saved enabled flag does not fake an effect that is not there',
        () async {
      final (s, _) = await boot(
        prefs: {'eq_enabled': true},
        caps: EqCapabilities.unavailable,
      );
      expect(s.isEnabled, isFalse);
    });

    test('reports an unhealthy engine and recovers', () async {
      final (s, fake) = await boot();
      await s.setEnabled(true);
      fake.result = EqSyncResult.failed;
      s.reportSession('d', 5);
      await s.flushPush();
      expect(s.engineHealthy, isFalse);
      fake.result = const EqSyncResult();
      s.setPreamp(-1);
      await s.flushPush();
      expect(s.engineHealthy, isTrue);
    });

    test('reset goes flat and clears the effects but keeps the switch', () async {
      final (s, _) = await boot();
      await s.setEnabled(true);
      await s.selectPreset('rock');
      s.setPreamp(3);
      s.setBassBoost(0.5);
      await s.reset();
      expect(s.profile.gains.every((g) => g == 0), isTrue);
      expect(s.profile.preampDb, 0);
      expect(s.profile.bassBoost, 0);
      expect(s.profile.presetId, 'flat');
      expect(s.profile.enabled, isTrue);
    });

    test('pre-amp, loudness and strengths are clamped', () async {
      final (s, _) = await boot();
      s.setPreamp(40);
      expect(s.profile.preampDb, 12);
      s.setPreamp(-40);
      expect(s.profile.preampDb, -12);
      s.setLoudness(99);
      expect(s.profile.loudnessDb, 9);
      s.setLoudness(-3);
      expect(s.profile.loudnessDb, 0);
      s.setBassBoost(3);
      expect(s.profile.bassBoost, 1);
      s.setVirtualizer(-1);
      expect(s.profile.virtualizer, 0);
    });

    test('a 10-band device gets every preset resampled onto its own bands',
        () async {
      final ten = [
        for (final hz in kIsoHz)
          EqBand(centerHz: hz, lowHz: hz / 1.41, highHz: hz * 1.41)
      ];
      final (s, _) = await boot(
          caps: EqCapabilities(
              available: true, bands: ten, minDb: -12, maxDb: 12));
      await s.selectPreset('dance');
      expect(s.profile.gains.length, 10);
      expect(s.profile.gains.first, greaterThan(4));
    });

    test('listeners are told about changes', () async {
      final (s, _) = await boot();
      var n = 0;
      s.addListener(() => n++);
      await s.selectPreset('jazz');
      s.setPreamp(1);
      expect(n, 2);
    });
  });

  group('persistence', () {
    test('the profile, effects and saved presets survive a restart', () async {
      final (a, _) = await boot();
      await a.setEnabled(true);
      await a.selectPreset('jazz');
      a.setPreamp(-2);
      a.setBassBoost(0.4);
      a.saveUserPreset('Late set');
      await a.flushSave();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('eq_state_v2'), isNotNull);

      final fake = FakeEqPlatform();
      final b = EqualizerService.test(platform: fake);
      await b.initialize();
      expect(b.isEnabled, isTrue);
      expect(b.profile.preampDb, -2);
      expect(b.profile.bassBoost, 0.4);
      expect(b.userPresets.single.name, 'Late set');
      expect(b.currentPresetName, 'Late set');
    });

    test('the first version\'s three keys are carried over', () async {
      final (s, _) = await boot(prefs: {
        'eq_enabled': true,
        'eq_preset': 'rock',
      });
      expect(s.isEnabled, isTrue);
      expect(s.currentPresetId, 'rock');
      expect(s.profile.gains.length, 5);
    });

    test('old custom gains are resampled, old preset ids renamed', () async {
      final (s, _) = await boot(prefs: {
        'eq_enabled': true,
        'eq_preset': 'custom',
        'eq_custom_gains': ['6.0', '0.0', '0.0', '0.0', '-4.0'],
      });
      expect(s.currentPresetId, 'custom');
      expect(s.profile.gains.first, 6);
      expect(s.profile.gains.last, -4);

      final (t, _) = await boot(prefs: {'eq_preset': 'hiphop'});
      expect(t.currentPresetId, 'hip_hop');
    });

    test('damaged stored state starts clean rather than failing', () async {
      final (s, _) = await boot(prefs: {'eq_state_v2': '{broken'});
      expect(s.isEnabled, isFalse);
      expect(s.currentPresetId, 'flat');
    });
  });

  group('saved presets', () {
    test('save, reapply, rename and delete', () async {
      final (s, _) = await boot();
      await s.selectPreset('rock');
      final saved = s.saveUserPreset('  Gym  ');
      expect(saved.name, 'Gym');
      expect(s.currentPresetId, saved.presetId);

      await s.selectPreset('flat');
      expect(s.profile.gains.every((g) => g == 0), isTrue);
      await s.selectPreset(saved.presetId);
      expect(s.profile.gains.any((g) => g != 0), isTrue);

      s.renameUserPreset(saved.id, 'Gym 2');
      expect(s.currentPresetName, 'Gym 2');
      s.renameUserPreset(saved.id, '   ');
      expect(s.currentPresetName, 'Gym 2', reason: 'blank names are ignored');

      final before = List<double>.of(s.profile.gains);
      s.deleteUserPreset(saved.id);
      expect(s.userPresets, isEmpty);
      expect(s.currentPresetId, 'custom');
      expect(s.profile.gains, before, reason: 'the curve is kept');
    });

    test('an empty name still gets a name', () async {
      final (s, _) = await boot();
      expect(s.saveUserPreset('').name, 'My preset');
    });
  });

  group('per-output profiles', () {
    test('each output keeps its own curve', () async {
      final (s, _) = await boot();
      final out = _Out();
      s.bindOutput(out);
      await s.selectPreset('flat');
      await s.setPerOutput(true);

      out.set('bluetooth', 'Pixel Buds');
      expect(s.outputKey, 'bluetooth');
      expect(s.outputName, 'Pixel Buds');
      await s.selectPreset('bass_boost');
      expect(s.currentPresetId, 'bass_boost');

      out.set('speaker', 'This phone');
      expect(s.outputKey, 'speaker');
      expect(s.currentPresetId, 'flat', reason: 'the phone speaker was untouched');

      out.set('wired', 'Headphones');
      expect(s.currentPresetId, 'flat');

      out.set('bluetooth', 'Pixel Buds');
      expect(s.currentPresetId, 'bass_boost');
    });

    test('with it off, every output shares one profile', () async {
      final (s, _) = await boot();
      final out = _Out();
      s.bindOutput(out);
      out.set('bluetooth', 'Buds');
      await s.selectPreset('jazz');
      out.set('speaker', 'Phone');
      expect(s.currentPresetId, 'jazz');
    });

    test('turning it on changes nothing audible until you do', () async {
      final (s, _) = await boot();
      await s.selectPreset('pop');
      await s.setPerOutput(true);
      expect(s.currentPresetId, 'pop');
    });

    test('output kinds map to profile keys', () {
      expect(EqualizerService.outputKeyFor('bluetooth'), 'bluetooth');
      expect(EqualizerService.outputKeyFor('wired'), 'wired');
      expect(EqualizerService.outputKeyFor('usb'), 'wired');
      expect(EqualizerService.outputKeyFor('hdmi'), 'speaker');
      expect(EqualizerService.outputKeyFor('other'), 'speaker');
    });

    test('a route change re-pushes the profile in force', () async {
      final (s, fake) = await boot();
      final out = _Out();
      s.bindOutput(out);
      await s.setPerOutput(true);
      await s.setEnabled(true);
      s.reportSession('d', 5);
      out.set('speaker', 'Phone');
      await s.selectPreset('flat');
      await s.flushPush();
      out.set('bluetooth', 'Buds');
      await s.selectPreset('rock');
      await s.flushPush();
      final rock = fake.last!.levelsDb;
      out.set('speaker', 'Phone');
      await s.flushPush();
      expect(fake.last!.levelsDb, isNot(rock));
    });
  });

  group('legacy surface (the Material You screen)', () {
    test('the static API it reads still exists and makes sense', () {
      final presets = EqualizerService.presets;
      expect(presets.first.id, 'flat');
      expect(presets.first.bandGains, [0, 0, 0, 0, 0]);
      expect(presets.last.id, 'custom');
      expect(presets.every((p) => p.bandGains.length == 5), isTrue);
      expect(EqualizerService.bandCount, greaterThan(0));
      expect(EqualizerService.bandLabels.length, EqualizerService.bandCount);
    });

    test('selecting by an old id works', () async {
      final (s, _) = await boot();
      await s.selectPreset('hiphop');
      expect(s.currentPresetId, 'hip_hop');
      expect(s.currentBandGains.length, 5);
      expect(s.currentPreset.id, 'hip_hop');
    });
  });
}
