import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/services/innertube/search_filter_params.dart';

/// These filters are protobuf blobs in which the **content type is the field
/// number**, not a value:
///
/// ```text
///   08 01 -> field 1  songs
///   10 01 -> field 2  videos
///   18 01 -> field 3  albums
///   20 01 -> field 4  artists
///   28 01 -> field 5  playlists
/// ```
///
/// So a wrong filter is indistinguishable from a right one by eye: it is valid
/// base64, well-formed protobuf, and simply selects different content. The
/// Albums tab shipped field 11 for a while, which is why it filled with artist
/// profiles. Asserting the literal string would not have caught that, and would
/// not catch it again. Asserting the decoded field number does.
void main() {
  /// The content-type field number out of a filter, decoded rather than compared.
  ///
  /// Walks the blob: outer field 2 (the filter) holds one length-delimited
  /// message, which in turn holds a single varint whose *tag* is the type.
  int? filterFieldNumber(String wireValue) {
    final bytes = base64.decode(Uri.decodeComponent(wireValue));

    var i = 0;
    int readVarint() {
      var result = 0;
      var shift = 0;
      while (i < bytes.length) {
        final byte = bytes[i++];
        result |= (byte & 0x7F) << shift;
        if (byte & 0x80 == 0) break;
        shift += 7;
      }
      return result;
    }

    // field 2, wire type 2 (length-delimited): the SearchFilter message.
    expect(readVarint(), 0x12, reason: 'expected outer field 2');
    readVarint(); // length

    // A nested message; its first tag byte encodes the content type.
    expect(readVarint(), 0x8A, reason: 'expected the nested content field');
    readVarint(); // length

    final tag = readVarint();
    expect(tag & 0x07, 0, reason: 'content field must be a varint');
    return tag >> 3;
  }

  test('every filter selects the field its name claims', () {
    const expected = {
      'songs': 1,
      'videos': 2,
      'albums': 3,
      'artists': 4,
      'playlists': 5,
    };

    expected.forEach((name, field) {
      final actual = filterFieldNumber(SearchFilterParams.byName[name]!);
      expect(actual, field,
          reason: '$name must select field $field, not $actual');
    });
  });

  test('albums is field 3 - the regression that filled the tab with profiles',
      () {
    // Spelled out separately from the table above so that changing the table
    // and this test together cannot hide the original bug.
    expect(filterFieldNumber(SearchFilterParams.albums), 3);
  });

  test('the blob that shipped is field 11, and field 11 is not albums', () {
    // Pinning the failure itself, not just the fix. This is the exact value the
    // Albums tab carried, and it decodes to a content type with nothing to do
    // with albums. If it is ever reintroduced - by copying an old build, or by
    // "correcting" the value to something that merely looks plausible - this
    // says why that is wrong.
    const shipped = 'EgWKAQJYAWoKEAkQBRAKEAMQBA%3D%3D';
    expect(filterFieldNumber(shipped), 11);
    expect(filterFieldNumber(shipped), isNot(3));
  });

  test('no two filters select the same content type', () {
    final fields =
        SearchFilterParams.byName.values.map(filterFieldNumber).toSet();
    expect(fields.length, SearchFilterParams.byName.length,
        reason: 'a duplicate field number means two tabs show the same kind of '
            'content');
  });

  test('every filter is valid, URL-escaped base64', () {
    for (final entry in SearchFilterParams.byName.entries) {
      // No raw '=' survives: the value goes into a JSON body as a query-style
      // parameter, so the padding has to stay percent-encoded.
      expect(entry.value.contains('='), isFalse,
          reason: '${entry.key} has unescaped base64 padding');
      expect(entry.value.contains('%3D'), isTrue,
          reason: '${entry.key} is missing escaped padding');
      expect(() => base64.decode(Uri.decodeComponent(entry.value)),
          returnsNormally,
          reason: '${entry.key} does not decode');
    }
  });

  test('the unfiltered page sends no params at all', () {
    // An empty string is the signal; a placeholder blob here would silently
    // turn the mixed "All" tab into a filtered one.
    expect(SearchFilterParams.all, isEmpty);
  });
}
