import 'dart:async';
import 'dart:convert' as json;
import 'dart:math' as math;
import 'dart:math';
import 'package:dearmusic/src/models/wrapped_models.dart';
import 'package:flutter/cupertino.dart';
import 'package:get_storage/get_storage.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class UsageTracker {
  UsageTracker._();

  static final UsageTracker instance = UsageTracker._();

  Database? _db;

  final Map<String, Map<String, int>> _countsCache = {};
  final List<Map<String, dynamic>> _recentCache = [];
  final Map<String, String> _sessCache = {};

  static const _kSong = 'stats:song';
  static const _kAlbum = 'stats:album';
  static const _kArtist = 'stats:artist';
  static const _kSkipSong = 'stats:skip_song';
  static const _kSkipArtist = 'stats:skip_artist';
  static const _kRecent = 'history:recent';
  static const _kGenre = 'stats:genre';
  static const _kFirstHeardTsBySong = 'stats:first_heard_ts_by_song';
  static const _kListenMsByHour = 'stats:listen_ms_by_hour';
  static const _kListenMsByDow = 'stats:listen_ms_by_dow';
  static const _kCompletionCounters = 'stats:completion';
  static const _kQuickSkipSong = 'stats:quick_skip_song';
  static const _kCompletedSong = 'stats:completed_song';

  static const _hardCooldownSameSongMs = 24 * 3600 * 1000;
  static const _cooldownSameArtistMs = 6 * 3600 * 1000;
  static const _softCooldownRecentMs = 72 * 3600 * 1000;
  static const _tauMs = 48 * 3600 * 1000;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'usage_tracker_production_v2.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE counts (category TEXT, key TEXT, val INTEGER, PRIMARY KEY (category, key))',
        );
        await db.execute(
          'CREATE TABLE play_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, song_id INTEGER, album_id INTEGER, artist_hash INTEGER, genre TEXT, ts INTEGER)',
        );
        await db.execute(
          'CREATE TABLE history (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT)',
        );
        await db.execute(
          'CREATE TABLE session (key TEXT PRIMARY KEY, val TEXT)',
        );
      },
    );

    await _loadToMemory();

    unawaited(migrateFromGetStorage());
  }

  Future<void> migrateFromGetStorage() async {
    final box = GetStorage();
    if (box.read('migration_to_sql_done') == true) return;

    final categories = [
      _kSong,
      _kAlbum,
      _kArtist,
      _kGenre,
      _kSkipSong,
      _kSkipArtist,
      _kQuickSkipSong,
      _kCompletedSong,
      _kListenMsByHour,
      _kListenMsByDow,
      _kFirstHeardTsBySong,
    ];

    final batch = _db!.batch();
    final legacyYear = 2025;

    for (var cat in categories) {
      final Map? oldData = box.read(cat);
      if (oldData == null || oldData.isEmpty) continue;

      final yearlyCat = '$cat:$legacyYear';

      oldData.forEach((key, val) {
        if (val is int) {
          batch.execute(
            'INSERT OR IGNORE INTO counts (category, key, val) VALUES (?, ?, ?)',
            [yearlyCat, key.toString(), val],
          );
        }
      });
    }

    try {
      await batch.commit(noResult: true);
      await box.write('migration_to_sql_done', true);
      await _loadToMemory();
      debugPrint(
        "Dear Music: Migration from GetStorage to SQLite Success (Background)",
      );
    } catch (e) {
      debugPrint("Dear Music: Migration Error: $e");
    }
  }

  Future<void> _loadToMemory() async {
    final db = _db!;
    final cRes = await db.query('counts');
    for (var r in cRes) {
      final cat = r['category'] as String;
      _countsCache.putIfAbsent(cat, () => {})[r['key'] as String] =
          r['val'] as int;
    }
    final hRes = await db.query('history', orderBy: 'id DESC', limit: 30);
    _recentCache.addAll(
      hRes.map(
        (r) => Map<String, dynamic>.from(json.jsonDecode(r['data'] as String)),
      ),
    );
    final sRes = await db.query('session');
    for (var r in sRes) {
      _sessCache[r['key'] as String] = r['val'] as String;
    }
  }

  void updateSessionProgress(int currentPosMs) {
    _sessCache['sess:lastPosMs'] = currentPosMs.toString();
    unawaited(
      _db?.insert('session', {
        'key': 'sess:lastPosMs',
        'val': currentPosMs.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace),
    );
  }

  String _normStr(String? s) => (s ?? '').trim().toLowerCase();

  List<MapEntry<int, int>> topSongs({int limit = 10}) {
    final ids = rankedSongIds(limit: limit);
    return ids.map((id) => MapEntry(id, 0)).toList();
  }

  List<int> rankedSongIds({
    int limit = 200,
    String? contextGenre,
    int recentWindow = 30,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    final countsSong = _readYearlyIntMap(_kSong);
    final countsAlbum = _readYearlyIntMap(_kAlbum);
    final countsArtist = _readYearlyIntMap(_kArtist);
    final countsGenre = _readYearlyIntMap(_kGenre);

    final recents = recentPlays(limit: 200);
    final lastTsById = <int, int>{};
    final lastTsByArtist = <int, int>{};
    final metaById = <int, ({int? albumId, int artistHash, String? genre})>{};

    for (final r in recents) {
      final id = r['id'] as int?;
      final ts = r['ts'] as int? ?? 0;
      final art = (r['artist'] as String?)?.trim().toLowerCase() ?? '';
      if (id != null) {
        lastTsById[id] = math.max(lastTsById[id] ?? 0, ts);
        metaById[id] = (
          albumId: r['albumId'] as int?,
          artistHash: art.hashCode,
          genre: r['genre'] as String?,
        );
      }
      if (art.isNotEmpty) {
        lastTsByArtist[art.hashCode] = math.max(
          lastTsByArtist[art.hashCode] ?? 0,
          ts,
        );
      }
    }

    final prefGenres = preferredGenres(limit: 4);

    double score({
      required int songId,
      required int? albumId,
      required int artistHash,
      required String? genre,
    }) {
      final gKey = _normStr(genre);
      final cSong = (countsSong[songId.toString()] ?? 0).toDouble();
      final cAlbum = albumId != null
          ? (countsAlbum[albumId.toString()] ?? 0).toDouble()
          : 0.0;
      final cArtist = (countsArtist[artistHash.toString()] ?? 0).toDouble();
      final cGenre = gKey.isNotEmpty
          ? (countsGenre[gKey] ?? 0).toDouble()
          : 0.0;

      final lastSongAgo = (now - (lastTsById[songId] ?? 0));
      final lastArtistAgo = (now - (lastTsByArtist[artistHash] ?? 0));

      if (lastSongAgo < _hardCooldownSameSongMs) return -1e12;

      final base =
          1.0 * math.log(1 + cSong) +
          0.6 * math.log(1 + cArtist) +
          0.4 * math.log(1 + cAlbum) +
          0.5 * math.log(1 + cGenre);
      final decaySong = math.exp(-(lastSongAgo / _tauMs));
      final timeGain = base * (1.0 - decaySong);

      double genreBoost = 0.0;
      if (gKey.isNotEmpty) {
        if (prefGenres.contains(gKey)) genreBoost += 0.8;
        if (contextGenre != null && _normStr(contextGenre) == gKey) {
          genreBoost += 0.6;
        }
      }

      double artistPenalty = (lastArtistAgo < _cooldownSameArtistMs)
          ? -3.0
          : (lastArtistAgo < _softCooldownRecentMs ? -0.7 : 0.0);

      final sSkip = (_readIntMap(_kSkipSong)[songId.toString()] ?? 0)
          .toDouble();
      final qSkip = (_readIntMap(_kQuickSkipSong)[songId.toString()] ?? 0)
          .toDouble();
      final completed = (_readIntMap(_kCompletedSong)[songId.toString()] ?? 0)
          .toDouble();

      return timeGain +
          genreBoost +
          (cSong == 0 ? 1.2 : 0.0) +
          (0.6 * math.log(1 + completed)) +
          (Random(songId).nextDouble() * 0.10) +
          artistPenalty -
          (0.9 * math.log(1 + sSkip) + 1.2 * math.log(1 + qSkip));
    }

    final universe = {
      ...countsSong.keys.map(int.parse),
      ...lastTsById.keys,
    }.toList();
    universe.sort((a, b) {
      final ma = metaById[a];
      final mb = metaById[b];
      return score(
        songId: b,
        albumId: mb?.albumId,
        artistHash: mb?.artistHash ?? 0,
        genre: mb?.genre,
      ).compareTo(
        score(
          songId: a,
          albumId: ma?.albumId,
          artistHash: ma?.artistHash ?? 0,
          genre: ma?.genre,
        ),
      );
    });
    return universe.take(limit).toList();
  }

  List<MapEntry<int, int>> topAlbums({int limit = 6}) {
    final m = _readYearlyIntMap(_kAlbum);
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list
        .take(limit)
        .map((e) => MapEntry(int.parse(e.key), e.value))
        .toList();
  }

  List<({int hash, int count})> topArtists({int limit = 8}) {
    final m = _readYearlyIntMap(_kArtist);
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list
        .take(limit)
        .map((e) => (hash: int.parse(e.key), count: e.value))
        .toList();
  }

  List<Map<String, dynamic>> recentPlays({int limit = 10}) =>
      _recentCache.take(limit).toList();

  List<MapEntry<String, int>> topGenres({int limit = 8}) {
    final m = _readIntMap(_kGenre);
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(limit).toList();
  }

  Set<String> preferredGenres({int limit = 4}) =>
      topGenres(limit: limit).map((e) => e.key).toSet();

  Future<void> logFromSong(SongModel s) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _finalizePreviousSession(now: now);
    _openSession(
      songId: s.id,
      albumId: s.albumId,
      artistHash: _normStr(s.artist).hashCode,
      title: s.title,
      startedMs: now,
      totalMs: s.duration ?? 0,
      genre: _normStr(s.genre),
    );
    _pushRecent({
      'id': s.id,
      'title': s.title,
      'artist': s.artist ?? '',
      'albumId': s.albumId,
      'genre': _normStr(s.genre),
      'ts': now,
    });
  }

  Future<void> logLite({
    required int? songId,
    required int? albumId,
    required String title,
    String? artist,
    String? uri,
    String? genre,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _finalizePreviousSession(now: now);
    _openSession(
      songId: songId,
      albumId: albumId,
      artistHash: _normStr(artist).hashCode,
      title: title,
      startedMs: now,
      totalMs: 0,
      genre: _normStr(genre),
    );
    _pushRecent({
      'id': songId,
      'title': title,
      'artist': artist ?? '',
      'albumId': albumId,
      'genre': _normStr(genre),
      'ts': now,
    });
  }

  Future<void> finalizeSong({
    required int songId,
    required bool completed,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prevId = int.tryParse(_sessCache['sess:songId'] ?? '');
    if (prevId != songId) return;

    final started = int.tryParse(_sessCache['sess:startedMs'] ?? '') ?? 0;
    final totalMs = int.tryParse(_sessCache['sess:totalMs'] ?? '') ?? 0;
    final listenedMs = (now - started).clamp(0, 1800000);

    await markPlayEnd(
      songId: songId,
      listenedMs: listenedMs,
      totalMs: totalMs,
      completed: completed,
      artistHash: int.tryParse(_sessCache['sess:artistHash'] ?? ''),
    );

    if (_shouldCountListen(listenedMs: listenedMs, totalMs: totalMs)) {
      _inc(_kSong, songId);
      final alb = int.tryParse(_sessCache['sess:albumId'] ?? '');
      if (alb != null) _inc(_kAlbum, alb);
      final art = int.tryParse(_sessCache['sess:artistHash'] ?? '');
      if (art != null) _inc(_kArtist, art);
      final gen = _sessCache['sess:genre'];
      if (gen != null && gen.isNotEmpty) _incString(_kGenre, gen);
    }
    _clearSession();
  }

  Future<void> markPlayEnd({
    required int songId,
    required int listenedMs,
    required int? totalMs,
    required bool completed,
    int? artistHash,
  }) async {
    _inc(
      _kFirstHeardTsBySong,
      songId,
      val: DateTime.now().millisecondsSinceEpoch,
      onlyIfAbsent: true,
    );
    final now = DateTime.now();
    _incString(_kListenMsByHour, now.hour.toString(), val: listenedMs);
    _incString(
      _kListenMsByDow,
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][now.weekday - 1],
      val: listenedMs,
    );
    _incString(_kCompletionCounters, 'total');
    if (completed) {
      _incString(_kCompletionCounters, 'done');
      _inc(_kCompletedSong, songId);
    } else {
      _incString(_kCompletionCounters, 'skip');
    }
  }

  Future<void> markSkipCurrent() async {
    final sid = int.tryParse(_sessCache['sess:songId'] ?? '');
    if (sid == null) return;
    _inc(_kSkipSong, sid);
    final art = int.tryParse(_sessCache['sess:artistHash'] ?? '');
    if (art != null) _inc(_kSkipArtist, art);
    final started = int.tryParse(_sessCache['sess:startedMs'] ?? '') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - started < 30000) {
      _inc(_kQuickSkipSong, sid);
    }
  }

  void _inc(String cat, int id, {int val = 1, bool onlyIfAbsent = false}) =>
      _incString(cat, id.toString(), val: val, onlyIfAbsent: onlyIfAbsent);

  void _incString(
    String cat,
    String key, {
    int val = 1,
    bool onlyIfAbsent = false,
  }) {
    final year = DateTime.now().year;
    final yearlyCat = '$cat:$year';

    final m = _countsCache.putIfAbsent(yearlyCat, () => {});
    if (onlyIfAbsent && m.containsKey(key)) return;

    m[key] = (m[key] ?? 0) + val;

    unawaited(
      _db?.execute(
        'INSERT INTO counts (category, key, val) VALUES (?, ?, ?) '
        'ON CONFLICT(category, key) DO UPDATE SET val = ${onlyIfAbsent ? 'val' : 'val + ?'}',
        onlyIfAbsent ? [yearlyCat, key, m[key]] : [yearlyCat, key, m[key], val],
      ),
    );
  }

  Map<String, int> _readIntMap(String key) => _countsCache[key] ?? {};

  Map<String, int> _readYearlyIntMap(String baseKey) {
    final year = DateTime.now().year;
    return _countsCache['$baseKey:$year'] ?? {};
  }

  void _pushRecent(Map<String, dynamic> snap) {
    _recentCache.insert(0, snap);
    if (_recentCache.length > 30) _recentCache.removeLast();
    unawaited(
      _db?.transaction((txn) async {
        await txn.execute('INSERT INTO history (data) VALUES (?)', [
          json.jsonEncode(snap),
        ]);
        await txn.execute(
          'DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY id DESC LIMIT 30)',
        );
      }),
    );
  }

  void _openSession({
    required int? songId,
    required int? albumId,
    required int? artistHash,
    required String title,
    required int startedMs,
    required int totalMs,
    String? genre,
  }) {
    final data = {
      'sess:songId': songId.toString(),
      'sess:albumId': albumId.toString(),
      'sess:artistHash': artistHash.toString(),
      'sess:title': title,
      'sess:startedMs': startedMs.toString(),
      'sess:totalMs': totalMs.toString(),
      'sess:genre': genre ?? '',
    };
    _sessCache.addAll(data);
    data.forEach(
      (k, v) => unawaited(
        _db?.insert('session', {
          'key': k,
          'val': v,
        }, conflictAlgorithm: ConflictAlgorithm.replace),
      ),
    );
  }

  void _clearSession() {
    _sessCache.clear();
    unawaited(_db?.delete('session'));
  }

  Future<void> _finalizePreviousSession({required int now}) async {
    final id = int.tryParse(_sessCache['sess:songId'] ?? '');
    if (id != null) await finalizeSong(songId: id, completed: false);
  }

  bool _shouldCountListen({required int listenedMs, required int totalMs}) {
    if (totalMs <= 0) return listenedMs >= 10000;
    final ratio = listenedMs / totalMs;
    return (ratio >= 0.60 || listenedMs >= 90000 || listenedMs >= 30000);
  }

  Future<void> flushSession() =>
      _finalizePreviousSession(now: DateTime.now().millisecondsSinceEpoch);

  void resetAll() {
    _countsCache.clear();
    _recentCache.clear();
    _sessCache.clear();
    unawaited(
      _db?.transaction((txn) async {
        await txn.delete('counts');
        await txn.delete('history');
        await txn.delete('session');
      }),
    );
  }

  Future<WrappedStats> getWrappedStats({
    int? sinceEpochMs,
    int? untilEpochMs,
    int topN = 10,
    int librarySize = 0,
  }) async {
    await flushSession();
    final songMap = _readYearlyIntMap(_kSong);
    final comp = _readYearlyIntMap(_kCompletionCounters);
    final hourMap = _readYearlyIntMap(_kListenMsByHour);
    final listenMs = hourMap.values.fold<int>(0, (a, b) => a + b);

    final Map<int, Map<String, int>> votes = {};
    for (var r in _recentCache) {
      final name = r['artist'] as String?;
      if (name != null) {
        votes.putIfAbsent(name.hashCode, () => {})[name] =
            (votes[name.hashCode]?[name] ?? 0) + 1;
      }
    }

    final topArtistHashes = _takeTop(_readYearlyIntMap(_kArtist), topN);
    final Map<String, int> topArtistsByName = {};
    topArtistHashes.forEach((hKey, count) {
      final h = int.parse(hKey);
      final bestName = votes[h]?.entries.toList()
        ?..sort((a, b) => b.value.compareTo(a.value));
      topArtistsByName[bestName?.first.key ?? 'Artis $h'] = count;
    });

    final dowMap = _readYearlyIntMap(_kListenMsByDow);

    return WrappedStats(
      librarySize: librarySize,
      totalPlays: songMap.values.fold(0, (a, b) => a + b),
      totalSkips: _readYearlyIntMap(_kSkipSong).values.fold(0, (a, b) => a + b),
      uniqueSongsPlayed: songMap.length,
      uniqueArtistsPlayed: _readYearlyIntMap(_kArtist).length,
      discoveryCount: _readYearlyIntMap(_kFirstHeardTsBySong).length,
      avgCompletionRate: (comp['total'] ?? 0) == 0
          ? 0
          : (comp['done'] ?? 0) / comp['total']!,
      listenMs: listenMs,
      topSongs: _takeTopInt(songMap, topN),
      topArtists: topArtistsByName,
      topAlbums: _takeTopInt(_readYearlyIntMap(_kAlbum), topN),
      topGenres: _takeTop(_readYearlyIntMap(_kGenre), topN),
      mostSkippedSongIds: _readYearlyIntMap(
        _kSkipSong,
      ).keys.map(int.parse).toList(),
      hourHistogram: {
        for (var i = 0; i < 24; i++) i: hourMap[i.toString()] ?? 0,
      },
      dowHistogram: {
        for (var d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
          d: dowMap[d] ?? 0,
      },
      firstPlayTs: 0,
      lastPlayTs: 0,
    );
  }

  Map<String, int> _takeTop(Map<String, int> m, int n) {
    final entries = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries.take(n));
  }

  Map<int, int> _takeTopInt(Map<String, int> m, int n) {
    final entries = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(
      entries.take(n).map((e) => MapEntry(int.parse(e.key), e.value)),
    );
  }

  Future<void> seedDemoStatsFromSongs(List<SongModel> librarySongs) async {
    if (librarySongs.isEmpty) return;
    final randomSongs = List<SongModel>.from(librarySongs)..shuffle();
    for (var i = 0; i < math.min(randomSongs.length, 5); i++) {
      final s = randomSongs[i];
      final count = 5 - i;

      _inc(_kSong, s.id, val: count);

      String artistName = s.artist ?? '';
      if (artistName.trim().isEmpty) {
        artistName = "Unknown Artist";
      }
      _inc(_kArtist, _normStr(artistName).hashCode, val: count);

      if (s.albumId != null) {
        _inc(_kAlbum, s.albumId!, val: count);
      }

      String genreName = s.genre ?? '';
      if (genreName.trim().isEmpty) {
        genreName = "Pop";
      }
      _incString(_kGenre, _normStr(genreName), val: count);

      markPlayEnd(
        songId: s.id,
        listenedMs: 1000 ?? 0,
        totalMs: 1000,
        completed: true,
        artistHash: _normStr(artistName).hashCode,
      );

      _pushRecent({
        'id': s.id,
        'title': s.title,
        'artist': artistName,
        'albumId': s.albumId,
        'genre': genreName,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }
}
