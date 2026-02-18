class WrappedStats {
  final int librarySize;
  final int totalPlays;
  final int totalSkips;
  final int uniqueSongsPlayed;
  final int uniqueArtistsPlayed;
  final int discoveryCount;
  final double avgCompletionRate;
  final int listenMs;
  final Map<int, int> topSongs;
  final Map<String, int> topArtists;
  final Map<int, int> topAlbums;
  final Map<String, int> topGenres;
  final List<int> mostSkippedSongIds;
  final Map<int, int> hourHistogram;
  final Map<String, int> dowHistogram;
  final int firstPlayTs;
  final int lastPlayTs;

  const WrappedStats({
    required this.librarySize,
    required this.totalPlays,
    required this.totalSkips,
    required this.uniqueSongsPlayed,
    required this.uniqueArtistsPlayed,
    required this.discoveryCount,
    required this.avgCompletionRate,
    required this.listenMs,
    required this.topSongs,
    required this.topArtists,
    required this.topAlbums,
    required this.topGenres,
    required this.mostSkippedSongIds,
    required this.hourHistogram,
    required this.dowHistogram,
    required this.firstPlayTs,
    required this.lastPlayTs,
  });

  Map<String, dynamic> toJson() => {
    'librarySize': librarySize,
    'totalPlays': totalPlays,
    'totalSkips': totalSkips,
    'uniqueSongsPlayed': uniqueSongsPlayed,
    'uniqueArtistsPlayed': uniqueArtistsPlayed,
    'discoveryCount': discoveryCount,
    'avgCompletionRate': avgCompletionRate,
    'listenMs': listenMs,
    'topSongs': topSongs,
    'topArtists': topArtists,
    'topAlbums': topAlbums,
    'topGenres': topGenres,
    'mostSkippedSongIds': mostSkippedSongIds,
    'hourHistogram': hourHistogram,
    'dowHistogram': dowHistogram,
    'firstPlayTs': firstPlayTs,
    'lastPlayTs': lastPlayTs,
  };
}
