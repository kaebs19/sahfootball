class LeaderboardEntry {
  final int rank;
  final String userId; // uuid
  final String displayName;
  final String? avatarUrl;
  final String? favoriteTeamLogo;
  final int totalPoints;
  final int settledPredictions;

  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.favoriteTeamLogo,
    required this.totalPoints,
    required this.settledPredictions,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        rank: json['rank'] as int,
        userId: json['user_id'] as String,
        displayName: (json['display_name'] ?? 'مشجع') as String,
        avatarUrl: json['avatar_url'] as String?,
        favoriteTeamLogo: json['favorite_team_logo'] as String?,
        totalPoints: json['total_points'] as int,
        settledPredictions: json['settled_predictions'] as int,
      );
}
