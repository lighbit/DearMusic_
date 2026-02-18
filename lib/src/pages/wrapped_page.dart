import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:dearmusic/src/audio/smart_intro_outro_service.dart';
import 'package:dearmusic/src/logic/usage_tracker.dart';
import 'package:dearmusic/src/models/wrapped_models.dart';
import 'package:dearmusic/src/widgets/wrapped_story_share.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

typedef _WrappedData = (WrappedStats stats, Map<int, SongModel> songMap);

extension IterableFirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class WrappedStoryPage extends StatefulWidget {
  const WrappedStoryPage({super.key});

  @override
  State<WrappedStoryPage> createState() => _WrappedStoryPageState();
}

class _WrappedStoryPageState extends State<WrappedStoryPage>
    with TickerProviderStateMixin {
  final OnAudioQuery _query = OnAudioQuery();
  final PageController _pageController = PageController();
  final _PreviewDJ _dj = _PreviewDJ();
  final ValueNotifier<double> _pageVN = ValueNotifier<double>(0.0);
  final Set<int> _playedSlides = {};

  late final AnimationController _autoCtrl =
      AnimationController(vsync: this, duration: _autoInterval)
        ..addListener(() {
          if (mounted) setState(() {});
        });
  late final Future<_WrappedData?> _dataFuture;

  static const _autoInterval = Duration(seconds: 12);

  Timer? _autoTimer;
  bool _autoplayStarted = false;
  bool _storyStarted = false;
  Future<Map<int, _PreviewCue>>? _previewFuture;
  _PreviewCue? _lastCuePlayed;

  @override
  void initState() {
    super.initState();

    _pageController.addListener(() {
      final p = _pageController.page ?? 0.0;
      _pageVN.value = p;
    });

    _dataFuture = _loadData();
    _dataFuture.then((data) async {
      if (data == null || !mounted) return;
      final stats = data.$1;
      final songMap = data.$2;
      final cues = await _preparePreviewCues(stats, songMap);
      if (!mounted) return;
      final firstCue = cues[0] ?? cues[2];
      setState(() {
        _previewFuture = Future.value(cues);
        _storyStarted = true;
        _lastCuePlayed = null;
      });

      if (firstCue != null) {
        _playedSlides.add(0);
        await _dj.play(firstCue);
      }
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _autoCtrl.dispose();
    _pageController.dispose();
    _dj.dispose();
    super.dispose();
  }

  void _startAutoplay(int pageCount) {
    _autoTimer?.cancel();
    _autoCtrl.forward(from: 0);

    _autoTimer = Timer.periodic(_autoInterval, (_) async {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_pageController.page ?? 0).round() + 1;
      if (next < pageCount) {
        _autoCtrl.forward(from: 0);
        await _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      } else {
        _autoTimer?.cancel();
        _autoCtrl
            .animateTo(1.0, duration: const Duration(milliseconds: 200))
            .whenComplete(() => _autoCtrl.stop());
      }
    });
  }

  Future<_WrappedData?> _loadData() async {
    try {
      final statsFuture = UsageTracker.instance.getWrappedStats(topN: 10);
      final songMapFuture = _query
          .querySongs(
            uriType: UriType.EXTERNAL,
            sortType: SongSortType.TITLE,
            orderType: OrderType.ASC_OR_SMALLER,
          )
          .then((songs) => {for (var s in songs) s.id: s});

      final results = await Future.wait([statsFuture, songMapFuture]);
      final stats = results[0] as WrappedStats;
      final songMap = results[1] as Map<int, SongModel>;
      return (stats, songMap);
    } catch (e) {
      debugPrint("Gagal memuat data Wrapped: $e");
      return null;
    }
  }

  Future<int> _pickPreviewStartMs({
    required int songId,
    required int? durationMs,
    required String? filePath,
  }) async {
    try {
      final markers = await SmartIntroOutroService.analyzeAndSave(
        songId: songId,
        filePath: filePath ?? "",
      );
      if (markers != null) {
        final hook = markers['hookMs'] ?? -1;
        final intro = markers['introMs'] ?? 0;
        final outro = markers['outroMs'] ?? 0;
        if (hook > 0) {
          return hook.clamp(0, (durationMs ?? 0) - 1000);
        }
        if (intro > 4000) {
          return (intro + 2000).clamp(0, (durationMs ?? 0) - 1000);
        }
        if (outro > 0 && durationMs != null && durationMs > 0) {
          final mid = (durationMs * 0.5).round();
          return mid.clamp(0, durationMs - 1000);
        }
      }
    } catch (_) {}

    final d = durationMs ?? 0;
    if (d <= 0) return 0;
    final s = (d * 0.35).round();
    final clampMin = 15000;
    final clampMax = 60000;
    return s.clamp(clampMin, d - 1000).clamp(0, clampMax);
  }

  Future<Map<int, _PreviewCue>> _preparePreviewCues(
    WrappedStats stats,
    Map<int, SongModel> songMap,
  ) async {
    final result = <int, _PreviewCue>{};

    _PreviewCue? cueSong;
    _PreviewCue? cueArtist;
    _PreviewCue? cueAlbum;

    Future<_PreviewCue?> pickCueFromSongIds(Iterable<int> ids) async {
      for (final id in ids) {
        final s = songMap[id];
        if (s == null) continue;
        if (s.uri == null || s.uri!.isEmpty) continue;

        final start = await _pickPreviewStartMs(
          songId: s.id,
          durationMs: s.duration,
          filePath: s.data,
        );

        return _PreviewCue(song: s, startMs: start, lengthMs: 12000);
      }
      return null;
    }

    if (stats.topSongs.isNotEmpty) {
      final topSongIdsSorted = stats.topSongs.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      cueSong = await pickCueFromSongIds(topSongIdsSorted.map((e) => e.key));
    }
    cueSong ??= await pickCueFromSongIds(songMap.keys);

    if (stats.topArtists.isNotEmpty) {
      final topArtistKey = stats.topArtists.entries.first.key;

      Iterable<SongModel> candidates;
      if (topArtistKey is int) {
        candidates = songMap.values.where(
          (s) => s.artistId == topArtistKey && (s.uri?.isNotEmpty ?? false),
        );
      } else {
        final name = topArtistKey.toString().trim().toLowerCase();
        candidates = songMap.values.where(
          (s) =>
              (s.artist ?? '').trim().toLowerCase() == name &&
              (s.uri?.isNotEmpty ?? false),
        );
      }

      final pick =
          (candidates.toList()
                ..sort((a, b) => (b.duration ?? 0).compareTo(a.duration ?? 0)))
              .firstOrNull;

      if (pick != null) {
        final start = await _pickPreviewStartMs(
          songId: pick.id,
          durationMs: pick.duration,
          filePath: pick.data,
        );
        cueArtist = _PreviewCue(song: pick, startMs: start, lengthMs: 12000);
      }
    }
    cueArtist ??= cueSong;

    if (stats.topAlbums.isNotEmpty) {
      final topAlbumId = stats.topAlbums.entries.first.key;

      SongModel? best;
      int bestPlays = -1;
      for (final e in stats.topSongs.entries) {
        final song = songMap[e.key];
        if (song == null) continue;
        if (song.albumId != topAlbumId) continue;
        if (song.uri == null || song.uri!.isEmpty) continue;
        if (e.value > bestPlays) {
          bestPlays = e.value;
          best = song;
        }
      }

      best ??= songMap.values.firstWhere(
        (s) => s.albumId == topAlbumId && (s.uri?.isNotEmpty ?? false),
        orElse: () => SongModel(const {}),
      );

      if (best.uri != null && best.uri!.isNotEmpty) {
        final start = await _pickPreviewStartMs(
          songId: best.id,
          durationMs: best.duration,
          filePath: best.data,
        );
        cueAlbum = _PreviewCue(song: best, startMs: start, lengthMs: 12000);
      }
    }
    cueAlbum ??= cueArtist ?? cueSong;

    for (final i in [0, 1, 2, 3]) {
      result[i] = cueSong!;
    }
    result[4] = cueArtist!;
    for (final i in [5, 6, 7, 8, 9, 10]) {
      result[i] = cueAlbum!;
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<_WrappedData?>(
        future: _dataFuture,
        builder: (context, snapData) {
          if (snapData.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapData.hasData || snapData.data == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    easy.tr("wrapped.loadError"),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                    },
                    child: Text(easy.tr("wrapped.back")),
                  ),
                ],
              ),
            );
          }

          final (stats, songMap) = snapData.data!;
          final slides = _buildStorySlides(stats, songMap);

          if (!_autoplayStarted) {
            _autoplayStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _autoCtrl.forward(from: 0);
                _startAutoplay(slides.length);
              }
            });
          }

          return FutureBuilder<Map<int, _PreviewCue>>(
            future: _previewFuture ?? Future.value(<int, _PreviewCue>{}),
            builder: (context, snapCue) {
              if (snapCue.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final cueMap = snapCue.data ?? const <int, _PreviewCue>{};

              return Stack(
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _pageVN,
                    builder: (context, livePageValue, _) {
                      return PageView.builder(
                        controller: _pageController,
                        itemCount: slides.length,
                        allowImplicitScrolling: true,
                        itemBuilder: (context, index) => slides[index](
                          context,
                          livePageValue,
                          _storyStarted,
                        ),
                        onPageChanged: (index) async {
                          setState(() => _storyStarted = true);
                          _autoCtrl.forward(from: 0);
                          _startAutoplay(slides.length);
                          final cue = cueMap[index];
                          if (cue == null) {
                            return;
                          }
                          debugPrint(
                            "TEST OMBAK $_lastCuePlayed on index $index",
                          );
                          if (identical(_lastCuePlayed, cue) && _dj.isPlaying) {
                            return;
                          }
                          final ok = await _dj.play(cue);
                          if (!ok) {
                            debugPrint("DJ GAGAL PLAY ${cue.song.displayName}");
                            return;
                          }
                          _playedSlides.add(index);
                          setState(() {
                            _lastCuePlayed = cue;
                          });
                        },
                      );
                    },
                  ),

                  SafeArea(
                    child: Column(
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: _pageVN,
                          builder: (_, v, __) {
                            return _StoryIndicator(
                              pageCount: slides.length,
                              currentPage: v,
                              timeProgress: _autoCtrl.value,
                            );
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.of(context).pop();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<Widget Function(BuildContext, double, bool)> _buildStorySlides(
    WrappedStats stats,
    Map<int, SongModel> songMap,
  ) {
    final topSongId = stats.topSongs.keys.firstOrNull;
    final topSong = songMap[topSongId];
    final topSongPlayCount = stats.topSongs.values.firstOrNull ?? 0;

    final Map<int, String> hashToRealName = {};
    for (final s in songMap.values) {
      final artistName = s.artist ?? '';
      if (artistName.isNotEmpty) {
        final hash = artistName.trim().toLowerCase().hashCode;
        hashToRealName[hash] = artistName;
      }
    }

    final top5ArtistEntries = stats.topArtists.entries.take(5).map((e) {
      String rawName = e.key;

      if (rawName.startsWith('Artis ') && RegExp(r'\d+').hasMatch(rawName)) {
        final hashStr = rawName.replaceAll('Artis ', '').trim();
        final hashInt = int.tryParse(hashStr);

        if (hashInt != null && hashToRealName.containsKey(hashInt)) {
          return MapEntry<String, int>(hashToRealName[hashInt]!, e.value);
        }
      }

      final id = int.tryParse(rawName);
      if (id != null) {
        final songWithArtistId = songMap.values.firstWhere(
          (s) => s.artistId == id,
          orElse: () => SongModel({'_id': 0}),
        );
        if (songWithArtistId.artist != null) {
          return MapEntry<String, int>(songWithArtistId.artist!, e.value);
        }
      }

      return MapEntry<String, int>(rawName, e.value);
    }).toList();

    if (top5ArtistEntries.isEmpty) {
      return [_buildErrorSlide(easy.tr("wrapped.missingData.artist"))];
    }

    final top5AlbumEntries = stats.topAlbums.entries.take(5).toList();
    final topAlbumId = top5AlbumEntries.firstOrNull?.key;
    if (topAlbumId == null) {
      return [_buildErrorSlide(easy.tr("wrapped.missingData.album"))];
    }

    String getAlbumName(int? albumId) {
      if (albumId == null) return "Albums Not Recognition";
      final song = songMap.values.firstWhere(
        (s) => s.albumId == albumId,
        orElse: () => SongModel({'_id': 0, 'album': 'Album (ID: $albumId)'}),
      );
      return song.album ?? "Albums Not Recognition";
    }

    final top5AlbumData = top5AlbumEntries.map((entry) {
      return (id: entry.key, name: getAlbumName(entry.key), count: entry.value);
    }).toList();

    final topGenre = stats.topGenres.keys.firstOrNull;

    if (topSongId == null || topSong == null || topGenre == null) {
      return [_buildErrorSlide(easy.tr("wrapped.missingData.general"))];
    }

    SongModel? topArtistSongForBg;
    if (stats.topArtists.isNotEmpty) {
      final topArtistKey = stats.topArtists.entries.first.key;
      if (topArtistKey is int) {
        final cand =
            songMap.values.where((s) => s.artistId == topArtistKey).toList()
              ..sort((a, b) => (b.duration ?? 0).compareTo(a.duration ?? 0));
        if (cand.isNotEmpty) {
          topArtistSongForBg = cand.first;
        }
      } else {
        final name = topArtistKey.toString().trim().toLowerCase();
        final cand = songMap.values
            .where((s) => (s.artist ?? '').trim().toLowerCase() == name)
            .toList();
        if (cand.isNotEmpty) {
          topArtistSongForBg = cand.first;
        }
      }
    }
    final artistBgAlbumId = topArtistSongForBg?.albumId ?? topSong.albumId;

    return [
      (context, page, started) => _SlideWrapper(
        index: 0,
        page: page,
        artId: topSong.albumId,
        artType: ArtworkType.ALBUM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FadeIn(
              animate: started && page.round() == 0,
              child: Text(
                easy.tr(
                  "wrapped.slide.intro.title",
                  namedArgs: {"year": "${DateTime.now().year}"},
                ),
                style: _text(42, FontWeight.w900),
              ),
            ),
            _FadeIn(
              animate: started && page.round() == 0,
              delay: 200,
              child: Text(
                easy.tr("wrapped.slide.intro.subtitle"),
                style: _text(36, FontWeight.w300),
              ),
            ),
            const SizedBox(height: 40),
            _FadeIn(
              animate: started && page.round() == 0,
              delay: 400,
              child: Text(
                easy.tr("wrapped.slide.intro.listened"),
                style: _text(18, FontWeight.w300),
              ),
            ),
            _CountUp(
              end: (stats.listenMs / 3600000),
              decimals: 1,
              suffix: easy.tr("wrapped.slide.intro.hours"),
              style: _text(60, FontWeight.w900),
              animate: started && page.round() == 0,
            ),
            _FadeIn(
              animate: started && page.round() == 0,
              delay: 600,
              child: Text(
                easy.tr("wrapped.slide.intro.end"),
                style: _text(18, FontWeight.w300),
              ),
            ),
          ],
        ),
      ),

      (context, page, started) => _SlideWrapper(
        index: 1,
        page: page,
        artId: topSong.albumId,
        artType: ArtworkType.ALBUM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FadeIn(
              animate: started && page.round() == 1,
              child: Text(
                easy.tr("wrapped.slide.genre.vibe"),
                style: _text(24, FontWeight.w300),
              ),
            ),
            _FadeIn(
              animate: started && page.round() == 1,
              delay: 200,
              child: Text(
                _getPersona(topGenre),
                style: _text(52, FontWeight.w900, color: Colors.cyanAccent),
              ),
            ),
            _FadeIn(
              animate: started && page.round() == 1,
              delay: 400,
              child: Text(
                easy.tr(
                  "wrapped.slide.genre.genreTop",
                  namedArgs: {"genre": topGenre.toUpperCase()},
                ),
                style: _text(
                  20,
                  FontWeight.w500,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _FadeIn(
              animate: started && page.round() == 1,
              delay: 600,
              child: Text(
                _getPersonaInsight(topGenre),
                style: _text(18, FontWeight.w400),
              ),
            ),
          ],
        ),
      ),

      (context, page, started) => _SlideWrapper(
        index: 2,
        page: page,
        artId: topSong.albumId,
        artType: ArtworkType.ALBUM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FadeIn(
              animate: started && page.round() == 2,
              child: Text(
                easy.tr("wrapped.slide.song.title"),
                style: _text(24, FontWeight.w300),
              ),
            ),
            const SizedBox(height: 10),
            _FadeIn(
              animate: started && page.round() == 2,
              delay: 200,
              child: Text(topSong.title, style: _text(48, FontWeight.w900)),
            ),
            _FadeIn(
              animate: started && page.round() == 2,
              delay: 400,
              child: Text(
                topSong.artist ?? easy.tr("wrapped.slide.song.unknownArtist"),
                style: _text(
                  22,
                  FontWeight.w400,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _CountUp(
              end: topSongPlayCount.toDouble(),
              suffix: " ${easy.tr("wrapped.slide.song.playCount")}",
              style: _text(32, FontWeight.w700, color: Colors.greenAccent),
              animate: started && page.round() == 2,
            ),
            const SizedBox(height: 10),
            _FadeIn(
              animate: started && page.round() == 2,
              delay: 600,
              child: Text(
                _getTopSongInsight(topSongPlayCount),
                style: _text(18, FontWeight.w400),
              ),
            ),
          ],
        ),
      ),

      (context, page, started) => _SlideWrapper(
        index: 3,
        page: page,
        artId: topSong.albumId,
        artType: ArtworkType.ALBUM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FadeIn(
              animate: started && page.round() == 3,
              child: Text(
                easy.tr("wrapped.slide.song.subtitle"),
                style: _text(36, FontWeight.w900),
              ),
            ),
            const SizedBox(height: 24),
            ...stats.topSongs.entries.take(5).indexed.map((e) {
              final int index = e.$1;
              final MapEntry<int, int> entry = e.$2;
              final song = songMap[entry.key];
              if (song == null) return const SizedBox.shrink();

              return _FadeIn(
                animate: started && page.round() == 3,
                delay: 200 + (index * 100),
                child: _SongRow(song: song, playCount: entry.value),
              );
            }),
          ],
        ),
      ),

      (context, page, started) => _AnimatedTopArtistSlide(
        key: const ValueKey('top-artist-slide'),
        index: 4,
        page: page,
        animate: started && page.round() == 4,
        artId: artistBgAlbumId,
        artType: ArtworkType.ALBUM,
        top5Entries: top5ArtistEntries,
      ),

      (context, page, started) => _AnimatedTopAlbumSlide(
        key: const ValueKey('top-album-slide'),
        index: 5,
        page: page,
        animate: started && page.round() == 5,
        artId: topAlbumId,
        artType: ArtworkType.ALBUM,
        top5AlbumData: top5AlbumData,
      ),

      (context, page, started) => _SlideWrapper(
        index: 6,
        page: page,
        artId: topSong.albumId,
        artType: ArtworkType.ALBUM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FadeIn(
              animate: started && page.round() == 6,
              child: Text(
                easy.tr("wrapped.slide.daily.title"),
                style: _text(36, FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            _FadeIn(
              animate: started && page.round() == 6,
              delay: 200,
              child: Text(
                easy.tr(
                  "wrapped.slide.daily.subtitle",
                  namedArgs: {"time": _getPeakHour(stats.hourHistogram)},
                ),
                style: _text(20, FontWeight.w300),
              ),
            ),
            const SizedBox(height: 40),
            _AnimatedBarChart(
              data: stats.hourHistogram,
              animate: started && page.round() == 6,
              color: Colors.purpleAccent,
            ),
          ],
        ),
      ),

      (context, page, started) => _SlideWrapper(
        index: 7,
        page: page,
        artId: topSong.albumId,
        artType: ArtworkType.ALBUM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FadeIn(
              animate: started && page.round() == 7,
              child: Text(
                easy.tr("wrapped.slide.weekly.title"),
                style: _text(36, FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            _FadeIn(
              animate: started && page.round() == 7,
              delay: 200,
              child: Text(
                _getPeakDayInsight(stats.dowHistogram),
                style: _text(20, FontWeight.w300),
              ),
            ),
            const SizedBox(height: 40),
            _AnimatedBarChartDow(
              data: stats.dowHistogram,
              animate: started && page.round() == 7,
              color: Colors.orangeAccent,
            ),
          ],
        ),
      ),

      (context, page, started) => _SlideWrapper(
        index: 8,
        page: page,
        artId: topSong.albumId,
        artType: ArtworkType.ALBUM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FadeIn(
              animate: started && page.round() == 8,
              child: Text(
                easy.tr("wrapped.slide.discovery.title"),
                style: _text(36, FontWeight.w900),
              ),
            ),
            const SizedBox(height: 20),
            _CountUp(
              end: stats.discoveryCount.toDouble(),
              suffix:
                  " ${easy.tr("wrapped.insight.discovery.high20")}".contains(
                    "{count}",
                  )
                  ? " New Song"
                  : " New Song",
              style: _text(45, FontWeight.w700, color: Colors.blueAccent),
              animate: started && page.round() == 8,
            ),
            _FadeIn(
              animate: started && page.round() == 8,
              delay: 200,
              child: Text(
                easy.tr("wrapped.slide.discovery.subtitle"),
                style: _text(20, FontWeight.w300),
              ),
            ),
            const SizedBox(height: 20),
            _FadeIn(
              animate: started && page.round() == 8,
              delay: 400,
              child: Text(
                _getDiscoveryInsight(stats.discoveryCount),
                style: _text(18, FontWeight.w400),
              ),
            ),
          ],
        ),
      ),

      (context, page, started) => _SlideWrapper(
        index: 9,
        page: page,
        artId: topAlbumId,
        artType: ArtworkType.ALBUM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FadeIn(
              animate: started && page.round() == 9,
              child: Text(
                easy.tr("wrapped.slide.loyalty.title"),
                style: _text(36, FontWeight.w900),
              ),
            ),
            const SizedBox(height: 20),
            _CountUp(
              end: (stats.avgCompletionRate * 100),
              decimals: 0,
              suffix: "%",
              style: _text(52, FontWeight.w700, color: Colors.pinkAccent),
              animate: started && page.round() == 9,
              begin: 0,
              prefix: "",
            ),
            _FadeIn(
              animate: started && page.round() == 9,
              delay: 200,
              child: Text(
                easy.tr("wrapped.slide.loyalty.subtitle"),
                style: _text(20, FontWeight.w300),
              ),
            ),
            const SizedBox(height: 20),
            _FadeIn(
              animate: started && page.round() == 9,
              delay: 400,
              child: Text(
                _getCompletionInsight(stats.avgCompletionRate),
                style: _text(18, FontWeight.w400),
              ),
            ),
          ],
        ),
      ),

      (context, page, started) => _SlideWrapper(
        index: 10,
        page: page,
        artId: topSong.albumId,
        artType: ArtworkType.ALBUM,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            _FadeIn(
              animate: started && page.round() == 10,
              child: Text(
                easy.tr("wrapped.slide.outro.title"),
                style: _text(42, FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            _FadeIn(
              animate: started && page.round() == 10,
              delay: 200,
              child: Text(
                easy.tr("wrapped.slide.outro.subtitle"),
                style: _text(20, FontWeight.w300),
              ),
            ),
            const Spacer(),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(easy.tr("wrapped.share.button")),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),

                    onPressed: () async {
                      HapticFeedback.lightImpact();

                      if (top5AlbumData.isEmpty) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(easy.tr("wrapped.error.noAlbum")),
                            ),
                          );
                        }
                        return;
                      }

                      final topAlbum = top5AlbumData.first;
                      final topAlbumArt = await _query.queryArtwork(
                        topAlbum.id,
                        ArtworkType.ALBUM,
                        size: 1024,
                      );

                      if (topAlbumArt == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(easy.tr("wrapped.error.loadCover")),
                            ),
                          );
                        }
                        return;
                      }

                      final List<WrappedAlbumItem> otherAlbums = [];
                      final otherAlbumData = top5AlbumData.skip(1).take(4);

                      for (final albumData in otherAlbumData) {
                        final artBytes = await _query.queryArtwork(
                          albumData.id,
                          ArtworkType.ALBUM,
                          size: 200,
                        );

                        if (artBytes != null) {
                          otherAlbums.add(
                            WrappedAlbumItem(
                              title: albumData.name,
                              artBytes: artBytes,
                              plays: albumData.count,
                            ),
                          );
                        }
                      }

                      await WrappedStoryShare.shareWrappedWithChooser(
                        s: WrappedAlbumSummary(
                          pageTitle: easy.tr("wrapped.slide.album.title"),
                          topAlbumName: topAlbum.name,
                          topAlbumArtBytes: topAlbumArt,
                          listTitle: easy.tr("wrapped.slide.album.listTitle"),
                          otherAlbums: otherAlbums,
                          playStoreUrl:
                              "\nhttps://bit.ly/4nmQV22\n\n#Singit. #Feelit. #Offline.",
                        ),
                        ctaText: 'Listen now at DearMusic 🎧',
                        context: context,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget Function(BuildContext, double, bool) _buildErrorSlide(String message) {
    return (context, page, started) => _SlideWrapper(
      index: 0,
      page: 0,
      artId: null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.music_off, color: Colors.white, size: 60),
          SizedBox(height: 20),
          Text(
            message,
            style: _text(20, FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 10),
          Text(
            easy.tr("wrapped.errorSlide.title"),
            style: _text(16, FontWeight.w300),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  TextStyle _text(
    double size,
    FontWeight weight, {
    Color color = Colors.white,
  }) {
    return TextStyle(
      color: color,
      fontSize: size.sp,
      fontWeight: weight,
      fontFamily: 'Inter',
      shadows: [const Shadow(blurRadius: 10.0, color: Colors.black54)],
    );
  }

  String _getTopSongInsight(int playCount) {
    if (playCount > 100) {
      return easy.tr(
        "wrapped.insight.topSong.high100",
        namedArgs: {"count": "$playCount"},
      );
    }
    if (playCount > 50) {
      return easy.tr(
        "wrapped.insight.topSong.high50",
        namedArgs: {"count": "$playCount"},
      );
    }
    return easy.tr(
      "wrapped.insight.topSong.default",
      namedArgs: {"count": "$playCount"},
    );
  }

  String _getDiscoveryInsight(int count) {
    if (count > 100) {
      return easy.tr(
        "wrapped.insight.discovery.high100",
        namedArgs: {"count": "$count"},
      );
    }
    if (count > 20) {
      return easy.tr(
        "wrapped.insight.discovery.high20",
        namedArgs: {"count": "$count"},
      );
    }
    return easy.tr(
      "wrapped.insight.discovery.default",
      namedArgs: {"count": "$count"},
    );
  }

  String _getCompletionInsight(double rate) {
    final pct = (rate * 100).round().toString();
    if (rate > 0.75) {
      return easy.tr(
        "wrapped.insight.completion.loyal",
        namedArgs: {"pct": pct},
      );
    }
    if (rate > 0.4) {
      return easy.tr(
        "wrapped.insight.completion.balance",
        namedArgs: {"pct": pct},
      );
    }
    return easy.tr(
      "wrapped.insight.completion.explorer",
      namedArgs: {"pct": pct},
    );
  }

  String _getPersona(String? topGenre) {
    if (topGenre == null) return easy.tr("wrapped.persona.mystery");
    final g = topGenre.toLowerCase();
    if (g.contains('pop')) return easy.tr("wrapped.persona.pop");
    if (g.contains('rock') || g.contains('metal')) {
      return easy.tr("wrapped.persona.rock");
    }
    if (g.contains('jazz') || g.contains('classic')) {
      return easy.tr("wrapped.persona.jazz");
    }
    if (g.contains('folk') || g.contains('acoustic')) {
      return easy.tr("wrapped.persona.folk");
    }
    if (g.contains('indie')) return easy.tr("wrapped.persona.indie");
    if (g.contains('hip hop') || g.contains('rap')) {
      return easy.tr("wrapped.persona.hiphop");
    }
    return easy.tr("wrapped.persona.eclectic");
  }

  String _getPersonaInsight(String? topGenre) {
    if (topGenre == null) return easy.tr("wrapped.personaInsight.mystery");
    final g = topGenre.toLowerCase();
    if (g.contains('pop')) return easy.tr("wrapped.personaInsight.pop");
    if (g.contains('rock') || g.contains('metal')) {
      return easy.tr("wrapped.personaInsight.rock");
    }
    if (g.contains('jazz') || g.contains('classic')) {
      return easy.tr("wrapped.personaInsight.jazz");
    }
    if (g.contains('folk') || g.contains('acoustic')) {
      return easy.tr("wrapped.personaInsight.folk");
    }
    if (g.contains('indie')) return easy.tr("wrapped.personaInsight.indie");
    return easy.tr("wrapped.personaInsight.eclectic");
  }

  String _getPeakHour(Map<int, int> hourMs) {
    if (hourMs.isEmpty) return easy.tr("wrapped.listenTime.anytime");

    int peakHour = 0;
    int maxMs = 0;
    hourMs.forEach((hour, ms) {
      if (ms > maxMs) {
        maxMs = ms;
        peakHour = hour;
      }
    });

    if (peakHour >= 5 && peakHour < 10) {
      return easy.tr("wrapped.listenTime.morning");
    }
    if (peakHour >= 10 && peakHour < 15) {
      return easy.tr("wrapped.listenTime.day");
    }
    if (peakHour >= 15 && peakHour < 19) {
      return easy.tr("wrapped.listenTime.afternoon");
    }
    if (peakHour >= 19 && peakHour < 24) {
      return easy.tr("wrapped.listenTime.night");
    }
    return easy.tr("wrapped.listenTime.late");
  }

  String _getPeakDayInsight(Map<String, int> dowMs) {
    if (dowMs.isEmpty) {
      return easy.tr("wrapped.weeklyInsight.none");
    }

    String peakDayKey = 'Mon';
    int maxMs = 0;

    dowMs.forEach((key, ms) {
      if (ms > maxMs) {
        maxMs = ms;
        peakDayKey = key;
      }
    });

    final localizedDay = easy.tr("wrapped.day.$peakDayKey");
    final isWeekend = peakDayKey == 'Sat' || peakDayKey == 'Sun';

    if (isWeekend) {
      return easy.tr(
        "wrapped.weeklyInsight.weekend",
        namedArgs: {"day": localizedDay},
      );
    }

    return easy.tr(
      "wrapped.weeklyInsight.weekday",
      namedArgs: {"day": localizedDay},
    );
  }
}

class _StoryIndicator extends StatelessWidget {
  final int pageCount;
  final double currentPage;
  final double? timeProgress;

  const _StoryIndicator({
    required this.pageCount,
    required this.currentPage,
    this.timeProgress,
  });

  @override
  Widget build(BuildContext context) {
    final active = currentPage.round().clamp(0, pageCount - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: List.generate(pageCount, (index) {
          double progress;
          if (index < active) {
            progress = 1.0;
          } else if (index == active) {
            progress = (timeProgress ?? 0.0).clamp(0.0, 1.0);
          } else {
            progress = 0.0;
          }
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 3.0,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _SlideWrapper extends StatefulWidget {
  final int index;
  final double page;
  final Widget child;
  final int? artId;
  final ArtworkType artType;

  const _SlideWrapper({
    required this.index,
    required this.page,
    required this.child,
    this.artId,
    this.artType = ArtworkType.AUDIO,
  });

  @override
  State<_SlideWrapper> createState() => _SlideWrapperState();
}

class _SlideWrapperState extends State<_SlideWrapper> {
  final OnAudioQuery _query = OnAudioQuery();
  Future<Uint8List?>? _artFuture;

  static final Map<String, Future<Uint8List?>> _artCache = {};

  @override
  void initState() {
    super.initState();
    _primeArt();
  }

  @override
  void didUpdateWidget(covariant _SlideWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artId != widget.artId ||
        oldWidget.artType != widget.artType) {
      _primeArt();
    }
  }

  void _primeArt() {
    final id = widget.artId;
    if (id == null || id == 0) {
      _artFuture = Future.value(null);
      return;
    }
    final key = '${widget.artType}_$id';
    _artFuture = _artCache[key] ??= _query.queryArtwork(
      id,
      widget.artType,
      size: 800,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double offset = (widget.page - widget.index);

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: _artFuture,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              Widget bg;
              if (bytes != null && bytes.isNotEmpty) {
                bg = Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                );
              } else {
                bg = Container(color: const Color(0xFF1A1A1A));
              }

              return Transform.translate(
                offset: Offset(offset * -60, 0),
                child: bg,
              );
            },
          ),

          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.90),
                    Colors.black.withOpacity(0.60),
                    Colors.black.withOpacity(0.90),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountUp extends StatelessWidget {
  final double begin;
  final double end;
  final String prefix;
  final String suffix;
  final TextStyle style;
  final bool animate;
  final int decimals;

  const _CountUp({
    required this.end,
    required this.style,
    required this.animate,
    this.begin = 0.0,
    this.prefix = "",
    this.suffix = "",
    this.decimals = 0,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: begin, end: animate ? end : begin),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Text(
          "$prefix${value.toStringAsFixed(decimals)}$suffix",
          style: style,
        );
      },
    );
  }
}

class _FadeIn extends StatefulWidget {
  final Widget child;
  final int delay;
  final bool animate;

  const _FadeIn({required this.child, this.delay = 0, required this.animate});

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_c);

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      Future.delayed(Duration(milliseconds: widget.delay), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _FadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) {
      Future.delayed(Duration(milliseconds: widget.delay), () {
        if (mounted) _c.forward(from: 0);
      });
    } else if (!widget.animate && oldWidget.animate) {
      if (mounted) _c.reset();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _SongRow extends StatelessWidget {
  final SongModel song;
  final int playCount;

  const _SongRow({required this.song, required this.playCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8.0)),
            child: _CachedArtwork(id: song.id, type: ArtworkType.AUDIO),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  song.artist ?? "Unknown Artist",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14.sp,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "${playCount}x",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class ArtworkCache {
  static final _fut = <String, Future<Uint8List?>>{};
  static final _mem = <String, Uint8List?>{};

  static Future<Uint8List?> get(
    int id,
    ArtworkType type,
    OnAudioQuery q, {
    int size = 300,
  }) {
    final key = '${type}_$id@$size';
    if (_mem.containsKey(key)) return Future.value(_mem[key]);
    return _fut[key] ??= q.queryArtwork(id, type, size: size).then((b) {
      _mem[key] = b;
      return b;
    });
  }
}

class _CachedArtwork extends StatefulWidget {
  final int id;
  final ArtworkType type;

  const _CachedArtwork({required this.id, required this.type});

  @override
  State<_CachedArtwork> createState() => _CachedArtworkState();
}

class _CachedArtworkState extends State<_CachedArtwork> {
  final _q = OnAudioQuery();
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    ArtworkCache.get(widget.id, widget.type, _q, size: 300).then((b) {
      if (!mounted) return;
      setState(() => _bytes = b);
      if (b != null) {
        precacheImage(MemoryImage(b), context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null || _bytes!.isEmpty) {
      return Container(
        color: Colors.grey.shade800,
        child: const Icon(Icons.music_note, color: Colors.white),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}

class _AnimatedBarChart extends StatelessWidget {
  final Map<int, int> data;
  final bool animate;
  final Color color;

  const _AnimatedBarChart({
    required this.data,
    required this.animate,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = data.values.fold<int>(0, (max, v) => math.max(max, v));
    if (maxVal == 0) return const SizedBox(height: 150);

    final List<int> values = List.generate(24, (i) => data[i] ?? 0);

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(24, (index) {
          final val = values[index];
          final double normalizedHeight = (val / maxVal.toDouble()) * 150.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0.0,
                  end: animate ? normalizedHeight.clamp(2.0, 150.0) : 0.0,
                ),
                duration: Duration(milliseconds: 800 + (index * 30)),
                curve: Curves.easeOutCubic,
                builder: (context, height, child) {
                  return Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                  );
                },
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _AnimatedBarChartDow extends StatelessWidget {
  final Map<String, int> data;
  final bool animate;
  final Color color;

  const _AnimatedBarChartDow({
    required this.data,
    required this.animate,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = data.values.fold<int>(0, (max, v) => math.max(max, v));
    if (maxVal == 0) return const SizedBox(height: 150);

    const dayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: dayOrder.map((dayKey) {
          final val = data[dayKey] ?? 0;
          final double normalizedHeight = (val / maxVal.toDouble()) * 150.0;
          final int index = dayOrder.indexOf(dayKey);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0.0,
                  end: animate ? normalizedHeight.clamp(2.0, 150.0) : 0.0,
                ),
                duration: Duration(milliseconds: 800 + (index * 60)),
                curve: Curves.easeOutCubic,
                builder: (context, height, child) {
                  return Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                  );
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BigArtwork extends StatelessWidget {
  final int id;
  final ArtworkType type;

  const _BigArtwork({required this.id, required this.type});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 200,
        height: 200,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: _CachedArtwork(id: id, type: type),
      ),
    );
  }
}

class _AnimatedTopArtistSlide extends StatefulWidget {
  final int index;
  final double page;
  final bool animate;
  final int? artId;
  final ArtworkType artType;
  final List<MapEntry<String, int>> top5Entries;

  const _AnimatedTopArtistSlide({
    super.key,
    required this.index,
    required this.page,
    required this.animate,
    required this.artId,
    required this.artType,
    required this.top5Entries,
  });

  @override
  State<_AnimatedTopArtistSlide> createState() =>
      _AnimatedTopArtistSlideState();
}

class _AnimatedTopArtistSlideState extends State<_AnimatedTopArtistSlide> {
  bool _showList = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedTopArtistSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate && !_showList) {
      _startTimer();
    }
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showList = true);
      }
    });
  }

  TextStyle _text(
    double size,
    FontWeight weight, {
    Color color = Colors.white,
  }) {
    return TextStyle(
      color: color,
      fontSize: size.sp,
      fontWeight: weight,
      fontFamily: 'Inter',
      shadows: [const Shadow(blurRadius: 10.0, color: Colors.black54)],
    );
  }

  String _safeArtist(String name) {
    final m = RegExp(r'^Artis\s+\(ID:\s*\d+\)$', caseSensitive: false);
    return m.hasMatch(name) ? 'Artis' : name;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.top5Entries.isEmpty) return const SizedBox.shrink();

    final topEntry = widget.top5Entries.first;
    final restOfList = widget.top5Entries.skip(1).toList();

    return _SlideWrapper(
      index: widget.index,
      page: widget.page,
      artId: widget.artId,
      artType: widget.artType,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedScale(
            scale: _showList ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FadeIn(
                  animate: widget.animate,
                  delay: 0,
                  child: Text(
                    easy.tr("wrapped.slide.artist.title"),
                    style: _text(24, FontWeight.w300),
                  ),
                ),
                _FadeIn(
                  animate: widget.animate,
                  delay: 200,
                  child: Text(
                    _safeArtist(topEntry.key),
                    style: _text(52, FontWeight.w900),
                  ),
                ),
                _CountUp(
                  end: topEntry.value.toDouble(),
                  suffix: " ${easy.tr("wrapped.artist.playSuffix")}",
                  style: _text(22, FontWeight.w500),
                  animate: widget.animate,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          AnimatedOpacity(
            opacity: _showList ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeIn,
            child: _showList
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          easy.tr("wrapped.slide.artist.listTitle"),
                          style: _text(16, FontWeight.w300),
                        ),
                      ),
                      ...restOfList.asMap().entries.map((e) {
                        final index = e.key;
                        final entry = e.value;

                        return _FadeIn(
                          animate: widget.animate,
                          delay: index * 150,
                          child: _ArtistRow(
                            rank: index + 2,
                            name: entry.key,
                            playCount: entry.value,
                          ),
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _AnimatedTopAlbumSlide extends StatefulWidget {
  final int index;
  final double page;
  final bool animate;
  final int? artId;
  final ArtworkType artType;
  final List<({int id, String name, int count})> top5AlbumData;

  const _AnimatedTopAlbumSlide({
    super.key,
    required this.index,
    required this.page,
    required this.animate,
    required this.artId,
    required this.artType,
    required this.top5AlbumData,
  });

  @override
  State<_AnimatedTopAlbumSlide> createState() => _AnimatedTopAlbumSlideState();
}

class _AnimatedTopAlbumSlideState extends State<_AnimatedTopAlbumSlide> {
  bool _showList = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedTopAlbumSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate && !_showList) {
      _startTimer();
    }
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showList = true);
      }
    });
  }

  TextStyle _text(
    double size,
    FontWeight weight, {
    Color color = Colors.white,
  }) {
    return TextStyle(
      color: color,
      fontSize: size.sp,
      fontWeight: weight,
      fontFamily: 'Inter',
      shadows: [const Shadow(blurRadius: 10.0, color: Colors.black54)],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.top5AlbumData.isEmpty) return const SizedBox.shrink();

    final topEntry = widget.top5AlbumData.first;
    final restOfList = widget.top5AlbumData.skip(1).toList();

    return _SlideWrapper(
      index: widget.index,
      page: widget.page,
      artId: widget.artId,
      artType: widget.artType,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          AnimatedPadding(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
            padding: EdgeInsets.only(top: _showList ? 0.0 : 60.0, bottom: 10.0),
            child: AnimatedScale(
              scale: _showList ? 0.8 : 1.0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  _FadeIn(
                    animate: widget.animate,
                    delay: 0,
                    child: Text(
                      easy.tr("wrapped.slide.album.title"),
                      style: _text(24, FontWeight.w300),
                    ),
                  ),
                  _FadeIn(
                    animate: widget.animate,
                    delay: 200,
                    child: Text(
                      topEntry.name,
                      style: _text(42, FontWeight.w900),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FadeIn(
                    animate: widget.animate,
                    delay: 400,
                    child: _BigArtwork(
                      id: topEntry.id,
                      type: ArtworkType.ALBUM,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: AnimatedOpacity(
              opacity: _showList ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeIn,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_showList)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
                        child: Text(
                          easy.tr("wrapped.slide.album.listTitle"),
                          style: _text(16, FontWeight.w300),
                        ),
                      ),
                    ...restOfList.asMap().entries.map((e) {
                      final index = e.key;
                      final entry = e.value;
                      return _FadeIn(
                        animate: _showList,
                        delay: index * 150,
                        child: _AlbumRow(
                          rank: index + 2,
                          albumId: entry.id,
                          name: entry.name,
                          playCount: entry.count,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistRow extends StatelessWidget {
  final int rank;
  final String name;
  final int playCount;

  const _ArtistRow({
    required this.rank,
    required this.name,
    required this.playCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Text(
            "#$rank",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "${playCount}x",
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  final int rank;
  final int albumId;
  final String name;
  final int playCount;

  const _AlbumRow({
    required this.rank,
    required this.albumId,
    required this.name,
    required this.playCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Text(
            "#$rank",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4.0)),
            child: _CachedArtwork(id: albumId, type: ArtworkType.ALBUM),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "${playCount}x",
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCue {
  final SongModel song;
  final int startMs;
  final int lengthMs;

  _PreviewCue({
    required this.song,
    required this.startMs,
    this.lengthMs = 12000,
  });
}

class _PreviewDJ {
  final AudioPlayer _p = AudioPlayer();
  bool _inited = false;

  _PreviewCue? _currentCue;

  bool get isPlaying => _p.playing;

  Future<void> init() async {
    if (_inited) return;
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidWillPauseWhenDucked: false,
      ),
    );
    _inited = true;
  }

  Future<bool> play(_PreviewCue cue) async {
    await init();
    try {
      await _fade(to: 0, ms: 160);

      final uri = cue.song.uri;
      if (uri == null || uri.isEmpty) {
        return false;
      }

      await _p.setAudioSource(AudioSource.uri(Uri.parse(uri)));

      final total = cue.song.duration ?? 0;
      final safeStart = cue.startMs.clamp(0, (total - 1000)).toInt();

      await _p.setVolume(0);
      await _p.seek(Duration(milliseconds: safeStart));
      await _p.play();

      await _fade(to: 1.0, ms: 220);

      _currentCue = cue;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      if (_p.playing) {
        await _fade(to: 0, ms: 180);
        await _p.stop();
      }
      _currentCue = null;
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await stop();
      await _p.dispose();
    } catch (_) {}
  }

  Future<void> _fade({required double to, int ms = 180}) async {
    final from = _p.volume;
    final steps = 24;
    final dt = (ms / steps).ceil();
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final v = from + (to - from) * t;
      await _p.setVolume(v.clamp(0.0, 1.0));
      await Future.delayed(Duration(milliseconds: dt));
    }
  }
}
