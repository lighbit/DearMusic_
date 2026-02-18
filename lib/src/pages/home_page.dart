import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dearmusic/src/audio/AudioPermissionGate.dart';
import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:dearmusic/src/logic/in_app_review.dart';
import 'package:dearmusic/src/logic/pin_hub.dart';
import 'package:dearmusic/src/logic/play_actions.dart';
import 'package:dearmusic/src/logic/playlist_store.dart';
import 'package:dearmusic/src/logic/usage_tracker.dart';
import 'package:dearmusic/src/models/pinned_model.dart';
import 'package:dearmusic/src/models/playlist_models.dart';
import 'package:dearmusic/src/pages/album_detail_page.dart';
import 'package:dearmusic/src/pages/album_grid_page.dart';
import 'package:dearmusic/src/pages/artist_list_page.dart';
import 'package:dearmusic/src/pages/artist_page.dart';
import 'package:dearmusic/src/pages/settings_page.dart';
import 'package:dearmusic/src/pages/song_list_page.dart';
import 'package:dearmusic/src/player_scope.dart';
import 'package:dearmusic/src/widgets/album_card.dart';
import 'package:dearmusic/src/widgets/artist_chip.dart';
import 'package:dearmusic/src/pages/genres_page.dart';
import 'package:dearmusic/src/widgets/empty_library_widget.dart';
import 'package:dearmusic/src/widgets/permission_widget.dart';
import 'package:dearmusic/src/widgets/pinned_card.dart';
import 'package:dearmusic/src/widgets/playlist_card.dart';
import 'package:dearmusic/src/widgets/playlist_editor.dart';
import 'package:dearmusic/src/widgets/quick_categories.dart';
import 'package:dearmusic/src/widgets/quick_pill.dart';
import 'package:dearmusic/src/widgets/recent_chip_song.dart';
import 'package:dearmusic/src/widgets/section_header.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shimmer/shimmer.dart';

import '../logic/utils.dart';

enum PermState { unknown, checking, granted, denied, deniedPermanently }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final _query = OnAudioQuery();
  final _storage = GetStorage();
  final Map<int, SongModel> _songByIdCache = {};

  StreamSubscription? _pinSub;

  PermState _perm = PermState.unknown;
  bool _loadingMedia = false;
  bool _showQuickAccess = true;

  List<SongModel> _recentSongs = [];
  List<AlbumModel> _albums = [];
  List<ArtistModel> _artists = [];
  List<AlbumModel> _sortedAlbums = [];
  List<ArtistModel> _sortedArtists = [];
  List<SongModel> _topSongs = [];
  List<AlbumModel> _topAlbums = [];
  List<ArtistModel> _topArtists = [];
  List<String> _favGenres = [];
  List<SongModel> _recentPlayed = [];
  List<Playlist> _playlists = [];

  Completer<void>? _booting;

  Uint8List? _headerArt;
  static const double _headerExpanded = 140;

  bool get _scanAllPref =>
      (GetStorage().read(SettingsKeys.scanAll) as bool?) ?? true;

  List<String> get _allowedDirsPref =>
      (GetStorage().read<List>(SettingsKeys.allowedDirs)?.cast<String>()) ??
      const <String>[];

  String _normSlashLower(String p) => p.replaceAll('\\', '/').toLowerCase();

  @override
  void initState() {
    super.initState();
    _pinSub = PinHub.I.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _boot();
  }

  @override
  void dispose() {
    _pinSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_perm == PermState.granted && _recentSongs.isNotEmpty) {
      _pickRandomHeaderArt();
    }
  }

  Future<void> _boot() async {
    if (_booting != null) return _booting!.future;
    _booting = Completer<void>();

    if (mounted) {
      setState(() {
        _loadingMedia = true;
        _perm = PermState.checking;
      });
    }

    try {
      final ok = await PermissionService.instance.ensureForOnAudioQuery(
        _query,
        force: true,
      );

      if (!mounted) {
        _booting!.complete();
        return;
      }

      if (!ok) {
        if (mounted) {
          setState(() {
            _perm = PermState.denied;
          });
        }
        _booting!.complete();
        return;
      }

      if (mounted) setState(() => _perm = PermState.granted);

      try {
        await _safeInitMedia();
      } on PlatformException catch (e) {
        if (e.code == 'MissingPermissions') {
          if (mounted) setState(() => _perm = PermState.denied);
          _booting!.complete();
          return;
        }
        rethrow;
      }

      _booting!.complete();
    } catch (e, st) {
      if (mounted) setState(() => _perm = PermState.denied);
      _booting!.completeError(e, st);
    } finally {
      _booting = null;
      if (mounted) setState(() => _loadingMedia = false);
      await ReviewService.maybePrompt();
    }
  }

  Future<void> _reloadPlaylists() async {
    _playlists = await PlaylistStore.I.listPlaylists();
    if (mounted) setState(() {});
  }

  Future<void> _safeInitMedia() async {
    try {
      await _initMedia();
      if (mounted) setState(() => _perm = PermState.granted);
    } on PlatformException catch (e) {
      if (e.code == 'MissingPermissions') {
        if (mounted) setState(() => _perm = PermState.denied);
        return;
      }
      rethrow;
    }
  }

  Future<void> _initMedia() async {
    final allRaw = await _query.querySongs(
      sortType: SongSortType.DISPLAY_NAME,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final bool scanAll = _storage.read(SettingsKeys.scanAll) is bool
        ? (_storage.read(SettingsKeys.scanAll) as bool)
        : true;
    final List<String> allowedRootsRaw =
        (_storage.read<List>(SettingsKeys.allowedDirs)?.cast<String>()) ??
        const [];

    String normSlashLower(String p) => p.replaceAll('\\', '/').toLowerCase();

    final List<String> allowedRoots = allowedRootsRaw
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    bool allowedByUser(String filePathOrUri) {
      if (scanAll || allowedRoots.isEmpty) return true;

      final p = normSlashLower(filePathOrUri);

      final hitPath = allowedRoots
          .where((r) => !r.startsWith('content://'))
          .map(normSlashLower)
          .map((r) => r.endsWith('/') ? r : '$r/')
          .any((root) => p.startsWith(root));

      if (hitPath) return true;

      final hitTree = allowedRoots
          .where((r) => r.startsWith('content://'))
          .map(
            (r) => Uri.decodeComponent(r).toLowerCase().replaceAll('%3a', ':'),
          )
          .any((tree) => p.contains(tree));

      return hitTree;
    }

    bool badPath(String path) {
      final p = path.toLowerCase().replaceAll('\\', '/');
      const badDirs = <String>[
        '/whatsapp/',
        '/voice notes',
        '/whatsapp audio',
        '/telegram/',
        '/telegram audio',
        '/record',
        '/recordings',
        '/recorder',
        '/callrec',
        '/call_recorder',
        '/status/',
        '/statuses/',
        '/.statuses/',
        '/notifications',
        '/ringtones',
        '/alarms',
        '/dcim/.thumbnails',
        '/cache/',
        '/tiktok/',
        '/instagram/',
        '/snapchat/',
      ];
      return badDirs.any((k) => p.contains(k));
    }

    bool badName(String name) {
      final n = name.toLowerCase();
      final patterns = <RegExp>[
        RegExp(r'^(aud|ptt)-\d{4}-\d{2}-\d{2}-wa\d+', caseSensitive: false),
        RegExp(r'^wa\d{4,}', caseSensitive: false),
        RegExp(
          r'^(voice[-_\s]?note|voicenote|record(ing)?|call[-_\s]?record(ing)?)',
        ),
        RegExp(r'^(vn[_\s-]?\d+)', caseSensitive: false),
      ];
      return patterns.any((re) => re.hasMatch(n));
    }

    bool tooShort(int? ms) {
      return (ms ?? 0) < 35000;
    }

    bool bannedExt(String ext) {
      final e = ext.toLowerCase();
      const banned = {'opus', 'amr', '3gp'};
      return banned.contains(e);
    }

    bool isRealMusic(SongModel s) {
      final title = s.title.toLowerCase();
      final path = s.data;
      if (!allowedByUser(path)) return false;
      final pl = path.toLowerCase();
      if ((s.isMusic ?? true) == false) return false;
      if (title.contains('notif') || title.contains('ringtone')) return false;
      if (badPath(pl)) return false;
      if (badName(s.displayName)) return false;
      if (bannedExt(s.fileExtension)) return false;
      if (tooShort(s.duration)) return false;
      return s.uri?.isNotEmpty == true;
    }

    final filteredSongs = allRaw.where(isRealMusic).toList();
    final recent = dedupeByKey<SongModel>(filteredSongs, songKey);

    final allowedAlbumIds = <int>{};
    final allowedArtistNames = <String>{};
    for (final s in filteredSongs) {
      final aid = s.albumId;
      if (aid != null && aid > 0) allowedAlbumIds.add(aid);
      final an = (s.artist ?? '').trim().toLowerCase();
      if (an.isNotEmpty) allowedArtistNames.add(an);
    }

    final rawAlbums = await _query.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
    );
    final rawArtists = await _query.queryArtists(
      sortType: ArtistSortType.ARTIST,
      orderType: OrderType.ASC_OR_SMALLER,
    );

    final albums = dedupeByKey<AlbumModel>(
      rawAlbums,
      albumKey,
    ).where((a) => allowedAlbumIds.contains(a.id)).toList();

    String norm(String? s) => (s ?? '').trim().toLowerCase();
    final artists = dedupeByKey<ArtistModel>(
      rawArtists,
      artistKey,
    ).where((a) => allowedArtistNames.contains(norm(a.artist))).toList();

    if (!mounted) return;
    setState(() {
      _recentSongs = recent;
      _albums = albums;
      _artists = artists;
      _showQuickAccess =
          (_storage.read(SettingsKeys.showQuickAccess) as bool?) ?? true;
    });

    debugPrint("_showQuickAccess $_showQuickAccess");

    _reorderCatalog();
    await _pickRandomHeaderArt();
    await _loadQuickAccess();
    await _reloadPlaylists();
  }

  Future<void> _loadQuickAccess() async {
    final tracker = UsageTracker.instance;

    List<int> rankedIds;
    try {
      rankedIds = tracker.rankedSongIds(limit: 200);
    } catch (_) {
      final entries = tracker.topSongs(limit: 200);
      rankedIds = entries.map((e) => e.key).toList();
    }

    final rankedHydrated = rankedIds.isEmpty
        ? <SongModel>[]
        : await _hydrateSongsByIds(rankedIds);

    final List<String> favGenresOrdered = () {
      try {
        final top = tracker.topGenres(limit: 6);
        return top.map((e) => e.key).where((g) => g.trim().isNotEmpty).toList();
      } catch (_) {
        return <String>[];
      }
    }();
    _favGenres = favGenresOrdered;

    final favGenres = favGenresOrdered.toSet();

    List<SongModel> biased;
    if (favGenres.isNotEmpty) {
      final match = <SongModel>[];
      final other = <SongModel>[];
      for (final s in rankedHydrated) {
        final g = norm(s.genre);
        if (g.isNotEmpty && favGenres.contains(g)) {
          match.add(s);
        } else {
          other.add(s);
        }
      }
      const target = 9;
      final takeMatch = (target * 0.7).round().clamp(0, target);
      biased = [...match.take(takeMatch), ...other.take(target - takeMatch)];
    } else {
      biased = rankedHydrated;
    }

    _topSongs = diverseSongs(biased, target: 9);

    if (_artists.isEmpty) {
      final allArtists = await _query.queryArtists();
      _artists = allArtists.toList();
    }
    final wantedArtistNames = <String>{
      for (final s in _topSongs) norm(s.artist),
    }..removeWhere((e) => e.isEmpty);

    _topArtists = _artists
        .where((a) => wantedArtistNames.contains(norm(a.artist)))
        .take(8)
        .toList();

    if (_topArtists.length < 8) {
      try {
        final topArtistByCount = tracker.topArtists(limit: 24);

        int artistHash(String name) {
          const int fnvPrime = 0x01000193;
          const int offset = 0x811C9DC5;
          int h = offset;
          for (final cu in name.codeUnits) {
            h ^= cu & 0xFF;
            h = (h * fnvPrime) & 0xFFFFFFFF;
          }
          return h;
        }

        final byHash = <int, ArtistModel>{};
        for (final a in _artists) {
          final n = norm(a.artist);
          if (n.isEmpty) continue;
          byHash[artistHash(n)] = a;
        }

        for (final rec in topArtistByCount) {
          final m = byHash[rec.hash];
          if (m == null) continue;
          if (_topArtists.any((x) => x.id == m.id)) continue;
          _topArtists.add(m);
          if (_topArtists.length >= 8) break;
        }
      } catch (_) {
        /* diam */
      }
    }

    final albumsAll = await _query.queryAlbums();
    final byAlbumId = {for (final a in albumsAll) a.id: a};

    final topAlbumIdsFromSongs = <int?>{for (final s in _topSongs) s.albumId}
      ..removeWhere((e) => e == null);

    final fromSongs = topAlbumIdsFromSongs
        .map((id) => byAlbumId[id!])
        .whereType<AlbumModel>()
        .toList();

    _topAlbums = fromSongs.take(6).toList();

    if (_topAlbums.length < 6) {
      try {
        final topAlbums = tracker.topAlbums(limit: 24);
        final ids = topAlbums
            .map((e) => e.key)
            .where((id) => !_topAlbums.any((x) => x.id == id))
            .toList();
        _topAlbums.addAll(
          ids
              .map((id) => byAlbumId[id])
              .whereType<AlbumModel>()
              .take(6 - _topAlbums.length),
        );
      } catch (_) {
        /* diam */
      }
    }

    final recents = tracker.recentPlays(limit: 9);
    if (recents.isNotEmpty) {
      final ids = recents.map((e) => e['id']).whereType<int>().toList();
      _recentPlayed = ids.isEmpty ? [] : await _hydrateSongsByIds(ids);
    } else {
      _recentPlayed = [];
    }

    _reorderCatalog();
    if (mounted) setState(() {});
  }

  Future<List<SongModel>> _hydrateSongsByIds(List<int> ids) async {
    final missing = ids.where((id) => !_songByIdCache.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      final all = await _query.querySongs(
        sortType: SongSortType.DISPLAY_NAME,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      for (final s in all) {
        _songByIdCache[s.id] = s;
      }
    }
    return ids
        .map((id) => _songByIdCache[id])
        .whereType<SongModel>()
        .where((s) => allowedByUser(s.data))
        .toList();
  }

  Future<void> _openCreatePlaylist({Playlist? edit}) async {
    await showCreatePlaylistSheet(
      context: context,
      allSongs: _recentSongs,
      queryApi: _query,
      onSaved: (pl) async {
        await PlaylistStore.I.savePlaylist(pl);
      },
      edit: edit,
    );
  }

  void _reorderCatalog() {
    final tracker = UsageTracker.instance;
    final topAlbumEntries = tracker.topAlbums(limit: 100);
    final Map<int, double> albumScore = {};
    for (var i = 0; i < topAlbumEntries.length; i++) {
      final e = topAlbumEntries[i];
      albumScore[e.key] = (topAlbumEntries.length - i).toDouble();
    }

    final topArtistEntries = tracker.topArtists(limit: 100);
    final Map<int, double> artistScore = {};
    for (var i = 0; i < topArtistEntries.length; i++) {
      final e = topArtistEntries[i];
      artistScore[e.hash] = (topArtistEntries.length - i).toDouble();
    }

    for (final rp in tracker.recentPlays(limit: 50)) {
      final sid = rp['id'];
      if (sid is! int) continue;
      final song = _songByIdCache[sid];
      if (song != null) {
        final aid = song.albumId;
        if (aid != null) {
          albumScore[aid] = (albumScore[aid] ?? 0) + 0.5;
        }
        final aName = song.artist ?? '';
        if (aName.isNotEmpty) {
          final h = aName.hashCode;
          artistScore[h] = (artistScore[h] ?? 0) + 0.5;
        }
      }
    }

    List<AlbumModel> sortedAlbums = List.of(_albums);
    sortedAlbums.sort((a, b) {
      final sa = albumScore[a.id] ?? 0;
      final sb = albumScore[b.id] ?? 0;
      if (sb.compareTo(sa) != 0) return sb.compareTo(sa);
      return a.album.toLowerCase().compareTo(b.album.toLowerCase());
    });

    List<ArtistModel> sortedArtists = List.of(_artists);
    sortedArtists.sort((a, b) {
      final sa = artistScore[a.artist.hashCode] ?? 0;
      final sb = artistScore[b.artist.hashCode] ?? 0;
      if (sb.compareTo(sa) != 0) return sb.compareTo(sa);
      return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
    });

    _sortedAlbums = sortedAlbums;
    _sortedArtists = sortedArtists;
  }

  @override
  Widget build(BuildContext context) {
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

    if (_perm == PermState.checking || _perm == PermState.unknown) {
      return const _ShimmerHomePlaceholder();
    }

    if (_perm == PermState.denied) {
      return PermissionView(
        title: easy.tr("permission.denied.title"),
        message: easy.tr("permission.denied.message"),
        primaryLabel: easy.tr("permission.denied.primaryLabel"),
        onPrimary: () async {
          final ok = await PermissionService.instance.ensureForOnAudioQuery(
            _query,
            force: true,
          );
          setState(
            () => _perm = ok ? PermState.granted : PermState.deniedPermanently,
          );
          if (ok) {
            await _safeInitMedia();
          }
        },
        secondaryLabel: easy.tr("permission.denied.secondaryLabel"),
        onSecondary: () {
          setState(() => _perm = PermState.deniedPermanently);
        },
      );
    }

    if (_perm == PermState.deniedPermanently) {
      return PermissionView(
        title: easy.tr("permission.permanentlyDenied.title"),
        message: easy.tr("permission.permanentlyDenied.message"),
        primaryLabel: easy.tr("permission.permanentlyDenied.primaryLabel"),
        onPrimary: () async {
          await _openAppSettings();
          if (!mounted) return;
          final ok = await PermissionService.instance.isGranted();
          setState(
            () => _perm = ok ? PermState.granted : PermState.deniedPermanently,
          );
          if (ok) {
            await _safeInitMedia();
          }
        },
        secondaryLabel: easy.tr("permission.permanentlyDenied.secondaryLabel"),
        onSecondary: () async {
          final ok = await PermissionService.instance.ensureForOnAudioQuery(
            _query,
            force: true,
          );
          setState(
            () => _perm = ok ? PermState.granted : PermState.deniedPermanently,
          );
          if (ok) {
            await _safeInitMedia();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  easy.tr("permission.permanentlyDenied.needAllow"),
                ),
              ),
            );
          }
        },
      );
    }

    if (_loadingMedia) {
      return const _ShimmerHomePlaceholder();
    }

    return _buildHomeContent(context);
  }

  Future<void> _pickRandomHeaderArt() async {
    final rnd = math.Random();

    if (_recentSongs.isNotEmpty) {
      final candidates = List<SongModel>.from(_recentSongs)..shuffle(rnd);
      for (final s in candidates.take(6)) {
        try {
          final art = await ArtworkMemCache.I.getBytes(
            id: s.id,
            type: ArtworkType.AUDIO,
            slot: ArtworkSlot.gridSmall,
          );
          if (art != null && art.isNotEmpty) {
            if (!mounted) return;
            setState(() {
              _headerArt = art;
            });
            return;
          }
        } catch (_) {
          /* skip */
        }
      }
    }

    if (_albums.isNotEmpty) {
      final candidates = List<AlbumModel>.from(_albums)..shuffle(rnd);
      for (final a in candidates.take(6)) {
        try {
          final art = await ArtworkMemCache.I.getBytes(
            id: a.id,
            type: ArtworkType.ALBUM,
            slot: ArtworkSlot.gridSmall,
          );
          if (art != null && art.isNotEmpty) {
            if (!mounted) return;
            setState(() {
              _headerArt = art;
            });
            return;
          }
        } catch (_) {
          /* skip */
        }
      }
    }
  }

  List<QuickAccessItem> _buildQuickItems(BuildContext context) {
    final ctrl = PlayerScope.of(context);
    final items = <QuickAccessItem>[];

    if (_recentPlayed.isNotEmpty) {
      final s = _recentPlayed.first;
      items.add(
        QuickAccessItem(
          id: s.albumId ?? s.id,
          artworkType: s.albumId != null
              ? ArtworkType.ALBUM
              : ArtworkType.AUDIO,
          title: easy.tr("common.continue"),
          subtitle: s.title,
          onOpen: () async => PlayActions.playNowSong(context, s),
          onAddToQueue: () async => PlayActions.enqueueOne(context, s),
          onPin: () => PinHub.I.toggleSong(
            id: s.id,
            title: s.title,
            artist: s.artist,
            artworkId: s.albumId ?? s.id,
            artworkType: (s.albumId != null && s.albumId! > 0)
                ? ArtworkType.ALBUM
                : ArtworkType.AUDIO,
          ),
          isPinned: PinHub.I.isPinned(PinKind.song, s.id),
        ),
      );
    }

    if (_topSongs.isNotEmpty) {
      final s = _topSongs.first;

      String? favGenreHint;
      try {
        final topG = UsageTracker.instance.topGenres(limit: 1);
        if (topG.isNotEmpty) favGenreHint = topG.first.key;
      } catch (_) {
        /* diam */
      }

      items.add(
        QuickAccessItem(
          id: s.id,
          artworkType: ArtworkType.AUDIO,
          title: easy.tr("common.mostPlayed"),
          subtitle: favGenreHint == null
              ? '${_topSongs.length} lagu'
              : '${_topSongs.length} lagu • $favGenreHint',

          onOpen: _openTopSongs,
          onAddToQueue: () async {
            if (_topSongs.isEmpty) return;
            final valid = _topSongs.where((x) => x.uri != null).toList();
            if (valid.isEmpty) return;
            await PlayerScope.of(context).enqueue(valid);
          },

          onPin: () => PinHub.I.toggleSong(
            id: s.id,
            title: s.title,
            artist: s.artist,
            artworkId: s.albumId ?? s.id,
            artworkType: (s.albumId != null && s.albumId! > 0)
                ? ArtworkType.ALBUM
                : ArtworkType.AUDIO,
          ),
          isPinned: PinHub.I.isPinned(PinKind.song, s.id),
        ),
      );
    }

    if (_favGenres.isNotEmpty) {
      final subtitle = _favGenres.take(3).join(', ');
      items.add(
        QuickAccessItem(
          id: subtitle.hashCode,
          artworkType: ArtworkType.AUDIO,
          title: easy.tr("common.favoriteGenre"),
          subtitle: subtitle,
          onOpen: _openTopGenres,
          onAddToQueue: () async {
            if (_favGenres.isEmpty) return;
            final got = await _songsByGenres([_favGenres.first], limit: 25);
            final valid = got.where((s) => s.uri != null).toList();
            if (valid.isEmpty) return;
            valid.shuffle();
            await ctrl.enqueue(valid);
          },
          isPinned: PinHub.I.isPinned(PinKind.song, subtitle.hashCode),
        ),
      );
    }

    if (_topAlbums.isNotEmpty) {
      final a = _topAlbums.first;
      items.add(
        QuickAccessItem(
          id: a.id,
          artworkType: ArtworkType.ALBUM,
          title: easy.tr("common.favoriteAlbum"),
          subtitle: a.album,
          onOpen: _openTopAlbums,
          isPinned: PinHub.I.isPinned(PinKind.album, a.id),
        ),
      );
    }

    if (_topArtists.isNotEmpty) {
      final ar = _topArtists.first;
      items.add(
        QuickAccessItem(
          id: ar.id,
          artworkType: ArtworkType.ARTIST,
          title: easy.tr("common.favoriteArtist"),
          subtitle: ar.artist,
          onOpen: _openTopArtists,
          isPinned: PinHub.I.isPinned(PinKind.artist, ar.id),
        ),
      );
    }

    for (final s in _recentPlayed.skip(1).take(5)) {
      items.add(
        QuickAccessItem(
          id: s.albumId ?? s.id,
          artworkType: s.albumId != null
              ? ArtworkType.ALBUM
              : ArtworkType.AUDIO,
          title: easy.tr("common.recentlyPlayed"),
          subtitle: s.title,
          onOpen: () async => PlayActions.playNowSong(context, s),
          onAddToQueue: () async => PlayActions.enqueueOne(context, s),
          onPin: () => PinHub.I.toggleSong(
            id: s.id,
            title: s.title,
            artist: s.artist,
            artworkId: s.albumId ?? s.id,
            artworkType: (s.albumId != null && s.albumId! > 0)
                ? ArtworkType.ALBUM
                : ArtworkType.AUDIO,
          ),
          isPinned: PinHub.I.isPinned(PinKind.song, s.id),
        ),
      );
    }

    return items.take(12).toList();
  }

  Future<void> _seedWrappedDemo() async {
    HapticFeedback.lightImpact();
    final songs = List<SongModel>.from(_recentSongs);
    if (songs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No local songs found, can't seed demo stats."),
          ),
        );
      }
      return;
    }
    await UsageTracker.instance.seedDemoStatsFromSongs(songs);
    await _loadQuickAccess();
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildHomeContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final albumsView = _sortedAlbums.isNotEmpty ? _sortedAlbums : _albums;
    final artistsView = _sortedArtists.isNotEmpty ? _sortedArtists : _artists;

    final pinned = PinHub.I.all;

    return RefreshIndicator(
      color: cs.primary,
      backgroundColor: cs.surface,
      onRefresh: () async {
        await _boot();
        await _pickRandomHeaderArt();
        await _loadQuickAccess();
      },
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 140,
            backgroundColor: Theme.of(context).colorScheme.surface,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              titlePadding: const EdgeInsetsDirectional.only(
                start: 16,
                bottom: 12,
              ),
              title: Text(
                'DearMusic 🎧',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              background: LayoutBuilder(
                builder: (context, constraints) {
                  final maxH = _headerExpanded;
                  final t =
                      ((constraints.maxHeight - kToolbarHeight) /
                              (maxH - kToolbarHeight))
                          .clamp(0.0, 1.0);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_headerArt != null)
                        Opacity(
                          opacity: t,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                _headerArt!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.medium,
                              ),
                              Positioned.fill(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 6,
                                    sigmaY: 6,
                                  ),
                                  child: const SizedBox(),
                                ),
                              ),

                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.black.withOpacity(0.35),
                                      Colors.transparent,
                                      cs.surface.withOpacity(0.3),
                                      cs.surface.withOpacity(0.90),
                                    ],
                                    stops: const [0.0, 0.5, 0.8, 1.0],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_headerArt == null)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                cs.primaryContainer.withOpacity(0.35),
                                Colors.transparent,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            actions: [
              _actionCircle(
                context,
                icon: Icons.search_rounded,
                tooltip: easy.tr("common.search"),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await showSearch(
                    context: context,
                    delegate: HomeSearchDelegate(
                      songs: _recentSongs,
                      albums: _albums,
                      artists: _artists,
                      queryApi: _query,
                      onPlaySong: _playSongFromHome,
                      onOpenAlbum: _openAlbum,
                      onOpenArtist: _openArtist,
                    ),
                  );
                },
              ),
              _actionCircle(
                context,
                icon: Icons.grid_view_rounded,
                tooltip: 'Create Playlist',
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await _openCreatePlaylist();
                  await _reloadPlaylists();
                },
              ),
              _actionCircle(
                context,
                icon: Icons.settings_rounded,
                tooltip: 'Settings',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                },
              ),
              if (kDebugMode)
                _actionCircle(
                  context,
                  icon: Icons.bug_report_rounded,
                  tooltip: 'Seed Stats',
                  onPressed: () {
                    _seedWrappedDemo();
                  },
                ),
            ],
          ),

          if (pinned.isNotEmpty) ...[
            SectionHeader(
              title: easy.tr("section.pinned"),
              action: easy.tr("section.pinned.viewAll"),
              onTap: _openPinnedMixed,
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 0,
                  childAspectRatio: 0.70,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final p = pinned[i];
                  switch (p.kind) {
                    case PinKind.song:
                      final song =
                          _songByIdCache[p.id] ??
                          SongModel({
                            'id': p.id,
                            'title': p.title,
                            'artist': p.subtitle ?? '',
                            'albumId': p.artworkId,
                            'uri': null,
                          });
                      return PinnedSquareSong(
                        song: song,
                        onTap: () async =>
                            PlayActions.playNowSong(context, song),
                        onAddToQueue: () async =>
                            PlayActions.enqueueOne(context, song),
                        onPin: () => PinHub.I.toggleSong(
                          id: song.id,
                          title: song.title,
                          artist: song.artist,
                          artworkId: song.albumId ?? song.id,
                          artworkType:
                              (song.albumId != null && song.albumId! > 0)
                              ? ArtworkType.ALBUM
                              : ArtworkType.AUDIO,
                        ),
                        onUnpin: () => PinHub.I.toggleSong(
                          id: song.id,
                          title: song.title,
                          artist: song.artist,
                          artworkId: song.albumId ?? song.id,
                          artworkType:
                              (song.albumId != null && song.albumId! > 0)
                              ? ArtworkType.ALBUM
                              : ArtworkType.AUDIO,
                        ),
                      );

                    case PinKind.album:
                      final album = _albums.firstWhere(
                        (a) => a.id == p.id,
                        orElse: () => AlbumModel({
                          'id': p.id,
                          'album': p.title,
                          'artist': p.subtitle ?? '',
                        }),
                      );
                      return AlbumCard(
                        album: album,
                        query: _query,
                        onOpen: () => _openAlbum(album),
                        onPin: () => PinHub.I.toggleAlbum(
                          id: album.id,
                          album: album.album,
                          artist: album.artist,
                        ),
                        isPin: PinHub.I.isPinned(PinKind.album, album.id),
                      );

                    case PinKind.artist:
                      final artist = _artists.firstWhere(
                        (a) => a.id == p.id,
                        orElse: () =>
                            ArtistModel({'id': p.id, 'artist': p.title}),
                      );
                      return ArtistCircleCard(
                        artist: artist,
                        onTap: () => _openArtist(artist),
                        onPin: () => PinHub.I.toggleArtist(
                          id: artist.id,
                          name: artist.artist,
                        ),
                        isPin: PinHub.I.isPinned(PinKind.artist, artist.id),
                      );
                  }
                }, childCount: pinned.length),
              ),
            ),
          ],

          if (_showQuickAccess &&
              (_topSongs.isNotEmpty ||
                  _topAlbums.isNotEmpty ||
                  _topArtists.isNotEmpty ||
                  _recentPlayed.isNotEmpty)) ...[
            SectionHeader(
              title: easy.tr("section.quickAccess"),
              action: easy.tr("section.quickAccess.smartMix"),
              onTap: () async {
                HapticFeedback.lightImpact();
                final recs = await PlayerScope.of(
                  context,
                ).recommendNext(want: 30);

                if (recs.isEmpty) return;
                await PlayActions.playQueue(
                  context,
                  recs,
                  startIndex: 0,
                  shuffle: false,
                );
              },
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: QuickAccessGrid(items: _buildQuickItems(context)),
            ),
          ],

          if (_playlists.isNotEmpty) ...[
            SectionHeader(
              title: easy.tr("common.myPlaylists"),
              action: '',
              onTap: () {},
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 0,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.70,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final pl = _playlists[i];
                  return PlaylistCard(
                    playlist: pl,
                    query: _query,
                    onOpen: () => _openPlaylist(pl),
                    onMore: () => _showPlaylistMenu(pl),
                  );
                }, childCount: _playlists.length),
              ),
            ),
          ],

          SectionHeader(
            title: easy.tr("section.albums"),
            action: easy.tr("section.pinned.viewAll"),
            onTap: _openAlbums,
          ),

          if (albumsView.isEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: EmptyAlbums(
                  message: easy.tr("empty.albums.message"),
                  primaryText: easy.tr("empty.albums.primary"),
                  onPrimary: _openSettings,
                  secondaryText: easy.tr("empty.albums.secondary"),
                  onSecondary: _refreshLibrary,
                ),
              ),
            ),
          ] else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 0,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.70,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => AlbumCard(
                    album: albumsView[i],
                    query: _query,
                    onOpen: () => _openAlbum(albumsView[i]),
                    onPin: () => PinHub.I.toggleAlbum(
                      id: albumsView[i].id,
                      album: albumsView[i].album,
                      artist: albumsView[i].artist,
                    ),
                    isPin: PinHub.I.isPinned(PinKind.album, albumsView[i].id),
                  ),
                  childCount: math.min(albumsView.length, 9),
                ),
              ),
            ),
          ],

          SectionHeader(
            title: easy.tr("section.artists"),
            action: easy.tr("section.artists.viewAll"),
            onTap: _openArtists,
          ),

          if (albumsView.isEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: EmptyArtists(
                  message: easy.tr("empty.artists.message"),
                  primaryText: easy.tr("empty.artists.primary"),
                  onPrimary: _openSettings,
                  secondaryText: easy.tr("empty.artists.secondary"),
                  onSecondary: _refreshLibrary,
                ),
              ),
            ),
          ] else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => ArtistCircleCard(
                    artist: artistsView[i],
                    onTap: () => _openArtist(artistsView[i]),
                    onPin: () => PinHub.I.toggleArtist(
                      id: artistsView[i].id,
                      name: artistsView[i].artist,
                    ),
                    isPin: PinHub.I.isPinned(PinKind.artist, artistsView[i].id),
                  ),
                  childCount: math.min(artistsView.length, 20),
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 30)),

          SectionHeader(
            title: easy.tr("section.recentlyAdded"),
            action: '',
            onTap: () {},
          ),

          if (_recentSongs.isEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: EmptySongs(
                  message: easy.tr("empty.songs.message"),
                  primaryText: easy.tr("empty.songs.primary"),
                  onPrimary: _openSettings,
                  secondaryText: easy.tr("empty.songs.secondary"),
                  onSecondary: _refreshLibrary,
                ),
              ),
            ),
          ] else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 0,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.70,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final s = _recentSongs[i];
                  return RecentSquareSong(
                    song: s,
                    onTap: () async => PlayActions.playNowSong(context, s),
                    onAddToQueue: () async =>
                        PlayActions.enqueueOne(context, s),
                    onPin: () => PinHub.I.toggleSong(
                      id: s.id,
                      title: s.title,
                      artist: s.artist,
                      artworkId: s.albumId ?? s.id,
                      artworkType: (s.albumId != null && s.albumId! > 0)
                          ? ArtworkType.ALBUM
                          : ArtworkType.AUDIO,
                    ),
                    isPin: PinHub.I.isPinned(PinKind.song, s.id),
                  );
                }, childCount: math.min(_recentSongs.length, 9)),
              ),
            ),
          ],

          SectionHeader(
            title: easy.tr("section.others"),
            action: '',
            onTap: () {},
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: QuickCategories(
                items: [
                  QuickItem(
                    easy.tr("quick.songs"),
                    Icons.music_note_rounded,
                    _recentSongs.length,
                    onTap: _openAllSongs,
                  ),
                  QuickItem(
                    easy.tr("quick.albums"),
                    Icons.headphones_rounded,
                    _albums.length,
                    onTap: _openAlbums,
                  ),
                  QuickItem(
                    easy.tr("quick.artists"),
                    Icons.mic_rounded,
                    _artists.length,
                    onTap: _openArtists,
                  ),

                  QuickItem(
                    easy.tr("quick.playlist"),
                    Icons.queue_music_rounded,
                    _playlists.length,
                    onTap: _openPlaylists,
                  ),

                  QuickItem(
                    easy.tr("quick.topSongs"),
                    Icons.trending_up_rounded,
                    _topSongs.length,
                    onTap: _openTopSongs,
                  ),
                  QuickItem(
                    easy.tr("quick.topAlbums"),
                    Icons.workspace_premium_rounded,
                    _topAlbums.length,
                    onTap: _openTopAlbums,
                  ),
                  QuickItem(
                    easy.tr("quick.topArtists"),
                    Icons.emoji_events_rounded,
                    _topArtists.length,
                    onTap: _openTopArtists,
                  ),

                  QuickItem(
                    easy.tr("quick.pinnedSongs"),
                    Icons.library_music_rounded,
                    pinned.where((p) => p.kind == PinKind.song).length,
                    onTap: _openPinnedSongs,
                  ),
                  QuickItem(
                    easy.tr("quick.pinnedAlbums"),
                    Icons.album_rounded,
                    pinned.where((p) => p.kind == PinKind.album).length,
                    onTap: _openPinnedAlbums,
                  ),
                  QuickItem(
                    easy.tr("quick.pinnedArtists"),
                    Icons.person_rounded,
                    pinned.where((p) => p.kind == PinKind.artist).length,
                    onTap: _openPinnedArtists,
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 35)),
        ],
      ),
    );
  }

  Widget _actionCircle(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const double kSize = 40;
    const double kIcon = 18;

    final bool isLight = theme.brightness == Brightness.light;
    final Color bg = isLight
        ? cs.surfaceContainerHighest.withOpacity(0.96)
        : cs.surfaceContainerHighest.withOpacity(0.20);

    final Color border = cs.outlineVariant.withOpacity(isLight ? 0.70 : 0.38);
    final Color fg = cs.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: bg,
        shape: CircleBorder(side: BorderSide(color: border, width: 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.lightImpact();
            onPressed();
          },
          child: SizedBox(
            width: kSize,
            height: kSize,
            child: Center(
              child: Icon(icon, size: kIcon, color: fg),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAppSettings() async {
    try {
      if (Platform.isAndroid) {
        final opened = await openAppSettings();
        if (!opened) {
          const platform = MethodChannel('app_settings_channel');
          await platform.invokeMethod('openAppSettings');
        }
      } else if (Platform.isIOS) {
        await openAppSettings();
      }
    } catch (e) {
      debugPrint('❌ Gagal buka pengaturan: $e');
    }
  }

  Future<void> _openPinnedSongs() async {
    HapticFeedback.lightImpact();
    final ids = PinHub.I.all
        .where((p) => p.kind == PinKind.song)
        .map((p) => p.id)
        .toList();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(easy.tr("snackbar.noPinnedSongs"))),
      );
      return;
    }
    final songs = await _hydrateSongsByIds(ids);
    if (!mounted || songs.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SongListPage(title: easy.tr("page.pinnedSongs"), songs: songs),
      ),
    );
  }

  void _openPinnedAlbums() {
    HapticFeedback.lightImpact();

    final pinned = PinHub.I.all
        .where((p) => p.kind == PinKind.album)
        .map((p) => p.id)
        .toSet();

    final albums = _albums.where((a) => pinned.contains(a.id)).toList();
    if (albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(easy.tr("snackbar.noPinnedAlbums"))),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumGridPage(
          title: easy.tr("page.pinnedAlbums"),
          albums: albums,
          query: _query,
          onOpen: _openAlbum,
          onPin: (a) =>
              PinHub.I.toggleAlbum(id: a.id, album: a.album, artist: a.artist),
        ),
      ),
    );
  }

  void _openPinnedArtists() {
    HapticFeedback.lightImpact();

    final pinned = PinHub.I.all
        .where((p) => p.kind == PinKind.artist)
        .map((p) => p.id)
        .toSet();

    final artists = _artists.where((a) => pinned.contains(a.id)).toList();
    if (artists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(easy.tr("snackbar.noPinnedArtists"))),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistListPage(
          title: easy.tr("page.pinnedArtists"),
          artists: artists,
          query: _query,
          allowedByUser: allowedByUser,
          onOpen: _openArtist,
          onPin: (ar) => PinHub.I.toggleArtist(id: ar.id, name: ar.artist),
        ),
      ),
    );
  }

  void _openPinnedMixed() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (ctx, setStateLocal) {
            final pinned = PinHub.I.all;
            return Scaffold(
              appBar: AppBar(
                title: Text(easy.tr("section.pinned")),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                ),
                elevation: 0.5,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                iconTheme: IconThemeData(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              body: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 0,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.70,
                ),
                itemCount: pinned.length,
                itemBuilder: (context, i) {
                  final p = pinned[i];
                  switch (p.kind) {
                    case PinKind.song:
                      final song =
                          _songByIdCache[p.id] ??
                          _recentSongs.firstWhere(
                            (s) => s.id == p.id,
                            orElse: () => SongModel({
                              'id': p.id,
                              'title': p.title,
                              'artist': p.subtitle ?? '',
                              'uri': null,
                              'albumId': (p.artworkId),
                            }),
                          );
                      return PinnedSquareSong(
                        song: song,
                        onTap: () async =>
                            PlayActions.playNowSong(context, song),
                        onAddToQueue: () async =>
                            PlayActions.enqueueOne(context, song),
                        onPin: () async {
                          await PinHub.I.toggleSong(
                            id: song.id,
                            title: song.title,
                            artist: song.artist,
                            artworkId: song.albumId ?? song.id,
                            artworkType:
                                (song.albumId != null && song.albumId! > 0)
                                ? ArtworkType.ALBUM
                                : ArtworkType.AUDIO,
                          );
                          setStateLocal(() {});
                        },
                        onUnpin: () async {
                          await PinHub.I.toggleSong(
                            id: song.id,
                            title: song.title,
                            artist: song.artist,
                            artworkId: song.albumId ?? song.id,
                            artworkType:
                                (song.albumId != null && song.albumId! > 0)
                                ? ArtworkType.ALBUM
                                : ArtworkType.AUDIO,
                          );
                          setStateLocal(() {});
                        },
                      );

                    case PinKind.album:
                      final a = _albums.firstWhere((x) => x.id == p.id);
                      return AlbumCard(
                        album: a,
                        query: _query,
                        onOpen: () => _openAlbum(a),
                        onPin: () async {
                          await PinHub.I.toggleAlbum(
                            id: a.id,
                            album: a.album,
                            artist: a.artist,
                          );
                          setStateLocal(() {});
                        },
                        isPin: PinHub.I.isPinned(PinKind.album, a.id),
                      );

                    case PinKind.artist:
                      final ar = _artists.firstWhere(
                        (x) => x.id == p.id,
                        orElse: () =>
                            ArtistModel({'id': p.id, 'artist': p.title}),
                      );
                      return ArtistCircleCard(
                        artist: ar,
                        onTap: () => _openArtist(ar),
                        onPin: () async {
                          await PinHub.I.toggleArtist(
                            id: ar.id,
                            name: ar.artist,
                          );
                          setStateLocal(() {});
                        },
                        isPin: PinHub.I.isPinned(PinKind.artist, ar.id),
                      );
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _openAllSongs() {
    HapticFeedback.lightImpact();
    if (_recentSongs.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongListPage(
          title: easy.tr("common.allSongs"),
          songs: _recentSongs,
        ),
      ),
    );
  }

  Future<void> _openPlaylists() async {
    HapticFeedback.lightImpact();
    await _reloadPlaylists();
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(easy.tr("common.myPlaylists")),
            actions: [
              IconButton(
                tooltip: easy.tr("common.createPlaylist"),
                icon: const Icon(Icons.add_rounded),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await _openCreatePlaylist();
                  await _reloadPlaylists();
                },
              ),
            ],
          ),
          body: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 0,
              crossAxisSpacing: 6,
              childAspectRatio: 0.70,
            ),
            itemCount: _playlists.length,
            itemBuilder: (context, i) {
              final pl = _playlists[i];
              return PlaylistCard(
                playlist: pl,
                query: _query,
                onOpen: () => _openPlaylist(pl),
                onMore: () => _showPlaylistMenu(pl),
              );
            },
          ),
        ),
      ),
    );
  }

  void _openAlbums() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumGridPage(
          title: easy.tr("common.allAlbums"),
          albums: _albums,
          query: _query,
          onOpen: _openAlbum,
          onPin: (a) =>
              PinHub.I.toggleAlbum(id: a.id, album: a.album, artist: a.artist),
        ),
      ),
    );
  }

  void _openArtists() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistListPage(
          title: easy.tr("common.allArtists"),
          artists: _artists,
          query: _query,
          allowedByUser: allowedByUser,
          onOpen: _openArtist,
          onPin: (ar) => PinHub.I.toggleArtist(id: ar.id, name: ar.artist),
        ),
      ),
    );
  }

  Future<void> _openAlbum(AlbumModel album) async {
    HapticFeedback.lightImpact();
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailPage(
          album: album,
          query: _query,
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
        ),
      ),
    );
  }

  Future<void> _openArtist(ArtistModel artist) async {
    HapticFeedback.lightImpact();

    String norm(String? s) => (s ?? '').trim().toLowerCase();
    final me = norm(artist.artist);

    final int? artistId = (artist.id is int)
        ? artist.id
        : int.tryParse('${artist.id}');

    List<SongModel> songs = [];
    if (artistId != null && artistId > 0) {
      try {
        songs = await _query.queryAudiosFrom(
          AudiosFromType.ARTIST_ID,
          artistId,
          sortType: SongSortType.ALBUM,
          orderType: OrderType.ASC_OR_SMALLER,
        );
      } catch (e) {
        debugPrint('queryAudiosFrom fail: $e');
      }
    }

    if (songs.isEmpty) {
      try {
        final all = await _query.querySongs(
          sortType: SongSortType.ARTIST,
          orderType: OrderType.ASC_OR_SMALLER,
        );
        songs = all.where((s) {
          final nameOk = norm(s.artist) == me;
          final pathOk = (() {
            final d = s.data;
            try {
              return allowedByUser(d);
            } catch (_) {
              return true;
            }
          })();
          final title = (s.title ?? '').toLowerCase();
          final junk = title.contains('notif') || title.contains('ringtone');
          return nameOk && pathOk && !junk && (s.uri?.isNotEmpty == true);
        }).toList();
      } catch (e) {
        debugPrint('fallback querySongs fail: $e');
      }
    }

    final albumIds = <int>{
      for (final s in songs)
        if ((s.albumId ?? 0) > 0) s.albumId!,
    };

    final allAlbums = await _query.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
    );
    final byId = {
      for (final a in allAlbums)
        if (a.id > 0) a.id: a,
    };

    final candidates = <AlbumModel>[];

    for (final id in albumIds) {
      final a = byId[id];
      if (a != null) candidates.add(a);
    }
    for (final a in allAlbums) {
      if (norm(a.artist) == me) candidates.add(a);
    }

    final seenId = <int>{};
    final seenKey = <String>{};
    final albums = <AlbumModel>[];
    for (final a in candidates) {
      if (a.id > 0) {
        if (seenId.add(a.id)) albums.add(a);
      } else {
        final key = '${norm(a.album)}|${norm(a.artist)}';
        if (seenKey.add(key)) albums.add(a);
      }
    }

    int cmpStr(String? x, String? y) =>
        (x ?? '').toLowerCase().compareTo((y ?? '').toLowerCase());
    albums.sort((a, b) {
      final n = (b.numOfSongs).compareTo(a.numOfSongs);
      return n != 0 ? n : cmpStr(a.album, b.album);
    });

    bool isPrimary(AlbumModel a) {
      final artists = norm(a.artist)
          .replaceAll('&', ',')
          .replaceAll('feat.', ',')
          .replaceAll('featuring', ',')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      return artists.any((t) => t == me);
    }

    final primary = <AlbumModel>[];
    final appearsOn = <AlbumModel>[];
    for (final a in albums) {
      (isPrimary(a) ? primary : appearsOn).add(a);
    }

    if (!mounted) return;

    Future<void> onPinAlbumSafe(AlbumModel a) async {
      if (a.id <= 0) return;
      await PinHub.I.toggleAlbum(id: a.id, album: a.album, artist: a.artist);
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistPageElegant(
          artist: artist,
          primary: primary,
          appearsOn: appearsOn,
          query: _query,
          onOpenAlbum: _openAlbum,
          onPinAlbum: onPinAlbumSafe,
        ),
      ),
    );
    return;
  }

  void _openTopSongs() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SongListPage(title: easy.tr("common.mostPlayed"), songs: _topSongs),
      ),
    );
  }

  void _openTopAlbums() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumGridPage(
          title: easy.tr("common.favoriteAlbum"),
          albums: _topAlbums,
          query: _query,
          onOpen: _openAlbum,
          onPin: (a) =>
              PinHub.I.toggleAlbum(id: a.id, album: a.album, artist: a.artist),
        ),
      ),
    );
  }

  void _openTopArtists() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistListPage(
          title: easy.tr("common.favoriteArtist"),
          artists: _topArtists,
          query: _query,
          allowedByUser: allowedByUser,
          onOpen: _openArtist,
          onPin: (ar) => PinHub.I.toggleArtist(id: ar.id, name: ar.artist),
        ),
      ),
    );
  }

  Future<void> _openTopGenres() async {
    HapticFeedback.lightImpact();
    if (_favGenres.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GenrePickerPage(
          genres: _favGenres,
          fetchSongs: (g) => _songsByGenres([g], limit: 400),
          onOpenSong: (s) async {
            final ctrl = PlayerScope.of(context);
            final uri = s.uri;
            if (uri == null) return;
            await ctrl.playUri(
              uri,
              title: s.title,
              artist: s.artist,
              artworkId: s.albumId ?? s.id,
              artworkType: s.albumId != null
                  ? ArtworkType.ALBUM
                  : ArtworkType.AUDIO,
              filePath: s.data,
              duration: s.duration,
              genre: s.genre,
            );
          },
        ),
      ),
    );
  }

  Future<void> _playSongFromHome(SongModel s) async {
    await PlayActions.playNowSong(context, s);
  }

  Future<void> _openPlaylist(Playlist pl) async {
    final songs = await PlaylistStore.I.getSongsFor(pl, query: _query);
    if (!mounted || songs.isEmpty) return;
    final ctrl = PlayerScope.of(context);
    await ctrl.playQueue(songs, startIndex: 0);
  }

  Future<List<SongModel>> _songsByGenres(
    List<String> genres, {
    int? limit,
  }) async {
    if (genres.isEmpty) return [];
    final wanted = genres.map(norm).where((e) => e.isNotEmpty).toSet();
    if (wanted.isEmpty) return [];

    final all = await _query.querySongs(
      sortType: SongSortType.DISPLAY_NAME,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
    );

    final withUri = all.where((s) {
      final g = norm(s.genre);
      return g.isNotEmpty &&
          wanted.contains(g) &&
          s.uri != null &&
          allowedByUser(s.data);
    });

    final seen = <int>{};
    final uniq = <SongModel>[];
    for (final s in withUri) {
      if (seen.add(s.id)) uniq.add(s);
    }

    uniq.sort((a, b) {
      final na = (a.displayName).toLowerCase();
      final nb = (b.displayName).toLowerCase();
      final c = na.compareTo(nb);
      if (c != 0) return c;
      return (a.artist ?? '').toLowerCase().compareTo(
        (b.artist ?? '').toLowerCase(),
      );
    });

    if (limit != null && uniq.length > limit) {
      return uniq.take(limit).toList();
    }
    return uniq;
  }

  void _showPlaylistMenu(Playlist pl) {
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
              onTap: () async {
                HapticFeedback.lightImpact();
                Navigator.pop(ctx);
                final songs = await PlaylistStore.I.getSongsFor(
                  pl,
                  query: _query,
                );
                if (songs.isEmpty) return;
                await PlayActions.playQueue(context, songs);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(easy.tr("common.addToQueue")),
              onTap: () async {
                HapticFeedback.lightImpact();
                Navigator.pop(ctx);
                final songs = await PlaylistStore.I.getSongsFor(
                  pl,
                  query: _query,
                );
                await PlayActions.enqueue(context, songs);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: Text(easy.tr("common.editPlaylist")),
              onTap: () async {
                HapticFeedback.lightImpact();
                Navigator.pop(ctx);
                await _openCreatePlaylist(edit: pl);
                await _reloadPlaylists();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(easy.tr("common.delete")),
              onTap: () async {
                HapticFeedback.lightImpact();
                Navigator.pop(ctx);
                await PlaylistStore.I.deletePlaylist(pl.id);
                await _reloadPlaylists();
              },
            ),
          ],
        ),
      ),
    );
  }

  bool allowedByUser(String filePathOrUri) {
    final scanAll = _scanAllPref;
    final rootsRaw = _allowedDirsPref;

    if (scanAll || rootsRaw.isEmpty) return true;

    final p = _normSlashLower(filePathOrUri);

    final hitPath = rootsRaw
        .where((r) => !r.startsWith('content://'))
        .map(_normSlashLower)
        .map((r) => r.endsWith('/') ? r : '$r/')
        .any((root) => p.startsWith(root));

    if (hitPath) return true;

    final hitTree = rootsRaw
        .where((r) => r.startsWith('content://'))
        .map((r) => Uri.decodeComponent(r).toLowerCase().replaceAll('%3a', ':'))
        .any((tree) => p.contains(tree));

    return hitTree;
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  Future<void> _refreshLibrary() async {
    HapticFeedback.lightImpact();
    await _safeInitMedia();
    if (mounted) setState(() {});
  }
}

class _ShimmerHomePlaceholder extends StatelessWidget {
  const _ShimmerHomePlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: cs.surfaceContainerHighest.withOpacity(0.4),
      highlightColor: cs.surfaceContainerHighest.withOpacity(0.8),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            backgroundColor: cs.surface,
            flexibleSpace: FlexibleSpaceBar(
              title: Container(width: 160, height: 22, color: Colors.white),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  5,
                  (i) => Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.7,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, __) => Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                childCount: 6,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.7,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, __) => Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                childCount: 9,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, __) => Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
                childCount: 8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeSearchDelegate extends SearchDelegate<void> {
  final List<SongModel> songs;
  final List<AlbumModel> albums;
  final List<ArtistModel> artists;
  final OnAudioQuery queryApi;

  final Future<void> Function(SongModel) onPlaySong;
  final Future<void> Function(AlbumModel) onOpenAlbum;
  final Future<void> Function(ArtistModel) onOpenArtist;

  HomeSearchDelegate({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.queryApi,
    required this.onPlaySong,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  }) : super(
         searchFieldLabel: easy.tr("common.searchPlaceholder"),
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
        tooltip: easy.tr("common.delete"),
        icon: const Icon(Icons.clear_rounded),
        onPressed: () {
          HapticFeedback.lightImpact();
          query = '';
          showSuggestions(context);
        },
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: easy.tr("common.back"),
    icon: const Icon(Icons.arrow_back_ios_new_rounded),
    onPressed: () {
      HapticFeedback.lightImpact();
      close(context, null);
    },
  );

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = query.trim().toLowerCase();

    final songRes = _filterSongs(q);
    final albumRes = _filterAlbums(q);
    final artistRes = _filterArtists(q);

    final isEmpty =
        q.isEmpty && songs.isEmpty && albums.isEmpty && artists.isEmpty;
    if (isEmpty) {
      return Center(
        child: Text(
          easy.tr("common.noContent"),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        if (songRes.isNotEmpty) ...[
          _sectionHeader(context, easy.tr("section.songs")),
          SliverList.builder(
            itemCount: songRes.length,
            itemBuilder: (_, i) {
              final s = songRes[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: FutureBuilder<Widget>(
                      future: ArtworkMemCache.I.imageWidget(
                        id: s.albumId ?? s.id,
                        type: s.albumId != null
                            ? ArtworkType.ALBUM
                            : ArtworkType.AUDIO,
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
                title: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  s.artist ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await onPlaySong(s);
                },
                trailing: const Icon(Icons.play_arrow_rounded),
              );
            },
          ),
        ],

        if (albumRes.isNotEmpty) ...[
          _sectionHeader(context, easy.tr("section.albums")),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 0,
                crossAxisSpacing: 6,
                childAspectRatio: 0.70,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final a = albumRes[i];
                return AlbumCard(
                  album: a,
                  query: queryApi,
                  onOpen: () async {
                    HapticFeedback.lightImpact();
                    await onOpenAlbum(a);
                  },
                  onPin: () async {
                    await PinHub.I.toggleAlbum(
                      id: a.id,
                      album: a.album,
                      artist: a.artist,
                    );
                  },
                  isPin: PinHub.I.isPinned(PinKind.album, a.id),
                );
              }, childCount: albumRes.length),
            ),
          ),
        ],

        if (artistRes.isNotEmpty) ...[
          _sectionHeader(context, easy.tr("section.artists")),
          SliverList.builder(
            itemCount: artistRes.length,
            itemBuilder: (_, i) {
              final ar = artistRes[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                leading: ClipOval(
                  child: SizedBox(
                    width: 48,
                    height: 48,
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
                title: Text(
                  ar.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _buildArtistSubtitle(ar),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await onOpenArtist(ar);
                },
              );
            },
          ),
        ],

        if (songRes.isEmpty && albumRes.isEmpty && artistRes.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                easy.tr("common.noResult", namedArgs: {"query": "query"}),
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }

  SliverToBoxAdapter _sectionHeader(BuildContext context, String title) {
    final txt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          title,
          style: txt.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }

  List<SongModel> _filterSongs(String q) {
    if (q.isEmpty) return songs.take(30).toList();
    final s = q.toLowerCase();
    bool m(SongModel x) {
      return (x.title.toLowerCase().contains(s)) ||
          ((x.artist ?? '').toLowerCase().contains(s)) ||
          ((x.album ?? '').toLowerCase().contains(s));
    }

    final out = songs.where(m).toList();
    out.sort((a, b) {
      int r(SongModel x) {
        final t = x.title.toLowerCase().contains(s) ? 0 : 1;
        final ar = (x.artist ?? '').toLowerCase().contains(s) ? 0 : 1;
        final al = (x.album ?? '').toLowerCase().contains(s) ? 0 : 1;
        return t * 4 + ar * 2 + al;
      }

      return r(a).compareTo(r(b));
    });
    return out.take(50).toList();
  }

  List<AlbumModel> _filterAlbums(String q) {
    if (q.isEmpty) return albums.take(18).toList();
    final s = q.toLowerCase();
    bool m(AlbumModel x) {
      return (x.album.toLowerCase().contains(s)) ||
          ((x.artist ?? '').toLowerCase().contains(s));
    }

    final out = albums.where(m).toList();
    out.sort((a, b) {
      int r(AlbumModel x) {
        final al = x.album.toLowerCase().contains(s) ? 0 : 1;
        final ar = (x.artist ?? '').toLowerCase().contains(s) ? 0 : 1;
        return al * 2 + ar;
      }

      return r(a).compareTo(r(b));
    });
    return out.take(30).toList();
  }

  List<ArtistModel> _filterArtists(String q) {
    if (q.isEmpty) return artists.take(24).toList();
    final s = q.toLowerCase();
    bool m(ArtistModel x) {
      return x.artist.toLowerCase().contains(s) ||
          ((x.numberOfAlbums ?? 0).toString().contains(s)) ||
          ((x.numberOfTracks ?? 0).toString().contains(s));
    }

    final out = artists.where(m).toList();
    out.sort((a, b) {
      final na = a.artist.toLowerCase().contains(s) ? 0 : 1;
      final nb = b.artist.toLowerCase().contains(s) ? 0 : 1;
      return na.compareTo(nb);
    });
    return out.take(40).toList();
  }

  String _buildArtistSubtitle(ArtistModel ar) {
    final t = ar.numberOfTracks ?? 0;
    final a = ar.numberOfAlbums ?? 0;
    if (a > 0) {
      return easy.tr(
        "artist.subtitle.withAlbums",
        namedArgs: {"tracks": "$t", "albums": "$a"},
      );
    }
    return easy.tr("artist.subtitle.noAlbums", namedArgs: {"tracks": "$t"});
  }
}
