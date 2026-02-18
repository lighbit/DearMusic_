import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

class ArtistRelations {
  final Uri? wikipedia;
  final String? wikidataQid;

  ArtistRelations({this.wikipedia, this.wikidataQid});
}

class ArtistDescription {
  final String? lang;
  final String? title;
  final String? extract;
  final Uri? sourceUrl;

  ArtistDescription({this.lang, this.title, this.extract, this.sourceUrl});
}

class WikipediaArtisService {
  final http.Client _client;
  final String userAgent;

  WikipediaArtisService({
    http.Client? client,
    this.userAgent = 'DearMusic/1.0 (https://dearmusic.id)',
  }) : _client = client ?? http.Client();

  Future<ArtistDescription?> getArtistDescription({
    String? mbid,
    String? name,
    String preferredLang = 'id',
  }) async {
    debugPrint("getArtistDescription for: $name with lang: $preferredLang");
    if (name == null || name.isEmpty) {
      return null;
    }

    final artistNames = name.split('/').map((e) => e.trim()).toList();
    for (final artistName in artistNames) {
      if (artistName.isNotEmpty) {
        debugPrint("Attempting to fetch summary for: $artistName");

        final result = await _fetchWikipediaSummary(
          pageTitle: artistName,
          lang: preferredLang,
        );

        if (result != null) {
          debugPrint("Success! Found summary for: $artistName");
          return result;
        }
      }
    }

    debugPrint("No summary found for any artist in: $name");
    return null;
  }

  Future<ArtistDescription?> _fetchWikipediaSummary({
    required String pageTitle,
    required String lang,
  }) async {
    final host = '$lang.wikipedia.org';

    String t1 = normalizeWikiTitle(pageTitle);
    String p1 = Uri.encodeComponent(t1);

    Future<ArtistDescription?> hit(String encodedTitle) async {
      final uri = Uri.https(host, '/api/rest_v1/page/summary/$encodedTitle');
      final res = await _client.get(
        uri,
        headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
      );
      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return ArtistDescription(
        lang: lang,
        title: json['title'] as String?,
        extract: json['extract'] as String?,
        sourceUrl: Uri.tryParse(
          (json['content_urls'] as Map?)?['desktop']?['page'] as String? ?? '',
        ),
      );
    }

    final r1 = await hit(p1);
    if (r1 != null) return r1;

    if (t1.isNotEmpty) {
      final t2 = '${t1[0].toUpperCase()}${t1.substring(1)}';
      final p2 = Uri.encodeComponent(t2);
      final r2 = await hit(p2);
      if (r2 != null) return r2;
    }

    return null;
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return '';
    if (length == 1) return toUpperCase();
    final firstChar = characters.first.toUpperCase();
    final rest = characters.skip(1).toString().toLowerCase();
    return '$firstChar$rest';
  }
}

String normalizeWikiTitle(String raw) {
  var t = raw.trim().replaceAll(RegExp(r'\s+'), '_');
  t = t.replaceAll(RegExp(r'[_\.]+$'), '');
  return t
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((word) {
        if (word.isNotEmpty &&
            word.characters.first.toUpperCase() ==
                word.characters.first.toLowerCase()) {
          return word;
        }
        return word.capitalize();
      })
      .join('_');
}
