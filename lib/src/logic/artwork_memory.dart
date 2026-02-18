import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

enum ArtworkSlot { gridSmall, tileMedium, hero }

class _Preset {
  final int size;
  final int quality;
  final FilterQuality fq;
  final int? cacheW, cacheH;

  const _Preset(this.size, this.quality, this.fq, {this.cacheW, this.cacheH});
}

class ArtworkMemCache {
  ArtworkMemCache._();

  static final ArtworkMemCache I = ArtworkMemCache._();

  OnAudioQuery? _query;

  void attachQuery(OnAudioQuery query) => _query = query;

  final _map = <String, Uint8List?>{};

  int maxEntries = 256;

  static _Preset presetFor(ArtworkSlot slot) {
    switch (slot) {
      case ArtworkSlot.gridSmall:
        return const _Preset(
          320,
          65,
          FilterQuality.medium,
          cacheW: 320,
          cacheH: 320,
        );
      case ArtworkSlot.tileMedium:
        return const _Preset(
          512,
          72,
          FilterQuality.high,
          cacheW: 512,
          cacheH: 512,
        );
      case ArtworkSlot.hero:
        return const _Preset(1024, 82, FilterQuality.none);
    }
  }

  String _key(ArtworkType t, int id, ArtworkSlot s) =>
      '${t.index}:$id:${s.index}';

  void _touch(String k, Uint8List? v) {
    _map.remove(k);
    _map[k] = v;
    if (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
  }

  Future<Uint8List?> getBytes({
    required int id,
    required ArtworkType type,
    required ArtworkSlot slot,
  }) async {
    final q = _query;
    assert(q != null, 'ArtworkMemCache.attachQuery(...) belum dipanggil');

    final k = _key(type, id, slot);
    if (_map.containsKey(k)) {
      final v = _map.remove(k);
      if (v != null) {
        _touch(k, v);
        return v;
      }
    }

    final p = presetFor(slot);
    final bytes = await q!.queryArtwork(
      id,
      type,
      size: p.size,
      quality: p.quality,
      format: ArtworkFormat.JPEG,
    );

    _touch(k, bytes);
    return bytes;
  }

  Future<Widget> imageWidget({
    required int id,
    required ArtworkType type,
    required ArtworkSlot slot,
    BorderRadius? radius,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Color? placeholderColor,
    IconData? placeholderIcon,
  }) async {
    final p = presetFor(slot);
    final bytes = await getBytes(id: id, type: type, slot: slot);

    final ph =
        placeholder ??
        Container(
          color: placeholderColor ?? Colors.black12,
          alignment: Alignment.center,
          child: Icon(
            placeholderIcon ?? Icons.album_rounded,
            color: Colors.black26,
          ),
        );

    final img = (bytes == null)
        ? ph
        : Image.memory(
            bytes,
            fit: fit,
            gaplessPlayback: true,
            filterQuality: p.fq,
            cacheWidth: p.cacheW,
            cacheHeight: p.cacheH,
          );

    if (radius != null) {
      return ClipRRect(borderRadius: radius, child: img);
    }
    return img;
  }

  void clear() => _map.clear();
}
