import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:dearmusic/src/logic/pin_hub.dart';
import 'package:dearmusic/src/logic/play_actions.dart';
import 'package:dearmusic/src/models/pinned_model.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../player_scope.dart';

class SongListPage extends StatefulWidget {
  final String title;
  final List<SongModel> songs;

  const SongListPage({super.key, required this.title, required this.songs});

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  final _storage = GetStorage();
  final _pinKey = 'pinned_songs';

  final String _sortKey = 'date_desc';
  String _query = '';

  final _queryAudio = OnAudioQuery();
  final List<int> _pinnedIds = [];
  List<SongModel> _pinned = [];

  @override
  void initState() {
    super.initState();
    _loadPinned();
  }

  Future<void> _loadPinned() async {
    final raw = _storage.read<List>(_pinKey);
    List<int> ids = [];
    List<PinnedSnapshot> snaps = [];

    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      snaps = raw
          .cast<Map>()
          .map((m) => PinnedSnapshot.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      ids = snaps.map((e) => e.id).toList();
    } else {
      final old = _storage.read<List>(_pinKey);
      if (old != null) {
        ids = old.cast<int>();
      }
    }

    _pinnedIds
      ..clear()
      ..addAll(ids);

    if (snaps.isNotEmpty) {
      final provisional = snaps.map((p) {
        return SongModel({
          'id': p.id,
          'title': p.title ?? 'Unknown',
          'artist': p.artist ?? '',
          'uri': p.uri,
        });
      }).toList();
      if (mounted) setState(() => _pinned = provisional);
    } else if (ids.isEmpty) {
      if (mounted) setState(() => _pinned = []);
      return;
    }

    final all = await _queryAudio.querySongs(
      sortType: SongSortType.DISPLAY_NAME,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
    );
    await _hydratePinnedFromAllSongs(all);

    final payload = _pinned
        .map((e) => PinnedSnapshot.fromSong(e).toJson())
        .toList();
    _storage.write(_pinKey, payload);
  }

  Future<void> _hydratePinnedFromAllSongs(List<SongModel> allSongs) async {
    if (_pinnedIds.isEmpty) {
      if (mounted) setState(() => _pinned = []);
      return;
    }
    final byId = {for (final s in allSongs) s.id: s};
    final resolved = _pinnedIds
        .map((id) => byId[id])
        .whereType<SongModel>()
        .toList();

    if (mounted) setState(() => _pinned = resolved);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
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

    final PlayerController ctrl = PlayerScope.of(context);

    final base = widget.songs;
    final filtered = (_query.isEmpty)
        ? base
        : base.where((s) {
            final t = s.title.toLowerCase();
            final a = (s.artist ?? '').toLowerCase();
            final q = _query.toLowerCase();
            return t.contains(q) || a.contains(q);
          }).toList();

    filtered.sort((a, b) {
      switch (_sortKey) {
        case 'title_asc':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'title_desc':
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        case 'artist_asc':
          return (a.artist ?? '').toLowerCase().compareTo(
            (b.artist ?? '').toLowerCase(),
          );
        case 'artist_desc':
          return (b.artist ?? '').toLowerCase().compareTo(
            (a.artist ?? '').toLowerCase(),
          );
        case 'duration_asc':
          return (a.duration ?? 0).compareTo(b.duration ?? 0);
        case 'duration_desc':
          return (b.duration ?? 0).compareTo(a.duration ?? 0);
        case 'date_desc':
        default:
          return (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0);
      }
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: PopScope(
        canPop: true,
        onPopInvoked: (didPop) {},
        child: Scaffold(
          appBar: AppBar(
            systemOverlayStyle: overlay,
            title: Text('${widget.title} (${widget.songs.length})'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
            ),
            actions: [
              IconButton(
                tooltip: 'Play all',
                onPressed: filtered.isEmpty
                    ? null
                    : () async {
                        HapticFeedback.lightImpact();
                        await ctrl.playQueue(filtered);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              IconButton(
                tooltip: 'Shuffle',
                onPressed: filtered.isEmpty
                    ? null
                    : () async {
                        HapticFeedback.lightImpact();
                        await ctrl.playQueue(filtered, shuffle: true);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.shuffle_rounded),
              ),
            ],
            elevation: 0.5,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            iconTheme: IconThemeData(color: cs.primary),
          ),

          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  onChanged: (v) {
                    HapticFeedback.lightImpact();
                    setState(() => _query = v);
                  },
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cari lagu atau artis',
                    prefixIcon: const Icon(Icons.search_rounded),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              Expanded(
                child: filtered.isEmpty
                    ? _EmptyState(
                        title: 'Tidak ada lagu',
                        subtitle: _query.isEmpty
                            ? 'Daftar kosong.'
                            : 'Tidak ada hasil untuk "$_query".',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final s = filtered[i];
                          final isNowPlaying = ctrl.nowPlayingAlbumId == s.id;
                          final cs = Theme.of(context).colorScheme;
                          final tt = Theme.of(context).textTheme;

                          final baseBg = cs.surfaceContainerHigh;
                          final activeBg = Color.alphaBlend(
                            cs.primary.withOpacity(0.08),
                            baseBg,
                          );
                          final bg = isNowPlaying ? activeBg : baseBg;
                          final borderColor = isNowPlaying
                              ? cs.primary.withOpacity(0.65)
                              : cs.outlineVariant.withOpacity(0.45);

                          final durLabel = s.duration != null
                              ? _fmtDuration(
                                  Duration(milliseconds: s.duration!),
                                )
                              : '–';

                          return TweenAnimationBuilder<double>(
                            key: ValueKey('row_${s.id}_$isNowPlaying'),
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            tween: Tween(begin: 1, end: 1),
                            builder: (_, __, child) => Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  HapticFeedback.lightImpact();
                                  await ctrl.playQueue(filtered, startIndex: i);
                                  if (!mounted) return;
                                  Navigator.of(context).pop();
                                },
                                onLongPress: () => _openSongActions(context, s),
                                borderRadius: BorderRadius.circular(14),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: borderColor,
                                      width: isNowPlaying ? 1.2 : 1,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              boxShadow: isNowPlaying
                                                  ? [
                                                      BoxShadow(
                                                        color: cs.primary
                                                            .withOpacity(0.18),
                                                        blurRadius: 14,
                                                        offset: const Offset(
                                                          0,
                                                          4,
                                                        ),
                                                      ),
                                                    ]
                                                  : const [],
                                            ),
                                          ),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: SizedBox(
                                              width: 60,
                                              height: 60,
                                              child: FutureBuilder<Widget>(
                                                future: ArtworkMemCache.I.imageWidget(
                                                  id: s.id,
                                                  type: ArtworkType.AUDIO,
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
                                                    snap.data ??
                                                    SizedBox.expand(),
                                              ),
                                            ),
                                          ),
                                          if (isNowPlaying)
                                            Positioned(
                                              right: 4,
                                              bottom: 4,
                                              child: Icon(
                                                Icons.equalizer_rounded,
                                                size: 16,
                                                color: cs.primary,
                                              ),
                                            ),
                                        ],
                                      ),

                                      const SizedBox(width: 12),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: tt.titleMedium?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.2,
                                                color: cs.onSurface,
                                                height: 1.05,
                                              ),
                                            ),
                                            const SizedBox(height: 4),

                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.headphones_rounded,
                                                  size: 13,
                                                  color: cs.onSurfaceVariant
                                                      .withOpacity(0.85),
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    s.album ?? '—',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: tt.bodySmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: cs
                                                              .onSurfaceVariant
                                                              .withOpacity(
                                                                0.88,
                                                              ),
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),

                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.person_rounded,
                                                  size: 12,
                                                  color: cs.onSurfaceVariant
                                                      .withOpacity(0.75),
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    s.artist ?? '—',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: tt.bodySmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                          color: cs
                                                              .onSurfaceVariant
                                                              .withOpacity(
                                                                0.78,
                                                              ),
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(width: 8),

                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            durLabel,
                                            style: tt.labelMedium?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          IconButton(
                                            tooltip: 'Lainnya',
                                            icon: const Icon(
                                              Icons.more_horiz_rounded,
                                            ),
                                            onPressed: () {
                                              HapticFeedback.lightImpact();
                                              _openSongActions(context, s);
                                            },
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                  width: 36,
                                                  height: 36,
                                                ),
                                            padding: EdgeInsets.zero,
                                            splashRadius: 18,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m >= 60) {
      final h = d.inHours;
      final mm = (m % 60).toString().padLeft(2, '0');
      final ss = s.toString().padLeft(2, '0');
      return '$h:$mm:$ss';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _openSongActions(BuildContext context, SongModel s) async {
    final cs = Theme.of(context).colorScheme;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Putar lagu ini'),
              onTap: () async {
                HapticFeedback.lightImpact();
                await PlayActions.playNowSong(context, s);
                if (mounted) Navigator.pop(context);
              },
            ),

            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(easy.tr("common.addToQueue")),
              onTap: () async {
                HapticFeedback.lightImpact();
                await PlayActions.enqueueOne(context, s);
                if (mounted) Navigator.pop(context);
              },
            ),

            ListTile(
              leading: Icon(
                PinHub.I.isPinned(PinKind.song, s.id)
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
              ),
              title: Text(
                PinHub.I.isPinned(PinKind.song, s.id)
                    ? 'Lepas sematan'
                    : 'Sematkan',
              ),
              onTap: () async {
                HapticFeedback.lightImpact();
                await PinHub.I.toggleSong(
                  id: s.id,
                  title: s.title,
                  artist: s.artist,
                  artworkId: s.albumId ?? s.id,
                  artworkType: (s.albumId != null && s.albumId! > 0)
                      ? ArtworkType.ALBUM
                      : ArtworkType.AUDIO,
                );
                if (mounted) Navigator.pop(context);
                if (mounted) setState(() {});
              },
            ),

            const SizedBox(height: 6),
          ],
        ),
      ),
      backgroundColor: cs.surface,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_rounded, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              style: txt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: txt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
