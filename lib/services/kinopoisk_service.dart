import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kinopoisk API client. The private API token is stored server-side.
class KinopoiskService {
  KinopoiskService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final Dio _wikidata = Dio(BaseOptions(
    baseUrl: 'https://www.wikidata.org/w/api.php',
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 18),
    headers: const {'Accept': 'application/json', 'User-Agent': 'KinoKino/1.0 (media metadata lookup)'},
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
    try {
      final data = await _invoke('search', query: query);
      final items = data['films'] as List? ?? const [];
      final films = items.whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)).toList();
      if (films.isNotEmpty) return films;
    } catch (_) {
      // The public app must still be able to resolve a catalog ID if the
      // optional private Kinopoisk API key is unavailable.
    }
    return _searchWikidata(query);
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
    final searchRows = (searchResponse.data is Map
        ? (searchResponse.data['search'] as List? ?? const [])
        : const <dynamic>[]);
    final ids = searchRows.whereType<Map>()
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => RegExp(r'^Q[0-9]+

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
).hasMatch(id))
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
      final rawId = (((kpClaims.first as Map?)?['mainsnak'] as Map?)?['datavalue'] as Map?)?['value'];
      final filmId = rawId?.toString().trim() ?? '';
      if (filmId.isEmpty || !RegExp(r'^\\d+

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
).hasMatch(filmId)) continue;

      String label(String language) {
        final labels = entity['labels'] as Map? ?? const {};
        return ((labels[language] as Map?)?['value'] ?? '').toString();
      }
      String claimEntityId(String property) {
        final rows = claims[property] as List? ?? const [];
        if (rows.isEmpty) return '';
        final value = (((rows.first as Map?)['mainsnak'] as Map?)?['datavalue'] as Map?)?['value'];
        return value is Map ? (value['id']?.toString() ?? '') : '';
      }
      int yearFromClaim(String property) {
        final rows = claims[property] as List? ?? const [];
        if (rows.isEmpty) return 0;
        final value = (((rows.first as Map?)['mainsnak'] as Map?)?['datavalue'] as Map?)?['value'];
        final match = RegExp(r'([12][0-9]{3})').firstMatch(value?.toString() ?? '');
        return int.tryParse(match?.group(1) ?? '') ?? 0;
      }

      final ru = label('ru');
      final en = label('en');
      final instance = claimEntityId('P31');
      final isSeries = const {'Q5398426', 'Q1259759', 'Q15416'}.contains(instance);
      results.add({
        'filmId': int.tryParse(filmId) ?? filmId,
        'nameRu': ru,
        'nameEn': en,
        'nameOriginal': en.isNotEmpty ? en : ru,
        'name': ru.isNotEmpty ? ru : en,
        'year': yearFromClaim('P577') != 0
            ? yearFromClaim('P577') : yearFromClaim('P571'),
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
