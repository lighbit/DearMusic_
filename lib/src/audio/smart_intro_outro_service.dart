import 'dart:async';
import 'package:dearmusic/src/logic/ffmeg_log.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class SmartIntroOutroService {
  static Database? _db;
  static final Map<int, Map<String, int>> _cache = {};
  static const double _noiseDb = -35.0;
  static const double _minSilenceSec = 0.40;

  static Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'smart_intro_outro_v1.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE intro_outro (
            song_id INTEGER PRIMARY KEY,
            intro_ms INTEGER,
            outro_ms INTEGER
          )
        ''');
      },
    );
    await _loadToMemory();
  }

  static Future<void> _loadToMemory() async {
    final res = await _db!.query('intro_outro');
    for (var r in res) {
      final songId = r['song_id'] as int;
      _cache[songId] = {
        'introMs': r['intro_ms'] as int,
        'outroMs': r['outro_ms'] as int,
      };
    }
  }

  static Map<String, int>? read(int songId) {
    return _cache[songId];
  }

  static Future<void> write({
    required int songId,
    required int introMs,
    required int outroMs,
  }) async {
    final safeIntro = introMs.clamp(0, 600000);
    final safeOutro = outroMs.clamp(0, 600000);

    _cache[songId] = {'introMs': safeIntro, 'outroMs': safeOutro};

    unawaited(
      _db?.insert('intro_outro', {
        'song_id': songId,
        'intro_ms': safeIntro,
        'outro_ms': safeOutro,
      }, conflictAlgorithm: ConflictAlgorithm.replace),
    );
  }

  static Future<Map<String, int>?> analyzeAndSave({
    required int songId,
    required String filePath,
    int? durationMs,
  }) {
    return FfmpegLogGuard.captureLogs((logLines) async {
      final args = <String>[
        '-nostats',
        '-i',
        filePath,
        '-af',
        'silencedetect=noise=${_noiseDb}dB:d=$_minSilenceSec',
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

        List<double> startsSec = RegExp(r'silence_start:\s*([0-9.]+)')
            .allMatches(text)
            .map((m) => double.tryParse(m.group(1) ?? ''))
            .whereType<double>()
            .toList();

        List<double> endsSec = RegExp(r'silence_end:\s*([0-9.]+)')
            .allMatches(text)
            .map((m) => double.tryParse(m.group(1) ?? ''))
            .whereType<double>()
            .toList();

        int cmp(double a, double b) => a < b ? -1 : (a > b ? 1 : 0);
        bool near(double a, double b) => (a - b).abs() < 0.01;

        startsSec.sort(cmp);
        endsSec.sort(cmp);

        List<double> dedupe(List<double> xs) {
          if (xs.isEmpty) return xs;
          final out = <double>[xs.first];
          for (int i = 1; i < xs.length; i++) {
            if (!near(xs[i], out.last)) out.add(xs[i]);
          }
          return out;
        }

        startsSec = dedupe(startsSec);
        endsSec = dedupe(endsSec);

        int introMs = 0;
        if (endsSec.isNotEmpty) {
          final firstEnd = endsSec.first;
          if (firstEnd > 0 && firstEnd <= 12.0) {
            introMs = (firstEnd * 1000).round();
          }
        }

        int outroMs = 0;
        if (startsSec.isNotEmpty) {
          final lastStart = startsSec.last;
          if (lastStart >= 5.0) {
            outroMs = (lastStart * 1000).round();
          }
        }

        if (durationMs != null && durationMs > 0 && outroMs > 0) {
          const guardFromEndMs = 2500;
          final maxOutro = (durationMs - guardFromEndMs).clamp(0, durationMs);
          if (outroMs > maxOutro) outroMs = maxOutro;
          if (outroMs < introMs || (durationMs - outroMs) < 1000) {
            outroMs = 0;
          }
        }

        await write(songId: songId, introMs: introMs, outroMs: outroMs);

        return {'introMs': introMs, 'outroMs': outroMs};
      } catch (err) {
        return null;
      }
    });
  }
}
