import 'package:dearmusic/src/models/playlist_models.dart';
import 'package:get_storage/get_storage.dart';
import 'package:on_audio_query/on_audio_query.dart';

class PlaylistStore {
  static final PlaylistStore I = PlaylistStore._();

  PlaylistStore._();

  final _box = GetStorage();

  static const _kIndex = 'dm_playlists';

  static String _kItem(String id) => 'dm_playlist_$id';

  Future<List<Playlist>> listPlaylists() async {
    final ids = (_box.read<List>(_kIndex) ?? []).cast<String>();
    final out = <Playlist>[];
    for (final id in ids) {
      final j = _box.read<Map>(_kItem(id))?.cast<String, dynamic>();
      if (j != null) out.add(Playlist.fromJson(j));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> savePlaylist(Playlist pl) async {
    final ids = (_box.read<List>(_kIndex) ?? []).cast<String>();
    if (!ids.contains(pl.id)) {
      ids.add(pl.id);
      await _box.write(_kIndex, ids);
    }
    await _box.write(_kItem(pl.id), pl.toJson());
  }

  Future<void> deletePlaylist(String id) async {
    final ids = (_box.read<List>(_kIndex) ?? []).cast<String>();
    ids.remove(id);
    await _box.write(_kIndex, ids);
    await _box.remove(_kItem(id));
  }

  Future<List<SongModel>> getSongsFor(
    Playlist pl, {
    required OnAudioQuery query,
  }) async {
    final all = await query.querySongs();
    final byId = {for (final s in all) s.id: s};
    final picked = <SongModel>[];
    for (final id in pl.songIds) {
      final s = byId[id];
      if (s != null && s.uri != null) picked.add(s);
    }
    return picked;
  }
}
