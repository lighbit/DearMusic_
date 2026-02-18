import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:dearmusic/src/logic/pin_hub.dart';
import 'package:dearmusic/src/models/pinned_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

class ArtistListPage extends StatelessWidget {
  final String title;
  final List<ArtistModel> artists;
  final OnAudioQuery query;
  final bool Function(String path) allowedByUser;
  final Future<void> Function(ArtistModel) onOpen;
  final Future<void> Function(ArtistModel) onPin;

  const ArtistListPage({
    super.key,
    required this.title,
    required this.artists,
    required this.query,
    required this.allowedByUser,
    required this.onOpen,
    required this.onPin,
  });

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

    final deduped = _dedupeArtists(artists);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: PopScope(
        canPop: true,
        onPopInvoked: (didPop) {},
        child: Scaffold(
          appBar: AppBar(
            systemOverlayStyle: overlay,
            title: Text('$title (${artists.length})'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
            ),
            actions: [
              IconButton(
                tooltip: 'Search Artist',
                icon: const Icon(Icons.search_rounded),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await showSearch<ArtistModel?>(
                    context: context,
                    delegate: ArtistSearchDelegate(
                      artists: artists,
                      onOpen: onOpen,
                      audioQuery: query,
                      allowedByUser: allowedByUser,
                    ),
                  );
                },
              ),
            ],
            elevation: 0.5,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            iconTheme: IconThemeData(color: cs.primary),
          ),
          body: _ArtistList(
            artists: deduped,
            query: query,
            allowedByUser: allowedByUser,
            onOpen: onOpen,
            onPin: onPin,
          ),
        ),
      ),
    );
  }

  List<ArtistModel> _dedupeArtists(List<ArtistModel> src) {
    String norm(String? s) => (s ?? '').trim().toLowerCase();
    final seen = <String>{};
    final out = <ArtistModel>[];
    for (final a in src) {
      final key = norm(a.artist);
      if (key.isEmpty) continue;
      if (seen.add(key)) out.add(a);
    }
    return out;
  }
}

class _ArtistList extends StatelessWidget {
  final List<ArtistModel> artists;
  final OnAudioQuery query;
  final bool Function(String path) allowedByUser;
  final Future<void> Function(ArtistModel) onOpen;
  final Future<void> Function(ArtistModel) onPin;

  const _ArtistList({
    required this.artists,
    required this.query,
    required this.allowedByUser,
    required this.onOpen,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: artists.length,
      separatorBuilder: (_, __) => Divider(
        height: 12,
        thickness: 0.6,
        color: cs.outlineVariant.withOpacity(0.4),
      ),
      itemBuilder: (_, i) {
        final ar = artists[i];
        return InkWell(
          onTap: () async {
            HapticFeedback.lightImpact();
            await onOpen(ar);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: FutureBuilder<Widget>(
                      future: ArtworkMemCache.I.imageWidget(
                        id: ar.id,
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
                          snap.data ?? const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ArtistTitleSubtitle(
                    ar: ar,
                    query: query,
                    allowedByUser: allowedByUser,
                  ),
                ),

                StreamBuilder<void>(
                  stream: PinHub.I.changes,
                  builder: (context, _) {
                    final pinned = PinHub.I.isPinned(PinKind.artist, ar.id);
                    return IconButton(
                      tooltip: pinned ? 'Batalkan sematan' : 'Sematkan',
                      icon: Icon(
                        pinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        color: pinned
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: () async {
                        HapticFeedback.selectionClick();
                        await onPin(ar);
                      },
                    );
                  },
                ),

                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ArtistTitleSubtitle extends StatelessWidget {
  final ArtistModel ar;
  final OnAudioQuery query;
  final bool Function(String path) allowedByUser;

  const _ArtistTitleSubtitle({
    required this.ar,
    required this.query,
    required this.allowedByUser,
  });

  static final _memo = <int, Future<(int tracks, int albums)>>{};

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ar.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: txt.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),

        FutureBuilder<(int tracks, int albums)>(
          future: _memo.putIfAbsent(ar.id, () => _computeCounts(ar)),
          builder: (context, snap) {
            if (!snap.hasData) {
              return Text(
                'Menghitung…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: txt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              );
            }
            final (tracks, albums) = snap.data!;
            final text = albums > 0
                ? '$tracks lagu • $albums album'
                : '$tracks lagu';
            return Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: txt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            );
          },
        ),
      ],
    );
  }

  Future<(int tracks, int albums)> _computeCounts(ArtistModel ar) async {
    String norm(String? s) => (s ?? '').trim().toLowerCase();
    final me = norm(ar.artist);

    List<SongModel> songs = [];
    final int? artistId = (ar.id is int) ? ar.id : int.tryParse('${ar.id}');
    if (artistId != null && artistId > 0) {
      try {
        songs = await query.queryAudiosFrom(
          AudiosFromType.ARTIST_ID,
          artistId,
          sortType: SongSortType.ALBUM,
          orderType: OrderType.ASC_OR_SMALLER,
        );
      } catch (_) {}
    }
    if (songs.isEmpty) {
      try {
        final all = await query.querySongs(
          sortType: SongSortType.ARTIST,
          orderType: OrderType.ASC_OR_SMALLER,
        );
        songs = all.where((s) {
          final goodName = norm(s.artist) == me;
          final d = s.data;
          final pathOk = allowedByUser(d);
          final title = (s.title).toLowerCase();
          final junk = title.contains('notif') || title.contains('ringtone');
          return goodName && pathOk && !junk && (s.uri?.isNotEmpty == true);
        }).toList();
      } catch (_) {}
    }

    final seen = <String>{};
    int albums = 0;
    for (final s in songs) {
      final albumName = (s.album ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final artistName = (s.artist ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final key = '$albumName|$artistName';
      if (seen.add(key)) albums++;
    }
    final tracks = songs.length;
    return (tracks, albums);
  }
}

class ArtistSearchDelegate extends SearchDelegate<ArtistModel?> {
  final List<ArtistModel> artists;
  final Future<void> Function(ArtistModel) onOpen;
  final OnAudioQuery audioQuery;
  final bool Function(String path) allowedByUser;

  ArtistSearchDelegate({
    required this.artists,
    required this.onOpen,
    required this.audioQuery,
    required this.allowedByUser,
  }) : super(
         searchFieldLabel: 'Search Artist…',
         keyboardType: TextInputType.text,
         textInputAction: TextInputAction.search,
       );

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: base.textTheme.bodyMedium?.copyWith(
          color: base.colorScheme.onSurfaceVariant,
        ),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Hapus',
        icon: const Icon(Icons.clear_rounded),
        onPressed: () {
          HapticFeedback.selectionClick();
          query = '';
          showSuggestions(context);
        },
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: 'Kembali',
    icon: const Icon(Icons.arrow_back_ios_new_rounded),
    onPressed: () {
      HapticFeedback.lightImpact();
      close(context, null);
    },
  );

  @override
  Widget buildResults(BuildContext context) {
    final data = _filter(artists, query);
    return _ArtistResultList(
      artists: data,
      onOpen: onOpen,
      audioQuery: audioQuery,
      allowedByUser: allowedByUser,
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final s = query.trim();
    final data = s.isEmpty ? artists.take(30).toList() : _filter(artists, s);
    return _ArtistResultList(
      artists: data,
      onOpen: onOpen,
      audioQuery: audioQuery,
      allowedByUser: allowedByUser,
    );
  }

  List<ArtistModel> _filter(List<ArtistModel> src, String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return src;
    bool match(ArtistModel a) {
      final name = a.artist.toLowerCase();
      final albums = (a.numberOfAlbums ?? 0).toString();
      final tracks = (a.numberOfTracks ?? 0).toString();
      return name.contains(s) || albums.contains(s) || tracks.contains(s);
    }

    final out = src.where(match).toList();
    out.sort((a, b) {
      final na = a.artist.toLowerCase().contains(s) ? 0 : 1;
      final nb = b.artist.toLowerCase().contains(s) ? 0 : 1;
      return na.compareTo(nb);
    });
    return out;
  }
}

class _ArtistResultList extends StatelessWidget {
  final List<ArtistModel> artists;
  final Future<void> Function(ArtistModel) onOpen;
  final OnAudioQuery audioQuery;
  final bool Function(String path) allowedByUser;

  const _ArtistResultList({
    required this.artists,
    required this.onOpen,
    required this.audioQuery,
    required this.allowedByUser,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (artists.isEmpty) {
      return Center(
        child: Text(
          'Tidak ada hasil',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: artists.length,
      separatorBuilder: (_, __) => Divider(
        height: 12,
        thickness: 0.6,
        color: cs.outlineVariant.withOpacity(0.4),
      ),
      itemBuilder: (_, i) {
        final ar = artists[i];
        return InkWell(
          onTap: () async {
            HapticFeedback.lightImpact();
            await onOpen(ar);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: FutureBuilder<Widget>(
                      future: ArtworkMemCache.I.imageWidget(
                        id: ar.id,
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
                      builder: (_, snap) => snap.data ?? SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ArtistTitleSubtitle(
                    ar: ar,
                    query: audioQuery,
                    allowedByUser: allowedByUser,
                  ),
                ),

                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
