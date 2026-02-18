import 'package:on_audio_query/on_audio_query.dart';

List<SongModel> diverseSongs(List<SongModel> input, {required int target}) {
  if (input.isEmpty || target <= 0) return const <SongModel>[];
  final rnd = List<SongModel>.from(input);
  rnd.shuffle();

  final out = <SongModel>[];
  final seenArtist = <String, int>{};
  final seenAlbum = <int?, int>{};

  for (final s in rnd) {
    final artistKey = norm(s.artist);
    final albumKey = s.albumId;
    final canArtist = (seenArtist[artistKey] ?? 0) < 1;
    final canAlbum = (seenAlbum[albumKey] ?? 0) < 1;
    if (canArtist && canAlbum && s.uri?.isNotEmpty == true) {
      out.add(s);
      seenArtist[artistKey] = (seenArtist[artistKey] ?? 0) + 1;
      seenAlbum[albumKey] = (seenAlbum[albumKey] ?? 0) + 1;
      if (out.length >= target) break;
    }
  }

  if (out.length < target) {
    for (final s in rnd) {
      if (out.any((x) => x.id == s.id)) continue;
      if (s.uri?.isNotEmpty != true) continue;
      out.add(s);
      if (out.length >= target) break;
    }
  }

  return out;
}

String norm(String? s) => (s ?? '').trim().toLowerCase();

String songKey(SongModel s) =>
    '${norm(s.title)}|${norm(s.artist)}|${s.duration ?? 0}';

String albumKey(AlbumModel a) => '${norm(a.album)}|${norm(a.artist)}';

String artistKey(ArtistModel a) => norm(a.artist);

List<T> dedupeByKey<T>(Iterable<T> items, String Function(T) keyOf) {
  final seen = <String>{};
  final out = <T>[];
  for (final x in items) {
    final k = keyOf(x);
    if (seen.add(k)) out.add(x);
  }
  return out;
}
