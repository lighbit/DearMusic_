import 'dart:ui';
import 'package:dearmusic/src/logic/artist_info_service.dart';
import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:dearmusic/src/logic/pin_hub.dart';
import 'package:dearmusic/src/models/pinned_model.dart';
import 'package:dearmusic/src/widgets/album_card.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

class ArtistPageElegant extends StatelessWidget {
  final ArtistModel artist;
  final List<AlbumModel> primary;
  final List<AlbumModel> appearsOn;
  final OnAudioQuery query;
  final Future<void> Function(AlbumModel) onOpenAlbum;
  final Future<void> Function(AlbumModel)? onPinAlbum;

  const ArtistPageElegant({
    super.key,
    required this.artist,
    required this.primary,
    required this.appearsOn,
    required this.query,
    required this.onOpenAlbum,
    required this.onPinAlbum,
  });

  List<AlbumModel> _dedupeList(List<AlbumModel> src) {
    final seen = <String>{};
    final out = <AlbumModel>[];
    for (final a in src) {
      final name = (a.album ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final artist = (a.artist ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final key = '$name|$artist';
      if (seen.add(key)) out.add(a);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final name = artist.artist ?? 'Artist';
    final bannerId = (primary.isNotEmpty ? primary : appearsOn).isNotEmpty
        ? (primary.isNotEmpty ? primary.first.id : appearsOn.first.id)
        : null;

    final brightness = Theme.of(context).brightness;

    final primaryClean = _dedupeList(primary);
    final appearsClean0 = _dedupeList(appearsOn);
    final primaryKeys = primaryClean.map((a) {
      final name = (a.album ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final artist = (a.artist ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return '$name|$artist';
    }).toSet();
    final appearsClean = appearsClean0.where((a) {
      final name = (a.album ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final artist = (a.artist ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return !primaryKeys.contains('$name|$artist');
    }).toList();

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
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 200,
              backgroundColor: cs.surface,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    FutureBuilder<Widget>(
                      future: _buildArtistBanner(
                        context,
                        artist,
                        query,
                        bannerFallbackAlbumId: bannerId,
                      ),
                      builder: (_, snap) =>
                          snap.data ??
                          Container(color: cs.surfaceContainerHighest),
                    ),

                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            cs.surface.withOpacity(0.55),
                            cs.surface,
                          ],
                        ),
                      ),
                    ),

                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _ArtistCircleSmart(
                              artist: artist,
                              query: query,
                              fallbackAlbumId: bannerId,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ArtistHeaderBlock(
                                name: name,
                                primaryCount: primary.length,
                                appearsOnCount: appearsOn.length,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(10),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: cs.outlineVariant.withOpacity(0.6),
                ),
              ),
            ),

            if (primaryClean.isNotEmpty) _sectionHeader(context, 'Albums'),
            if (primaryClean.isNotEmpty)
              _AlbumGrid(
                albums: primaryClean,
                query: query,
                onOpen: onOpenAlbum,
                onPin: onPinAlbum!,
              ),

            if (appearsClean.isNotEmpty) _sectionHeader(context, 'Appears on'),
            if (appearsClean.isNotEmpty)
              _AlbumGrid(
                albums: appearsClean,
                query: query,
                onOpen: onOpenAlbum,
                onPin: onPinAlbum!,
              ),

            if (primary.isEmpty && appearsOn.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Tidak ada album.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _sectionHeader(BuildContext ctx, String title) {
    final txt = Theme.of(ctx).textTheme;
    final cs = Theme.of(ctx).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Row(
          children: [
            Text(
              title,
              style: txt.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumGrid extends StatefulWidget {
  final List<AlbumModel> albums;
  final OnAudioQuery query;
  final Future<void> Function(AlbumModel) onOpen;
  final Future<void> Function(AlbumModel) onPin;

  const _AlbumGrid({
    required this.albums,
    required this.query,
    required this.onOpen,
    required this.onPin,
  });

  @override
  State<_AlbumGrid> createState() => _AlbumGridState();
}

class _AlbumGridState extends State<_AlbumGrid> {
  Future<void> _handlePin(AlbumModel album) async {
    if (album.id <= 0) return;
    await widget.onPin(album);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, i) {
          final album = widget.albums[i];
          final int safeId = album.id;
          if (safeId <= 0) {
            return _AlbumGhostTile(title: album.album, subtitle: album.artist);
          }
          return KeyedSubtree(
            key: ValueKey(safeId),
            child: AlbumCard(
              album: album,
              query: widget.query,
              onOpen: () => widget.onOpen(album),
              onPin: () => _handlePin(album),
              isPin: PinHub.I.isPinned(PinKind.album, album.id),
            ),
          );
        }, childCount: widget.albums.length),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 0,
          crossAxisSpacing: 8,
          childAspectRatio: 0.75,
        ),
      ),
    );
  }
}

class _AlbumGhostTile extends StatelessWidget {
  final String? title;
  final String? subtitle;

  const _AlbumGhostTile({this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.album_outlined, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title ?? 'Unknown album',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            subtitle ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ArtistHeaderBlock extends StatelessWidget {
  final String name;
  final int primaryCount;
  final int appearsOnCount;

  const _ArtistHeaderBlock({
    required this.name,
    required this.primaryCount,
    required this.appearsOnCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: txt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 16),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (primaryCount > 0)
              _MetricChip(label: 'Albums', value: '$primaryCount'),
            if (appearsOnCount > 0)
              _MetricChip(label: 'Appears on', value: '$appearsOnCount'),
          ],
        ),
        const SizedBox(height: 10),

        FutureBuilder<_ResolvedArtistDesc?>(
          future: _getResolvedArtistDesc(name, context),
          builder: (context, snap) {
            final data = snap.data;
            final text = data?.text?.trim();

            if (text == null || text.isEmpty) {
              return GestureDetector(
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await showArtistInfoSheet(context, artistName: name);
                },
                child: Text(
                  'Tambahkan deskripsi artis…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }

            return GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                await showArtistInfoSheet(context, artistName: name);
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      text.length > 180 ? '${text.substring(0, 180)}…' : text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (data?.isUserOverride == true)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.edit_rounded, size: 16),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Text(
        '$label: $value',
        style: txt.labelLarge?.copyWith(color: cs.onSurface),
      ),
    );
  }
}

class _ArtistCircleSmart extends StatelessWidget {
  final ArtistModel artist;
  final OnAudioQuery query;
  final int? fallbackAlbumId;

  const _ArtistCircleSmart({
    required this.artist,
    required this.query,
    required this.fallbackAlbumId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final int? artistId = ((artist.id ?? 0) > 0) ? artist.id : null;

    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: cs.surfaceContainerHighest, width: 3),
      ),
      child: ClipOval(
        child: artistId != null
            ? FutureBuilder<Uint8List?>(
                future: query.queryArtwork(
                  artistId,
                  ArtworkType.ARTIST,
                  format: ArtworkFormat.JPEG,
                  size: 512,
                  quality: 80,
                ),
                builder: (_, snap) {
                  final bytes = snap.data;
                  if (bytes != null && bytes.isNotEmpty) {
                    return Image.memory(bytes, fit: BoxFit.cover);
                  }
                  return _fallbackAlbumOrNull(context);
                },
              )
            : _fallbackAlbumOrNull(context),
      ),
    );
  }

  Widget _fallbackAlbumOrNull(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (fallbackAlbumId != null) {
      return FutureBuilder<Widget>(
        future: ArtworkMemCache.I.imageWidget(
          id: fallbackAlbumId!,
          type: ArtworkType.ALBUM,
          slot: ArtworkSlot.gridSmall,
          radius: BorderRadius.circular(12),
          placeholder: _nullArt(context),
        ),
        builder: (_, s2) => s2.data ?? _nullArt(context),
      );
    }
    return _nullArt(context);
  }

  Widget _nullArt(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, color: cs.onSurfaceVariant),
    );
  }
}

Future<Widget> _buildArtistBanner(
  BuildContext context,
  ArtistModel artist,
  OnAudioQuery query, {
  required int? bannerFallbackAlbumId,
}) async {
  final cs = Theme.of(context).colorScheme;
  Uint8List? bytes;
  try {
    bytes = await query.queryArtwork(
      artist.id,
      ArtworkType.ARTIST,
      format: ArtworkFormat.JPEG,
      size: 1024,
      quality: 80,
    );
  } catch (_) {}

  Widget base;
  if (bytes != null && bytes.isNotEmpty) {
    base = Image.memory(bytes, fit: BoxFit.cover);
  } else if (bannerFallbackAlbumId != null) {
    base = await ArtworkMemCache.I.imageWidget(
      id: bannerFallbackAlbumId,
      type: ArtworkType.ALBUM,
      slot: ArtworkSlot.gridSmall,
      radius: BorderRadius.circular(12),
      placeholder: _bannerShimmer(context),
    );
  } else {
    base = _bannerShimmer(context);
  }

  return Stack(
    fit: StackFit.expand,
    children: [
      base,
      Positioned.fill(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: const SizedBox(),
        ),
      ),
    ],
  );
}

Widget _bannerShimmer(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Shimmer.fromColors(
    baseColor: cs.surfaceContainerHighest,
    highlightColor: cs.surfaceContainerLow,
    child: Container(color: cs.surfaceContainerHighest),
  );
}

class _ArtistSummaryCache {
  static final _mem = <String, Future<ArtistDescription?>>{};

  static Future<ArtistDescription?> get(
    String artistName,
    BuildContext context,
  ) {
    return _mem.putIfAbsent(artistName.toLowerCase(), () async {
      final svc = WikipediaArtisService(
        userAgent: 'DearMusic/1.0 (https://dearmeapp.id; support@dearmeapp.id)',
      );
      return await svc.getArtistDescription(
        name: artistName,
        preferredLang: context.locale.languageCode,
      );
    });
  }
}

Future<void> showArtistInfoSheet(
  BuildContext context, {
  required String artistName,
}) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;

  final box = GetStorage();
  final storageKey = 'artist_desc_${artistName.toLowerCase()}';
  final initialCustom = box.read<String>(storageKey) ?? '';
  final textController = TextEditingController(text: initialCustom);

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
        initialChildSize: 0.60,
        minChildSize: 0.40,
        maxChildSize: 0.95,
        builder: (context, scroll) {
          return StatefulBuilder(
            builder: (context, setState) {
              return FutureBuilder<ArtistDescription?>(
                future: _ArtistSummaryCache.get(artistName, context),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return _ArtistInfoSheetShimmer(scroll: scroll);
                  }

                  final data = snap.data;
                  final wikiExtract = data?.extract?.trim();
                  final source = data?.sourceUrl;
                  final lang = data?.lang?.toUpperCase();

                  final customText = box.read<String>(storageKey)?.trim();
                  final hasCustom = customText != null && customText.isNotEmpty;
                  final effectiveText = hasCustom
                      ? customText
                      : (wikiExtract?.isNotEmpty == true ? wikiExtract : null);

                  return CustomScrollView(
                    controller: scroll,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            10,
                            16,
                            MediaQuery.of(context).viewInsets.bottom + 16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                artistName,
                                style: txt.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 16),

                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (lang != null)
                                    _chip(context, label: 'Lang: $lang'),
                                  if (source != null)
                                    GestureDetector(
                                      onTap: () async {
                                        HapticFeedback.lightImpact();
                                        await _openUrl(
                                          context,
                                          source.toString(),
                                        );
                                      },
                                      child: _chip(context, label: 'Wikipedia'),
                                    ),
                                  if (hasCustom)
                                    _chip(context, label: 'Custom aktif'),
                                ],
                              ),

                              const SizedBox(height: 14),

                              if (effectiveText != null &&
                                  effectiveText.isNotEmpty)
                                Text(
                                  effectiveText,
                                  style: txt.bodyLarge?.copyWith(
                                    color: cs.onSurface,
                                    height: 1.35,
                                  ),
                                )
                              else
                                Text(
                                  'Tidak ada ringkasan yang tersedia.',
                                  style: txt.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),

                              const SizedBox(height: 18),

                              Row(
                                children: [
                                  _pillButton(
                                    context,
                                    icon: Icons.open_in_new_rounded,
                                    label: 'Buka sumber',
                                    onTap: source == null
                                        ? null
                                        : () async {
                                            HapticFeedback.lightImpact();
                                            await _openUrl(
                                              context,
                                              source.toString(),
                                            );
                                          },
                                  ),
                                  const SizedBox(width: 8),
                                  _pillButton(
                                    context,
                                    icon: Icons.link_rounded,
                                    label: 'Salin tautan',
                                    onTap: source == null
                                        ? null
                                        : () async {
                                            HapticFeedback.lightImpact();
                                            await Clipboard.setData(
                                              ClipboardData(
                                                text: source.toString(),
                                              ),
                                            );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    'Tautan disalin',
                                                  ),
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  backgroundColor: cs.primary,
                                                ),
                                              );
                                            }
                                          },
                                  ),
                                ],
                              ),

                              const SizedBox(height: 22),

                              Text(
                                'Deskripsi kustom kamu',
                                style: txt.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: textController,
                                maxLines: 6,
                                textInputAction: TextInputAction.newline,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Tulis deskripsi artis versi kamu...',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  FilledButton.icon(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      final t = textController.text.trim();
                                      if (t.isEmpty) {
                                        box.remove(storageKey);
                                      } else {
                                        box.write(storageKey, t);
                                      }
                                      HapticFeedback.lightImpact();
                                      setState(() {});
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              t.isEmpty ? 'Deleted' : 'Saved',
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.save_rounded),
                                    label: const Text('Save'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      box.remove(storageKey);
                                      textController.clear();
                                      setState(() {});
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Reset ke sumber asli',
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.restore_rounded),
                                    label: const Text('Reset'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
  );
}

Widget _chip(BuildContext context, {required String label}) {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
    ),
    child: Text(label, style: txt.labelLarge?.copyWith(color: cs.onSurface)),
  );
}

Widget _pillButton(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final enabled = onTap != null;
  return InkWell(
    onTap: () {
      HapticFeedback.lightImpact();
      onTap!();
    },
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: enabled ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: enabled ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: enabled ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ArtistInfoSheetShimmer extends StatelessWidget {
  final ScrollController scroll;

  const _ArtistInfoSheetShimmer({required this.scroll});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Shimmer.fromColors(
                  baseColor: cs.surfaceContainerHighest,
                  highlightColor: cs.surfaceContainerLow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 24,
                        width: 180,
                        color: cs.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            height: 28,
                            width: 100,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            height: 28,
                            width: 120,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 12,
                        width: double.infinity,
                        color: cs.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: double.infinity,
                        color: cs.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: MediaQuery.of(context).size.width * 0.7,
                        color: cs.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            height: 36,
                            width: 130,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            height: 36,
                            width: 130,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _openUrl(BuildContext context, String nameOrUrl) async {
  Uri target;
  if (nameOrUrl.startsWith('http')) {
    target = Uri.parse(nameOrUrl);
  } else {
    final title = normalizeWikiTitle(nameOrUrl);
    target = Uri.parse('https://id.wikipedia.org/wiki/$title');
  }
  await launchUrl(target, mode: LaunchMode.externalApplication);
}

class _ResolvedArtistDesc {
  final String? text;
  final bool isUserOverride;

  _ResolvedArtistDesc({this.text, this.isUserOverride = false});
}

Future<_ResolvedArtistDesc?> _getResolvedArtistDesc(
  String name,
  BuildContext context,
) async {
  final box = GetStorage();
  final key = 'artist_desc_${name.toLowerCase()}';
  final userText = box.read<String>(key);

  if (userText != null && userText.trim().isNotEmpty) {
    return _ResolvedArtistDesc(text: userText.trim(), isUserOverride: true);
  }

  final cached = await _ArtistSummaryCache.get(name, context);
  final text = cached?.extract?.trim();
  return _ResolvedArtistDesc(text: text, isUserOverride: false);
}
