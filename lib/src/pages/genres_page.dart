import 'package:dearmusic/src/player_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

class GenrePickerPage extends StatelessWidget {
  final List<String> genres;
  final Future<List<SongModel>> Function(String genre) fetchSongs;
  final ValueChanged<SongModel> onOpenSong;

  const GenrePickerPage({
    super.key,
    required this.genres,
    required this.fetchSongs,
    required this.onOpenSong,
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

    final list = genres.toList()..sort((a, b) => a.compareTo(b));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        appBar: AppBar(
          systemOverlayStyle: overlay,
          title: const Text('Genre favorit'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          elevation: 0.5,
          backgroundColor: theme.scaffoldBackgroundColor,
          iconTheme: IconThemeData(color: cs.primary),
        ),
        body: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: list.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 1,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 5,
          ),
          itemBuilder: (ctx, i) {
            final g = list[i];

            return _GenreCard(
              label: g,
              colorScheme: cs,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => _GenreSongsPage(
                      title: g,
                      fetchSongs: () => fetchSongs(g),
                      onOpenSong: onOpenSong,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _GenreCard extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _GenreCard({
    required this.label,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;

    return Material(
      color: cs.surfaceContainerHighest.withOpacity(
        Theme.of(context).brightness == Brightness.light ? 1 : 0.18,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.55), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withOpacity(0.12),
                  border: Border.all(
                    color: cs.primary.withOpacity(0.45),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.library_music_rounded,
                  size: 18,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreSongsPage extends StatefulWidget {
  final String title;
  final Future<List<SongModel>> Function() fetchSongs;
  final ValueChanged<SongModel> onOpenSong;

  const _GenreSongsPage({
    required this.title,
    required this.fetchSongs,
    required this.onOpenSong,
  });

  @override
  State<_GenreSongsPage> createState() => _GenreSongsPageState();
}

class _GenreSongsPageState extends State<_GenreSongsPage> {
  late Future<List<SongModel>> _future;
  List<SongModel> _songs = const [];

  @override
  void initState() {
    super.initState();
    _future = widget.fetchSongs().then((v) {
      final filtered = v.where((s) => s.uri != null).toList();
      if (mounted) {
        setState(() {
          _songs = filtered;
        });
      } else {
        _songs = filtered;
      }
      return filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ctrl = PlayerScope.of(context);
    final canPlay = _songs.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
            onPressed: !canPlay
                ? null
                : () async {
                    HapticFeedback.lightImpact();
                    await ctrl.playQueue(_songs);
                  },
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          IconButton(
            tooltip: 'Shuffle',
            onPressed: !canPlay
                ? null
                : () async {
                    HapticFeedback.lightImpact();
                    await ctrl.playQueue(_songs, shuffle: true);
                  },
            icon: const Icon(Icons.shuffle_rounded),
          ),
        ],
        elevation: 0.5,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        iconTheme: IconThemeData(color: cs.primary),
      ),
      body: FutureBuilder<List<SongModel>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done && _songs.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final list = (snap.data ?? _songs);
          if (list.isEmpty) {
            return Center(
              child: Text(
                'Tidak ada lagu untuk genre ini',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }

          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
            itemBuilder: (ctx, i) {
              final s = list[i];
              return ListTile(
                leading: QueryArtworkWidget(
                  id: s.albumId ?? s.id,
                  type: s.albumId != null
                      ? ArtworkType.ALBUM
                      : ArtworkType.AUDIO,
                  size: 128,
                  artworkFit: BoxFit.cover,
                  nullArtworkWidget: const Icon(Icons.music_note_rounded),
                ),
                title: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    s.artist,
                    s.genre,
                  ].where((e) => (e ?? '').isNotEmpty).join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onOpenSong(s);
                },
              );
            },
          );
        },
      ),
    );
  }
}
