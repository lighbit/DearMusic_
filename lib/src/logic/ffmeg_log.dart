import 'dart:async';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';

typedef _LogSink = void Function(String msg);

class FfmpegLogGuard {
  static Future<void> _lock = Future.value();
  static _LogSink? _currentSink;
  static bool _installed = false;

  static void _installOnce() {
    if (_installed) return;
    _installed = true;

    FFmpegKitConfig.enableLogCallback((log) {
      final msg = log.getMessage();
      final sink = _currentSink;
      if (sink != null) sink(msg);
    });
  }

  static Future<T> captureLogs<T>(Future<T> Function(List<String> lines) job) {
    _installOnce();

    final prev = _lock;
    final done = Completer<void>();
    _lock = _lock.whenComplete(() => done.future);

    return prev.then((_) async {
      final lines = <String>[];
      _currentSink = (msg) => lines.add(msg);
      try {
        return await job(lines);
      } finally {
        _currentSink = null;
        done.complete();
      }
    });
  }
}
