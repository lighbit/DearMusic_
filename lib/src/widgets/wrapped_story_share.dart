import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class WrappedAlbumItem {
  final String title;
  final Uint8List artBytes;
  final int plays;

  const WrappedAlbumItem({
    required this.title,
    required this.artBytes,
    required this.plays,
  });
}

class WrappedAlbumSummary {
  final String pageTitle;
  final String topAlbumName;
  final Uint8List topAlbumArtBytes;
  final String listTitle;
  final List<WrappedAlbumItem> otherAlbums;
  final String playStoreUrl;

  const WrappedAlbumSummary({
    required this.pageTitle,
    required this.topAlbumName,
    required this.topAlbumArtBytes,
    required this.listTitle,
    required this.otherAlbums,
    required this.playStoreUrl,
  });
}

class WrappedStoryShare {
  static const _ig = MethodChannel('dearmusic/share');

  static Future<void> shareWrappedToInstagramStory(
    WrappedAlbumSummary s,
  ) async {
    final png = await _renderWrappedPng(s);

    final ok = await _ig.invokeMethod<bool>('ig_story', {
      'pngBytes': png,
      'contentUrl': s.playStoreUrl,
    });

    if (ok != true) {}
  }

  static Future<void> shareWrappedWithChooser({
    required WrappedAlbumSummary s,
    required String ctaText,
    BuildContext? context,
  }) async {
    final png = await _renderWrappedPng(s);

    final ctx =
        context ??
        ((WidgetsBinding.instance.platformDispatcher.views.isNotEmpty)
            ? WidgetsBinding.instance.focusManager.primaryFocus?.context
            : null);

    Future<void> act(String which) async {
      try {
        if (which == 'ig') {
          await _ig.invokeMethod('ig_story', {
            'pngBytes': png,
            'contentUrl': s.playStoreUrl,
          });
        } else if (which == 'wa') {
          final caption = '$ctaText\n${s.playStoreUrl}';
          await _ig.invokeMethod('wa_status', {
            'pngBytes': png,
            'text': caption,
          });
        } else if (which == 'save') {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final name = 'DearMusic_Wrapped_$ts.png';
          final ok = await _ig.invokeMethod('save_image', {
            'pngBytes': png,
            'filename': name,
            'relativeDir': 'Pictures/DearMusic',
          });
          if (ctx != null && ok == true) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text('Gambar disimpan ke Pictures/DearMusic'),
              ),
            );
          }
        }
      } catch (_) {}
    }

    if (context != null) {
      await showModalBottomSheet(
        context: context,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (c) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    easy.tr("share.shareOrSave"),
                    style: Theme.of(c).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _SharePill(
                        label: 'Instagram',
                        asset: 'assets/images/instagram.png',
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(c);
                          act('ig');
                        },
                      ),
                      _SharePill(
                        label: 'WhatsApp',
                        asset: 'assets/images/whatsapp.png',
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(c);
                          act('wa');
                        },
                      ),
                      _SharePill(
                        label: 'Save',
                        asset: 'assets/images/download.png',
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(c);
                          act('save');
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      await act('save');
    }
  }

  static Future<Uint8List> _renderWrappedPng(WrappedAlbumSummary s) async {
    const double igSafeBottom = 240.0;
    const w = 1080.0, h = 1920.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    final paint = Paint();

    paint.color = const Color(0xFF0E0E0F);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

    final bgImg = await decodeImageFromList(s.topAlbumArtBytes);
    final src = Rect.fromLTWH(
      0,
      0,
      bgImg.width.toDouble(),
      bgImg.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, w, h);
    paint.imageFilter = ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25);
    paint.colorFilter = const ui.ColorFilter.mode(
      Colors.black54,
      BlendMode.darken,
    );
    canvas.save();
    canvas.drawImageRect(bgImg, src, dst, paint);
    canvas.restore();
    paint
      ..imageFilter = null
      ..colorFilter = null;

    final shader = ui.Gradient.linear(
      const Offset(0, 0),
      Offset(0, h),
      [
        Colors.black.withOpacity(0.85),
        Colors.black.withOpacity(0.20),
        Colors.black.withOpacity(0.85),
      ],
      const [0.0, 0.5, 1.0],
    );
    paint.shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
    paint.shader = null;

    const double padH = 56, padV = 200.0, gap = 16;
    final left = padH, right = w - padH;
    double currentY = padV;

    _drawText(
      canvas,
      s.pageTitle,
      left,
      currentY,
      right - left,
      fontSize: 36.sp,
      weight: FontWeight.w600,
      color: Colors.white.withOpacity(0.9),
      align: TextAlign.center,
    );
    currentY += 56;

    _drawText(
      canvas,
      s.topAlbumName,
      left,
      currentY,
      right - left,
      fontSize: 88.sp,
      weight: FontWeight.w900,
      color: Colors.white,
      align: TextAlign.center,
      maxLines: 3,
    );
    currentY += 230 + gap;

    const artSize = 500.0;
    const artRadius = 48.0;
    final artRect = Rect.fromLTWH(
      (w - artSize) / 2,
      currentY,
      artSize,
      artSize,
    );
    final artRRect = RRect.fromRectAndRadius(
      artRect,
      const Radius.circular(artRadius),
    );

    paint.color = Colors.black.withOpacity(0.4);
    paint.imageFilter = ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15);
    canvas.drawRRect(artRRect.shift(const Offset(0, 10)), paint);
    paint.imageFilter = null;

    canvas.save();
    canvas.clipRRect(artRRect);
    canvas.drawImageRect(bgImg, src, artRect, Paint());
    canvas.restore();
    currentY += artSize + (gap * 4);

    _drawText(
      canvas,
      s.listTitle,
      left,
      currentY,
      right - left,
      fontSize: 28.sp,
      weight: FontWeight.w400,
      color: Colors.white70,
    );
    currentY += 28 + (gap * 2);

    final double ctaBaseY = h - igSafeBottom;
    final double listStopY = ctaBaseY - 50.0;

    const double itemHeight = 90.0;
    const double listArtSize = 64.0;
    const double listArtRadius = listArtSize / 2;

    for (int i = 0; i < s.otherAlbums.length && i < 4; i++) {
      final item = s.otherAlbums[i];
      final rank = i + 2;
      final itemY = currentY;

      if (itemY + itemHeight > listStopY - 8) break;

      _drawText(
        canvas,
        "#$rank",
        left,
        itemY + (itemHeight - 36) / 2,
        40,
        fontSize: 36.sp,
        weight: FontWeight.w700,
        color: Colors.white,
      );

      final img = await decodeImageFromList(item.artBytes);
      final listArtRect = Rect.fromLTWH(
        left + 60,
        itemY + (itemHeight - listArtSize) / 2,
        listArtSize,
        listArtSize,
      );
      final listArtRRect = RRect.fromRectAndRadius(
        listArtRect,
        const Radius.circular(listArtRadius),
      );

      canvas.save();
      canvas.clipRRect(listArtRRect);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        listArtRect,
        Paint(),
      );
      canvas.restore();

      final titleX = left + 60 + listArtSize + 20;
      final titleWidth = (right - 80) - titleX;
      _drawText(
        canvas,
        item.title,
        titleX,
        itemY + (itemHeight - 32) / 2,
        titleWidth,
        fontSize: 32.sp,
        weight: FontWeight.w600,
        color: Colors.white,
        maxLines: 2,
      );

      _drawText(
        canvas,
        "${item.plays}×",
        right - 60,
        itemY + (itemHeight - 32) / 2,
        60,
        fontSize: 32.sp,
        weight: FontWeight.w400,
        color: Colors.white70,
        align: TextAlign.right,
      );

      currentY += itemHeight + (gap / 2);
    }

    const footerText = "LISTEN ON";
    const appNameText = "DEARMUSIC";
    const ctaGap = 12.0;
    const ctaIconSize = 28.0;

    final footerPara = _buildText(
      footerText,
      right - left,
      fontSize: 22.sp,
      weight: FontWeight.w600,
      color: Colors.white.withOpacity(0.8),
      letterSpacing: 0.8,
    );

    final iconPara = _buildText(
      String.fromCharCode(Icons.headphones.codePoint),
      right - left,
      fontSize: ctaIconSize,
      color: Colors.white.withOpacity(0.8),
      fontFamily: 'MaterialIcons',
    );

    final appNamePara = _buildText(
      appNameText,
      right - left,
      fontSize: 22.sp,
      weight: FontWeight.w800,
      color: Colors.white,
      letterSpacing: 1.0,
    );

    final fw = footerPara.maxIntrinsicWidth;
    final iw = iconPara.maxIntrinsicWidth;
    final aw = appNamePara.maxIntrinsicWidth;
    final totalW = fw + ctaGap + iw + ctaGap + aw;
    final startX = (w - totalW) / 2;
    final baseY = ctaBaseY;

    canvas.drawParagraph(footerPara, Offset(startX, baseY));
    canvas.drawParagraph(iconPara, Offset(startX + fw + ctaGap, baseY - 2));
    canvas.drawParagraph(
      appNamePara,
      Offset(startX + fw + ctaGap + iw + ctaGap, baseY),
    );

    final pic = recorder.endRecording();
    final img = await pic.toImage(w.toInt(), h.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  static ui.Paragraph _buildText(
    String text,
    double maxWidth, {
    double fontSize = 24,
    FontWeight weight = FontWeight.w400,
    Color color = Colors.white,
    int maxLines = 1,
    TextAlign align = TextAlign.left,
    String fontFamily = 'Roboto',
    double? letterSpacing,
  }) {
    final pb =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: fontFamily,
              fontSize: fontSize,
              fontWeight: weight,
              maxLines: maxLines,
              textAlign: align,
            ),
          )
          ..pushStyle(ui.TextStyle(color: color, letterSpacing: letterSpacing))
          ..addText(text);

    final paragraph = pb.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    return paragraph;
  }

  static void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y,
    double maxWidth, {
    double fontSize = 24,
    FontWeight weight = FontWeight.w400,
    Color color = Colors.white,
    int maxLines = 1,
    TextAlign align = TextAlign.left,
    String fontFamily = 'Roboto',
    double? letterSpacing,
  }) {
    final paragraph = _buildText(
      text,
      maxWidth,
      fontSize: fontSize,
      weight: weight,
      color: color,
      maxLines: maxLines,
      align: align,
      fontFamily: fontFamily,
      letterSpacing: letterSpacing,
    );
    canvas.drawParagraph(paragraph, Offset(x, y));
  }
}

class _SharePill extends StatelessWidget {
  final String label;
  final String asset;
  final VoidCallback onTap;

  const _SharePill({
    required this.label,
    required this.asset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: cs.surfaceContainerHighest,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkResponse(
            onTap: onTap,
            radius: 48,
            containedInkWell: true,
            highlightShape: BoxShape.circle,
            child: ClipOval(
              child: SizedBox.square(
                dimension: 72,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.5),
                      width: 0.6,
                    ),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Image.asset(
                        asset,
                        width: 36,
                        height: 36,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.broken_image_outlined,
                          color: cs.onSurface.withOpacity(0.6),
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 84,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
