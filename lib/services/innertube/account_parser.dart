import '../auth_models.dart';

/// Parsing of InnerTube's account endpoints.
///
/// Pure and separated from the transport so the response shapes can be pinned by
/// tests. Both parsers scan for a RENDERER by name rather than walking a fixed
/// path, because the two endpoints that return the channel list wrap the same
/// `accountItem` renderer in different envelopes, and the envelope is not the
/// part worth agreeing on.
class AccountParser {
  const AccountParser._();

  /// The signed-in viewer from `account/account_menu`.
  ///
  /// Not every client gets an `email` back - some answer with only the @handle -
  /// so the secondary line falls back rather than going blank.
  ///
  /// Returns null when there is no account header or no name. A response we
  /// cannot read is not an identity, and guessing one is how a session becomes a
  /// durable broken account.
  static AccountIdentity? parseIdentity(dynamic root) {
    final headers = _collect(root, 'activeAccountHeaderRenderer');
    if (headers.isEmpty) return null;

    for (final header in headers) {
      final name = _text(header['accountName']);
      if (name.isEmpty) continue;

      var email = _text(header['email']);
      if (email.isEmpty) email = _text(header['channelHandle']);

      return AccountIdentity(
        name: name,
        email: email,
        avatarUrl: _bestThumbnail(header['accountPhoto']),
      );
    }
    return null;
  }

  /// Every channel this session can act as, in the order YouTube lists them.
  ///
  /// [pageId] and [datasyncIdToken] are located BY KEY NAME anywhere inside the
  /// item rather than at a fixed path: they arrive inside `supportedTokens`, a
  /// list of single-key objects in no promised order, alongside tokens meant for
  /// other purposes. Reading that list positionally would be a guess about a
  /// structure Google never said was ordered.
  static List<AccountChannel> parseChannels(dynamic root) {
    final out = <AccountChannel>[];
    final seen = <String>{};

    for (final item in _collect(root, 'accountItem')) {
      final name = _text(item['accountName']);
      if (name.isEmpty) continue;

      final pageId =
          _findString(item, 'pageIdToken') ?? _findString(item, 'pageId');
      // `normalizeDataSyncId` answers '' for a blank input rather than null, so
      // the empty case has to be folded here or every "no usable tokens" check
      // below silently passes and we offer a channel we cannot act as.
      final normalizedSync = normalizeDataSyncId(
          _findString(item, 'datasyncIdToken') ?? _findString(item, 'dataSyncId'));
      final dataSyncId = normalizedSync.isEmpty ? null : normalizedSync;
      // Nothing to send for this entry, so it cannot be selected honestly.
      if (pageId == null && dataSyncId == null) continue;

      var subtitle = _text(item['channelHandle']);
      if (subtitle.isEmpty) subtitle = _text(item['accountByline']);

      final channel = AccountChannel(
        name: name,
        subtitle: subtitle,
        avatarUrl: _bestThumbnail(item['accountPhoto']),
        pageId: pageId,
        dataSyncId: dataSyncId,
        activeOnWeb: _isTrue(item['isSelected']),
      );

      if (seen.add(channel.key)) out.add(channel);
    }
    return out;
  }

  /// Depth-first search for every map that contains [rendererName].
  static List<Map<String, dynamic>> _collect(dynamic root, String rendererName) {
    final out = <Map<String, dynamic>>[];
    void walk(dynamic node) {
      if (node is Map) {
        for (final entry in node.entries) {
          final value = entry.value;
          if (entry.key == rendererName && value is Map) {
            out.add(value.cast<String, dynamic>());
          }
          walk(value);
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(root);
    return out;
  }

  /// First non-empty string value stored under [key] anywhere beneath [node].
  static String? _findString(dynamic node, String key) {
    String? found;
    void walk(dynamic current) {
      if (found != null) return;
      if (current is Map) {
        for (final entry in current.entries) {
          if (entry.key == key) {
            final value = entry.value;
            if (value is String && value.trim().isNotEmpty) {
              found = value.trim();
              return;
            }
            // A token can arrive as {"pageIdToken": "UC..."} rather than a bare
            // value, so descend into a match before giving up on it.
            walk(value);
          } else {
            walk(entry.value);
          }
        }
      } else if (current is List) {
        for (final item in current) {
          walk(item);
        }
      }
    }

    walk(node);
    return found;
  }

  /// Concatenate a `{runs: [...]}` or `{simpleText: "..."}` text node.
  static String _text(dynamic node) {
    if (node is! Map) return '';
    final map = node.cast<String, dynamic>();
    final runs = map['runs'];
    if (runs is List) {
      final buffer = StringBuffer();
      for (final run in runs) {
        if (run is Map) {
          final text = (run.cast<String, dynamic>()['text']);
          if (text is String) buffer.write(text);
        }
      }
      final joined = buffer.toString().trim();
      if (joined.isNotEmpty) return joined;
    }
    final simple = map['simpleText'];
    if (simple is String) return simple.trim();
    return '';
  }

  /// Largest thumbnail offered.
  ///
  /// Widths are not guaranteed to be present, so the last entry is preferred
  /// when they are missing: YouTube orders thumbnails ascending.
  static String? _bestThumbnail(dynamic node) {
    if (node is! Map) return null;
    final thumbnails = node.cast<String, dynamic>()['thumbnails'];
    if (thumbnails is! List) return null;

    String? bestUrl;
    var bestWidth = -1;
    for (final entry in thumbnails) {
      if (entry is! Map) continue;
      final url = (entry.cast<String, dynamic>()['url']);
      if (url is! String || url.isEmpty) continue;
      final width = entry.cast<String, dynamic>()['width'];
      final numeric = width is num ? width.toInt() : -1;
      if (numeric >= bestWidth) {
        bestWidth = numeric;
        bestUrl = url;
      }
    }
    return bestUrl;
  }

  static bool _isTrue(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }
}