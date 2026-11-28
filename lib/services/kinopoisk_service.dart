import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves source-catalog IDs through public Wikidata data.
/// No private Kinopoisk API key or endpoint is used.
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

  /// Best-effort shared cache write. Failure never blocks opening the source.
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
    } catch (_) {
      // The public lookup still works when shared cache storage is unavailable.
    }
  }

  /// Resolve an exact IMDb identifier through Wikidata's public SPARQL API.
  Future<List<Map<String, dynamic>>> byImdbId(String imdbId) async {
    final id = imdbId.trim();
    if (!RegExp(r'^tt[0-9]{5,12}$').hasMatch(id)) return const [];
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
    if (!RegExp(r'^Q[0-9]+$').hasMatch(id)) return const [];
    return _entitiesToKinopoisk([id]);
  }

  Future<List<Map<String, dynamic>>> searchWikidata(String query) async {
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
        if (RegExp(r'^Q[0-9]+$').hasMatch(id)) ids.add(id);
      }
    }
    if (ids.isEmpty) return const [];
    return _entitiesToKinopoisk(ids.take(50).toList());
  }

  Future<List<Map<String, dynamic>>> _entitiesToKinopoisk(List<String> ids) async {
    final response = await _wikidata.get('', queryParameters: {
      'action': 'wbgetentities',
      'ids': ids.join('|'),
      'props': 'labels|claims',
      'languages': 'ru|en',
      'format': 'json',
    });
    final entities = response.data is Map
        ? (response.data['entities'] as Map? ?? const {})
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
        final match = RegExp(r'(19[0-9]{2}|20[0-9]{2})').firstMatch(value);
        return int.tryParse(match?.group(1) ?? '') ?? 0;
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
        'wikidataId': entry.key.toString(),
      });
    }
    return results;
  }
}
