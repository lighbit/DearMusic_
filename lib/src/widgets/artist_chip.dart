import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

class ArtistCircleCard extends StatelessWidget {
  final ArtistModel artist;
  final VoidCallback onTap;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onPin;
  final bool isPin;

  const ArtistCircleCard({
    super.key,
    required this.artist,
    required this.onTap,
    this.onAddToQueue,
    this.onPin,
    this.isPin = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap.call();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cs = Theme.of(context).colorScheme;
          final txt = Theme.of(context).textTheme;

          return Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipOval(
                    child: FutureBuilder<Widget>(
                      future: ArtworkMemCache.I.imageWidget(
                        id: artist.id,
                        type: ArtworkType.ARTIST,
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
                      builder: (_, snap) =>
                          snap.data ?? const SizedBox.shrink(),
                    ),
                  ),

                  Positioned(
                    top: 2,
                    right: 2,
                    child: Material(
                      color: Colors.black.withOpacity(0.35),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          showSongMenu(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.more_vert_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (isPin)
                    Positioned(
                      left: 6,
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
              const SizedBox(height: 8),

              Text(
                artist.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: txt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          );
        },
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
                  onTap();
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
              if (onPin != null)
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(
                    isPin ? easy.tr("pin.unpin") : easy.tr("pin.pin"),
                  ),
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
