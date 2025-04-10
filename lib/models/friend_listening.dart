class FriendListening {
  final String friendName;
  final String trackName;
  final String artistName;

  FriendListening({
    required this.friendName,
    required this.trackName,
    required this.artistName,
  });

  factory FriendListening.fromJson(Map<String, dynamic> json) {
    return FriendListening(
      friendName: json['friendName'] ?? 'Unknown',
      trackName: json['trackName'] ?? 'Unknown Track',
      artistName: json['artistName'] ?? 'Unknown Artist',
    );
  }
}