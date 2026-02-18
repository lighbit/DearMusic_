import 'dart:async';
import 'package:dearmusic/src/logic/ffmeg_log.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LoudnessService {
  static Database? _db;
  static final Map<int, Map<String, num>> _cache = {};
  static const double _targetLufs = -16.0;

  static Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'loudness_analysis_v1.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE loudness (
            song_id INTEGER PRIMARY KEY,
            gain_db REAL,
            lufs REAL,
            true_peak_db REAL
          )
        ''');
      },
    );
    await _loadToMemory();
  }

  static Future<void> _loadToMemory() async {
    final res = await _db!.query('loudness');
    for (var r in res) {
      final songId = r['song_id'] as int;
      _cache[songId] = {
        'gainDb': r['gain_db'] as num,
        'lufs': r['lufs'] as num,
        'true_peak_db': r['true_peak_db'] as num,
      };
    }
  }

  static Map<String, num>? read(int songId) {
    return _cache[songId];
  }

  static Future<void> write(
      int songId, {
        required double gainDb,
        required double lufs,
        required double truePeakDb,
      }) async {
    _cache[songId] = {
      'gainDb': gainDb,
      'lufs': lufs,
      'truePeakDb': truePeakDb,
    };

    unawaited(_db?.insert(
      'loudness',
      {
        'song_id': songId,
        'gain_db': gainDb,
        'lufs': lufs,
        'true_peak_db': truePeakDb,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    ));
  }

  static Future<Map<String, num>?> analyzeAndSave({
    required int songId,
    required String filePath,
  }) {
    return FfmpegLogGuard.captureLogs((logLines) async {
      final args = <String>[
        '-hide_banner',
        '-nostats',
        '-i',
        filePath,
        '-filter_complex',
        'ebur128=peak=true:framelog=verbose',
        '-f',
        'null',
        '-',
      ];

      try {
        final session = await FFmpegKit.executeWithArguments(args);
        final rc = await session.getReturnCode();
        if (rc == null || !ReturnCode.isSuccess(rc)) {
          return null;
        }

        final text = logLines.join('\n');

        final lufsMatch = RegExp(
          r'(Integrated loudness:|I:\s*)(-?\d+(?:\.\d+)?)\s*LUFS',
        ).firstMatch(text);
        final tpMatch = RegExp(
          r'(True peak:|Peak:\s*)(-?\d+(?:\.\d+)?)\s*dB(?:FS|TP)?',
        ).firstMatch(text);

        if (lufsMatch == null || tpMatch == null) return null;

        final lufs = double.parse(lufsMatch.group(2)!);
        final truePeakDb = double.parse(tpMatch.group(2)!);

        const headroomDb = 0.8;
        final target = _targetLufs;
        double gainDb = target - lufs;

        final maxAllowedGain = -headroomDb - truePeakDb;
        if (gainDb > maxAllowedGain) gainDb = maxAllowedGain;

        await write(songId, gainDb: gainDb, lufs: lufs, truePeakDb: truePeakDb);

        return {'gainDb': gainDb, 'lufs': lufs, 'truePeakDb': truePeakDb};
      } catch (_) {
        return null;
      }
    });
  }
}