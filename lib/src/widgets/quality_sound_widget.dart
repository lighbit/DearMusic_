import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:on_audio_query/on_audio_query.dart';

class QualityTag extends StatelessWidget {
  final SongModel song;
  final ColorScheme cs;
  final TextTheme txt;

  const QualityTag({
    super.key,
    required this.song,
    required this.cs,
    required this.txt,
  });

  @override
  Widget build(BuildContext context) {
    final path = song.data.toString().toLowerCase();
    final parts = path.split('.');
    final ext = parts.isNotEmpty ? parts.last : '';

    final (label, grad, textColor) = _mapQuality(ext, cs);

    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        gradient: grad,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 3,
            offset: const Offset(0, 1.2),
          ),
        ],
      ),
      child: Text(
        label,
        style: txt.labelSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          fontSize: 11.sp,
        ),
      ),
    );
  }

  (String, Gradient, Color) _mapQuality(String ext, ColorScheme cs) {
    switch (ext) {
      case 'flac':
      case 'alac':
      case 'wav':
        return (
          'LOSSLESS',
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
          ),
          Colors.black,
        );

      case 'aac':
      case 'm4a':
        return (
          'HQ',
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF81C784), Color(0xFF43A047)],
          ),
          cs.onTertiaryContainer,
        );

      case 'mp3':
        return (
          'SQ',
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB0BEC5), Color(0xFF90A4AE)],
          ),
          Colors.black87,
        );

      case 'opus':
        return (
          'EFF',
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4DB6AC), Color(0xFF009688)],
          ),
          Colors.white,
        );

      case 'ogg':
        return (
          'CMP',
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8A65), Color(0xFFE53935)],
          ),
          Colors.white,
        );

      default:
        return (
          'UNK',
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEEEEEE), Color(0xFFCFD8DC)],
          ),
          Colors.black54,
        );
    }
  }
}
