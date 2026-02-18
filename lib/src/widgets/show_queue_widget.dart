import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:dearmusic/src/player_scope.dart';

void showQueueSheet(BuildContext context) {
  final ctrl = PlayerScope.of(context);
  final player = ctrl.player;
  final cs = Theme.of(context).colorScheme;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollCtrl) {
          return StreamBuilder<SequenceState?>(
            stream: player.sequenceStateStream,
            initialData: player.sequenceState,
            builder: (_, snap) {
              final seq = player.sequence;
              final currentIndex = player.currentIndex ?? -1;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        Text(
                          'Queue',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Shuffle',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            if (!player.shuffleModeEnabled) {
                              player.setShuffleModeEnabled(true);
                              player.shuffle();
                            } else {
                              player.setShuffleModeEnabled(false);
                            }
                          },
                          icon: Icon(
                            player.shuffleModeEnabled
                                ? Icons.shuffle_on_rounded
                                : Icons.shuffle_rounded,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Clear',
                          onPressed: player.sequence.isNotEmpty == true
                              ? () {
                                  HapticFeedback.lightImpact();
                                  ctrl.smartClear(refill: true, want: 50);
                                  Navigator.of(context).maybePop();
                                }
                              : null,
                          icon: const Icon(Icons.clear_all_rounded),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),
                  Divider(height: 1, color: cs.outlineVariant),

                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      itemCount: seq.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (context, i) {
                        final tag = seq[i].tag;
                        String title = 'Track';
                        String subtitle = '–';
                        int? albumId;
                        int? songId;
                        ArtworkType type = ArtworkType.ALBUM;

                        if (tag is MediaItem) {
                          title = tag.title.isNotEmpty ? tag.title : 'Track';
                          subtitle = tag.artist?.isNotEmpty == true
                              ? tag.artist!
                              : '–';
                          albumId = tag.extras?['albumId'] as int?;
                          final t = tag.extras?['artworkType'] as String?;
                          if (t == 'AUDIO') type = ArtworkType.AUDIO;
                          songId = int.tryParse(tag.id);
                        }

                        final isCurrent = i == currentIndex;

                        return InkWell(
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            await player.seek(Duration.zero, index: i);
                            await player.play();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: albumId != null
                                        ? FutureBuilder<Widget>(
                                            future: ArtworkMemCache.I
                                                .imageWidget(
                                                  id: albumId,
                                                  type: type,
                                                  slot: ArtworkSlot.gridSmall,
                                                  radius: BorderRadius.circular(
                                                    12,
                                                  ),
                                                  placeholder: Container(
                                                    color: cs
                                                        .surfaceContainerHighest,
                                                    alignment: Alignment.center,
                                                    child: Icon(
                                                      Icons.music_note_rounded,
                                                      color:
                                                          cs.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                            builder: (_, snap) =>
                                                snap.data ?? SizedBox.expand(),
                                          )
                                        : (songId != null
                                              ? FutureBuilder<Widget>(
                                                  future: ArtworkMemCache.I.imageWidget(
                                                    id: songId,
                                                    type: ArtworkType.AUDIO,
                                                    slot: ArtworkSlot.gridSmall,
                                                    radius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    placeholder: Container(
                                                      color: cs
                                                          .surfaceContainerHighest,
                                                      alignment:
                                                          Alignment.center,
                                                      child: Icon(
                                                        Icons
                                                            .music_note_rounded,
                                                        color:
                                                            cs.onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ),
                                                  builder: (_, snap) =>
                                                      snap.data ??
                                                      SizedBox.expand(),
                                                )
                                              : Container(
                                                  color: cs
                                                      .surfaceContainerHighest,
                                                  child: const Icon(
                                                    Icons.headphones_rounded,
                                                  ),
                                                )),
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: isCurrent
                                              ? cs.primary
                                              : cs.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isCurrent
                                              ? cs.primary.withOpacity(0.8)
                                              : cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                IconButton(
                                  tooltip: 'Hapus dari queue',
                                  onPressed: () async {
                                    HapticFeedback.lightImpact();
                                    final src = player.audioSource;
                                    if (src is ConcatenatingAudioSource) {
                                      await src.removeAt(i);
                                    }
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}
