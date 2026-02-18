import 'package:animations/animations.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:dearmusic/src/player_scope.dart';
import 'package:dearmusic/src/widgets/mini_player.dart';
import 'package:dearmusic/src/pages/full_player_page.dart';
import 'package:dearmusic/src/pages/home_page.dart';


class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static final GlobalKey<NavigatorState> innerNavKey =
      GlobalKey<NavigatorState>();

  static NavigatorState get innerNavigator => innerNavKey.currentState!;

  static BuildContext? get innerContext => innerNavKey.currentContext;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context).player;
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

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final inn = AppShell.innerNavKey.currentState;
        if (inn != null && await inn.maybePop()) {
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: Navigator(
          key: AppShell.innerNavKey,
          onGenerateRoute: (settings) {
            return MaterialPageRoute(
              builder: (_) => const HomePage(),
              settings: const RouteSettings(name: '/'),
            );
          },
        ),

        bottomNavigationBar: StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, snap) {
            final tag = snap.data?.currentSource?.tag;
            final title = (tag is MediaItem)
                ? tag.title
                : (snap.data != null ? 'Playing' : 'Nothing playing');
            final artist = (tag is MediaItem) ? tag.artist : '—';

            const dxThreshold = 60.0;
            const velThreshold = 600.0;

            double accumDx = 0;
            bool swiping = false;

            Future<void> handleSwipeEnd(DragEndDetails d) async {
              final vx = d.primaryVelocity ?? 0.0;

              if (accumDx.abs() > dxThreshold || vx.abs() > velThreshold) {
                if (accumDx < 0 || vx < -velThreshold) {
                  if (player.hasNext) {
                    await player.seekToNext();
                    await player.play();
                  } else {
                    await PlayerScope.of(context).next();
                  }
                } else {
                  final pos = player.position;
                  if (pos > const Duration(seconds: 3)) {
                    await player.seek(Duration.zero);
                  } else if (player.hasPrevious) {
                    await player.seekToPrevious();
                    await player.play();
                  } else {
                    await PlayerScope.of(context).prev();
                  }
                }
              }
              swiping = false;
              accumDx = 0;
            }

            final seq = player.sequenceState;
            final tagObj = seq.currentSource?.tag;
            final heroTag = (tagObj is MediaItem)
                ? 'cover_${tagObj.id}'
                : 'cover_none';

            return SafeArea(
              bottom: true,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) {
                  swiping = true;
                  accumDx = 0;
                },
                onHorizontalDragUpdate: (d) {
                  accumDx += d.delta.dx;
                },
                onHorizontalDragEnd: (d) async {
                  await handleSwipeEnd(d);
                },
                child: OpenContainer(
                  tappable: true,
                  closedElevation: 1,
                  openElevation: 1,
                  closedColor: Colors.transparent,
                  openColor: Colors.transparent,
                  transitionDuration: const Duration(milliseconds: 100),
                  transitionType: ContainerTransitionType.fadeThrough,
                  closedBuilder: (context, open) => MiniPlayer(
                    player: player,
                    title: title,
                    subtitle: artist ?? '-',
                    positionStream: player.positionStream,
                    durationStream: player.durationStream,
                    bufferedStream: player.bufferedPositionStream,
                    playing: player.playing,
                    heroTag: heroTag,
                    onPlayPause: () async {
                      player.playing ? player.pause() : player.play();
                      // if (!context.mounted) return;
                      // await BatteryHelper.maybeAskUnrestricted(context);
                    },
                    onTap: () {
                      if (!swiping) open();
                    },
                    onSeek: (d) => player.seek(d),
                  ),
                  openBuilder: (context, close) => FullPlayerPage(
                    player: player,
                    onClose: close,
                    heroTag: heroTag,
                    query: PlayerScope.of(context).query,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
