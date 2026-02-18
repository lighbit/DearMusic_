import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:dearmusic/src/player_scope.dart';
import 'package:dearmusic/src/logic/usage_tracker.dart';

class PlayActions {
  PlayActions._();

  static Future<void> playNowSong(BuildContext context, SongModel s) async {
    HapticFeedback.lightImpact();
    final uri = s.uri;
    if (uri == null) return;

    final ctrl = PlayerScope.of(context);

    await ctrl.playUri(
      uri,
      title: s.title,
      artist: s.artist,
      artworkId: s.albumId ?? s.id,
      artworkType: (s.albumId != null && s.albumId! > 0)
          ? ArtworkType.ALBUM
          : ArtworkType.AUDIO,
      filePath: s.data,
      duration: s.duration,
      genre: s.genre,
    );

    await UsageTracker.instance.logFromSong(s);
  }

  static Future<void> playQueue(
    BuildContext context,
    List<SongModel> songs, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    if (songs.isEmpty) return;
    final ctrl = PlayerScope.of(context);
    await ctrl.playQueue(songs, startIndex: startIndex, shuffle: shuffle);
    final start = songs[startIndex];
    await UsageTracker.instance.logFromSong(start);
  }

  static Future<void> enqueue(
    BuildContext context,
    List<SongModel> songs,
  ) async {
    if (songs.isEmpty) return;
    final withUri = songs.where((s) => s.uri != null).toList();
    if (withUri.isEmpty) return;
    final ctrl = PlayerScope.of(context);
    await ctrl.enqueue(withUri);
  }

  static Future<void> enqueueOne(BuildContext context, SongModel s) async {
    HapticFeedback.lightImpact();
    final uri = s.uri;
    if (uri == null) return;
    final ctrl = PlayerScope.of(context);
    await ctrl.enqueue([s]);
  }
}
