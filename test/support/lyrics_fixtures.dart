// Helpers shared by the lyric provider tests. Not a test itself.
//
// The fixtures in test/fixtures/lyrics/ are REAL responses captured from the
// live hosts on 2026-10-12 (see the capture list in the worker report), so a
// provider that passes against them parses what the hosts actually send rather
// than what someone remembered them sending.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:music_streaming_app/models/lyrics_entry.dart';

/// A captured response body, exactly as served.
String fixture(String name) =>
    File('test/fixtures/lyrics/$name').readAsStringSync();

/// A 200 carrying [body]. Bytes rather than a string, so non-Latin lyrics are
/// not squeezed through the latin-1 default `http.Response(String)` applies.
http.Response okBody(String body, {Map<String, String>? headers}) =>
    http.Response.bytes(utf8.encode(body), 200, headers: headers ?? const {});

http.Response status(int code) => http.Response('', code);

/// Whether line start times never go backwards.
bool isMonotonic(List<LyricsEntry> lines) {
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].timeMs < lines[i - 1].timeMs) return false;
  }
  return true;
}

/// The lines that carry text, which is what "sung" means for a test: the
/// optional empty head entry an LRC parse adds is not a lyric.
List<LyricsEntry> sung(List<LyricsEntry> lines) =>
    lines.where((l) => l.text.trim().isNotEmpty).toList();

/// Fraction of [lines] carrying word timing.
double wordSyncedShare(List<LyricsEntry> lines) {
  final s = sung(lines);
  if (s.isEmpty) return 0;
  return s.where((l) => l.isWordSynced).length / s.length;
}
