// import 'package:equatable/equatable.dart'; // Commented out

class UserModel { // Removed "extends Equatable"
  final String id;
  final String name;
  final String? avatarUrl;
  final String? currentTrackName;
  final String? currentTrackArtist;

  const UserModel({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.currentTrackName,
    this.currentTrackArtist,
  });

  // @override
  // List<Object?> get props => [id, name, avatarUrl, currentTrackName, currentTrackArtist]; // Commented out

  // Factory constructor for creating a new UserModel instance from a map
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String,
      name: map['name'] as String,
      avatarUrl: map['avatarUrl'] as String?,
      currentTrackName: map['currentTrackName'] as String?,
      currentTrackArtist: map['currentTrackArtist'] as String?,
    );
  }

  // Method for converting a UserModel instance to a map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'currentTrackName': currentTrackName,
      'currentTrackArtist': currentTrackArtist,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? currentTrackName,
    String? currentTrackArtist,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      currentTrackName: currentTrackName ?? this.currentTrackName,
      currentTrackArtist: currentTrackArtist ?? this.currentTrackArtist,
    );
  }
}
