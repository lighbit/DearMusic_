import 'dart:async';

import 'package:dearmusic/src/logic/lyrics_logic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

Future<void> showLyricsSheet({
  required BuildContext context,
  required AudioPlayer player,
  required String title,
  required String? artist,
  int? durationMs,
  String? vagalumeApiKey,
}) async {
  final cs = Theme.of(context).colorScheme;
  final mq = MediaQuery.of(context);

  var lines = LyricsCache.I.getLrc(title, artist);
  var plain = LyricsCache.I.getPlain(title, artist);

  if (lines == null && plain == null) {
    final res = await fetchFromLrclib(
      title: title,
      artist: artist,
      durationSec: durationMs != null ? (durationMs ~/ 1000) : null,
    );
    lines = res.lrc;
    plain = res.plain;
    if (lines != null) LyricsCache.I.putLrc(title, artist, lines);
    if (plain != null && (lines == null)) {
      LyricsCache.I.putPlain(title, artist, plain);
    }

    if (lines == null &&
        plain == null &&
        vagalumeApiKey != null &&
        vagalumeApiKey.isNotEmpty) {
      final v = await fetchPlainFromVagalume(
        title: title,
        artist: artist,
        apiKey: vagalumeApiKey,
      );
      if (v != null) {
        plain = v;
        LyricsCache.I.putPlain(title, artist, v);
      }
    }
  }

  if ((lines == null || lines.isEmpty) && (plain == null || plain.isEmpty)) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lirik tidak tersedia')));
    }
    return;
  }

  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: cs.surface,
    constraints: BoxConstraints(
      maxHeight: mq.size.height - mq.padding.top - 90,
    ),
    builder: (ctx) {
      final Widget lyricsView = (lines != null && lines.isNotEmpty)
          ? _KaraokeView(player: player, lines: lines)
          : _PlainLyricsView(text: plain!);

      return SafeArea(
        top: true,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: lyricsView,
        ),
      );
    },
  );
}

class _PlainLyricsView extends StatelessWidget {
  final String text;

  const _PlainLyricsView({required this.text});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final TextStyle lyricStyle = tt.titleLarge!.copyWith(
      color: cs.onSurfaceVariant,
      height: 1.6,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
    );

    final stanzas = text.trim().split(RegExp(r'\n\s*\n'));

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Colors.white,
            Colors.transparent,
            Colors.transparent,
            Colors.white,
          ],
          stops: const [0.0, 0.05, 0.95, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstOut,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < stanzas.length; i++) ...[
              SelectableText(
                stanzas[i],
                style: lyricStyle,
                textAlign: TextAlign.left,
              ),
              if (i < stanzas.length - 1) const SizedBox(height: 28.0),
            ],
          ],
        ),
      ),
    );
  }
}

class _KaraokeView extends StatefulWidget {
  final AudioPlayer player;
  final List<LyricLine> lines;

  const _KaraokeView({required this.player, required this.lines});

  @override
  State<_KaraokeView> createState() => _KaraokeViewState();
}

class _KaraokeViewState extends State<_KaraokeView> {
  final _controller = ScrollController();
  final List<GlobalKey> _keys = [];

  static const double _lineExtent = 65.0;
  StreamSubscription<Duration>? _posSub;

  int _active = 0;
  int _lastUiMs = 0;
  bool _seekingManually = false;

  @override
  void initState() {
    super.initState();

    _posSub = widget.player.positionStream.listen((pos) {
      if (_seekingManually) return;

      final ms = pos.inMilliseconds;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastUiMs < 120) return;
      _lastUiMs = now;

      final idx = _indexFor(ms, widget.lines);
      if (idx != _active) {
        if (!mounted) return;
        setState(() => _active = idx);
        _scrollToCenter(idx);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCenter(_active, jump: true);
    });
  }

  Future<void> _seekToLine(int index) async {
    HapticFeedback.lightImpact();
    if (index < 0 || index >= widget.lines.length) return;

    final targetMs = widget.lines[index].ms - 150;
    final safeMs = targetMs < 0 ? 0 : targetMs;

    _seekingManually = true;
    HapticFeedback.selectionClick();

    await widget.player.seek(Duration(milliseconds: safeMs));

    if (!mounted) return;
    setState(() => _active = index);
    _scrollToCenter(index);

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _seekingManually = false;
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  int _indexFor(int ms, List<LyricLine> lines) {
    int lo = 0, hi = lines.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].ms <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  void _scrollToCenter(int idx, {bool jump = false}) {
    if (!_controller.hasClients) return;
    final ctx = _keys[idx].currentContext;
    if (ctx == null) return;

    final ro = ctx.findRenderObject();
    if (ro == null) return;

    final viewport = RenderAbstractViewport.of(ro);

    const centerAlignment = 0.5;
    const biasPx = -12.0;

    final target =
        viewport.getOffsetToReveal(ro, centerAlignment).offset + biasPx;
    final clamped = target.clamp(0.0, _controller.position.maxScrollExtent);

    if (jump) {
      _controller.jumpTo(clamped);
    } else {
      _controller.animateTo(
        clamped,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (_keys.length != widget.lines.length) {
      _keys
        ..clear()
        ..addAll(List.generate(widget.lines.length, (_) => GlobalKey()));
    }

    final list = ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 0),
      itemCount: widget.lines.length,
      itemBuilder: (_, i) {
        final line = widget.lines[i];
        final on = i == _active;

        return Container(
          key: _keys[i],
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
          child: InkWell(
            onTap: () => _seekToLine(i),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              textAlign: TextAlign.center,
              style: on
                  ? tt.headlineSmall!.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                      letterSpacing: 0.1,
                    )
                  : tt.titleLarge!.copyWith(
                      color: cs.onSurface.withOpacity(0.34),
                      height: 1.22,
                      letterSpacing: 0.2,
                      fontWeight: FontWeight.w700,
                    ),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                opacity: on ? 1.0 : 0.55,
                child: Text(
                  line.text.isEmpty ? '♪' : line.text,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
            ),
          ),
        );
      },
    );

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: list,
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cs.surface, cs.surface.withOpacity(0.0)],
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [cs.surface, cs.surface.withOpacity(0.0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
