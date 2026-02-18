import 'dart:math';
import 'dart:ui';
import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:dearmusic/src/models/playlist_models.dart';
import 'package:dearmusic/src/widgets/album_story_share.dart';
import 'package:dearmusic/src/widgets/playlist_editor.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AlbumDetailPage extends StatefulWidget {
  final AlbumModel album;
  final OnAudioQuery query;

  final Future<void> Function(List<SongModel> tracks)? onPlayAll;
  final Future<void> Function(List<SongModel> tracks)? onShuffle;

  final Future<void> Function(SongModel track, List<SongModel> all)?
  onPlayTrack;
  final void Function(SongModel track)? onAddToQueue;
  final void Function(SongModel track)? onPin;
  final bool Function(SongModel track)? isPinned;
  final Future<void> Function(Playlist pl)? onPlaylistSaved;
  final bool isAutoClose;

  const AlbumDetailPage({
    super.key,
    required this.album,
    required this.query,
    this.onPlayAll,
    this.onShuffle,
    this.onPlayTrack,
    this.onAddToQueue,
    this.onPin,
    this.isPinned,
    this.onPlaylistSaved,
    this.isAutoClose = false,
  });

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  late Future<List<SongModel>> _tracksFut;

  @override
  void initState() {
    super.initState();
    _tracksFut = _loadTracks();
  }

  Future<List<SongModel>> _loadTracks() async {
    final list = await widget.query.queryAudiosFrom(
      AudiosFromType.ALBUM_ID,
      widget.album.id,
      sortType: SongSortType.DISPLAY_NAME,
      orderType: OrderType.ASC_OR_SMALLER,
    );

    final filtered = list.where((s) => s.uri?.isNotEmpty == true).toList();

    final Map<int, List<SongModel>> grouped = {};

    for (final s in filtered) {
      final disc = _extractDiscNumber(s);
      grouped.putIfAbsent(disc, () => []).add(s);
    }

    for (final d in grouped.keys) {
      grouped[d]!.sort((a, b) {
        final at = a.track ?? 0;
        final bt = b.track ?? 0;
        if (at != bt) return at.compareTo(bt);
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }

    final merged = grouped.keys.toList()..sort();
    final result = <SongModel>[];
    for (final d in merged) {
      result.addAll(grouped[d]!);
    }

    return result;
  }

  int _extractDiscNumber(SongModel s) {
    final info = s.getMap;
    debugPrint("info: $info");

    final candidates = [
      info['disc_number'],
      info['discNo'],
      info['disc'],
      info['cd_number'],
    ];

    for (final val in candidates) {
      if (val == null) continue;
      if (val is int && val > 0) return val;
      if (val is String) {
        final n = int.tryParse(val);
        if (n != null && n > 0) return n;
      }
    }

    final title = (s.title).toLowerCase();
    final path = (s.data).toLowerCase();
    final match =
        RegExp(r'(disc|cd)\s?(\d+)').firstMatch(title) ??
        RegExp(r'(disc|cd)\s?(\d+)').firstMatch(path);
    if (match != null) {
      return int.tryParse(match.group(2) ?? '1') ?? 1;
    }

    return 1;
  }

  Future<void> _createPlaylistFromAlbum(List<SongModel> tracks) async {
    if (tracks.isEmpty) return;
    final name = widget.album.album.trim().isNotEmpty == true
        ? widget.album.album.trim()
        : 'Album ${DateTime.now().millisecondsSinceEpoch}';

    await showCreatePlaylistSheet(
      context: context,
      allSongs: tracks,
      queryApi: widget.query,
      edit: Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        songIds: tracks.map((e) => e.id).toList(),
        createdAt: DateTime.now(),
      ),
      onSaved: (pl) async {
        if (widget.onPlaylistSaved != null) {
          await widget.onPlaylistSaved!(pl);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Playlist "${pl.name}" disimpan')),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final a = widget.album;

    final title = a.album ?? 'Album';
    final artist = a.artist ?? '';

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
      canPop: true,
      onPopInvoked: (didPop) {},
      child: Scaffold(
        backgroundColor: cs.surface,
        body: FutureBuilder<List<SongModel>>(
          future: _tracksFut,
          builder: (ctx, snap) {
            final tracks = snap.data ?? const <SongModel>[];
            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 420,
                  backgroundColor: cs.surface,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.parallax,
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        FutureBuilder<Widget>(
                          future: ArtworkMemCache.I.imageWidget(
                            id: a.id,
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
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                            child: const SizedBox(),
                          ),
                        ),

                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                cs.surface.withOpacity(0.6),
                                cs.surface,
                              ],
                            ),
                          ),
                        ),

                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: SizedBox(
                                    width:
                                        MediaQuery.of(context).size.width *
                                        0.55,
                                    height:
                                        MediaQuery.of(context).size.width *
                                        0.55,
                                    child: FutureBuilder<Widget>(
                                      future: ArtworkMemCache.I.imageWidget(
                                        id: a.id,
                                        type: ArtworkType.ALBUM,
                                        slot: ArtworkSlot.tileMedium,
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
                                          snap.data ?? SizedBox.expand(),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 16),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 10,
                                      backgroundColor:
                                          cs.surfaceContainerHighest,
                                      child: const Icon(
                                        Icons.headphones_rounded,
                                        size: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        artist,
                                        overflow: TextOverflow.ellipsis,
                                        style: txt.bodyMedium?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: txt.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                    height: 1.05,
                                  ),
                                ),
                                const SizedBox(height: 14),

                                _AlbumActionsRow(
                                  onInfo: () async {
                                    HapticFeedback.lightImpact();
                                    await showAlbumInfoSheet(
                                      context,
                                      album: a,
                                      tracks: tracks,
                                      onViewArtist: null,
                                      onOpenWeb: null,
                                    );
                                  },
                                  onPlay:
                                      tracks.isNotEmpty &&
                                          widget.onPlayAll != null
                                      ? () => widget.onPlayAll!(tracks)
                                      : null,
                                  onShuffle:
                                      tracks.isNotEmpty &&
                                          widget.onShuffle != null
                                      ? () => widget.onShuffle!(tracks)
                                      : null,
                                  onAdd: tracks.isNotEmpty
                                      ? () => _createPlaylistFromAlbum(tracks)
                                      : null,
                                  onShare: tracks.isNotEmpty
                                      ? () async {
                                          final cover = await ArtworkMemCache.I
                                              .getBytes(
                                                id: a.id,
                                                type: ArtworkType.ALBUM,
                                                slot: ArtworkSlot.tileMedium,
                                              );

                                          await AlbumStoryShare.shareAlbumStoryWithChooser(
                                            coverBytes: cover,
                                            albumTitle: title,
                                            artistName: artist,
                                            hook: '#Singit. #Feelit. #Offline.',
                                            ctaText:
                                                'Listen now at DearMusic 🎧',
                                            playStoreUrl:
                                                'https://bit.ly/4nmQV22',
                                            context: context,
                                          );
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(12),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.outlineVariant.withOpacity(0.6),
                    ),
                  ),
                ),

                if (snap.connectionState == ConnectionState.waiting)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (tracks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Tidak ada lagu dalam album ini.',
                        style: txt.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  (() {
                    final Map<int, List<SongModel>> discs = {};
                    for (final s in tracks) {
                      final d = _discFromTrack(s.track);
                      (discs[d] ??= <SongModel>[]).add(s);
                    }

                    final discKeys = discs.keys.toList()..sort();
                    for (final d in discKeys) {
                      discs[d]!.sort((a, b) {
                        final at = a.track ?? 0;
                        final bt = b.track ?? 0;
                        if (at != bt) return at.compareTo(bt);

                        return a.title.toLowerCase().compareTo(
                          b.title.toLowerCase(),
                        );
                      });
                    }

                    final List<Widget> children = [];
                    for (final d in discKeys) {
                      final listPerDisc = discs[d]!;
                      if (discKeys.length > 1) {
                        children.add(
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: cs.outlineVariant.withOpacity(0.5),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.shadow.withOpacity(0.06),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: cs.primary.withOpacity(0.10),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.album_rounded,
                                      size: 20,
                                      color: cs.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  Text(
                                    'Disc $d',
                                    style: txt.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const Spacer(),

                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${listPerDisc.length}',
                                      style: txt.labelLarge?.copyWith(
                                        color: cs.onPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      for (var i = 0; i < listPerDisc.length; i++) {
                        final s = listPerDisc[i];
                        final trackNo = _trackNoInDisc(s.track);

                        children.add(
                          _TrackTile(
                            index: trackNo > 0 ? trackNo : (i + 1),
                            song: s,
                            onPlay: widget.onPlayTrack != null
                                ? () {
                                    widget.onPlayTrack!(s, tracks);
                                    if (widget.isAutoClose) {
                                      Future.delayed(
                                        const Duration(milliseconds: 300),
                                        () {
                                          Navigator.pop(ctx);
                                        },
                                      );
                                    }
                                  }
                                : null,
                            onMore: () => _showSongMenu(context, s, tracks),
                          ),
                        );

                        if (i != listPerDisc.length - 1) {
                          children.add(
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: cs.outlineVariant.withOpacity(0.3),
                            ),
                          );
                        }
                      }

                      children.add(const SizedBox(height: 8));
                      children.add(
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: cs.outlineVariant.withOpacity(0.4),
                        ),
                      );
                      children.add(const SizedBox(height: 8));
                    }

                    return SliverList(
                      delegate: SliverChildListDelegate(children),
                    );
                  })(),
              ],
            );
          },
        ),
      ),
    );
  }

  int parseTrack(int? t) {
    if (t == null) return 0;
    if (t > 1000) return t % 1000;
    return t;
  }

  int _discFromTrack(int? t) {
    if (t == null || t <= 0) return 1;
    if (t > 1000) return t ~/ 1000;
    return 1;
  }

  int _trackNoInDisc(int? t) {
    if (t == null || t <= 0) return 0;
    if (t > 1000) return t % 1000;
    return t;
  }

  void _showSongMenu(BuildContext context, SongModel s, List<SongModel> all) {
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
                widget.onPlayTrack?.call(s, all);
              },
            ),
            if (widget.onAddToQueue != null)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(easy.tr("common.addToQueue")),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  widget.onAddToQueue!(s);
                },
              ),
            if (widget.onPin != null)
              ListTile(
                leading: Icon(
                  (widget.isPinned?.call(s) ?? false)
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                ),
                title: Text(
                  (widget.isPinned?.call(s) ?? false)
                      ? easy.tr("pin.unpin")
                      : easy.tr("pin.pin"),
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  widget.onPin!(s);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _AlbumActionsRow extends StatelessWidget {
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback? onAdd;
  final VoidCallback? onShare;
  final VoidCallback? onInfo;

  const _AlbumActionsRow({
    required this.onPlay,
    required this.onShuffle,
    required this.onAdd,
    required this.onShare,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _tonalBtn(Icons.info_rounded, cs, onInfo),

          SizedBox(width: 10),
          _tonalBtn(Icons.playlist_add_rounded, cs, onAdd),

          SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: const StadiumBorder(),
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              onPlay!();
            },
            child: const Icon(Icons.play_arrow_rounded, size: 34),
          ),

          SizedBox(width: 10),
          _tonalBtn(Icons.shuffle_rounded, cs, onShuffle),

          SizedBox(width: 10),
          _tonalBtn(Icons.ios_share_rounded, cs, onShare),
        ],
      ),
    );
  }

  Widget _tonalBtn(IconData icon, ColorScheme cs, VoidCallback? onTap) {
    return IconButton.filledTonal(
      onPressed: () {
        HapticFeedback.lightImpact();
        onTap!();
      },
      icon: Icon(icon, size: 24),
      style: IconButton.styleFrom(
        backgroundColor: cs.surfaceContainerHighest,
        foregroundColor: cs.onSurfaceVariant,
        padding: const EdgeInsets.all(12),
        shape: const CircleBorder(),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final int index;
  final SongModel song;
  final VoidCallback? onPlay;
  final VoidCallback? onMore;

  const _TrackTile({
    required this.index,
    required this.song,
    this.onPlay,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    String fmt(Duration d) {
      final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    final dur = song.duration != null
        ? Duration(milliseconds: song.duration!)
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Text(
        index.toString(),
        style: txt.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: txt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              [
                song.artist ?? '',
                if (dur != null) fmt(dur),
              ].where((e) => e.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: txt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),

      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Putar',
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: () {
              HapticFeedback.lightImpact();
              onPlay!();
            },
          ),
          IconButton(
            tooltip: 'Lainnya',
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: onMore,
          ),
        ],
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        onPlay!();
      },
    );
  }
}

Future<void> showAlbumInfoSheet(
  BuildContext context, {
  required AlbumModel album,
  required List<SongModel> tracks,
  VoidCallback? onViewArtist,
  VoidCallback? onOpenWeb,
}) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;

  String fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  int discFromTrackNum(int? t) {
    if (t == null || t <= 0) return 1;
    return t > 1000 ? t ~/ 1000 : 1;
  }

  final totalMs = tracks.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
  final discSet = tracks.map((s) => discFromTrackNum(s.track)).toSet()
    ..removeWhere((e) => e <= 0);
  final discCount = max(1, discSet.length);
  final songCount = tracks.length;
  final releaseYear = tracks.first.getMap["year"] ?? tracks.first.dateAdded;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.50,
        minChildSize: 0.40,
        maxChildSize: 0.90,
        builder: (context, scroll) {
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.album_rounded, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: txt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            album.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: txt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              _InfoRow(
                icon: Icons.music_note_rounded,
                label: easy.tr("info.songCount"),
                value: '$songCount',
              ),
              _InfoRow(
                icon: Icons.schedule_rounded,
                label: easy.tr("info.totalDuration"),
                value: fmtDur(Duration(milliseconds: totalMs)),
              ),
              if (discCount > 1)
                _InfoRow(
                  icon: Icons.library_music_rounded,
                  label: easy.tr("info.discCount"),
                  value: '$discCount',
                ),
              if (releaseYear != null)
                _InfoRow(
                  icon: Icons.calendar_month_rounded,
                  label: easy.tr("info.releaseYear"),
                  value: releaseYear.toString(),
                ),
            ],
          );
        },
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: txt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(value, style: txt.bodyLarge?.copyWith(color: cs.onSurface)),
        ],
      ),
    );
  }
}
