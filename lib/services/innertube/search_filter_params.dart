/// The InnerTube `search` endpoint's content-type filters.
///
/// These are protobuf blobs, base64-encoded and URL-escaped for the wire. The
/// important thing about them - and the thing that is invisible if you read them
/// as opaque strings - is that **the content type is encoded in the protobuf
/// field number, not in a value**:
///
/// ```text
///   08 01  ->  field 1  ->  songs
///   10 01  ->  field 2  ->  videos
///   18 01  ->  field 3  ->  albums
///   20 01  ->  field 4  ->  artists
///   28 01  ->  field 5  ->  playlists
/// ```
///
/// So a filter can look plausible, be well-formed base64, and still select a
/// completely different kind of content. That is not hypothetical: the albums
/// filter here shipped as field 11 (`58 01`) for a while, which is why the
/// Albums tab filled with artist profiles instead of albums. Nothing about the
/// string was malformed; it was simply the wrong field.
///
/// They live in one place, named, for two reasons: so the five tabs cannot drift
/// apart, and so `search_filter_params_test.dart` can decode each one and assert
/// the field number rather than trusting a literal that no reviewer can check by
/// eye.
abstract final class SearchFilterParams {
  const SearchFilterParams._();

  /// No `params` at all - YouTube Music's mixed page, which spreads results
  /// across songs, artists, albums and playlists.
  static const String all = '';

  static const String songs = 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D'; // field 1

  static const String videos = 'EgWKAQIQAWoKEAkQBRAKEAMQBA%3D%3D'; // field 2

  static const String albums = 'EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D'; // field 3

  static const String artists = 'EgWKAQIgAWoKEAkQBRAKEAMQBA%3D%3D'; // field 4

  static const String playlists = 'EgWKAQIoAWoKEAkQBRAKEAMQBA%3D%3D'; // field 5

  /// Every filter by name, so a test can walk them all.
  static const Map<String, String> byName = {
    'songs': songs,
    'videos': videos,
    'albums': albums,
    'artists': artists,
    'playlists': playlists,
  };
}
