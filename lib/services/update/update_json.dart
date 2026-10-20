// lib/services/update/update_json.dart
//
// Tolerant readers for JSON that comes from outside the app (a GitHub API
// response, an `update.json` asset, our own cached copy of either).
//
// Every reader answers "what is it, or null" instead of throwing. The update
// path must never take the app down because a release author typed a string
// where a number belongs, so the model code reads through these and decides for
// itself what a missing or malformed field means.

/// Lone surrogate halves, which are not valid UTF-16. Flutter's text engine
/// throws on them ("string is not well-formed UTF-16"), so a release note that
/// carries one would crash the screen that shows it.
final RegExp _loneSurrogate = RegExp(
  r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
);

/// [s] with any lone surrogate replaced by U+FFFD.
String sanitizeText(String s) =>
    _loneSurrogate.hasMatch(s) ? s.replaceAll(_loneSurrogate, '\uFFFD') : s;

/// A trimmed, sanitised, non-empty string - or null.
String? asTrimmed(Object? v) {
  if (v is! String) return null;
  final s = sanitizeText(v.trim());
  return s.isEmpty ? null : s;
}

int? asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.toInt() : null;
  if (v is String) return int.tryParse(v.trim());
  return null;
}

bool? asBool(Object? v) => v is bool ? v : null;

/// Any JSON object, with its keys forced to strings.
Map<String, dynamic>? asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return {for (final e in v.entries) e.key.toString(): e.value};
  return null;
}

List<Object?> asList(Object? v) => v is List ? v : const <Object?>[];

/// The non-empty strings of a JSON array, trimmed.
List<String> asStringList(Object? v) => [
      for (final e in asList(v))
        if (asTrimmed(e) case final s?) s,
    ];

/// An ISO-8601 timestamp as UTC, or null.
DateTime? asDate(Object? v) {
  final s = asTrimmed(v);
  if (s == null) return null;
  return DateTime.tryParse(s)?.toUtc();
}

/// [v] when it is an absolute `https://` URL with a host, else null.
///
/// An update is a native executable; it only ever comes over TLS.
String? asHttpsUrl(Object? v) {
  final s = asTrimmed(v);
  if (s == null) return null;
  final uri = Uri.tryParse(s);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return s;
}

final RegExp _sha256Exact = RegExp(r'^[a-f0-9]{64}$');

/// A lower-case 64-hex SHA-256, from `<hex>` or `sha256:<hex>`; else null.
String? normalizeSha256(Object? v) {
  final raw = asTrimmed(v);
  if (raw == null) return null;
  var s = raw.toLowerCase();
  if (s.startsWith('sha256:')) s = s.substring(7);
  return _sha256Exact.hasMatch(s) ? s : null;
}

final RegExp _sha256Anywhere = RegExp(r'(?<![a-fA-F0-9])[a-fA-F0-9]{64}(?![a-fA-F0-9])');

/// The first 64-hex run in [text] (the `<hex>  <filename>` of a `.sha256`
/// file), lower-cased; else null.
String? firstSha256In(String text) =>
    _sha256Anywhere.firstMatch(text)?.group(0)?.toLowerCase();
