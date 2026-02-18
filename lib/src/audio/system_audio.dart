import 'dart:io';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class SystemAudio {
  static const _ch = MethodChannel('dearmusic/system_audio');

  static Future<bool> openEqualizer(AudioPlayer player) async {
    if (!Platform.isAndroid) return false;
    int? sessionId = player.androidAudioSessionId;
    sessionId ??= await player.androidAudioSessionIdStream.firstWhere(
      (e) => e != null,
    );
    final ok =
        await _ch.invokeMethod<bool>('openEqualizer', {
          'sessionId': sessionId,
        }) ??
        false;
    return ok;
  }

  static Future<bool> openOutputSwitcher() async {
    if (!Platform.isAndroid) return false;
    final ok = await _ch.invokeMethod<bool>('openOutputSwitcher') ?? false;
    return ok;
  }
}
