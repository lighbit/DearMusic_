import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AlbumCard extends StatelessWidget {
  final AlbumModel album;
  final OnAudioQuery query;
  final VoidCallback onOpen;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onPin;
  final bool isPin;

  const AlbumCard({
    super.key,
    required this.album,
    required this.query,
    required this.onOpen,
    this.onAddToQueue,
    this.onPin,
    this.isPin = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedback.lightImpact();
        onOpen();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: FutureBuilder<Widget>(
                    future: ArtworkMemCache.I.imageWidget(
                      id: album.id,
                      type: ArtworkType.ALBUM,
                      slot: ArtworkSlot.gridSmall,
                      radius: BorderRadius.circular(12),
                      placeholder: Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.music_note_rounded,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    builder: (_, snap) => snap.data ?? SizedBox.expand(),
                  ),
                ),

                if (isPin)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Material(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withOpacity(0.7),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onPin!();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.push_pin, size: 16),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: txt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      album.artist ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: txt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ),
              ),

              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  HapticFeedback.lightImpact();
                  showSongMenu(context);
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
        ],
      ),
    );
  }

  void showSongMenu(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: Text(easy.tr("common.playNow")),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  onOpen();
                },
              ),
              if (onAddToQueue != null)
                ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(easy.tr("common.addToQueue")),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(ctx);
                    onAddToQueue?.call();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: Text(isPin ? easy.tr("pin.unpin") : easy.tr("pin.pin")),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  onPin?.call();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
