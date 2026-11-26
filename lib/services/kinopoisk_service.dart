import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves Kinopoisk IDs through the private API, with a Wikidata fallback.
class KinopoiskService {
  KinopoiskService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final Dio _wikidata = Dio(BaseOptions(
    baseUrl: 'https://www.wikidata.org/w/api.php',
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 18),
    headers: const {
      'Accept': 'application/json',
      'User-Agent': 'KinoKino/1.0 (media metadata lookup)',
    },
  ));

  Future<Map<String, dynamic>> _invoke(
    String action, {
    String? query,
    int? filmId,
  }) async {
    final body = <String, dynamic>{'action': action};
    if (query != null) body['query'] = query;
    if (filmId != null) body['film_id'] = filmId;
    final response = await _client.functions.invoke('kinopoisk-proxy', body: body);
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const FormatException('Некорректный ответ Kinopoisk API.');
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    final results = <Map<String, dynamic>>[];
    try {
      final data = await _invoke('search', query: query);
      final items = data['films'] as List? ?? const [];
      results.addAll(items.whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)));
    } catch (_) {
      // Keep resolving IDs through the public index if the private API fails.
    }
    try {
      results.addAll(await _searchWikidata(query));
    } catch (_) {
      // A temporary Wikidata outage must not discard Kinopoisk API results.
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> _searchWikidata(String query) async {
    final searchResponse = await _wikidata.get('', queryParameters: {
      'action': 'wbsearchentities',
      'search': query,
      'language': 'ru',
      'uselang': 'ru',
      'type': 'item',
      'limit': 12,
      'format': 'json',
    });
    final searchRows = searchResponse.data is Map
        ? (searchResponse.data['search'] as List? ?? const [])
        : const <dynamic>[];
    final ids = searchRows.whereType<Map>()
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.startsWith('Q') &&
            id.length > 1 && int.tryParse(id.substring(1)) != null)
        .toSet().toList();
    if (ids.isEmpty) return const [];

    final entityResponse = await _wikidata.get('', queryParameters: {
      'action': 'wbgetentities',
      'ids': ids.join('|'),
      'props': 'labels|claims',
      'languages': 'ru|en',
      'format': 'json',
    });
    final entities = entityResponse.data is Map
        ? (entityResponse.data['entities'] as Map? ?? const {})
        : const {};
    final results = <Map<String, dynamic>>[];

    for (final entry in entities.entries) {
      final entity = entry.value;
      if (entity is! Map) continue;
      final claims = entity['claims'] as Map? ?? const {};
      final kpClaims = claims['P2603'] as List? ?? const [];
      if (kpClaims.isEmpty) continue;
      final firstClaim = kpClaims.first as Map?;
      final mainSnak = firstClaim?['mainsnak'] as Map?;
      final dataValue = mainSnak?['datavalue'] as Map?;
      final filmId = dataValue?['value']?.toString().trim() ?? '';
      if (int.tryParse(filmId) == null) continue;

      String label(String language) {
        final labels = entity['labels'] as Map? ?? const {};
        return ((labels[language] as Map?)?['value'] ?? '').toString();
      }

      String claimEntityId(String property) {
        final rows = claims[property] as List? ?? const [];
        if (rows.isEmpty) return '';
        final claim = rows.first as Map?;
        final snak = claim?['mainsnak'] as Map?;
        final value = (snak?['datavalue'] as Map?)?['value'];
        return value is Map ? (value['id']?.toString() ?? '') : '';
      }

      int yearFromClaim(String property) {
        final rows = claims[property] as List? ?? const [];
        if (rows.isEmpty) return 0;
        final claim = rows.first as Map?;
        final snak = claim?['mainsnak'] as Map?;
        final value = (snak?['datavalue'] as Map?)?['value']?.toString() ?? '';
        for (var index = 0; index + 4 <= value.length; index++) {
          final candidate = value.substring(index, index + 4);
          final year = int.tryParse(candidate);
          if (year != null && year >= 1800 && year <= 2200) return year;
        }
        return 0;
      }

      final ru = label('ru');
      final en = label('en');
      final instance = claimEntityId('P31');
      final isSeries = const {'Q5398426', 'Q1259759', 'Q15416'}.contains(instance);
      final releaseYear = yearFromClaim('P577');
      results.add({
        'filmId': int.parse(filmId),
        'nameRu': ru,
        'nameEn': en,
        'nameOriginal': en.isNotEmpty ? en : ru,
        'name': ru.isNotEmpty ? ru : en,
        'year': releaseYear != 0 ? releaseYear : yearFromClaim('P571'),
        'type': isSeries ? 'TV_SERIES' : (instance == 'Q11424' ? 'FILM' : ''),
      });
    }
    return results;
  }

  Future<Map<String, dynamic>> film(int id) => _invoke('film', filmId: id);

  Future<List<Map<String, dynamic>>> seasons(int id) async {
    final data = await _invoke('seasons', filmId: id);
    final items = data['items'] as List? ?? const [];
    return items.whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> videos(int id) async {
    final data = await _invoke('videos', filmId: id);
    final items = data['items'] as List? ?? const [];
    return items.whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item)).toList();
  }
}
