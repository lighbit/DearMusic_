class Playlist {
  final String id;
  final String name;
  final List<int> songIds;
  final DateTime createdAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    required this.createdAt,
  });

  Playlist copyWith({String? name, List<int>? songIds}) => Playlist(
    id: id,
    name: name ?? this.name,
    songIds: songIds ?? this.songIds,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songIds': songIds,
    'createdAt': createdAt.toIso8601String(),
  };

  static Playlist fromJson(Map<String, dynamic> j) => Playlist(
    id: j['id'] as String,
    name: j['name'] as String,
    songIds: (j['songIds'] as List).cast<int>(),
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}
