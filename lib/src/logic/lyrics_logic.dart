import 'dart:convert';
import 'package:http/http.dart' as http;

class LyricLine {
  final int ms;
  final String text;

  LyricLine(this.ms, this.text);
}

class LyricsCache {
  static final LyricsCache I = LyricsCache._();

  LyricsCache._();

  final Map<String, List<LyricLine>> _lrc = {};
  final Map<String, String> _plain = {};

  String _key(String title, String? artist) =>
      '${title.trim().toLowerCase()}::${(artist ?? '').trim().toLowerCase()}';

  List<LyricLine>? getLrc(String title, String? artist) =>
      _lrc[_key(title, artist)];

  String? getPlain(String title, String? artist) => _plain[_key(title, artist)];

  void putLrc(String title, String? artist, List<LyricLine> lines) =>
      _lrc[_key(title, artist)] = lines;

  void putPlain(String title, String? artist, String text) =>
      _plain[_key(title, artist)] = text;
}

Future<({List<LyricLine>? lrc, String? plain})> fetchFromLrclib({
  required String title,
  required String? artist,
  int? durationSec,
}) async {
  final uri = Uri.https('lrclib.net', '/api/search', {
    'track_name': title,
    if (artist != null && artist.isNotEmpty) 'artist_name': artist,
    if (durationSec != null) 'duration': '$durationSec',
  });
  final res = await http.get(uri);
  if (res.statusCode != 200) return (lrc: null, plain: null);

  final list = jsonDecode(res.body) as List;
  if (list.isEmpty) return (lrc: null, plain: null);

  final m = list.first as Map<String, dynamic>;
  final synced = m['syncedLyrics'] as String?;
  final plain = m['plainLyrics'] as String?;

  return (lrc: synced != null ? parseLrc(synced) : null, plain: plain);
}

Future<String?> fetchPlainFromVagalume({
  required String title,
  required String? artist,
  required String apiKey,
}) async {
  final uri = Uri.https('api.vagalume.com.br', '/search.php', {
    'apikey': apiKey,
    if (artist != null) 'art': artist,
    'mus': title,
  });
  final res = await http.get(uri);
  if (res.statusCode != 200) return null;
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final mus = (data['mus'] as List?)?.cast<Map<String, dynamic>>();
  if (mus == null || mus.isEmpty) return null;
  return mus.first['text'] as String?;
}

List<LyricLine> parseLrc(String lrc) {
  final lines = <LyricLine>[];
  final re = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,2}))?\]\s*(.*)');
  for (final raw in lrc.split('\n')) {
    final m = re.firstMatch(raw.trim());
    if (m == null) continue;
    final mm = int.parse(m.group(1)!);
    final ss = int.parse(m.group(2)!);
    final cs = int.tryParse(m.group(3) ?? '0') ?? 0;
    final text = m.group(4)!.trim();
    final ms = (mm * 60 + ss) * 1000 + (cs * (cs < 10 ? 100 : 10));
    lines.add(LyricLine(ms, text));
  }
  lines.sort((a, b) => a.ms.compareTo(b.ms));
  return lines;
}
