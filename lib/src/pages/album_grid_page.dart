import 'package:dearmusic/src/logic/pin_hub.dart';
import 'package:dearmusic/src/models/pinned_model.dart';
import 'package:dearmusic/src/widgets/album_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AlbumGridPage extends StatelessWidget {
  final String title;
  final List<AlbumModel> albums;
  final OnAudioQuery query;
  final Future<void> Function(AlbumModel) onOpen;
  final Future<void> Function(AlbumModel) onPin;

  const AlbumGridPage({
    super.key,
    required this.title,
    required this.albums,
    required this.query,
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: PopScope(
        canPop: true,
        onPopInvoked: (didPop) {},
        child: Scaffold(
          appBar: AppBar(
            systemOverlayStyle: overlay,
            title: Text(title),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
            ),
            actions: [
              IconButton(
                tooltip: 'Search Album',
                icon: const Icon(Icons.search_rounded),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await showSearch<AlbumModel?>(
                    context: context,
                    delegate: AlbumSearchDelegate(
                      albums: albums,
                      queryApi: query,
                      onOpen: onOpen,
                    ),
                  );
                },
              ),
            ],
            elevation: 0.5,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            iconTheme: IconThemeData(color: cs.primary),
          ),
          body: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: albums.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 0,
              crossAxisSpacing: 6,
              childAspectRatio: 0.70,
            ),
            itemBuilder: (_, i) {
              final a = albums[i];
              return AlbumCard(
                album: a,
                query: query,
                onOpen: () async => onOpen(a),
                onPin: () async => onPin(a),
                isPin: PinHub.I.isPinned(PinKind.album, a.id),
              );
            },
          ),
        ),
      ),
    );
  }
}

class AlbumSearchDelegate extends SearchDelegate<AlbumModel?> {
  final List<AlbumModel> albums;
  final OnAudioQuery queryApi;
  final Future<void> Function(AlbumModel) onOpen;

  AlbumSearchDelegate({
    required this.albums,
    required this.queryApi,
    required this.onOpen,
  }) : super(
         searchFieldLabel: 'Search Album or Artist',
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
    final filtered = _filter(albums, query);
    return _AlbumGridResult(
      albums: filtered,
      queryApi: queryApi,
      onOpen: onOpen,
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final filtered = _filter(albums, query);

    final data = query.trim().isEmpty ? albums.take(18).toList() : filtered;
    return _AlbumGridResult(albums: data, queryApi: queryApi, onOpen: onOpen);
  }

  List<AlbumModel> _filter(List<AlbumModel> src, String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return src;
    bool match(AlbumModel a) {
      final album = (a.album).toLowerCase();
      final artist = (a.artist ?? '').toLowerCase();
      return album.contains(s) || artist.contains(s);
    }

    final out = src.where(match).toList();
    out.sort((a, b) {
      final sAlbumA = (a.album).toLowerCase().contains(s) ? 0 : 1;
      final sAlbumB = (b.album).toLowerCase().contains(s) ? 0 : 1;
      final sArtistA = (a.artist ?? '').toLowerCase().contains(s) ? 0 : 1;
      final sArtistB = (b.artist ?? '').toLowerCase().contains(s) ? 0 : 1;
      final rankA = sAlbumA * 2 + sArtistA;
      final rankB = sAlbumB * 2 + sArtistB;
      return rankA.compareTo(rankB);
    });
    return out;
  }
}

class _AlbumGridResult extends StatelessWidget {
  final List<AlbumModel> albums;
  final OnAudioQuery queryApi;
  final Future<void> Function(AlbumModel) onOpen;

  const _AlbumGridResult({
    required this.albums,
    required this.queryApi,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (albums.isEmpty) {
      return Center(
        child: Text(
          'Tidak ada hasil',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: albums.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 0,
        crossAxisSpacing: 6,
        childAspectRatio: 0.70,
      ),
      itemBuilder: (_, i) {
        final a = albums[i];
        return AlbumCard(
          album: a,
          query: queryApi,
          onOpen: () async {
            HapticFeedback.lightImpact();
            await onOpen(a);
          },
        );
      },
    );
  }
}
