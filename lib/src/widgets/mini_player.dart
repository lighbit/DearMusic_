import 'package:dearmusic/src/pages/full_player_page.dart';
import 'package:dearmusic/src/widgets/expressive_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class MiniPlayer extends StatelessWidget {
  final AudioPlayer player;
  final String title, subtitle;
  final Stream<Duration> positionStream;
  final Stream<Duration?> durationStream;
  final Stream<Duration> bufferedStream;
  final bool playing;
  final VoidCallback onPlayPause;
  final VoidCallback onTap;
  final ValueChanged<Duration> onSeek;
  final Object heroTag;

  const MiniPlayer({
    super.key,
    required this.player,
    required this.title,
    required this.subtitle,
    required this.positionStream,
    required this.durationStream,
    required this.bufferedStream,
    required this.playing,
    required this.onPlayPause,
    required this.onTap,
    required this.onSeek,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(0),
              border: Border(
                top: BorderSide(color: cs.outlineVariant.withOpacity(0.9)),
                bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),

                Flexible(
                  fit: FlexFit.tight,
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onTap();
                        },
                        child: Hero(
                          tag: heroTag,
                          flightShuttleBuilder: _heroShuttle,
                          child: CoverArt(
                            player: player,
                            isMini: true,
                            heroTag: heroTag,
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                onTap();
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 6),

                            SizedBox(
                              height: 14,
                              child: StreamBuilder<PlayerState>(
                                stream: player.playerStateStream,
                                builder: (_, stSnap) {
                                  final ps = stSnap.data;
                                  final isActive =
                                      (ps?.playing ?? false) &&
                                      (ps?.processingState ==
                                              ProcessingState.ready ||
                                          ps?.processingState ==
                                              ProcessingState.buffering);

                                  return StreamBuilder<Duration?>(
                                    stream: durationStream,
                                    builder: (_, durSnap) {
                                      final total =
                                          durSnap.data ?? Duration.zero;
                                      return StreamBuilder<Duration>(
                                        stream: positionStream,
                                        builder: (_, posSnap) {
                                          final pos =
                                              posSnap.data ?? Duration.zero;
                                          return StreamBuilder<Duration>(
                                            stream: bufferedStream,
                                            builder: (_, bufSnap) {
                                              final buffered =
                                                  bufSnap.data ?? Duration.zero;
                                              final active =
                                                  isActive &&
                                                  total > Duration.zero &&
                                                  pos < total;

                                              return GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap: () {
                                                  HapticFeedback.selectionClick();
                                                },
                                                child: ExpressiveProgressBar(
                                                  position: pos,
                                                  duration: total,
                                                  buffered: buffered,
                                                  isActive: active,
                                                  onSeek: onSeek,
                                                  colorScheme: cs,
                                                  height: 3,
                                                  amplitude: 2,
                                                  wavelength: 20,
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                playing
                    ? IconButton.filled(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onPlayPause();
                        },
                        icon: const Icon(Icons.pause_rounded),
                      )
                    : IconButton.filledTonal(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onPlayPause();
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroShuttle(
    BuildContext _,
    Animation<double> __,
    HeroFlightDirection ___,
    BuildContext from,
    BuildContext to,
  ) {
    return to.widget;
  }
}
