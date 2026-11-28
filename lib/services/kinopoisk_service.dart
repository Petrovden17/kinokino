import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves Kinopoisk IDs and keeps a shared TMDB → Kinopoisk cache.
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
    String? imdbId,
    int? filmId,
  }) async {
    final body = <String, dynamic>{'action': action};
    if (query != null) body['query'] = query;
    if (imdbId != null) body['imdb_id'] = imdbId;
    if (filmId != null) body['film_id'] = filmId;
    final response = await _client.functions.invoke('kinopoisk-proxy', body: body);
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const FormatException('Некорректный ответ Kinopoisk API.');
  }

  /// Returns a previously verified TMDB → Kinopoisk mapping, if available.
  Future<Map<String, dynamic>?> cachedMatch(
    int tmdbId, {required String mediaType, String? fallbackTitle}
  ) async {
    final row = await _client.from('kinokino_id_map')
        .select('kinopoisk_id, title, release_year, imdb_id, wikidata_id, match_method, confidence')
        .eq('tmdb_id', tmdbId)
        .eq('media_type', mediaType)
        .eq('status', 'matched')
        .maybeSingle();
    if (row == null) return null;
    return {
      'filmId': row['kinopoisk_id'],
      'nameRu': (fallbackTitle?.trim().isNotEmpty ?? false) ? fallbackTitle!.trim() : row['title'],
      'name': (fallbackTitle?.trim().isNotEmpty ?? false) ? fallbackTitle!.trim() : row['title'],
      'year': row['release_year'],
      'imdbId': row['imdb_id'],
      'wikidataId': row['wikidata_id'],
      'matchMethod': row['match_method'],
      'confidence': row['confidence'],
    };
  }

  /// Stores a resolved mapping through the trusted Edge Function.
  /// Cache writes are best-effort and must never block playback.
  Future<void> cacheMatch({
    required int tmdbId,
    required String mediaType,
    required int kinopoiskId,
    required String title,
    int? releaseYear,
    String? imdbId,
    String? wikidataId,
    required String matchMethod,
    required double confidence,
  }) async {
    try {
      await _client.functions.invoke('kinopoisk-proxy', body: {
        'action': 'cache',
        'tmdb_id': tmdbId,
        'media_type': mediaType,
        'kinopoisk_id': kinopoiskId,
        'title': title,
        'release_year': releaseYear,
        'imdb_id': imdbId,
        'wikidata_id': wikidataId,
        'match_method': matchMethod,
        'confidence': confidence,
      });
    } catch (error) {
      // A cache outage must not prevent a valid Kinopoisk match from opening.
    }
  }

  /// Extracts result rows from the response variants used by Kinopoisk API
  /// versions and proxy deployments.
  List<Map<String, dynamic>> _resultRows(Map<String, dynamic> data) {
    dynamic rows = data['films'] ?? data['items'] ?? data['results'];
    if (rows is! List && data['data'] is Map) {
      final nested = Map<String, dynamic>.from(data['data'] as Map);
      rows = nested['films'] ?? nested['items'] ?? nested['results'];
    }
    if (rows is! List && data['data'] is List) rows = data['data'];
    if (rows is! List) return const [];
    return rows.whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item)).toList();
  }

  /// Fast search against the primary Kinopoisk proxy only. Used for the
  /// first playback lookup; Wikidata is a slower fallback, not a per-query step.
  Future<List<Map<String, dynamic>>> searchKinopoisk(String query) async {
    final data = await _invoke('search', query: query);
    return _resultRows(data);
  }

  /// Public catalog lookup backed only by Wikidata; no Kinopoisk API token.
  Future<List<Map<String, dynamic>>> searchWikidata(String query) =>
      _searchWikidata(query);

  Future<List<Map<String, dynamic>>> search(String query) =>
      _searchWikidata(query);

  /// Resolves an IMDb ID through Wikidata's public SPARQL endpoint.
  /// This is independent of the private Kinopoisk API and requires no key.
  Future<List<Map<String, dynamic>>> byImdbId(String imdbId) async {
    final id = imdbId.trim();
    if (!RegExp(r'^tt[0-9]{5,12}

  Future<List<Map<String, dynamic>>> byWikidataId(String entityId) async {
    final id = entityId.trim();
    if (!id.startsWith('Q') || id.length < 2 ||
        int.tryParse(id.substring(1)) == null) return const [];
    return _entitiesToKinopoisk([id]);
  }

  Future<List<Map<String, dynamic>>> _searchWikidata(String query) async {
    final ids = <String>{};
    for (final language in const ['ru', 'en']) {
      final response = await _wikidata.get('', queryParameters: {
        'action': 'wbsearchentities',
        'search': query,
        'language': language,
        'uselang': language,
        'type': 'item',
        'limit': 25,
        'format': 'json',
      });
      final rows = response.data is Map
          ? (response.data['search'] as List? ?? const [])
          : const <dynamic>[];
      for (final row in rows.whereType<Map>()) {
        final id = row['id']?.toString() ?? '';
        if (id.startsWith('Q') && id.length > 1 &&
            int.tryParse(id.substring(1)) != null) {
          ids.add(id);
        }
      }
    }
    if (ids.isEmpty) return const [];
    return _entitiesToKinopoisk(ids.take(50).toList());
  }

  Future<List<Map<String, dynamic>>> _entitiesToKinopoisk(List<String> ids) async {
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
).hasMatch(id)) return const [];
    final query = '''
      SELECT ?item ?itemLabel ?kpId ?date ?instance WHERE {
        ?item wdt:P345 "$id".
        OPTIONAL { ?item wdt:P2603 ?kpId. }
        OPTIONAL { ?item wdt:P577 ?date. }
        OPTIONAL { ?item wdt:P31 ?instance. }
        SERVICE wikibase:label { bd:serviceParam wikibase:language "ru,en". }
      } LIMIT 10
    ''';
    final response = await _wikidata.get(
      'https://query.wikidata.org/sparql',
      queryParameters: {'query': query, 'format': 'json'},
      options: Options(headers: const {'Accept': 'application/sparql-results+json'}),
    );
    final bindings = response.data is Map
        ? ((response.data['results'] as Map?)?['bindings'] as List? ?? const [])
        : const [];
    final results = <Map<String, dynamic>>[];
    for (final row in bindings.whereType<Map>()) {
      final item = row['item'] is Map ? row['item']['value']?.toString() ?? '' : '';
      final entityId = item.split('/').last;
      final rawKpId = row['kpId'] is Map ? row['kpId']['value']?.toString() ?? '' : '';
      final label = row['itemLabel'] is Map ? row['itemLabel']['value']?.toString() ?? '' : '';
      final date = row['date'] is Map ? row['date']['value']?.toString() ?? '' : '';
      final instance = row['instance'] is Map ? row['instance']['value']?.toString() ?? '' : '';
      final filmId = int.tryParse(rawKpId);
      if (!entityId.startsWith('Q') || filmId == null || filmId <= 0) continue;
      final year = RegExp(r'^(\d{4})').firstMatch(date)?.group(1) ?? '';
      final isSeries = instance.endsWith('/Q5398426') ||
          instance.endsWith('/Q1259759') || instance.endsWith('/Q15416');
      results.add({
        'filmId': filmId,
        'nameRu': label,
        'nameEn': label,
        'nameOriginal': label,
        'name': label,
        'year': year,
        'type': isSeries ? 'TV_SERIES' : (instance.endsWith('/Q11424') ? 'FILM' : ''),
        'wikidataId': entityId,
        'imdbId': id,
      });
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> byWikidataId(String entityId) async {
    final id = entityId.trim();
    if (!id.startsWith('Q') || id.length < 2 ||
        int.tryParse(id.substring(1)) == null) return const [];
    return _entitiesToKinopoisk([id]);
  }

  Future<List<Map<String, dynamic>>> _searchWikidata(String query) async {
    final ids = <String>{};
    for (final language in const ['ru', 'en']) {
      final response = await _wikidata.get('', queryParameters: {
        'action': 'wbsearchentities',
        'search': query,
        'language': language,
        'uselang': language,
        'type': 'item',
        'limit': 25,
        'format': 'json',
      });
      final rows = response.data is Map
          ? (response.data['search'] as List? ?? const [])
          : const <dynamic>[];
      for (final row in rows.whereType<Map>()) {
        final id = row['id']?.toString() ?? '';
        if (id.startsWith('Q') && id.length > 1 &&
            int.tryParse(id.substring(1)) != null) {
          ids.add(id);
        }
      }
    }
    if (ids.isEmpty) return const [];
    return _entitiesToKinopoisk(ids.take(50).toList());
  }

  Future<List<Map<String, dynamic>>> _entitiesToKinopoisk(List<String> ids) async {
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
