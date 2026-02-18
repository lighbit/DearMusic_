import 'dart:async';
import 'dart:ui';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dearmusic/src/pages/full_player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_storage/get_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:dearmusic/src/audio/loudness_analysis_service.dart';

class NerdFlipCover extends StatefulWidget {
  final AudioPlayer player;
  final Object heroTag;

  const NerdFlipCover({super.key, required this.player, required this.heroTag});

  @override
  State<NerdFlipCover> createState() => _NerdFlipCoverState();
}

class _NerdFlipCoverState extends State<NerdFlipCover>
    with SingleTickerProviderStateMixin {
  final box = GetStorage();

  bool _showInfo = false;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeInOutCubic,
  );

  final Map<String, Map<String, dynamic>> _cache = {};

  String? _currentKey;

  StreamSubscription<SequenceState?>? _seqSub;

  void _toggle() {
    HapticFeedback.lightImpact();
    if (_showInfo) {
      _ctrl.reverse();
    } else {
      _ctrl.forward();
    }
    setState(() => _showInfo = !_showInfo);
  }

  @override
  void initState() {
    super.initState();

    _seqSub = widget.player.sequenceStateStream.listen((st) {
      final keyNow = _songKeyFromState(st);
      if (keyNow != _currentKey) {
        setState(() {
          _currentKey = keyNow;
        });
      }
    });

    _currentKey = _songKeyFromState(widget.player.sequenceState);
  }

  @override
  void dispose() {
    _seqSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  String? _songKeyFromState(SequenceState? st) {
    final tag = st?.currentSource?.tag;
    if (tag is MediaItem) {
      final songId = int.tryParse(tag.id);
      if (songId != null) return 'id:$songId';

      final extras = tag.extras ?? {};
      final path =
          extras['filePath']?.toString() ?? extras['uri']?.toString() ?? '';
      if (path.isNotEmpty) return 'path:$path';
    }
    return null;
  }

  String? _songKey(MediaItem? tag, Map<String, dynamic> extras) {
    if (tag != null) {
      final songId = int.tryParse(tag.id);
      if (songId != null) return 'id:$songId';
    }
    final path =
        extras['filePath']?.toString() ?? extras['uri']?.toString() ?? '';
    if (path.isNotEmpty) return 'path:$path';
    return null;
  }

  Future<void> _ensureReplayGain({
    required String cacheKey,
    required MediaItem? tag,
    required String path,
  }) async {
    final cached = _cache[cacheKey];
    if (cached == null) return;
    if (cached['replayGainTrackDb'] != null) return;

    final id = int.tryParse(tag?.id ?? '');
    if (id == null || path.isEmpty) return;

    try {
      var rg = LoudnessService.read(id);
      rg ??= await LoudnessService.analyzeAndSave(songId: id, filePath: path);
      if (rg != null) {
        cached['replayGainTrackDb'] = (rg['gainDb'] ?? 0).toString();
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint('[NerdFlipCover] rg fail: $e');
    }
  }

  Future<Map<String, dynamic>> _probeIfNeeded(
    Map<String, dynamic> extras,
    MediaItem? tag,
  ) async {
    final cacheKey = _songKey(tag, extras);
    if (cacheKey != null && _cache[cacheKey] != null) {
      return _cache[cacheKey]!;
    }

    final out = Map<String, dynamic>.from(extras);
    final path =
        extras['filePath']?.toString() ?? extras['uri']?.toString() ?? '';

    bool needProbe = false;
    for (final k in [
      'bitrate',
      'sampleRate',
      'channels',
      'fileSize',
      'format',
    ]) {
      if (out[k] == null) needProbe = true;
    }

    if (needProbe && path.isNotEmpty) {
      try {
        final meta = readMetadata(File(path), getImage: false);

        out['bitrate'] ??= meta.bitrate;
        out['sampleRate'] ??= meta.sampleRate;
        out['durationMs'] ??= meta.duration?.inMilliseconds;

        out['fileSize'] ??= () {
          try {
            return File(path).lengthSync();
          } catch (_) {
            return null;
          }
        }();

        out['format'] ??= () {
          final dot = path.lastIndexOf('.');
          return (dot > 0 && dot < path.length - 1)
              ? path.substring(dot + 1).toLowerCase()
              : null;
        }();

        if (out['bitrate'] == null &&
            out['fileSize'] != null &&
            out['durationMs'] != null) {
          final sizeBytes = out['fileSize'] as int;
          final durMs = out['durationMs'] as int;
          if (durMs > 0) {
            final avgBps = (sizeBytes * 8) / (durMs / 1000.0);
            out['bitrate'] = avgBps.toInt();
          }
        }
      } catch (e) {
        debugPrint('[NerdFlipCover] probe fail: $e');
      }
    }

    if (cacheKey != null) {
      _cache[cacheKey] = out;
    }

    if (cacheKey != null && path.isNotEmpty) {
      _ensureReplayGain(cacheKey: cacheKey, tag: tag, path: path);
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Hero(
            tag: widget.heroTag,
            child: CoverArt(player: widget.player, heroTag: widget.heroTag),
          ),
          AnimatedBuilder(
            animation: _fade,
            builder: (context, _) {
              return IgnorePointer(
                ignoring: !_showInfo,
                child: Opacity(
                  opacity: _fade.value,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 15 * _fade.value,
                      sigmaY: 15 * _fade.value,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surface.withOpacity(0.45 * _fade.value),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(20),
                      child: _buildInfo(context, tt, cs),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(BuildContext context, TextTheme tt, ColorScheme cs) {
    final st = widget.player.sequenceState;
    final tag = st.currentSource?.tag;
    Map<String, dynamic> baseExtras = {};
    if (tag is MediaItem) {
      baseExtras = Map<String, dynamic>.from(tag.extras ?? {});
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _probeIfNeeded(baseExtras, tag is MediaItem ? tag : null),
      builder: (context, snap) {
        final extras = snap.data ?? baseExtras;
        final fmtRaw = extras['format']?.toString();
        final bitrateBps = extras['bitrate'] is num
            ? extras['bitrate'] as num
            : null;
        final sampleRate = extras['sampleRate'] is num
            ? extras['sampleRate'] as num
            : null;
        final channels = extras['channels'] is num
            ? extras['channels'] as num
            : null;
        final sizeBytes = extras['fileSize'] is num
            ? extras['fileSize'] as num
            : null;
        final path =
            extras['filePath']?.toString() ?? extras['uri']?.toString();
        final rgTrackDb = extras['replayGainTrackDb']?.toString();

        final isLossless = () {
          final l = (fmtRaw ?? '').toLowerCase();
          return l.contains('flac') ||
              l.contains('alac') ||
              l.contains('wav') ||
              l.contains('pcm') ||
              l.contains('ape');
        }();

        final fmtStr = fmtRaw ?? '—';
        final bitrateStr = (bitrateBps != null && bitrateBps > 0)
            ? '${(bitrateBps / 1000).toStringAsFixed(0)} kbps'
            : '—';
        final sampleRateStr = (sampleRate != null && sampleRate > 0)
            ? '${(sampleRate / 1000).toStringAsFixed(1)} kHz'
            : '—';
        final sizeStr = (sizeBytes != null && sizeBytes > 0)
            ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
            : '—';

        final rgEnabled = (box.read('st_rg_enable') as bool?) ?? false;
        final replayGainStr = (!rgEnabled)
            ? 'off'
            : (rgTrackDb != null && rgTrackDb.isNotEmpty)
            ? '${double.tryParse(rgTrackDb)?.toStringAsFixed(2)} dB'
            : '—';

        final sourceStr = (path != null && path.startsWith('/'))
            ? 'Local file'
            : 'Content URI';
        final compStr = isLossless ? 'Lossless' : 'Lossy';
        final tierLabel = _qualityTier(
          fmtRaw,
          bitrateBps,
          sampleRate,
          isLossless,
        );

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340, maxHeight: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surface.withOpacity(0.30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.outlineVariant.withOpacity(0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'Technical Info',
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (tierLabel != null) ...[
                    const SizedBox(width: 8),
                    _QualityBadge(label: tierLabel),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _kvRow('Format', fmtStr, tt, cs),
                      _kvRow('Bitrate', bitrateStr, tt, cs),
                      _kvRow('Sample Rate', sampleRateStr, tt, cs),
                      _kvRow('Size', sizeStr, tt, cs),
                      _kvRow('Compression', compStr, tt, cs),
                      _kvRow('Source', sourceStr, tt, cs),
                      _kvRow('ReplayGain', replayGainStr, tt, cs),
                      if (path != null && path.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            path,
                            textAlign: TextAlign.center,
                            style: tt.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: cs.onSurfaceVariant,
                              fontSize: 11.sp,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'tap to close',
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 11.sp,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kvRow(
    String keyLabel,
    String valueLabel,
    TextTheme tt,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 1,
            child: Text(
              keyLabel,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 1,
            child: Text(
              valueLabel,
              textAlign: TextAlign.right,
              style: tt.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  final String label;

  const _QualityBadge({required this.label});

  (Gradient, Color) _getStyle(String label) {
    switch (label) {
      case 'HI-RES':
        return (
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF176), Color(0xFFFFB300)],
          ),
          Colors.black,
        );
      case 'LOSSLESS':
        return (
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
          ),
          Colors.black,
        );
      case 'HQ':
        return (
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF81C784), Color(0xFF43A047)],
          ),
          Colors.white,
        );
      case 'SQ':
        return (
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB0BEC5), Color(0xFF90A4AE)],
          ),
          Colors.black87,
        );
      case 'EFF':
        return (
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4DB6AC), Color(0xFF009688)],
          ),
          Colors.white,
        );
      case 'CMP':
        return (
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8A65), Color(0xFFE53935)],
          ),
          Colors.white,
        );
      default:
        return (
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEEEEEE), Color(0xFFCFD8DC)],
          ),
          Colors.black54,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (grad, textColor) = _getStyle(label);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: grad,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.2), width: 0.6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w800,
          fontSize: 10.sp,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

String? _qualityTier(
  String? format,
  num? bitrateBps,
  num? sampleRate,
  bool isLossless,
) {
  final fmt = (format ?? '').toLowerCase();

  if (isLossless && sampleRate != null && sampleRate > 48000) {
    return 'HI-RES';
  }
  if (isLossless) {
    return 'LOSSLESS';
  }
  if (bitrateBps != null && bitrateBps >= 256000) {
    return 'HQ';
  }
  if (bitrateBps != null && bitrateBps > 0) {
    return 'SQ';
  }
  return null;
}
