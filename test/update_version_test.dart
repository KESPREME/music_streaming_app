import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/update/update_models.dart';
import 'package:music_streaming_app/services/update/version_compare.dart';

/// UPDATES: "is that release newer than what I run?" Pure, table-driven, and
/// never throws - the inputs are an OS versionName and a free-form git tag.

ReleaseInfo _release(String version, int build) =>
    ReleaseInfo(version: version, build: build, tag: 'v$version+$build');

void main() {
  group('AppVersion.parse', () {
    // input, major, minor, patch, preRelease, build
    final table = <(String, int, int, int, List<String>, int)>[
      ('1.2.3', 1, 2, 3, [], 0),
      ('v1.2.3', 1, 2, 3, [], 0),
      ('V2', 2, 0, 0, [], 0),
      ('1', 1, 0, 0, [], 0),
      ('1.2', 1, 2, 0, [], 0),
      ('1.2.3+45', 1, 2, 3, [], 45),
      ('v1.1.0+142', 1, 1, 0, [], 142),
      ('1.2.3-beta.2+45', 1, 2, 3, ['beta', '2'], 45),
      ('v1.2.0-beta.1+150', 1, 2, 0, ['beta', '1'], 150),
      ('1.2.3-b45', 1, 2, 3, [], 45),
      ('v1.1.0-b142', 1, 1, 0, [], 142),
      ('1.2.3-beta.2-b45', 1, 2, 3, ['beta', '2'], 45),
      ('1.2.3-RC.1', 1, 2, 3, ['rc', '1'], 0),
      ('  1.2.3  ', 1, 2, 3, [], 0),
      ('1.2.3.4', 1, 2, 3, [], 0), // a 4th segment is ignored
      ('1.x.3', 1, 0, 3, [], 0),
      ('1.2.3+', 1, 2, 3, [], 0),
      ('1.2.3-', 1, 2, 3, [], 0),
      ('', 0, 0, 0, [], 0),
      ('abc', 0, 0, 0, [], 0),
      ('v', 0, 0, 0, [], 0),
      ('version', 0, 0, 0, [], 0),
      ('99999999999999999999.0.0', 999999999, 0, 0, [], 0),
      ('\u{1F680}.\u{1F680}', 0, 0, 0, [], 0),
    ];

    for (final (input, major, minor, patch, pre, build) in table) {
      test('"$input"', () {
        final v = AppVersion.parse(input);
        // Lists have no value equality, so they are compared on their own.
        expect((v.major, v.minor, v.patch, v.build), (major, minor, patch, build));
        expect(v.preRelease, pre);
      });
    }

    test('never throws on hostile input', () {
      final inputs = <String>[
        '+',
        '-',
        '++--',
        '...',
        '1..2..3',
        '-b',
        '+-+-',
        'v-1',
        '\u0000\u0001',
        String.fromCharCodes([0xD800, 0x31]),
        'x' * 100000,
        '9' * 100000,
        '1.2.3-${'a.' * 5000}',
      ];
      for (final s in inputs) {
        expect(() => AppVersion.parse(s), returnsNormally, reason: s.length > 20 ? 'long' : s);
      }
    });

    test('name drops the build and keeps the pre-release', () {
      expect(AppVersion.parse('v1.2.0-beta.1+150').name, '1.2.0-beta.1');
      expect(AppVersion.parse('1.2').name, '1.2.0');
      expect(AppVersion.parse('1.2.3+4').toString(), '1.2.3+4');
    });

    test('isZero is true only when nothing could be read', () {
      expect(AppVersion.parse('').isZero, isTrue);
      expect(AppVersion.parse('0.0.0').isZero, isTrue);
      expect(AppVersion.parse('0.0.1').isZero, isFalse);
      expect(AppVersion.parse('0.0.0+1').isZero, isFalse);
    });
  });

  group('AppVersion.compareTo', () {
    // a, b, expected sign of a.compareTo(b)
    final table = <(String, String, int)>[
      ('1.10.0', '1.9.0', 1), // numeric, not lexical
      ('1.9.0', '1.10.0', -1),
      ('2.0.0', '1.99.99', 1),
      ('1.0.0', '1', 0),
      ('1.2', '1.2.0', 0),
      ('1.2.3+143', '1.2.3+142', 1), // a rebuild of the same name is an update
      ('1.2.3+142', '1.2.3+142', 0),
      ('1.0.0+1', '1.0.0', 1), // a missing build is 0
      ('1.2.0-beta.1', '1.2.0', -1), // pre-release < release
      ('1.2.0-beta.1+999', '1.2.0+1', -1), // ... whatever the build
      ('1.2.0-beta.2', '1.2.0-beta.10', -1), // numeric identifiers
      ('1.2.0-alpha', '1.2.0-beta', -1),
      ('1.2.0-beta', '1.2.0-beta.1', -1), // shorter loses a tie
      ('1.2.0-1', '1.2.0-alpha', -1), // numeric below alphanumeric
      ('1.2.0-rc.1+5', '1.2.0-rc.1+4', 1),
      ('1.2.0-beta.1', '1.1.9', 1), // numbers first
      ('0.0.0', '0.0.1', -1),
      ('0.0.0', '0.0.0', 0),
      ('1.2.0-02', '1.2.0-2', 0), // leading zeros do not matter
    ];

    for (final (a, b, sign) in table) {
      test('$a vs $b -> $sign', () {
        final r = AppVersion.parse(a).compareTo(AppVersion.parse(b));
        expect(r.sign, sign);
        // And the mirror image.
        expect(AppVersion.parse(b).compareTo(AppVersion.parse(a)).sign, -sign);
      });
    }

    test('is a consistent total order', () {
      final ordered = [
        '0.0.0',
        '0.9.0',
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-beta.2',
        '1.0.0-beta.11',
        '1.0.0-rc.1',
        '1.0.0',
        '1.0.0+5',
        '1.0.1',
        '1.9.0',
        '1.10.0',
        '2.0.0',
      ].map(AppVersion.parse).toList();

      for (var i = 0; i < ordered.length; i++) {
        for (var j = 0; j < ordered.length; j++) {
          expect(ordered[i].compareTo(ordered[j]).sign, i.compareTo(j).sign,
              reason: '${ordered[i]} vs ${ordered[j]}');
        }
      }

      final shuffled = [...ordered]..shuffle();
      shuffled.sort();
      expect(shuffled, ordered);
    });

    test('equality follows comparison', () {
      expect(AppVersion.parse('1'), AppVersion.parse('v1.0.0'));
      expect(AppVersion.parse('1').hashCode, AppVersion.parse('v1.0.0').hashCode);
      expect(AppVersion.parse('1.0.0'), isNot(AppVersion.parse('1.0.0+1')));
    });
  });

  group('isNewerRelease', () {
    // installed name, installed build, release version, release build, newer?
    final table = <(String, int, String, int, bool)>[
      ('1.1.0', 142, '1.1.0', 143, true), // higher build, same name
      ('1.1.0', 142, '1.1.0', 142, false), // identical
      ('1.1.0', 143, '1.1.0', 142, false), // we are ahead
      ('1.1.0', 142, '1.2.0', 1, true), // higher name beats a lower build
      ('1.2.0', 1, '1.1.0', 999, false), // lower name never wins on build
      ('1.9.0', 10, '1.10.0', 1, true),
      ('0.0.0', 0, '0.0.1', 1, true), // unknown install is older than anything
      ('0.0.0', 0, '1.0.0', 0, true),
      ('0.0.0', 0, '0.0.0', 0, false), // nothing to compare
      ('1.2.0-beta.1', 150, '1.2.0', 151, true), // beta -> stable
      ('1.2.0-beta.1', 150, '1.2.0', 1, true), // ... even with a lower build
      ('1.2.0', 151, '1.2.0-beta.2', 152, false), // stable never "updates" to a beta
      ('1.2.0-beta.1', 150, '1.2.0-beta.2', 151, true),
      ('1.2.0-beta.2', 151, '1.2.0-beta.2', 151, false),
      ('garbage', 0, '1.0.0', 1, true),
      ('1.0.0', 1, 'garbage', 99, false),
      ('1.1.0+142', 0, '1.1.0', 142, false), // build carried in the name
      ('1.1.0+142', 0, '1.1.0', 143, true),
      ('1.1.0', 0, '1.1.0', 0, false),
    ];

    for (final (iName, iBuild, rName, rBuild, newer) in table) {
      test('$iName+$iBuild -> $rName+$rBuild is ${newer ? 'an update' : 'not an update'}', () {
        expect(
          isNewerRelease(
            installedName: iName,
            installedBuild: iBuild,
            release: _release(rName, rBuild),
          ),
          newer,
        );
      });
    }
  });
}
