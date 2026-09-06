import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/lyrics/better_lyrics_provider.dart';

void main() {
  group('BetterLyricsProvider.parseTtml spacing and syllable parity', () {
    test('preserves spacing between word spans in TTML (prevents Oneteardropfrommyeye bug)', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div>
      <p begin="00:01.000" end="00:05.000">
        <span begin="00:01.000" end="00:01.500">One</span> <span begin="00:01.500" end="00:02.000">tear</span> <span begin="00:02.000" end="00:02.500">drop</span> <span begin="00:02.500" end="00:03.000">from</span> <span begin="00:03.000" end="00:03.500">my</span> <span begin="00:03.500" end="00:04.000">eye</span>
      </p>
    </div>
  </body>
</tt>
''';

      final entries = BetterLyricsProvider.parseTtml(ttml);
      expect(entries.length, 1);
      expect(entries.first.text, 'One tear drop from my eye');
      expect(entries.first.words?.length, 6);
      expect(entries.first.words?.map((w) => w.text).toList(), [
        'One', 'tear', 'drop', 'from', 'my', 'eye'
      ]);
    });

    test('preserves syllable concatenation within words while separating words', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div>
      <p begin="00:01.000" end="00:05.000">
        <span begin="00:01.000" end="00:01.400">Will</span> <span begin="00:01.400" end="00:01.800">ne</span><span begin="00:01.800" end="00:02.100">ver</span> <span begin="00:02.100" end="00:02.500">let</span> <span begin="00:02.500" end="00:02.800">you</span> <span begin="00:02.800" end="00:03.200">go</span>
      </p>
    </div>
  </body>
</tt>
''';

      final entries = BetterLyricsProvider.parseTtml(ttml);
      expect(entries.length, 1);
      expect(entries.first.text, 'Will never let you go');
      expect(entries.first.words?.length, 6);
      expect(entries.first.words?.map((w) => w.text).toList(), [
        'Will', 'ne', 'ver', 'let', 'you', 'go'
      ]);
    });

    test('unescapes XML entities in TTML lines and words', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div>
      <p begin="00:01.000" end="00:05.000">
        <span begin="00:01.000" end="00:01.500">I&apos;m</span> <span begin="00:01.500" end="00:02.000">drowning</span> <span begin="00:02.000" end="00:02.500">in</span> <span begin="00:02.500" end="00:03.000">&quot;the&quot;</span> <span begin="00:03.000" end="00:03.500">night</span>
      </p>
    </div>
  </body>
</tt>
''';

      final entries = BetterLyricsProvider.parseTtml(ttml);
      expect(entries.length, 1);
      expect(entries.first.text, 'I\'m drowning in "the" night');
      expect(entries.first.words?.first.text, "I'm");
    });

    test('handles trailing spaces inside span tags in TTML', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div>
      <p begin="00:01.000" end="00:05.000">
        <span begin="00:01.000" end="00:01.500">One </span><span begin="00:01.500" end="00:02.000">tear </span><span begin="00:02.000" end="00:02.500">drop </span>
      </p>
    </div>
  </body>
</tt>
''';

      final entries = BetterLyricsProvider.parseTtml(ttml);
      expect(entries.length, 1);
      expect(entries.first.text, 'One tear drop');
      expect(entries.first.words?.map((w) => w.text).toList(), [
        'One', 'tear', 'drop'
      ]);
    });

    test('handles background vocal wrappers and line breaks (<br/>) as spaces', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div>
      <p begin="00:01.000" end="00:05.000">
        <span begin="00:01.000" end="00:01.500">Hello</span><br/><span begin="00:01.500" end="00:02.000">World</span> <span ttm:role="x-bg"><span begin="00:02.000" end="00:02.500">(Echo)</span></span>
      </p>
    </div>
  </body>
</tt>
''';

      final entries = BetterLyricsProvider.parseTtml(ttml);
      expect(entries.length, 1);
      expect(entries.first.text, 'Hello World (Echo)');
    });
  });
}
