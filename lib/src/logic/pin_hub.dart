import 'dart:async';
import 'package:get_storage/get_storage.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:dearmusic/src/models/pinned_model.dart';

class PinHub {
  static final PinHub I = PinHub._();

  PinHub._();

  static const _pinKeyAny = 'pinned_any_v2';
  final _box = GetStorage();
  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  int _asInt(dynamic v, {int fallback = -1}) {
    if (v is int) return v;
    return int.tryParse('$v') ?? fallback;
  }

  int? _asIntOrNull(dynamic v) {
    if (v is int) return v;
    return int.tryParse('$v');
  }

  PinKind? _parseKind(dynamic k) {
    if (k is PinKind) return k;
    if (k is String) {
      for (final v in PinKind.values) {
        if (v.name == k) return v;
      }
    }
    return null;
  }

  Future<int> deleteAllPins() async {
    final raw = _box.read<List>(_pinKeyAny);
    final before = (raw is List) ? raw.length : 0;
    await _box.write(_pinKeyAny, <Map<String, dynamic>>[]);
    _changes.add(null);
    return before;
  }

  List<PinnedAny> get all {
    final raw = _box.read<List>(_pinKeyAny);
    if (raw is! List || raw.isEmpty) {
      return <PinnedAny>[];
    }

    final cleaned = <PinnedAny>[];
    final seen = <String>{};
    var changed = false;
    var invalidCount = 0;

    for (final item in raw) {
      if (item is! Map) {
        changed = true;
        invalidCount++;
        continue;
      }

      final m = Map<String, dynamic>.from(item);

      final kind = _parseKind(m['kind']);
      if (kind == null) {
        changed = true;
        invalidCount++;
        continue;
      }

      final id = _asIntOrNull(m['id']);
      if (id == null || id < 0) {
        changed = true;
        invalidCount++;
        continue;
      }
      m['id'] = id;

      if (m.containsKey('artworkId')) {
        final ai = _asIntOrNull(m['artworkId']);
        if (ai == null || ai < 0) {
          m.remove('artworkId');
          changed = true;
        } else {
          m['artworkId'] = ai;
        }
      }

      m['kind'] = kind.name;

      try {
        final pin = PinnedAny.fromJson(m);
        final key = '${pin.kind.name}|${pin.id}';
        if (seen.add(key)) {
          cleaned.add(pin);
        } else {
          changed = true;
        }
      } catch (err) {
        changed = true;
        invalidCount++;
      }
    }

    if (changed || cleaned.length != raw.length) {
      _box.write(_pinKeyAny, cleaned.map((e) => e.toJson()).toList());
      _changes.add(null);
    }

    return cleaned;
  }

  Future<int> purgeBadPins() async {
    final raw = _box.read<List>(_pinKeyAny);
    if (raw is! List || raw.isEmpty) return 0;

    final before = raw.length;
    final _ = all;
    final afterList = _box.read<List>(_pinKeyAny);
    final after = (afterList is List) ? afterList.length : 0;
    return before - after;
  }

  void _saveSanitized(List<PinnedAny> list) {
    _box.write(_pinKeyAny, list.map((e) => e.toJson()).toList());
    _changes.add(null);
  }

  void _save(List<PinnedAny> list) {
    final sanitized = list.map((p) {
      final json = p.toJson();
      json['id'] = _asInt(json['id']);
      if (json['artworkId'] != null) {
        json['artworkId'] = _asInt(json['artworkId']);
      }
      return PinnedAny.fromJson(json);
    }).toList();
    _saveSanitized(sanitized);
  }

  bool isPinned(PinKind kind, int id) =>
      all.any((p) => p.kind == kind && p.id == id);

  Future<void> toggleSong({
    required int id,
    required String title,
    String? artist,
    int? artworkId,
    ArtworkType? artworkType,
  }) async {
    final list = all.toList();
    final i = list.indexWhere((p) => p.kind == PinKind.song && p.id == id);
    if (i >= 0) {
      list.removeAt(i);
    } else {
      list.add(
        PinnedAny(
          kind: PinKind.song,
          id: id,
          title: title,
          subtitle: artist,
          artworkId: artworkId ?? id,
          artworkType: artworkType ?? ArtworkType.AUDIO,
        ),
      );
    }
    _save(list);
  }

  Future<void> toggleAlbum({
    required int id,
    required String album,
    String? artist,
  }) async {
    final list = all.toList();
    final i = list.indexWhere((p) => p.kind == PinKind.album && p.id == id);
    if (i >= 0) {
      list.removeAt(i);
    } else {
      list.add(
        PinnedAny(
          kind: PinKind.album,
          id: id,
          title: album,
          subtitle: artist,
          artworkId: id,
          artworkType: ArtworkType.ALBUM,
        ),
      );
    }
    _save(list);
  }

  Future<void> toggleArtist({required int id, required String name}) async {
    final list = all.toList();
    final i = list.indexWhere((p) => p.kind == PinKind.artist && p.id == id);
    if (i >= 0) {
      list.removeAt(i);
    } else {
      list.add(
        PinnedAny(
          kind: PinKind.artist,
          id: id,
          title: name,
          artworkId: id,
          artworkType: ArtworkType.ARTIST,
        ),
      );
    }
    _save(list);
  }
}

AlbumModel? findAlbumById(List<AlbumModel> list, int id) {
  for (final a in list) {
    if (a.id == id) return a;
  }
  return null;
}
