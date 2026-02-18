import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ExpressiveProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration? buffered;
  final bool isActive;
  final ValueChanged<Duration>? onSeek;
  final ColorScheme colorScheme;
  final double height;
  final double amplitude;
  final double wavelength;
  final Duration waveTransitionDuration;

  const ExpressiveProgressBar({
    super.key,
    required this.position,
    required this.duration,
    this.buffered,
    required this.isActive,
    this.onSeek,
    required this.colorScheme,
    this.height = 4.0,
    this.amplitude = 4.0,
    this.wavelength = 24.0,
    this.waveTransitionDuration = const Duration(milliseconds: 350),
  });

  @override
  State<ExpressiveProgressBar> createState() => _ExpressiveProgressBarState();
}

class _ExpressiveProgressBarState extends State<ExpressiveProgressBar>
    with TickerProviderStateMixin {
  late final AnimationController _phaseCtrl;
  late final AnimationController _ampCtrl;
  late final Animation<double> _ampAnimation;

  bool _dragging = false;
  double _dragFrac = 0;

  @override
  void initState() {
    super.initState();
    _phaseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _ampCtrl = AnimationController(
      vsync: this,
      duration: widget.waveTransitionDuration,
    );
    _ampAnimation = CurvedAnimation(parent: _ampCtrl, curve: Curves.easeInOut);

    if (widget.isActive) {
      _ampCtrl.value = 1.0;
    }
    _syncPhaseAnim();
  }

  @override
  void didUpdateWidget(covariant ExpressiveProgressBar old) {
    super.didUpdateWidget(old);
    _syncPhaseAnim();

    if (old.isActive != widget.isActive && !_dragging) {
      if (widget.isActive) {
        _ampCtrl.forward();
      } else {
        _ampCtrl.reverse();
      }
    }
  }

  void _syncPhaseAnim() {
    final active =
        widget.isActive &&
        widget.duration > Duration.zero &&
        widget.position < widget.duration;
    if (active) {
      if (!_phaseCtrl.isAnimating) _phaseCtrl.repeat();
    } else {
      if (_phaseCtrl.isAnimating) _phaseCtrl.stop();
    }
  }

  @override
  void dispose() {
    _phaseCtrl.dispose();
    _ampCtrl.dispose();
    super.dispose();
  }

  double _safeFrac(Duration a, Duration b) {
    final total = b.inMilliseconds;
    if (total <= 0) return 0;
    return (a.inMilliseconds / total).clamp(0, 1).toDouble();
  }

  void _seekAtLocalDx(double x, double maxWidth) {
    if (widget.onSeek == null) return;
    final frac = (x / maxWidth).clamp(0.0, 1.0);
    setState(() => _dragFrac = frac);
    final targetMs = (widget.duration.inMilliseconds * frac).round();
    widget.onSeek!(Duration(milliseconds: targetMs));
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final valueFrac = _dragging
        ? _dragFrac
        : _safeFrac(widget.position, widget.duration);
    final bufferedFrac = _safeFrac(
      widget.buffered ?? Duration.zero,
      widget.duration,
    );

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final touchAreaHeight = math.max(
          widget.height + widget.amplitude * 2,
          48.0,
        );

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) {
            setState(() {
              _dragging = true;
              _dragFrac = valueFrac;
            });
          },
          onHorizontalDragUpdate: (d) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(d.globalPosition);
            _seekAtLocalDx(local.dx, w);
          },
          onHorizontalDragEnd: (_) => setState(() => _dragging = false),
          onTapDown: (d) {
            HapticFeedback.lightImpact();
            _seekAtLocalDx(d.localPosition.dx, w);
          },
          child: AnimatedBuilder(
            animation: Listenable.merge([_phaseCtrl, _ampAnimation]),
            builder: (_, __) {
              return RepaintBoundary(
                child: CustomPaint(
                  size: Size(w, touchAreaHeight),
                  painter: _ExpressiveProgressPainter(
                    value: valueFrac,
                    buffered: bufferedFrac,
                    cs: cs,
                    h: widget.height,
                    animatedAmp: _ampAnimation.value * widget.amplitude,
                    wave: widget.wavelength,
                    phase: _phaseCtrl.value * 2 * math.pi,
                    isDragging: _dragging,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ExpressiveProgressPainter extends CustomPainter {
  final double value;
  final double buffered;
  final ColorScheme cs;
  final double h;
  final double animatedAmp;
  final double wave;
  final double phase;
  final bool isDragging;

  _ExpressiveProgressPainter({
    required this.value,
    required this.buffered,
    required this.cs,
    required this.h,
    required this.animatedAmp,
    required this.wave,
    required this.phase,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final yMid = size.height / 2;
    final activeW = size.width * value;
    final buffW = size.width;
    final currentAmp = isDragging ? 0.0 : animatedAmp;

    final inactiveTrackPaint = Paint()
      ..color = cs.surfaceContainerHighest
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, yMid),
      Offset(size.width, yMid),
      inactiveTrackPaint,
    );

    if (buffW > 0) {
      final bufferedPaint = Paint()
        ..color = cs.primary.withOpacity(0.25)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0, yMid), Offset(buffW, yMid), bufferedPaint);
    }

    if (activeW > 0) {
      final path = Path();
      path.moveTo(0, yMid);
      for (double x = 0; x <= activeW; x++) {
        final y =
            yMid + math.sin((x / wave) * 2 * math.pi + phase) * currentAmp;
        path.lineTo(x, y);
      }

      final activePaint = Paint()
        ..color = cs.primary
        ..strokeWidth = h
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, activePaint);

      final thumbPaint = Paint()
        ..color = cs.primary
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;

      final thumbTop = yMid - h - 4;
      final thumbBottom = yMid + h + 4;
      canvas.drawLine(
        Offset(activeW, thumbTop),
        Offset(activeW, thumbBottom),
        thumbPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExpressiveProgressPainter old) {
    return old.isDragging != isDragging ||
        old.animatedAmp != animatedAmp ||
        old.value != value ||
        old.buffered != buffered ||
        old.phase != phase ||
        old.cs != cs;
  }
}
