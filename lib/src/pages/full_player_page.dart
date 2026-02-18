import 'dart:io';
import 'dart:ui';
import 'package:dearmusic/src/audio/system_audio.dart';
import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:dearmusic/src/logic/pin_hub.dart';
import 'package:dearmusic/src/logic/play_actions.dart';
import 'package:dearmusic/src/logic/playlist_store.dart';
import 'package:dearmusic/src/pages/album_detail_page.dart';
import 'package:dearmusic/src/pages/artist_page.dart';
import 'package:dearmusic/src/player_scope.dart';
import 'package:dearmusic/src/widgets/album_story_share.dart';
import 'package:dearmusic/src/widgets/nerd_flip_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:dearmusic/src/widgets/expressive_progress_bar.dart';

import '../widgets/lyrics_sheet.dart';
import '../widgets/show_queue_widget.dart';

class FullPlayerPage extends StatefulWidget {
  final AudioPlayer player;
  final VoidCallback onClose;
  final Object heroTag;
  final OnAudioQuery query;

  const FullPlayerPage({
    super.key,
    required this.player,
    required this.onClose,
    required this.heroTag,
    required this.query,
  });

  @override
  State<FullPlayerPage> createState() => _FullPlayerPageState();
}

class _FullPlayerPageState extends State<FullPlayerPage> {
  double _dragDy = 0;
  static const double _closeThreshold = 90;
  static const double _velocityThreshold = 900;

  void _resetDrag() {
    if (mounted) setState(() => _dragDy = 0);
  }

  void _maybeCloseByGesture(DragEndDetails d) {
    final vy = d.velocity.pixelsPerSecond.dy;
    if (_dragDy > _closeThreshold || vy > _velocityThreshold) {
      HapticFeedback.lightImpact();
      widget.onClose();
      return;
    }
    _resetDrag();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  (String title, String artist) _titleArtist(SequenceState? st) {
    final tag = st?.currentSource?.tag;

    if (tag is MediaItem) {
      final title = tag.title.isNotEmpty ? tag.title : 'Track';
      final artist = tag.artist?.isNotEmpty == true ? tag.artist! : '–';
      return (title, artist);
    }

    return ('Track', '–');
  }

  Future<void> _openAlbumFromNowPlaying() async {
    HapticFeedback.lightImpact();
    final st = widget.player.sequenceState;
    final tag = st.currentSource?.tag;
    if (tag is! MediaItem) return;

    final extras = tag.extras ?? const <String, Object?>{};
    final albumId = extras['albumId'] as int?;
    if (albumId == null) return;

    final albums = await widget.query.queryAlbums();
    final album = albums.firstWhere(
      (a) => a.id == albumId,
      orElse: () => AlbumModel({}),
    );

    if (!mounted) return;
    final ctrl = PlayerScope.of(context);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailPage(
          album: album,
          query: widget.query,
          onPlayAll: (tracks) async => PlayActions.playQueue(context, tracks),
          onShuffle: (tracks) async =>
              PlayActions.playQueue(context, tracks, shuffle: true),
          onPlayTrack: (track, all) async {
            final idx = all.indexWhere((e) => e.id == track.id);
            if (idx >= 0) {
              await PlayActions.playQueue(context, all, startIndex: idx);
            }
          },
          onPlaylistSaved: (pl) async {
            await PlaylistStore.I.savePlaylist(pl);
          },
          onAddToQueue: (track) async => PlayActions.enqueueOne(context, track),
          onPin: (track) => PinHub.I.toggleSong(
            id: track.id,
            title: track.title,
            artist: track.artist,
            artworkId: track.albumId ?? track.id,
            artworkType: (track.albumId != null && track.albumId! > 0)
                ? ArtworkType.ALBUM
                : ArtworkType.AUDIO,
          ),
          isPinned: (track) => ctrl.isPinned(track.id),
          isAutoClose: true,
        ),
      ),
    );
  }

  Future<void> _openArtistFromNowPlaying() async {
    HapticFeedback.lightImpact();
    final st = widget.player.sequenceState;
    final tag = st.currentSource?.tag;
    if (tag is! MediaItem) return;

    final artistName = (tag.artist ?? '').trim();
    if (artistName.isEmpty) return;

    final allArtists = await widget.query.queryArtists(
      sortType: ArtistSortType.ARTIST,
      orderType: OrderType.ASC_OR_SMALLER,
    );
    final me = artistName.toLowerCase();
    final matched = allArtists.firstWhere(
      (a) => (a.artist).trim().toLowerCase() == me,
      orElse: () => ArtistModel({'artist': artistName}),
    );

    final allSongs = await widget.query.querySongs(
      sortType: SongSortType.ARTIST,
      orderType: OrderType.ASC_OR_SMALLER,
    );
    final mine = allSongs.where((s) {
      final a = (s.artist ?? '').trim().toLowerCase();
      return a == me;
    }).toList();

    final albumIds = <int>{
      for (final s in mine)
        if ((s.albumId ?? 0) > 0) s.albumId!,
    };
    if (albumIds.isEmpty) return;

    final allAlbums = await widget.query.queryAlbums();
    final byId = {for (final a in allAlbums) a.id: a};
    final albums = <AlbumModel>[
      for (final id in albumIds)
        if (byId[id] != null) byId[id]!,
    ];

    albums.sort((a, b) {
      final n = (b.numOfSongs).compareTo(a.numOfSongs);
      return n != 0 ? n : (a.album).compareTo(b.album);
    });

    String norm(String? s) => (s ?? '').trim().toLowerCase();
    bool isPrimary(AlbumModel a) {
      final artists = norm(a.artist)
          .replaceAll('&', ',')
          .replaceAll('feat.', ',')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      return artists.any((t) => t == norm(artistName));
    }

    final primary = <AlbumModel>[];
    final appearsOn = <AlbumModel>[];
    for (final a in albums) {
      (isPrimary(a) ? primary : appearsOn).add(a);
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistPageElegant(
          artist: matched,
          primary: primary,
          appearsOn: appearsOn,
          query: widget.query,
          onOpenAlbum: (alb) async => _openAlbumFromId(alb.id),
          onPinAlbum: (a) =>
              PinHub.I.toggleAlbum(id: a.id, album: a.album, artist: a.artist),
        ),
      ),
    );
  }

  Future<void> _openAlbumFromId(int albumId) async {
    if (!mounted) return;

    final albums = await widget.query.queryAlbums();
    final album = albums.firstWhere(
      (a) => a.id == albumId,
      orElse: () => AlbumModel({}),
    );

    if ((album.id) == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Album tidak ditemukan di perangkat.')),
      );
      return;
    }

    if (!mounted) return;
    final ctrl = PlayerScope.of(context);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailPage(
          album: album,
          query: widget.query,
          onPlayAll: (tracks) async => PlayActions.playQueue(context, tracks),
          onShuffle: (tracks) async =>
              PlayActions.playQueue(context, tracks, shuffle: true),
          onPlayTrack: (track, all) async {
            final idx = all.indexWhere((e) => e.id == track.id);
            if (idx >= 0) {
              await PlayActions.playQueue(context, all, startIndex: idx);
            }
          },
          onPlaylistSaved: (pl) async {
            await PlaylistStore.I.savePlaylist(pl);
          },
          onAddToQueue: (track) async => PlayActions.enqueueOne(context, track),
          onPin: (track) => PinHub.I.toggleSong(
            id: track.id,
            title: track.title,
            artist: track.artist,
            artworkId: track.albumId ?? track.id,
            artworkType: (track.albumId != null && track.albumId! > 0)
                ? ArtworkType.ALBUM
                : ArtworkType.AUDIO,
          ),
          isPinned: (track) => ctrl.isPinned(track.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final player = widget.player;

    final isDark = theme.brightness == Brightness.dark;

    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: theme.scaffoldBackgroundColor,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          systemOverlayStyle: overlay,
          centerTitle: true,
          title: const Text('DearMusic 🎧'),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.onClose();
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () async {
                HapticFeedback.lightImpact();

                final st = widget.player.sequenceState;
                final tag = st.currentSource?.tag;

                if (tag is! MediaItem) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ga ada lagu yang lagi diputar.'),
                      ),
                    );
                  }
                  return;
                }

                final title = tag.title.isNotEmpty ? tag.title : 'Track';
                final artist = (tag.artist ?? '').isNotEmpty
                    ? tag.artist!
                    : '–';
                final extras = tag.extras ?? const <String, Object?>{};
                final albumId = extras['albumId'] as int?;
                final songId = int.tryParse(tag.id);

                Uint8List? coverBytes;
                if (songId != null) {
                  coverBytes = await ArtworkMemCache.I.getBytes(
                    id: songId,
                    type: ArtworkType.AUDIO,
                    slot: ArtworkSlot.tileMedium,
                  );
                }
                coverBytes ??= (albumId != null
                    ? await ArtworkMemCache.I.getBytes(
                        id: albumId,
                        type: ArtworkType.ALBUM,
                        slot: ArtworkSlot.tileMedium,
                      )
                    : null);

                await AlbumStoryShare.shareAlbumStoryWithChooser(
                  coverBytes: coverBytes,
                  albumTitle: title,
                  artistName: artist,
                  hook: '#Singit. #Feelit. #Offline.',
                  ctaText: 'Listen now at DearMusic 🎧',
                  playStoreUrl: 'https://bit.ly/4nmQV22',
                  context: context,
                );
              },
            ),
          ],

          elevation: 0.5,
          backgroundColor: Colors.transparent,
          iconTheme: IconThemeData(color: cs.primary),
        ),
        body: GestureDetector(
          onVerticalDragUpdate: (d) {
            final next = (_dragDy + d.delta.dy).clamp(0, 140);
            setState(() => _dragDy = next.toDouble());
          },
          onVerticalDragEnd: _maybeCloseByGesture,
          onVerticalDragCancel: _resetDrag,
          behavior: HitTestBehavior.translucent,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  StreamBuilder<SequenceState?>(
                    stream: player.sequenceStateStream,
                    initialData: player.sequenceState,
                    builder: (_, st) {
                      final (title, artist) = _titleArtist(st.data);
                      final tag = st.data?.currentSource?.tag;
                      final mediaId = (tag is MediaItem) ? tag.id : 'none';
                      return Column(
                        children: [
                          const SizedBox(height: 4),
                          NerdFlipCover(
                            key: ValueKey('nfc_$mediaId'),
                            player: widget.player,
                            heroTag: widget.heroTag,
                          ),

                          const SizedBox(height: 18),
                          GestureDetector(
                            onTap: _openAlbumFromNowPlaying,
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: tt.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: _openArtistFromNowPlaying,
                            customBorder: const StadiumBorder(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Text(
                                artist,
                                textAlign: TextAlign.center,
                                style: tt.bodyMedium?.copyWith(
                                  color: cs.primary,
                                  decoration: TextDecoration.underline,
                                  decorationColor: cs.primary.withOpacity(0.4),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    initialData: player.playerState,
                    builder: (_, stSnap) {
                      final ps = stSnap.data;
                      final isActive =
                          (ps?.playing ?? false) &&
                          (ps?.processingState == ProcessingState.ready ||
                              ps?.processingState == ProcessingState.buffering);

                      return StreamBuilder<Duration?>(
                        stream: player.durationStream,
                        initialData: player.duration,
                        builder: (_, durSnap) {
                          final total = durSnap.data ?? Duration.zero;
                          return StreamBuilder<Duration>(
                            stream: player.positionStream,
                            initialData: player.position,
                            builder: (_, posSnap) {
                              final pos = posSnap.data ?? Duration.zero;
                              return StreamBuilder<Duration>(
                                stream: player.bufferedPositionStream,
                                initialData: player.bufferedPosition,
                                builder: (_, bufSnap) {
                                  final buf = bufSnap.data ?? Duration.zero;
                                  final active =
                                      isActive &&
                                      total > Duration.zero &&
                                      pos < total;

                                  return Column(
                                    children: [
                                      SizedBox(
                                        height: 18,
                                        child: ExpressiveProgressBar(
                                          position: pos,
                                          duration: total,
                                          buffered: buf,
                                          isActive: active,
                                          onSeek: (d) => player.seek(d),
                                          colorScheme: cs,
                                          height: 5,
                                          amplitude: 3.0,
                                          wavelength: 50,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _fmt(pos),
                                            style: tt.labelSmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                          Text(
                                            _fmt(total),
                                            style: tt.labelSmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 6),

                  StreamBuilder<SequenceState?>(
                    stream: player.sequenceStateStream,
                    initialData: player.sequenceState,
                    builder: (_, stSnap) {
                      final ctrl = PlayerScope.of(context);
                      final st = stSnap.data;
                      final seq = st?.effectiveSequence ?? const [];
                      final idx = st?.currentIndex ?? 0;
                      final hasSeq = seq.isNotEmpty;

                      final canPrevByIndex = hasSeq && idx > 0;
                      final canNextByIndex = hasSeq && idx < (seq.length - 1);

                      final enablePrev = hasSeq;
                      final enableNext = hasSeq;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          StreamBuilder<bool>(
                            stream: player.shuffleModeEnabledStream,
                            initialData: player.shuffleModeEnabled,
                            builder: (_, snap) {
                              final shuffleOn =
                                  snap.data ?? player.shuffleModeEnabled;
                              final shuffleEnabled = hasSeq;
                              return IconButton(
                                tooltip: shuffleOn
                                    ? 'Shuffle: ON'
                                    : 'Shuffle: OFF',
                                onPressed: shuffleEnabled
                                    ? () async {
                                        HapticFeedback.lightImpact();
                                        await ctrl.setShuffle(!shuffleOn);
                                      }
                                    : null,
                                icon: Icon(
                                  shuffleOn
                                      ? Icons.shuffle_on_rounded
                                      : Icons.shuffle_rounded,
                                  color: shuffleEnabled && shuffleOn
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                              );
                            },
                          ),

                          IconButton(
                            tooltip: canPrevByIndex
                                ? 'Previous'
                                : 'Restart/Previous',
                            onPressed: enablePrev
                                ? () async {
                                    HapticFeedback.lightImpact();
                                    await ctrl.prev();
                                  }
                                : null,
                            iconSize: 34,
                            icon: const Icon(Icons.skip_previous_rounded),
                          ),

                          StreamBuilder<bool>(
                            stream: player.playingStream,
                            initialData: player.playing,
                            builder: (_, snap) {
                              final playing = snap.data ?? false;
                              return FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 14,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: () async {
                                  HapticFeedback.lightImpact();
                                  playing ? player.pause() : player.play();
                                },
                                child: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 34,
                                ),
                              );
                            },
                          ),

                          IconButton(
                            tooltip: canNextByIndex ? 'Next' : 'Next (auto)',
                            onPressed: enableNext
                                ? () async {
                                    HapticFeedback.lightImpact();
                                    await ctrl.next();
                                  }
                                : null,
                            iconSize: 34,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),

                          StreamBuilder<LoopMode>(
                            stream: player.loopModeStream,
                            initialData: player.loopMode,
                            builder: (_, snap) {
                              final mode = snap.data ?? player.loopMode;
                              final active = mode != LoopMode.off;
                              IconData icon = switch (mode) {
                                LoopMode.one => Icons.repeat_one_rounded,
                                LoopMode.all => Icons.repeat_on_rounded,
                                LoopMode.off => Icons.repeat_rounded,
                              };
                              return IconButton(
                                tooltip: 'Repeat',
                                onPressed: hasSeq
                                    ? () async {
                                        HapticFeedback.lightImpact();
                                        final next = switch (mode) {
                                          LoopMode.off => LoopMode.all,
                                          LoopMode.all => LoopMode.one,
                                          LoopMode.one => LoopMode.off,
                                        };
                                        await player.setLoopMode(next);
                                      }
                                    : null,
                                icon: Icon(
                                  icon,
                                  color: active
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),

                  const Spacer(),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TonalPillButton(
                        icon: Icons.queue_music_rounded,
                        label: 'Queue',
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          showQueueSheet(context);
                        },
                      ),
                      const SizedBox(width: 3),
                      TonalPillButton(
                        icon: Icons.lyrics_rounded,
                        label: 'Lyrics',
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          final st = player.sequenceState;
                          final tag = st.currentSource?.tag;
                          String title = 'Track';
                          String? artist;
                          int? durationMs = player.duration?.inMilliseconds;

                          if (tag is MediaItem) {
                            title = tag.title.isNotEmpty ? tag.title : 'Track';
                            artist = tag.artist;
                            durationMs ??= tag.duration?.inMilliseconds;
                          }

                          await showLyricsSheet(
                            context: context,
                            player: player,
                            title: title,
                            artist: artist,
                            durationMs: durationMs,
                            vagalumeApiKey: null,
                          );
                        },
                      ),

                      const SizedBox(width: 3),
                      TonalPillButton(
                        icon: Icons.equalizer_rounded,
                        label: 'EQ',
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          final ok = await SystemAudio.openEqualizer(player);
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Equalizer bawaan tidak tersedia. Buka pengaturan suara?',
                                ),
                                action: SnackBarAction(
                                  label: 'Buka',
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    SystemAudio.openOutputSwitcher();
                                  },
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 3),
                      TonalPillButton(
                        icon: Icons.speaker_rounded,
                        label: 'Output',
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          final ok = await SystemAudio.openOutputSwitcher();
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Panel output tidak tersedia. Buka pengaturan Bluetooth.',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CoverArt extends StatelessWidget {
  final AudioPlayer player;
  final bool isMini;
  final double miniSize;
  final Widget? staticChild;
  final Object? heroTag;

  const CoverArt({
    super.key,
    required this.player,
    this.isMini = false,
    this.miniSize = 56,
    this.staticChild,
    this.heroTag,
  });

  ({
    String? mediaId,
    int? albumId,
    int? songId,
    ArtworkType type,
    String? artUri,
  })
  _extractKey(SequenceState? st) {
    final tag = st?.currentSource?.tag;
    String? mediaId;
    int? albumId;
    int? songId;
    ArtworkType type = ArtworkType.ALBUM;
    String? artUri;

    if (tag is MediaItem) {
      mediaId = tag.id;
      final extras = tag.extras ?? const <String, Object?>{};
      albumId = extras['albumId'] as int?;
      final t = (extras['artworkType'] as String?) ?? 'AUDIO';
      type = t == 'AUDIO' ? ArtworkType.AUDIO : ArtworkType.ALBUM;
      songId = int.tryParse(tag.id);
      artUri = tag.artUri?.toString();
    }
    return (
      mediaId: mediaId,
      albumId: albumId,
      songId: songId,
      type: type,
      artUri: artUri,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = BorderRadius.circular(isMini ? 12 : 24);
    final bg = cs.surfaceContainerHighest;

    final double glowScale = isMini ? 1.14 : 1.24;
    final double glowSigma = isMini ? 18 : 26;

    if (staticChild != null) {
      final box = isMini
          ? SizedBox(width: miniSize, height: miniSize, child: staticChild!)
          : AspectRatio(aspectRatio: 1, child: staticChild!);
      return ClipRRect(borderRadius: r, child: box);
    }

    final stream = player.sequenceStateStream
        .map(_extractKey)
        .distinct((a, b) => a.mediaId == b.mediaId);

    return StreamBuilder<
      ({
        String? mediaId,
        int? albumId,
        int? songId,
        ArtworkType type,
        String? artUri,
      })
    >(
      stream: stream,
      initialData: _extractKey(player.sequenceState),
      builder: (context, snap) {
        final k = snap.data!;
        Widget child;

        if (k.albumId != null) {
          child = FutureBuilder<Widget>(
            key: ValueKey('alb_${k.albumId}'),
            future: ArtworkMemCache.I.imageWidget(
              id: k.albumId!,
              type: k.type,
              slot: ArtworkSlot.hero,
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
          );
        } else if (k.songId != null) {
          child = FutureBuilder<Widget>(
            key: ValueKey('aud_${k.songId}'),
            future: ArtworkMemCache.I.imageWidget(
              id: k.songId!,
              type: ArtworkType.AUDIO,
              slot: ArtworkSlot.hero,
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
          );
        } else if (k.artUri != null && k.artUri!.isNotEmpty) {
          if (k.artUri!.startsWith('http')) {
            child = Image.network(
              k.artUri!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Container(
                color: bg,
                child: Icon(Icons.headphones_rounded, color: cs.primary),
              ),
            );
          } else {
            child = Image.file(
              File(k.artUri!.replaceFirst('file://', '')),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Container(
                color: bg,
                child: Icon(Icons.headphones_rounded, color: cs.primary),
              ),
            );
          }
        } else {
          child = Container(
            color: bg,
            alignment: Alignment.center,
            child: Icon(Icons.headphones_rounded, color: cs.primary),
          );
        }

        final sharp = ClipRRect(borderRadius: r, child: child);

        final glow = Transform.scale(
          scale: glowScale,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: glowSigma, sigmaY: glowSigma),
            child: ClipRRect(borderRadius: r, child: child),
          ),
        );

        Widget boxWithGlow = Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: glow),
            Positioned.fill(child: sharp),
          ],
        );

        boxWithGlow = isMini
            ? SizedBox(width: miniSize, height: miniSize, child: boxWithGlow)
            : AspectRatio(aspectRatio: 1, child: boxWithGlow);

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: Container(
            key: ValueKey('media_${k.mediaId ?? 'none'}'),
            child: boxWithGlow,
          ),
        );
      },
    );
  }
}

class TonalPillButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final int minBusyMs;
  final bool enableHaptics;

  const TonalPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.minBusyMs = 300,
    this.enableHaptics = true,
  });

  @override
  State<TonalPillButton> createState() => _TonalPillButtonState();
}

class _TonalPillButtonState extends State<TonalPillButton> {
  bool _busy = false;
  int _lastStartMs = 0;

  Future<void> _handlePress() async {
    if (_busy) return;
    setState(() => _busy = true);
    _lastStartMs = DateTime.now().millisecondsSinceEpoch;

    if (widget.enableHaptics) {
      HapticFeedback.lightImpact();
    }

    try {
      await widget.onTap();
    } catch (e) {
      debugPrint('TonalPillButton: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memproses. Coba lagi.')),
        );
      }
    } finally {
      final elapsed = DateTime.now().millisecondsSinceEpoch - _lastStartMs;
      final waitMore = widget.minBusyMs - elapsed;
      if (waitMore > 0) await Future.delayed(Duration(milliseconds: waitMore));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilledButton.tonal(
      onPressed: _busy ? null : _handlePress,
      style: FilledButton.styleFrom(
        foregroundColor: cs.onSecondaryContainer,
        backgroundColor: cs.secondaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: const StadiumBorder(),
        disabledForegroundColor: cs.onSurface.withOpacity(0.38),
        disabledBackgroundColor: cs.surfaceContainerHighest.withOpacity(0.45),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: _busy
                ? const SizedBox(
                    key: ValueKey('spinner'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(widget.icon, size: 18, key: const ValueKey('icon')),
          ),
          const SizedBox(width: 8),
          Text(widget.label, style: TextStyle(fontSize: 12.sp)),
        ],
      ),
    );
  }
}
