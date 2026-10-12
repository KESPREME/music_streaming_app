// lib/services/lyrics/lyrics_url.dart
// Query-string building for the lyric providers.

/// [base] with [params] appended, percent-encoded the way OkHttp does it.
///
/// `Uri.replace(queryParameters:)` writes a space as `+`, which every host here
/// happens to decode, but `%20` is understood by all of them without having to
/// know that, and it is what the reference client sends. Blank values are
/// kept; deciding which parameters to send is the caller's business.
String buildLyricsUrl(String base, Map<String, String> params) {
  if (params.isEmpty) return base;
  final query = params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return '$base${base.contains('?') ? '&' : '?'}$query';
}
