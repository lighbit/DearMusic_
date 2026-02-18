import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:on_audio_query/on_audio_query.dart';

class QuickAccessItem {
  final int id;
  final ArtworkType artworkType;
  final String title;
  final String? subtitle;
  final VoidCallback onOpen;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onPin;
  final bool isPinned;

  const QuickAccessItem({
    required this.id,
    required this.artworkType,
    required this.title,
    required this.onOpen,
    this.subtitle,
    this.onAddToQueue,
    this.onPin,
    this.isPinned = false,
  });
}

class QuickAccessGrid extends StatelessWidget {
  final List<QuickAccessItem> items;

  const QuickAccessGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 0,
        crossAxisSpacing: 6,
        childAspectRatio: 0.70,
      ),
      delegate: SliverChildBuilderDelegate((context, i) {
        final it = items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.lightImpact();
            it.onOpen();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: FutureBuilder<Widget>(
                    future: ArtworkMemCache.I.imageWidget(
                      id: it.id,
                      type: it.artworkType,
                      slot: ArtworkSlot.gridSmall,
                      radius: BorderRadius.circular(12),
                      placeholder: Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.headphones_rounded,
                          color: cs.onSurfaceVariant,
                          size: 60,
                        ),
                      ),
                    ),
                    builder: (_, snap) => snap.data ?? SizedBox.expand(),
                  ),
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
                          it.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: txt.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        if (it.subtitle != null && it.subtitle!.isNotEmpty)
                          Text(
                            it.subtitle!,
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
                      _showSongMenu(context, it);
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
      }, childCount: items.length.clamp(0, 9)),
    );
  }

  void _showSongMenu(BuildContext context, QuickAccessItem it) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text(easy.tr("common.playNow")),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(ctx);
                it.onOpen();
              },
            ),
            if (it.onAddToQueue != null)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(easy.tr("common.addToQueue")),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  it.onAddToQueue?.call();
                },
              ),
            if (it.onPin != null)
              ListTile(
                leading: Icon(
                  it.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(
                  it.isPinned ? easy.tr("pin.unpin") : easy.tr("pin.pin"),
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  it.onPin?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}
