import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:dearmusic/src/models/playlist_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:on_audio_query/on_audio_query.dart';

class PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final OnAudioQuery query;
  final VoidCallback onOpen;
  final VoidCallback? onMore;

  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.query,
    required this.onOpen,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final brightness = Theme.of(context).brightness;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        HapticFeedback.lightImpact();
        onOpen();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _Cover(playlist: playlist, query: query),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 6, top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${playlist.songIds.length} lagu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onMore != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onMore!();
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, top: 2),
                      child: Icon(
                        Icons.more_vert_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final Playlist playlist;
  final OnAudioQuery query;

  const _Cover({required this.playlist, required this.query});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget emptyState() {
      final tt = Theme.of(context).textTheme;
      return Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_rounded,
              color: cs.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              'Playlist masih kosong',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tambahkan lagu favoritmu di sini.',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 12.sp,
              ),
            ),
          ],
        ),
      );
    }

    if (playlist.songIds.isEmpty) {
      return emptyState();
    }

    return FutureBuilder<List<SongModel>>(
      future: query.querySongs(),
      builder: (_, snap) {
        final list = snap.data;
        if (list == null) {
          return emptyState();
        }

        final byId = {for (final s in list) s.id: s};

        final albumIds = <int>[];
        for (final sid in playlist.songIds) {
          final s = byId[sid];
          final a = s?.albumId;
          if (a != null && !albumIds.contains(a)) {
            albumIds.add(a);
            if (albumIds.length == 4) break;
          }
        }

        if (albumIds.isEmpty) {
          return emptyState();
        }

        return _MosaicCover(albumIds: albumIds, colorScheme: cs);
      },
    );
  }
}

class _MosaicCover extends StatelessWidget {
  final List<int> albumIds;
  final ColorScheme colorScheme;

  const _MosaicCover({required this.albumIds, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final ids = albumIds;

    Widget artwork(int id) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FutureBuilder<Widget>(
          future: ArtworkMemCache.I.imageWidget(
            id: id,
            type: ArtworkType.ALBUM,
            slot: ArtworkSlot.gridSmall,
            radius: BorderRadius.circular(12),
            placeholder: Container(
              color: colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Icon(
                Icons.music_note_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          builder: (_, snap) => snap.data ?? SizedBox.expand(),
        ),
      );
    }

    Widget artwork2(int id) {
      return LayoutBuilder(
        builder: (ctx, cons) {
          final dpr = MediaQuery.of(ctx).devicePixelRatio;
          final px = (cons.maxWidth * dpr).clamp(256, 2048).round();

          return QueryArtworkWidget(
            id: id,
            type: ArtworkType.ALBUM,
            size: px,
            quality: 10,
            artworkFit: BoxFit.cover,
            artworkClipBehavior: Clip.hardEdge,
            nullArtworkWidget: Container(
              color: colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Icon(
                Icons.headphones_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
          );
        },
      );
    }

    if (ids.length == 1) {
      return artwork(ids[0]);
    }

    if (ids.length == 2) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(children: [Expanded(child: artwork(ids[0]))]),
          Row(children: [Expanded(child: artwork(ids[1]))]),
        ],
      );
    }

    final cells = [
      for (int i = 0; i < 4; i++)
        if (i < ids.length) artwork2(ids[i]) else _placeholder(),
    ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          children: [
            Expanded(child: cells[0]),
            const SizedBox(width: 3),
            Expanded(child: cells[1]),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(child: cells[2]),
            const SizedBox(width: 3),
            Expanded(child: cells[3]),
          ],
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.headphones_rounded,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
