import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AlbumStoryShare {
  static const _ch = MethodChannel('dearmusic/share');

  static Future<void> shareAlbumToInstagramStory({
    required Uint8List? coverBytes,
    required String albumTitle,
    required String artistName,
    required String hook,
    required String ctaText,
    required String playStoreUrl,
    Color? bgTint,
    Color? ctaColor,
    Uint8List? watermarkPng,
  }) async {
    final png = await _renderStoryPng(
      coverBytes: coverBytes,
      albumTitle: albumTitle,
      artistName: artistName,
      hook: hook,
      playStoreUrl: playStoreUrl,
      bgTint: bgTint,
      watermarkPng: watermarkPng,
    );

    await _ch.invokeMethod('ig_story', {
      'pngBytes': png,
      'contentUrl': playStoreUrl,
    });
  }

  static Future<void> shareAlbumStoryWithChooser({
    required Uint8List? coverBytes,
    required String albumTitle,
    required String artistName,
    required String hook,
    required String ctaText,
    required String playStoreUrl,
    Color? bgTint,
    Color? ctaColor,
    Uint8List? watermarkPng,
    BuildContext? context,
  }) async {
    final png = await _renderStoryPng(
      coverBytes: coverBytes,
      albumTitle: albumTitle,
      artistName: artistName,
      hook: hook,
      playStoreUrl: playStoreUrl,
      bgTint: bgTint,
      watermarkPng: watermarkPng,
    );

    final ctx =
        context ??
        ((WidgetsBinding.instance.platformDispatcher.views.isNotEmpty)
            ? WidgetsBinding.instance.focusManager.primaryFocus?.context
            : null);

    Future<void> act(String which) async {
      try {
        if (which == 'ig') {
          await _ch.invokeMethod('ig_story', {
            'pngBytes': png,
            'contentUrl': playStoreUrl,
          });
        } else if (which == 'wa') {
          final caption = '$ctaText\n$playStoreUrl';
          await _ch.invokeMethod('wa_status', {
            'pngBytes': png,
            'text': caption,
          });
        } else if (which == 'save') {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final name = 'DearMusic_Story_$ts.png';
          final ok = await _ch.invokeMethod('save_image', {
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
          final cs = Theme.of(c).colorScheme;
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
                  const SizedBox(height: 6),
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

  static Future<Uint8List> _renderStoryPng({
    required Uint8List? coverBytes,
    required String albumTitle,
    required String artistName,
    required String hook,
    required String playStoreUrl,
    Color? bgTint,
    Uint8List? watermarkPng,
  }) async {
    const W = 1080.0;
    const H = 1920.0;
    const PAD = 72.0;

    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final full = Rect.fromLTWH(0, 0, W, H);

    ui.Image? coverImg;
    if (coverBytes != null && coverBytes.isNotEmpty) {
      try {
        final codec = await ui.instantiateImageCodec(
          coverBytes,
          targetWidth: 720,
        );
        final frame = await codec.getNextFrame();
        coverImg = frame.image;
      } catch (_) {
        coverImg = null;
      }
    }

    final dominant =
        await _dominantColorFrom(coverImg) ?? const Color(0xFF111111);
    final baseBg = bgTint ?? Color.lerp(dominant, Colors.black, 0.35)!;

    c.drawRect(full, Paint()..color = baseBg);
    if (coverImg != null) {
      c.saveLayer(
        full,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
      );
      c.drawImageRect(
        coverImg,
        Rect.fromLTWH(
          0,
          0,
          coverImg.width.toDouble(),
          coverImg.height.toDouble(),
        ),
        full,
        Paint(),
      );
      c.restore();
      final grad = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, H),
          [
            baseBg.withOpacity(0.65),
            baseBg.withOpacity(0.35),
            Colors.black.withOpacity(0.35),
          ],
          [0.0, 0.55, 1.0],
        );
      c.drawRect(full, grad);
      final vignette = Paint()
        ..shader = ui.Gradient.radial(
          Offset(W / 2, H * 0.38),
          W * 0.95,
          [Colors.transparent, Colors.black.withOpacity(0.34)],
          [0.62, 1.0],
        );
      c.drawRect(full, vignette);
    } else {
      final stripes = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(W, H),
          [baseBg, baseBg.withOpacity(0.92), baseBg.withOpacity(0.98)],
          [0.0, 0.5, 1.0],
        );
      c.drawRect(full, stripes);
    }

    final cx = W / 2;
    final coverSize = 720.0;
    final coverRect = Rect.fromCenter(
      center: Offset(cx, H * 0.38),
      width: coverSize,
      height: coverSize,
    );
    final coverR = RRect.fromRectXY(coverRect, 30, 30);

    void softShadow(RRect r) {
      c.saveLayer(r.outerRect.inflate(30), Paint());
      c.drawRRect(
        r.shift(const Offset(0, 10)),
        Paint()..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18),
      );
      c.drawRRect(
        r.shift(const Offset(0, 10)),
        Paint()..color = Colors.black.withOpacity(0.22),
      );
      c.restore();
    }

    softShadow(coverR);
    if (coverImg != null) {
      c.save();
      c.clipRRect(coverR);
      c.drawImageRect(
        coverImg,
        Rect.fromLTWH(
          0,
          0,
          coverImg.width.toDouble(),
          coverImg.height.toDouble(),
        ),
        coverRect,
        Paint(),
      );
      c.restore();
      c.drawRRect(
        coverR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withOpacity(0.08),
      );
    } else {
      c.drawRRect(coverR, Paint()..color = Colors.white.withOpacity(0.06));
      final icon = _iconPainter(
        Icons.music_note_rounded,
        140,
        Colors.white.withOpacity(0.28),
      );
      icon.paint(
        c,
        Offset(cx - icon.width / 2, coverRect.center.dy - icon.height / 2),
      );
    }

    TextPainter tp(
      String text,
      TextStyle style,
      double maxW, {
      int? maxLines,
      TextAlign align = TextAlign.center,
    }) {
      return TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: align,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: maxW);
    }

    final artistTp = tp(
      artistName,
      TextStyle(
        fontSize: 30.sp,
        fontWeight: FontWeight.w700,
        color: const Color(0xFFEDEDED).withOpacity(0.96),
        letterSpacing: 0.25,
      ),
      W - PAD * 2,
    );
    final artistY = coverRect.bottom + 52;
    artistTp.paint(c, Offset(cx - artistTp.width / 2, artistY));

    final titleTp = tp(
      albumTitle.toUpperCase(),
      TextStyle(
        fontSize: 56.sp,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.8,
        color: Colors.white,
        height: 1.1,
      ),
      W - PAD * 2,
      maxLines: 2,
    );
    final titleY = artistY + artistTp.height + 12;
    titleTp.paint(c, Offset(cx - titleTp.width / 2, titleY));

    final hookTp = tp(
      hook,
      TextStyle(
        fontSize: 28.sp,
        fontWeight: FontWeight.w500,
        color: Colors.white.withOpacity(0.92),
        height: 1.3,
      ),
      W - PAD * 2.5,
      maxLines: 2,
    );
    final hookTop = titleY + titleTp.height + 32;
    hookTp.paint(c, Offset(cx - hookTp.width / 2, hookTop));

    {
      final footerText = "LISTEN ON";
      final appNameText = "DEARMUSIC";
      final icon = _iconPainter(
        Icons.headphones,
        28,
        Colors.white.withOpacity(0.8),
      );

      final footerTp = tp(
        footerText,
        TextStyle(
          fontSize: 22.sp,
          fontWeight: FontWeight.w600,
          color: Colors.white.withOpacity(0.8),
          letterSpacing: 0.8,
        ),
        W,
      );
      final appNameTp = tp(
        appNameText,
        TextStyle(
          fontSize: 22.sp,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 1.0,
        ),
        W,
      );

      final totalW = footerTp.width + 12 + icon.width + 12 + appNameTp.width;
      final startX = cx - totalW / 2;
      final baseY = H - PAD * 2;

      footerTp.paint(c, Offset(startX, baseY));
      icon.paint(c, Offset(startX + footerTp.width + 12, baseY - 2));
      appNameTp.paint(
        c,
        Offset(startX + footerTp.width + 12 + icon.width + 12, baseY),
      );
    }

    if (watermarkPng != null && watermarkPng.isNotEmpty) {}

    final pic = rec.endRecording();
    final img = await pic.toImage(W.toInt(), H.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  static TextPainter _iconPainter(IconData icon, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: 'MaterialIcons',
          fontSize: size.sp,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  static Future<Color?> _dominantColorFrom(ui.Image? img) async {
    if (img == null) return null;
    final scaleW = 32;
    final scaleH = (32 * img.height / img.width).clamp(1, 32).toInt();
    final pic = ui.PictureRecorder();
    final can = Canvas(pic);
    can.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, scaleW.toDouble(), scaleH.toDouble()),
      Paint(),
    );
    final mini = await pic.endRecording().toImage(scaleW, scaleH);
    final bd = await mini.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return null;
    final data = bd.buffer.asUint8List();
    var r = 0, g = 0, b = 0, n = 0;
    for (var i = 0; i < data.length; i += 4) {
      final rr = data[i];
      final gg = data[i + 1];
      final bb = data[i + 2];
      final aa = data[i + 3];
      if (aa < 8) continue;
      r += rr;
      g += gg;
      b += bb;
      n++;
    }
    if (n == 0) return null;
    return Color.fromARGB(255, (r ~/ n), (g ~/ n), (b ~/ n));
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
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            radius: 48,
            containedInkWell: true,
            highlightShape: BoxShape.circle,
            child: Container(
              padding: EdgeInsets.zero,
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
              child: ClipOval(
                child: SizedBox.square(
                  dimension: 72,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Image.asset(
                        asset,
                        width: 50,
                        height: 50,
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
