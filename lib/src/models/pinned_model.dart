import 'package:on_audio_query/on_audio_query.dart';

enum PinKind { song, album, artist }

class PinnedAny {
  final PinKind kind;
  final int id;
  final String title;
  final String? subtitle;
  final int artworkId;
  final ArtworkType artworkType;

  PinnedAny({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    required this.artworkId,
    required this.artworkType,
  });

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'artworkId': artworkId,
    'artworkType': artworkType.name,
  };

  static PinnedAny fromJson(Map<String, dynamic> m) {
    final k = PinKind.values.firstWhere(
      (e) => e.name == m['kind'],
      orElse: () => PinKind.song,
    );
    final at = ArtworkType.values.firstWhere(
      (e) => e.name == m['artworkType'],
      orElse: () => ArtworkType.AUDIO,
    );
    return PinnedAny(
      kind: k,
      id: m['id'] as int,
      title: (m['title'] as String?) ?? 'Unknown',
      subtitle: m['subtitle'] as String?,
      artworkId: (m['artworkId'] as int?) ?? (m['id'] as int),
      artworkType: at,
    );
  }
}

class PinnedSnapshot {
  final int id;
  final String? title;
  final String? artist;
  final String? uri;

  PinnedSnapshot({required this.id, this.title, this.artist, this.uri});

  factory PinnedSnapshot.fromSong(SongModel s) => PinnedSnapshot(
    id: s.id,
    title: s.title,
    artist: s.artist,
    uri: s.uri?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'uri': uri,
  };

  factory PinnedSnapshot.fromJson(Map<String, dynamic> j) => PinnedSnapshot(
    id: j['id'] as int,
    title: j['title'] as String?,
    artist: j['artist'] as String?,
    uri: j['uri'] as String?,
  );
}
