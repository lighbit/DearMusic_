import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dearmusic/src/audio/AudioPermissionGate.dart';
import 'package:dearmusic/src/audio/loudness_analysis_service.dart';
import 'package:dearmusic/src/audio/smart_intro_outro_service.dart';
import 'package:dearmusic/src/pages/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:get_storage/get_storage.dart';
import 'package:home_widget/home_widget.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:dearmusic/src/logic/usage_tracker.dart';

enum _PendingAction { none, next, prev }

_PendingAction _pending = _PendingAction.none;

class PlayerController extends BaseAudioHandler
    with ChangeNotifier, WidgetsBindingObserver {
  final AudioPlayer player = AudioPlayer();
  final OnAudioQuery _query = OnAudioQuery();
  final GetStorage _box = GetStorage();
  final Map<int, SongModel> _songByIdCache = {};
  final List<int> _recentAutoIds = [];
  final int _lastWidgetSyncMs = 0;

  static Future<void> _volLock = Future.value();
  static const _pinKey = 'pinned_song_ids';
  static const _kAutoRecent = 'auto:recent_ids';

  double? _pendingRgLinear;
  bool _fading = false;

  List<SongModel> _all = [];
  List<int> _pinnedIds = [];

  List<SongModel> get allSongs => _all;

  List<int> get pinnedIds => _pinnedIds;

  OnAudioQuery get query => _query;
  MediaItem? _lastStartedTag;

  String? _lastFadedTagId;
  Future _navQueue = Future.value();
  int _lastNavMs = 0;

  int? _lastLoggedSongId;
  int _lastAutoFillMs = 0;
  int _crossfadeSec = 0;
  int _trackStartMs = 0;
  int _cachedOutroMs = 0;
  int _lastProgressSaveMs = 0;

  StreamSubscription<Duration>? _positionBroadcastSub;
  StreamSubscription<Duration>? _crossfadeSub;
  StreamSubscription<Duration>? _outroCutSub;

  bool _autoFillInProgress = false;
  bool _widgetSyncScheduled = false;

  int _lastPosMsForLoop = 0;
  String? _loopWatchTagId;

  Future<T> _withNavLock<T>(Future<T> Function() job) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final shouldDelay = (now - _lastNavMs) < 120;
    _lastNavMs = now;

    final completer = Completer<T>();
    _navQueue = _navQueue
        .then((_) async {
          if (shouldDelay) {
            await Future.delayed(const Duration(milliseconds: 120));
          }
          return job();
        })
        .then(completer.complete)
        .catchError(completer.completeError);
    return completer.future;
  }

  String? _currentTagId() {
    final tag = player.sequenceState.currentSource?.tag;
    return (tag is MediaItem) ? tag.id : null;
  }

  Future<void> _commitPlayEnd({required bool completed}) async {
    final curTag = player.sequenceState.currentSource?.tag;
    final tag = (curTag is MediaItem) ? curTag : _lastStartedTag;

    final songId = (tag is MediaItem) ? int.tryParse(tag.id) : null;

    if (songId != null) {
      unawaited(
        UsageTracker.instance.finalizeSong(
          songId: songId,
          completed: completed,
        ),
      );
    }
  }

  Future<void> _commitSkipNow() async {
    unawaited(UsageTracker.instance.markSkipCurrent());

    await _commitPlayEnd(completed: false);
  }

  PlayerController() {
    _connectStreamsToAudioService();
  }

  void broadcastState([Duration? position]) {
    final isPlaying = player.playing;

    playbackState.add(
      PlaybackState(
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[player.processingState]!,
        playing: isPlaying,
        updatePosition: position ?? player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: player.currentIndex,
        controls: [
          MediaControl.stop,
          MediaControl.skipToPrevious,
          player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.rewind,
          MediaControl.fastForward,
        ],
        androidCompactActionIndices: const [1, 2, 3],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
          MediaAction.skipToPrevious,
          MediaAction.skipToNext,
          MediaAction.playPause,
          MediaAction.stop,
        },
        repeatMode: playbackState.value.repeatMode,
        shuffleMode: playbackState.value.shuffleMode,
        captioningEnabled: playbackState.value.captioningEnabled,
      ),
    );
  }

  void _checkRepeatLoop(Duration newPosition) {
    final curTag = player.sequenceState.currentSource?.tag;
    if (curTag is! MediaItem) {
      _lastPosMsForLoop = newPosition.inMilliseconds;
      _loopWatchTagId = null;
      return;
    }

    final curId = curTag.id;
    final durMs = player.duration?.inMilliseconds ?? 0;
    final posMs = newPosition.inMilliseconds;
    final sameTrack = (_loopWatchTagId == null || _loopWatchTagId == curId);
    final endedAndRestarted =
        sameTrack &&
        durMs > 0 &&
        _lastPosMsForLoop > (durMs - 2000) &&
        posMs < 2000;

    if (endedAndRestarted) {
      final sid = int.tryParse(curId);
      if (sid != null) {
        unawaited(
          UsageTracker.instance.finalizeSong(songId: sid, completed: true),
        );

        _lastLoggedSongId = null;
        unawaited(_logCurrentPlay());
      }
    }

    _loopWatchTagId = curId;
    _lastPosMsForLoop = posMs;
  }

  void _connectStreamsToAudioService() {
    player.sequenceStateStream.listen((sequenceState) {
      final currentItem = sequenceState.currentSource?.tag;
      if (currentItem is MediaItem) {
        mediaItem.add(currentItem);
      }
    });

    player.playbackEventStream.listen((PlaybackEvent event) {
      broadcastState(event.updatePosition);
    });

    _positionBroadcastSub?.cancel();
    _positionBroadcastSub = player.positionStream.listen((
      Duration newPosition,
    ) {
      broadcastState(newPosition);
      _checkRepeatLoop(newPosition);

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastProgressSaveMs > 5000) {
        UsageTracker.instance.updateSessionProgress(newPosition.inMilliseconds);
        _lastProgressSaveMs = now;
      }
    });

    player.sequenceStream.listen((sequence) {
      queue.add(sequence.map((s) => s.tag as MediaItem).toList());
    });

    player.loopModeStream.listen((mode) {
      final mapped = switch (mode) {
        LoopMode.off => AudioServiceRepeatMode.none,
        LoopMode.one => AudioServiceRepeatMode.one,
        LoopMode.all => AudioServiceRepeatMode.all,
      };

      playbackState.add(playbackState.value.copyWith(repeatMode: mapped));
    });

    player.shuffleModeEnabledStream.listen((enabled) {
      final mapped = enabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none;

      playbackState.add(playbackState.value.copyWith(shuffleMode: mapped));
    });
  }

  Future<void> initHandler() async {
    WidgetsBinding.instance.addObserver(this);
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    session.becomingNoisyEventStream.listen((_) {
      if (player.playing) {
        player.pause();
      }
    });

    _pinnedIds = (_box.read<List>(_pinKey)?.cast<int>()) ?? [];
    _recentAutoIds.addAll((_box.read<List>(_kAutoRecent)?.cast<int>()) ?? []);
    await _loadLibrary();
    _seedCacheWithAllSongs();
    await _resumeFromLastListened();

    player.playerStateStream.listen((_) => notifyListeners());
    player.playingStream.listen((_) => _scheduleWidgetSync());

    player.currentIndexStream.listen((i) async {
      await _applyStartupSettings();
      if (i != null && player.playing) {
        await _logCurrentPlay();
      }
      await _applyIntroSkipIfAny();
      await _applyReplayGainIfAny();
      await _scheduleWidgetSync();
      notifyListeners();
    });

    player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        await _commitPlayEnd(completed: true);

        if (player.loopMode == LoopMode.off &&
            !player.hasNext &&
            player.playing) {
          if (_isAutoplayEnabled()) {
            await _autoplayFromRecommendations();
          } else {
            await player.pause();
            await _scheduleWidgetSync();
            notifyListeners();
          }
        }
      }

      if (state == ProcessingState.ready && _pending != _PendingAction.none) {
        final action = _pending;
        _pending = _PendingAction.none;

        await _withNavLock(() async {
          if (action == _PendingAction.next && player.hasNext) {
            await _commitSkipNow();
            await player.seekToNext();
            await player.play();
            await _logCurrentPlay();
            await _scheduleWidgetSync();
            notifyListeners();
          } else if (action == _PendingAction.prev) {
            await _commitSkipNow();
            final lastIndex = player.sequence.length - 1;
            if (lastIndex >= 0) {
              await player.seek(Duration.zero, index: lastIndex);
              await player.play();
              await _logCurrentPlay();
              await _scheduleWidgetSync();
              notifyListeners();
            }
          }
        });
      }
    });

    await _scheduleWidgetSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (!player.playing) {
        UsageTracker.instance.flushSession();
      } else {}
    }
  }

  Future<void> _resumeFromLastListened() async {
    final recents = UsageTracker.instance.recentPlays(limit: 1);
    if (recents.isEmpty) return;

    final r = recents.first;
    final lastId = r['id'] as int?;
    if (lastId == null) return;

    SongModel? s = _songByIdCache[lastId];
    s ??= _all.firstWhere(
      (e) => e.id == lastId && e.uri?.isNotEmpty == true,
      orElse: () => SongModel(const {}),
    );
    if (s.uri == null || s.uri!.isEmpty) return;

    final single = ConcatenatingAudioSource(children: [_toSource(s)]);
    await player.stop();
    await player.setAudioSource(
      single,
      initialIndex: 0,
      initialPosition: Duration.zero,
    );
    await player.pause();

    await _scheduleWidgetSync();
    notifyListeners();
  }

  Future<void> _scheduleWidgetSync({int throttleMs = 750}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_widgetSyncScheduled) return;
    if (now - _lastWidgetSyncMs < throttleMs) {
      _widgetSyncScheduled = true;
      final wait = throttleMs - (now - _lastWidgetSyncMs);
      Future.delayed(Duration(milliseconds: wait)).then((_) {
        _widgetSyncScheduled = false;
        _doWidgetSync();
      });
      return;
    }
    await _doWidgetSync();
  }

  Future<void> _doWidgetSync() async {
    String title = 'Track';
    String artist = '–';
    String? artUri;
    bool isPlaying = player.playing;

    final tag = player.sequenceState.currentSource?.tag;
    if (tag is MediaItem) {
      if (tag.title.isNotEmpty) title = tag.title;
      if (tag.artist?.isNotEmpty == true) artist = tag.artist!;
      artUri = tag.artUri?.toString();

      final albumId = tag.extras?['albumId'];
      if ((artUri == null || artUri.isEmpty) && albumId != null) {
        artUri = 'content://media/external/audio/albumart/$albumId';
      }
    }

    await HomeWidget.saveWidgetData<String>('now_title', title);
    await HomeWidget.saveWidgetData<String>('now_subtitle', artist);
    await HomeWidget.saveWidgetData<bool>('is_playing', isPlaying);
    if (artUri != null) {
      await HomeWidget.saveWidgetData<String>('now_art_uri', artUri);
    } else {
      await HomeWidget.saveWidgetData<String>('now_art_uri', null);
    }

    await HomeWidget.updateWidget(
      name: 'DearMusicWidgetProvider',
      iOSName: 'DearMusicWidgetProvider',
    );
  }

  void _rememberAutoPlayed(Iterable<SongModel> items) {
    for (final s in items) {
      _recentAutoIds.remove(s.id);
      _recentAutoIds.insert(0, s.id);
    }
    while (_recentAutoIds.length > 50) {
      _recentAutoIds.removeLast();
    }
    _box.write(_kAutoRecent, _recentAutoIds);
  }

  Future<void> _applyIntroSkipIfAny() async {
    final skipOn = (_box.read(SettingsKeys.skipSilent) as bool?) ?? false;
    if (!skipOn) return;

    await Future.delayed(const Duration(milliseconds: 50));

    final tag = player.sequenceState.currentSource?.tag;
    if (tag is! MediaItem) return;

    final id = int.tryParse(tag.id);
    if (id == null) return;

    var durMs = player.duration?.inMilliseconds;

    if (durMs == null || durMs == 0) {
      durMs = tag.duration?.inMilliseconds;
    }

    final path = tag.extras?['filePath'] ?? tag.extras?['uri'];
    if (path == null) return;

    final markers =
        SmartIntroOutroService.read(id) ??
        await SmartIntroOutroService.analyzeAndSave(
          songId: id,
          filePath: path,
          durationMs: durMs,
        );

    final introMs = (markers?['introMs'] ?? 0);

    if (introMs > 400 && player.position < const Duration(milliseconds: 500)) {
      await player.seek(Duration(milliseconds: introMs));
    }
  }

  Future<void> _autoplayFromRecommendations({
    _PendingAction postAction = _PendingAction.none,
  }) async {
    if (_autoFillInProgress) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAutoFillMs < 1500) return;

    _autoFillInProgress = true;
    try {
      final byId = Map<int, SongModel>.from(_songByIdCache);
      if (byId.isEmpty && _all.isNotEmpty) {
        for (final s in _all) {
          byId[s.id] = s;
        }
      }

      final currentId = () {
        final tag = player.sequenceState.currentSource?.tag;
        if (tag is MediaItem) return int.tryParse(tag.id);
        return null;
      }();
      final queuedIds = <int>{};
      for (final e in player.sequence) {
        final tag = e.tag;
        if (tag is MediaItem) {
          final id = int.tryParse(tag.id);
          if (id != null) queuedIds.add(id);
        }
      }

      final recents = UsageTracker.instance.recentPlays(limit: 60);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const coolMs = 48 * 3600 * 1000;
      final recentCooldownIds = <int>{
        for (final r in recents)
          if ((r['id'] as int?) != null &&
              (nowMs - (r['ts'] as int? ?? 0)) < coolMs)
            r['id'] as int,
      };

      final ranked = UsageTracker.instance.rankedSongIds(limit: 200);
      final exclude = <int>{
        ...queuedIds,
        ..._recentAutoIds.take(120),
        ...recentCooldownIds,
        if (currentId != null) currentId,
      };

      final recPool = <SongModel>[
        for (final id in ranked)
          if (byId[id]?.uri?.isNotEmpty == true && !exclude.contains(id))
            byId[id]!,
      ];

      final explorePool = _all.where((s) {
        return s.uri != null &&
            s.uri!.isNotEmpty &&
            !exclude.contains(s.id) &&
            !recPool.any((r) => r.id == s.id);
      }).toList();

      if (recPool.isEmpty && explorePool.isEmpty) return;

      const target = 12;
      final picked = _diversePick(recPool, explorePool, target: target);
      if (picked.isEmpty) return;

      final toAdd = [for (final s in picked) _toSource(s)];
      final src = player.audioSource;
      if (src == null) {
        await player.setAudioSource(ConcatenatingAudioSource(children: toAdd));
      } else if (src is ConcatenatingAudioSource) {
        await src.addAll(toAdd);
      } else {
        final pos = player.position;
        final newList = ConcatenatingAudioSource(children: [src, ...toAdd]);
        await player.setAudioSource(
          newList,
          initialIndex: 0,
          initialPosition: pos,
        );
      }

      if (postAction == _PendingAction.next) {
        if (player.hasNext) {
          await player.seekToNext();
        } else if (player.sequence.isNotEmpty) {
          final last = player.sequence.length - 1;
          await player.seek(Duration.zero, index: last);
        }
        await player.play();
        await _logCurrentPlay();
      } else if (postAction == _PendingAction.prev) {
        final lastIndex = player.sequence.length - 1;
        if (lastIndex >= 0) {
          await player.seek(Duration.zero, index: lastIndex);
          await player.play();
          await _logCurrentPlay();
        }
      } else {}

      _rememberAutoPlayed(picked);
      _lastAutoFillMs = now;
    } finally {
      _autoFillInProgress = false;
      await _scheduleWidgetSync();
      notifyListeners();
    }
  }

  List<SongModel> _diversePick(
    List<SongModel> recPool,
    List<SongModel> explorePool, {
    required int target,
  }) {
    recPool.shuffle();
    explorePool.shuffle();

    final recent = UsageTracker.instance.recentPlays(limit: 24);
    final lastArtists = <String>{};
    for (final r in recent.take(6)) {
      final a = (r['artist'] as String?)?.trim();
      if (a != null && a.isNotEmpty) lastArtists.add(a);
    }

    final libSize = _all.length;
    final recRatio = libSize > 400
        ? 0.55
        : libSize > 150
        ? 0.58
        : 0.5;
    final recTarget = (target * recRatio).round();

    final pre = <SongModel>[
      ...recPool
          .where((s) => !(lastArtists.contains((s.artist ?? '').trim())))
          .take(recTarget),
      ...explorePool
          .where((s) {
            final id = s.id;
            final heardCount = UsageTracker.instance
                .topSongs(limit: 9999)
                .any((e) => e.key == id);
            return !heardCount;
          })
          .take((target * 0.6).round()),
      ...explorePool.take(target),
    ];

    final byArtist = <String, int>{};
    final byAlbum = <int?, int>{};
    final out = <SongModel>[];

    bool okArtist(String a) =>
        (byArtist[a] ?? 0) < 1 && !lastArtists.contains(a);
    bool okAlbum(int? id) => (byAlbum[id] ?? 0) < 1;

    for (final s in pre) {
      final a = (s.artist ?? '').trim();
      final alb = s.albumId;
      if (okArtist(a) && okAlbum(alb)) {
        out.add(s);
        byArtist[a] = (byArtist[a] ?? 0) + 1;
        byAlbum[alb] = (byAlbum[alb] ?? 0) + 1;
        if (out.length >= target) break;
      }
    }

    if (out.length < target) {
      final extra = [...recPool.skip(recTarget), ...explorePool];
      for (final s in extra) {
        if (!out.any((e) => e.id == s.id)) {
          out.add(s);
          if (out.length >= target) break;
        }
      }
    }

    out.shuffle();
    return out;
  }

  Future<List<SongModel>> recommendNext({
    int want = 20,
    String? contextGenre,
  }) async {
    final byId = Map<int, SongModel>.from(_songByIdCache);
    if (byId.isEmpty && _all.isNotEmpty) {
      for (final s in _all) {
        byId[s.id] = s;
      }
    }

    final st = player.sequenceState;
    final curTag = st.currentSource?.tag;
    final currentId = (curTag is MediaItem) ? int.tryParse(curTag.id) : null;

    final queuedIds = <int>{
      for (final e in player.sequence)
        if (e.tag is MediaItem) int.tryParse((e.tag as MediaItem).id) ?? -1,
    }..remove(-1);

    final recents = UsageTracker.instance.recentPlays(limit: 60);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const coolMs = 48 * 3600 * 1000;
    final recentCooldownIds = <int>{
      for (final r in recents)
        if ((r['id'] as int?) != null &&
            (nowMs - (r['ts'] as int? ?? 0)) < coolMs)
          r['id'] as int,
    };

    final rankedIds = UsageTracker.instance.rankedSongIds(
      limit: 400,
      contextGenre: contextGenre,
    );

    final exclude = <int>{
      ...queuedIds,
      ..._recentAutoIds.take(40),
      ...recentCooldownIds,
      if (currentId != null) currentId,
    };

    final recPool = <SongModel>[
      for (final id in rankedIds)
        if (byId[id]?.uri?.isNotEmpty == true && !exclude.contains(id))
          byId[id]!,
    ];

    final explorePool = _all.where((s) {
      return s.uri?.isNotEmpty == true &&
          !exclude.contains(s.id) &&
          !recPool.any((r) => r.id == s.id);
    }).toList();

    if (recPool.isEmpty && explorePool.isEmpty) return const <SongModel>[];

    final picked = _diversePick(recPool, explorePool, target: want);
    return picked;
  }

  Future<void> smartClear({required bool refill, int want = 50}) async {
    String? genreCtx;
    final st = player.sequenceState;
    final curTag = st.currentSource?.tag;
    if (curTag is MediaItem) genreCtx = curTag.genre;

    try {
      if (player.shuffleModeEnabled) {
        await player.setShuffleModeEnabled(false);
      }
    } catch (_) {}

    await player.stop();
    await player.setAudioSource(
      ConcatenatingAudioSource(children: const []),
      preload: false,
    );

    if (!refill) {
      await _scheduleWidgetSync();
      notifyListeners();
      return;
    }

    final recs = await recommendNext(want: want, contextGenre: genreCtx);

    if (recs.isEmpty) {
      await _scheduleWidgetSync();
      notifyListeners();
      return;
    }

    await playQueue(recs, startIndex: 0, shuffle: false);
  }

  Future<void> _applyReplayGainIfAny() async {
    final enabled = (_box.read(SettingsKeys.replayGain) as bool?) ?? false;

    Future<void> resetVol() async {
      if (_fading) {
        _pendingRgLinear = 1.0;
      } else {
        await _fadeVolume(to: 1.0, duration: const Duration(milliseconds: 180));
      }
    }

    if (!enabled) {
      await resetVol();
      return;
    }

    if (_fading) return;

    final tag = player.sequenceState.currentSource?.tag;
    if (tag is! MediaItem) {
      await resetVol();
      return;
    }

    final id = int.tryParse(tag.id);
    if (id == null) {
      await resetVol();
      return;
    }

    final path = tag.extras?['filePath'] ?? tag.extras?['uri'];
    if (path == null) {
      await resetVol();
      return;
    }

    var rg = LoudnessService.read(id);
    rg ??= await LoudnessService.analyzeAndSave(songId: id, filePath: path);

    if (rg == null) {
      await resetVol();
      return;
    }

    final gainDyn = rg['gainDb'];
    if (gainDyn is! num) {
      await resetVol();
      return;
    }

    final gainDb = gainDyn.toDouble();
    final linear = pow(10.0, gainDb / 20.0).toDouble();
    final clamped = linear.clamp(0.0, 1.0);

    if (_fading) {
      _pendingRgLinear = clamped;
      return;
    }
    await _fadeVolume(to: clamped, duration: const Duration(milliseconds: 180));
  }

  Future<void> setReplayGainEnabled(bool enabled) async {
    await _box.write('st_rg_enable', enabled);

    if (!enabled) {
      if (_fading) {
        _pendingRgLinear = 1.0;
      } else {
        await _fadeVolume(to: 1.0, duration: const Duration(milliseconds: 180));
      }
      return;
    }

    await _applyReplayGainIfAny();
  }

  Future<void> _ensurePermission() async {
    if (Platform.isAndroid) {
      final ok = await _query.permissionsStatus();
      if (!ok) {
        final granted = await _query.permissionsRequest();
        if (!granted) return;
      }
    }
  }

  Future<void> _loadLibrary() async {
    final ok = await PermissionService.instance.ensureForOnAudioQuery(
      _query,
      force: true,
    );
    if (!ok) {
      notifyListeners();
      return;
    }

    final box = _box;
    final bool scanAll = box.read(SettingsKeys.scanAll) is bool
        ? (box.read(SettingsKeys.scanAll) as bool)
        : true;

    final List<String> allowedRootsRaw =
        (box.read<List>(SettingsKeys.allowedDirs)?.cast<String>()) ?? const [];

    String normSlashLower(String p) => p.replaceAll('\\', '/').toLowerCase();

    bool allowedByUser(String filePathOrUri) {
      if (scanAll || allowedRootsRaw.isEmpty) return true;

      final p = normSlashLower(filePathOrUri);

      final hitPath = allowedRootsRaw
          .where((r) => !r.startsWith('content://'))
          .map(normSlashLower)
          .map((r) => r.endsWith('/') ? r : '$r/')
          .any((root) => p.startsWith(root));
      if (hitPath) return true;

      final hitTree = allowedRootsRaw
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
      final title = (s.title).toLowerCase();
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

    final allRaw = await _query.querySongs(
      sortType: SongSortType.DISPLAY_NAME,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final filteredSongs = allRaw.where(isRealMusic).toList();

    _all = filteredSongs;

    final children = filteredSongs.map(_toSource).toList();

    if (children.isNotEmpty) {
      await player.setAudioSource(ConcatenatingAudioSource(children: children));
    }

    await _scheduleWidgetSync();
    notifyListeners();
  }

  AudioSource _toSource(SongModel s) {
    return AudioSource.uri(
      Uri.parse(s.uri!),
      tag: MediaItem(
        id: s.id.toString(),
        title: s.title,
        artist: s.artist ?? '—',
        album: s.album ?? '',
        genre: s.genre,
        artUri: Uri.parse(
          'content://media/external/audio/albumart/${s.albumId}',
        ),
        duration: (s.duration != null && s.duration! > 0)
            ? Duration(milliseconds: s.duration!)
            : null,
        extras: {
          'albumId': s.albumId,
          'artworkType': 'ALBUM',
          'filePath': s.data,
          'uri': s.uri,
          if ((s.genre ?? '').isNotEmpty) 'genre': s.genre,
        },
      ),
    );
  }

  void _seedCacheWithAllSongs() {
    for (final s in _all) {
      _songByIdCache[s.id] = s;
    }
  }

  Future<void> _logCurrentPlay() async {
    final tag = player.sequenceState.currentSource?.tag;
    _lastStartedTag = tag;
    _trackStartMs = DateTime.now().millisecondsSinceEpoch;

    int? songId;
    int? albumId;
    String title = 'Track';
    String? artist;
    String? genre;

    if (tag is MediaItem) {
      songId = int.tryParse(tag.id);
      albumId = tag.extras?['albumId'] as int?;
      title = tag.title.isNotEmpty ? tag.title : title;
      artist = tag.artist;
      genre = tag.genre;
    }

    if (songId != null && _lastLoggedSongId == songId) return;

    if (songId != null) {
      final s = _songByIdCache[songId];
      if (s != null) {
        _lastLoggedSongId = songId;
        await UsageTracker.instance.logFromSong(s);
        return;
      }
    }

    _lastLoggedSongId = songId;
    await UsageTracker.instance.logLite(
      songId: songId,
      albumId: albumId,
      title: title,
      artist: artist,
      uri: null,
      genre: genre,
    );
  }

  Future<void> playAtIndex(int index) async {
    if (player.audioSource == null) return;
    await player.seek(Duration.zero, index: index);
    await player.play();
    await _scheduleWidgetSync();
    await _logCurrentPlay();

    notifyListeners();
  }

  Future<void> playSongId(int songId) async {
    final idx = _all.indexWhere((e) => e.id == songId);
    if (idx >= 0) await playAtIndex(idx);
  }

  Future<void> playUri(
    String uri, {
    String? title,
    String? artist,
    int? artworkId,
    ArtworkType? artworkType,
    String? artUri,
    String? filePath,
    int? duration,
    String? genre,
  }) async {
    String? resolvedArtUri = artUri;
    if (resolvedArtUri == null && artworkId != null) {
      if (artworkType == ArtworkType.ALBUM) {
        resolvedArtUri = 'content://media/external/audio/albumart/$artworkId';
      } else if (artworkType == ArtworkType.AUDIO) {
        resolvedArtUri =
            'content://media/external/audio/media/$artworkId/albumart';
      }
    }

    final surrogateId = (filePath ?? uri).hashCode;

    final src = AudioSource.uri(
      Uri.parse(uri),
      tag: MediaItem(
        id: surrogateId.toString(),
        title: title ?? 'Track',
        artist: artist ?? '—',
        album: '',
        genre: genre,
        artUri: resolvedArtUri != null ? Uri.parse(resolvedArtUri) : null,
        duration: (duration != null && duration > 0)
            ? Duration(milliseconds: duration)
            : null,
        extras: {
          if (artworkType == ArtworkType.ALBUM && artworkId != null)
            'albumId': artworkId,
          if (artworkType != null) 'artworkType': artworkType.name,
          'filePath': filePath,
          'uri': uri,
          if ((genre ?? '').isNotEmpty) 'genre': genre,
        },
      ),
    );

    await player.setAudioSource(src);
    await player.play();
    await _scheduleWidgetSync();
    await _logCurrentPlay();
    notifyListeners();
  }

  Future<void> playQueue(
    List<SongModel> songs, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    if (songs.isEmpty) return;

    final list = ConcatenatingAudioSource(
      children: [
        for (final s in songs.where((e) => e.uri != null)) _toSource(s),
      ],
    );

    await player.stop();
    await player.setAudioSource(
      list,
      initialIndex: startIndex.clamp(0, list.length - 1),
      initialPosition: Duration.zero,
    );

    if (shuffle) {
      await player.shuffle();
      await player.setShuffleModeEnabled(true);
    } else {
      await player.setShuffleModeEnabled(false);
    }

    await player.play();
    await _scheduleWidgetSync();
    await _logCurrentPlay();

    notifyListeners();
  }

  Future<void> enqueue(List<SongModel> songs) async {
    if (songs.isEmpty) return;

    final toAdd = <AudioSource>[
      for (final s in songs.where((e) => e.uri != null)) _toSource(s),
    ];

    final source = player.audioSource;

    if (source == null) {
      final list = ConcatenatingAudioSource(children: toAdd);
      await player.setAudioSource(list);
      await _scheduleWidgetSync();
      notifyListeners();
      return;
    }

    if (source is ConcatenatingAudioSource) {
      await source.addAll(toAdd);
      await _scheduleWidgetSync();
      notifyListeners();
      return;
    }

    final currentPos = player.position;
    final newList = ConcatenatingAudioSource(children: [source, ...toAdd]);

    await player.setAudioSource(
      newList,
      initialIndex: 0,
      initialPosition: currentPos,
    );
    await _scheduleWidgetSync();
    notifyListeners();
  }

  Future<void> toggle() async {
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
      await _logCurrentPlay();
    }
    await _scheduleWidgetSync();
    notifyListeners();
  }

  Future<void> next() async {
    await _withNavLock(() async {
      await _commitSkipNow();

      if (!player.hasNext) {
        final genreCtx = () {
          final t = player.sequenceState.currentSource?.tag;
          if (t is MediaItem) return t.genre;
          return null;
        }();
        final recs = await recommendNext(want: 35, contextGenre: genreCtx);
        if (recs.isNotEmpty) {
          await enqueue(recs);
        }
      }

      if (player.hasNext) {
        await player.seekToNext();
        await player.play();
        await _logCurrentPlay();
        await _scheduleWidgetSync();
        notifyListeners();
        return;
      }
    });
  }

  Future<void> prev() async {
    await _withNavLock(() async {
      final pos = player.position;
      if (pos > const Duration(seconds: 3)) {
        await player.seek(Duration.zero);
        await _scheduleWidgetSync();
        notifyListeners();
        return;
      }
      if (player.hasPrevious) {
        await player.seekToPrevious();
        await player.play();
        await _logCurrentPlay();
        await _scheduleWidgetSync();
        notifyListeners();
        return;
      }
      if (player.loopMode == LoopMode.off && !_autoFillInProgress) {
        if (_isAutoplayEnabled()) {
          await _autoplayFromRecommendations(postAction: _PendingAction.prev);
        } else {
          await player.pause();
          await _scheduleWidgetSync();
          notifyListeners();
        }
      }
    });
  }

  Future<void> setShuffle(bool enabled) async {
    await _withNavLock(() async {
      if (enabled &&
          player.processingState == ProcessingState.completed &&
          !player.hasNext) {
        if (_isAutoplayEnabled()) {
          await _autoplayFromRecommendations();
        }
      }

      await player.setShuffleModeEnabled(enabled);
      if (enabled && player.sequence.isNotEmpty == true) {
        await player.shuffle();
      }
      await _scheduleWidgetSync();
      notifyListeners();
    });
  }

  void togglePin(int songId) {
    if (_pinnedIds.contains(songId)) {
      _pinnedIds.remove(songId);
    } else {
      _pinnedIds.add(songId);
    }
    _box.write(_pinKey, _pinnedIds);
    notifyListeners();
  }

  bool isPinned(int songId) => _pinnedIds.contains(songId);

  int? get nowPlayingAlbumId {
    final tag = player.sequenceState.currentSource?.tag;
    if (tag is MediaItem) {
      return tag.extras?['albumId'] as int?;
    }
    return null;
  }

  Future<void> setCrossfade(int seconds) async {
    _crossfadeSec = seconds.clamp(0, 12);
    await _box.write(SettingsKeys.crossfadeSec, _crossfadeSec);
    _ensureFadeWatcher();
  }

  Future<void> _applyPendingRgIfAny() async {
    final v = _pendingRgLinear;
    if (v == null) return;
    _pendingRgLinear = null;
    await _fadeVolume(
      to: v.clamp(0.0, 1.0),
      duration: const Duration(milliseconds: 120),
    );
  }

  void _ensureFadeWatcher() {
    _crossfadeSub?.cancel();
    if (_crossfadeSec <= 0) {
      _crossfadeSub = null;
      return;
    }

    _crossfadeSub = player.positionStream.listen((pos) async {
      if (_fading) return;
      if (!player.playing) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _trackStartMs < 4000) return;

      if (player.processingState != ProcessingState.ready) return;
      if (player.loopMode == LoopMode.one) return;
      if (pos < const Duration(seconds: 1)) return;

      final dur = player.duration;
      if (dur == null || dur == Duration.zero) return;

      final minDurMs = _crossfadeSec * 2000 + 700;
      if (dur.inMilliseconds < minDurMs) return;

      final smartOutro = (_box.read(SettingsKeys.smartOutro) as bool?) ?? false;
      if (smartOutro && _cachedOutroMs == 0) {
        final tag = player.sequenceState.currentSource?.tag;
        final id = (tag is MediaItem) ? int.tryParse(tag.id) : null;
        if (id != null) {
          final m = SmartIntroOutroService.read(id);
          _cachedOutroMs = (m?['outroMs'] ?? 0);
        }
      }

      final currentPosMs = pos.inMilliseconds;
      final remainingMs = (dur - pos).inMilliseconds;
      final triggerRemainMs = _crossfadeSec * 1000 + 700;

      bool shouldStartFade;
      if (smartOutro &&
          _cachedOutroMs > 0 &&
          dur.inMilliseconds > _cachedOutroMs) {
        final marginOk = remainingMs >= (triggerRemainMs * 0.8);
        shouldStartFade = currentPosMs >= _cachedOutroMs && marginOk;
      } else {
        shouldStartFade = remainingMs <= triggerRemainMs;
      }

      if (!shouldStartFade) return;

      _fading = true;
      try {
        _lastFadedTagId = _currentTagId();

        await _fadeVolume(to: 0.0, duration: Duration(seconds: _crossfadeSec));

        final curTag = player.sequenceState.currentSource?.tag;
        final curSongId = (curTag is MediaItem)
            ? int.tryParse(curTag.id)
            : null;
        final curArtistHash = (curTag is MediaItem)
            ? (curTag.artist ?? '').hashCode
            : null;
        final d = player.duration;
        if (curSongId != null) {
          unawaited(
            UsageTracker.instance.markPlayEnd(
              songId: curSongId,
              listenedMs: d?.inMilliseconds ?? 0,
              totalMs: d?.inMilliseconds,
              completed: true,
              artistHash: curArtistHash,
            ),
          );
        }

        if (player.hasNext) {
          await player.seekToNext();
          await player.play();
          await _logCurrentPlay();
        } else if (player.loopMode == LoopMode.off && !_autoFillInProgress) {
          if (_isAutoplayEnabled()) {
            await _autoplayFromRecommendations();
          } else {
            await player.pause();
            await _scheduleWidgetSync();
            notifyListeners();
          }
        }
      } finally {
        _fading = false;
        await _applyPendingRgIfAny();
      }
    });
  }

  Future<T> _withVolLock<T>(Future<T> Function() job) {
    final prev = _volLock;
    final done = Completer<void>();
    _volLock = _volLock.whenComplete(() => done.future);
    return prev.then((_) async {
      try {
        return await job();
      } finally {
        done.complete();
      }
    });
  }

  Future<void> _fadeVolume({required double to, required Duration duration}) {
    return _withVolLock(() async {
      final double from = player.volume;

      final double toClamped = to.clamp(0.0, 1.0);

      if (duration <= Duration.zero || (toClamped - from).abs() < 0.0001) {
        await player.setVolume(toClamped);
        return;
      }

      const int steps = 30;
      final int dtMs = (duration.inMilliseconds / steps).round().clamp(1, 1000);

      for (int i = 1; i <= steps; i++) {
        final double t = i / steps;
        final double v = (from + (toClamped - from) * t).clamp(0.0, 1.0);
        await player.setVolume(v);
        await Future.delayed(Duration(milliseconds: dtMs));
      }
    });
  }

  Future<void> setSkipSilence(bool value) async {
    await _box.write(SettingsKeys.skipSilent, value);
    try {
      await (player).setSkipSilenceEnabled(value);
    } catch (_) {}
  }

  Future<void> _applyStartupSettings() async {
    final cf = (_box.read(SettingsKeys.crossfadeSec) as num?)?.toInt() ?? 0;
    final skipOn = (_box.read(SettingsKeys.skipSilent) as bool?) ?? false;
    await setCrossfade(cf);

    try {
      final bool finalSkipSetting = cf == 0 && skipOn == true;
      await setSkipSilence(finalSkipSetting);
    } catch (e) {
      debugPrint("Skip silence error: $e");
    }
  }

  bool _isAutoplayEnabled() {
    final val = _box.read(SettingsKeys.autoplayEnabled);
    if (val is bool) return val;
    return true;
  }

  @override
  Future<void> play() => toggle();

  @override
  Future<void> pause() => toggle();

  @override
  Future<void> stop() async {
    await player.seek(Duration.zero);
    await player.pause();
    broadcastState(Duration.zero);
  }

  @override
  Future<void> skipToNext() => next();

  @override
  Future<void> skipToPrevious() => prev();

  @override
  Future<void> fastForward() async {
    final jump = const Duration(seconds: 15);
    final total = player.duration;
    final to = player.position + jump;
    await player.seek(total != null && to > total ? total : to);
  }

  @override
  Future<void> rewind() async {
    final jump = const Duration(seconds: 15);
    final to = player.position - jump;
    await player.seek(to < Duration.zero ? Duration.zero : to);
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await setShuffle(shuffleMode != AudioServiceShuffleMode.none);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final next = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.group => LoopMode.all,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
    };
    await player.setLoopMode(next);
  }

  @override
  Future<void> onTaskRemoved() async {
    await player.stop();
    await player.dispose();
    await super.onTaskRemoved();
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case 'toggle_shuffle':
        {
          final enabled = !player.shuffleModeEnabled;
          await setShuffle(enabled);
          broadcastState(player.position);
          return null;
        }

      case 'cycle_repeat':
        {
          await cycleRepeat(player);
          broadcastState(player.position);
          return null;
        }

      case 'toggle_pin':
        {
          final tag = player.sequenceState.currentSource?.tag;
          if (tag is MediaItem) {
            final curId = int.tryParse(tag.id);
            if (curId != null) {
              togglePin(curId);
            }
          }

          broadcastState(player.position);
          return null;
        }
    }

    return null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(UsageTracker.instance.flushSession());
    _positionBroadcastSub?.cancel();
    _crossfadeSub?.cancel();
    _positionBroadcastSub = null;
    _crossfadeSub = null;
    player.dispose();
    super.dispose();
  }
}

class PlayerScope extends InheritedWidget {
  final PlayerController controller;

  const PlayerScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static PlayerController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PlayerScope>();
    assert(scope != null, 'PlayerScope belum diset di root.');
    return scope!.controller;
  }

  static PlayerController? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PlayerScope>();
    return scope?.controller;
  }

  @override
  bool updateShouldNotify(covariant PlayerScope oldWidget) {
    return oldWidget.controller != controller;
  }
}

Future<void> toggleShuffle(AudioPlayer p) async {
  if (p.shuffleModeEnabled) {
    await p.setShuffleModeEnabled(false);
    return;
  }
  final hasList = p.sequence.isNotEmpty == true;
  if (hasList) await p.shuffle();
  await p.setShuffleModeEnabled(true);
}

Future<void> cycleRepeat(AudioPlayer p) async {
  final mode = p.loopMode;
  final next = switch (mode) {
    LoopMode.off => LoopMode.all,
    LoopMode.all => LoopMode.one,
    LoopMode.one => LoopMode.off,
  };
  await p.setLoopMode(next);
}

extension PlayerX on BuildContext {
  PlayerController get playerCtrl => PlayerScope.of(this);

  AudioPlayer get audio => PlayerScope.of(this).player;
}
