import 'track.dart';

class Playlist {
  final String id;
  final String name;
  final String imageUrl;
  final List<Track> tracks;

  /// Optional free text shown under the title.
  final String description;

  /// Epoch milliseconds. Null for playlists saved before these were recorded
  /// ([created] then falls back to the time baked into a `pl_<ms>` id).
  final int? createdAtMs;
  final int? updatedAtMs;

  /// Pinned playlists sort first.
  final bool pinned;

  /// Position in the listener's own ordering (Sort > Custom). Null = unplaced.
  final int? customOrder;

  Playlist({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.tracks,
    this.description = '',
    this.createdAtMs,
    this.updatedAtMs,
    this.pinned = false,
    this.customOrder,
  });

  /// Made in this app (`pl_<ms>` ids). Everything else was imported.
  bool get isUserCreated => id.startsWith('pl_');

  /// When the playlist was made, if that can be known.
  DateTime? get created {
    final ms = createdAtMs ?? int.tryParse(id.startsWith('pl_') ? id.substring(3) : '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// When it last changed, if known. A playlist saved before changes were
  /// stamped reports when it was created, and nothing is invented beyond that.
  DateTime? get updated {
    final ms = updatedAtMs;
    return ms == null ? created : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Playlist copyWith({
    String? id,
    String? name,
    String? imageUrl,
    List<Track>? tracks,
    String? description,
    int? createdAtMs,
    int? updatedAtMs,
    bool? pinned,
    int? customOrder,
    bool clearCustomOrder = false,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      tracks: tracks ?? this.tracks,
      description: description ?? this.description,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      pinned: pinned ?? this.pinned,
      customOrder: clearCustomOrder ? null : (customOrder ?? this.customOrder),
    );
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      imageUrl: json['imageUrl'] ?? '',
      tracks: (json['tracks'] as List)
          .map((trackJson) => Track.fromJson(trackJson))
          .toList(),
      description: json['description'] as String? ?? '',
      createdAtMs: json['createdAt'] as int?,
      updatedAtMs: json['updatedAt'] as int?,
      pinned: json['pinned'] as bool? ?? false,
      customOrder: json['order'] as int?,
    );
  }

  /// New fields are written only when set, so a file saved here still loads in
  /// an older build.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      'tracks': tracks.map((track) => track.toJson()).toList(),
      if (description.isNotEmpty) 'description': description,
      if (createdAtMs != null) 'createdAt': createdAtMs,
      if (updatedAtMs != null) 'updatedAt': updatedAtMs,
      if (pinned) 'pinned': true,
      if (customOrder != null) 'order': customOrder,
    };
  }
}
