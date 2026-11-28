import 'package:dio/dio.dart';
import '../models/media_item.dart';
class TmdbService {
  TmdbService() : _dio = Dio(BaseOptions(
    baseUrl: 'https://kinokino-tmdb.get46-get47.workers.dev/3',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    queryParameters: const {'language': 'ru-RU'},
  ));
  final Dio _dio;
  bool get isConfigured => true;
  Future<List<MediaItem>> trending({int page = 1}) => _list('/trending/all/week', extra: {'page': page});
  Future<List<MediaItem>> popular({String type = 'movie', int page = 1}) => _list('/$type/popular', extra: {'page': page});
  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return const [];
    return _list('/search/multi', extra: {'query': query.trim(), 'include_adult': false, 'page': page});
  }
  Future<List<Map<String, dynamic>>> genres({String type = 'movie'}) async {
    final response = await _dio.get('/genre/$type/list');
    final list = (response.data['genres'] as List? ?? const []);
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  Future<List<MediaItem>> discover({String type = 'movie', int? genreId, String sortBy = 'popularity.desc', int? year, double? minRating, int page = 1}) async {
    final params = <String, dynamic>{'sort_by': sortBy, 'include_adult': false, 'page': page};
    if (genreId != null) params['with_genres'] = genreId;
    if (year != null) params['primary_release_year'] = year;
    if (minRating != null) params['vote_average.gte'] = minRating;
    return _list('/discover/$type', extra: params);
  }
  Future<Map<String, dynamic>> details(int id, {String type = 'movie'}) async {
    final response = await _dio.get('/$type/$id', queryParameters: {'append_to_response': 'credits,videos,similar,recommendations'});
    return Map<String, dynamic>.from(response.data);
  }
  Future<Map<String, dynamic>> externalIds(int id, {String type = 'movie'}) async {
    final response = await _dio.get('/$type/$id/external_ids');
    return Map<String, dynamic>.from(response.data);
  }
  Future<List<MediaItem>> recommendations(int id, {String type = 'movie'}) =>
      _relatedList('/$type/$id/recommendations', type: type, excludeId: id);
  Future<List<MediaItem>> similar(int id, {String type = 'movie'}) =>
      _relatedList('/$type/$id/similar', type: type, excludeId: id);

  Future<List<MediaItem>> _relatedList(
    String path, {required String type, required int excludeId}) async {
    final response = await _dio.get(path);
    final payload = response.data;
    if (payload is! Map) return const [];
    final results = payload['results'];
    if (results is! List) return const [];
    final unique = <int, MediaItem>{};
    for (final row in results.whereType<Map>()) {
      final json = Map<String, dynamic>.from(row);
      // TMDB's movie and TV related endpoints do not always include
      // media_type. The endpoint itself is authoritative for the type.
      json['media_type'] = type;
      if (_isFutureRelease(json)) continue;
      final item = MediaItem.fromJson(json);
      if (item.id == 0 || item.id == excludeId) continue;
      if (item.mediaType != 'movie' && item.mediaType != 'tv') continue;
      unique[item.id] = item;
    }
    return unique.values.toList();
  }
  Future<List<MediaItem>> findByExternalId(
    String externalId, {required String mediaType}
  ) async {
    final id = externalId.trim();
    if (!RegExp(r'^tt[0-9]{5,12}
    final response = await _dio.get('/tv/$id/season/$seasonNumber');
    return Map<String, dynamic>.from(response.data);
  }
  Future<Map<String, dynamic>> watchProviders(int id, {String type = 'movie', String region = 'NL'}) async {
    final response = await _dio.get('/$type/$id/watch/providers');
    final results = response.data['results'] as Map? ?? const {};
    final country = results[region] as Map? ?? const {};
    return {
      'link': country['link']?.toString(),
      'flatrate': (country['flatrate'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      'rent': (country['rent'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      'buy': (country['buy'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
    };
  }
  Future<List<MediaItem>> _list(String path, {Map<String, dynamic> extra = const {}}) async {
    final response = await _dio.get(path, queryParameters: extra);
    final results = (response.data['results'] as List? ?? const []);
    return results.whereType<Map>().map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
      .where((e) => e.id != 0 && e.hasRussianTitle && e.hasConfirmedRelease &&
        (e.mediaType == 'movie' || e.mediaType == 'tv')).toList();
  }
}
).hasMatch(id)) return const [];
    final response = await _dio.get('/find/$id', queryParameters: {
      'external_source': 'imdb_id',
    });
    final payload = response.data;
    if (payload is! Map) return const [];
    final key = mediaType == 'tv' ? 'tv_results' : 'movie_results';
    final rows = payload[key];
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((row) {
      final json = Map<String, dynamic>.from(row);
      json['media_type'] = mediaType;
      return MediaItem.fromJson(json);
    }).where((item) => item.id > 0).toList();
  }

  /// Search TMDB for a title returned by another connected catalogue.
  /// Unlike the home feed, related-title mapping allows missing dates and
  /// English-only titles, but never includes a confirmed future release.
  Future<List<MediaItem>> searchRelated(
    String query, {required String mediaType, int? year}
  ) async {
    final value = query.trim();
    if (value.length < 2) return const [];
    final response = await _dio.get('/search/multi', queryParameters: {
      'query': value,
      'include_adult': false,
      'page': 1,
    });
    final payload = response.data;
    final rows = payload is Map ? payload['results'] : null;
    if (rows is! List) return const [];
    final results = <MediaItem>[];
    for (final row in rows.whereType<Map>()) {
      final json = Map<String, dynamic>.from(row);
      final rawType = (json['media_type'] ?? '').toString();
      if (rawType != mediaType) continue;
      if (_isFutureRelease(json)) continue;
      final item = MediaItem.fromJson(json);
      if (item.id > 0) results.add(item);
    }
    if (year != null) {
      results.sort((a, b) {
        final ay = a.releaseDate.length >= 4 ? int.tryParse(a.releaseDate.substring(0, 4)) ?? 0 : 0;
        final by = b.releaseDate.length >= 4 ? int.tryParse(b.releaseDate.substring(0, 4)) ?? 0 : 0;
        return (ay == year ? 0 : (ay - year).abs() + 1)
            .compareTo(by == year ? 0 : (by - year).abs() + 1);
      });
    }
    return results;
  }

  bool _isFutureRelease(Map<String, dynamic> json) {
    final raw = (json['release_date'] ?? json['first_air_date'] ?? '')
        .toString().trim();
    if (raw.length < 10) return false;
    final date = DateTime.tryParse(raw.substring(0, 10));
    if (date == null) return false;
    final now = DateTime.now();
    return DateTime(date.year, date.month, date.day)
        .isAfter(DateTime(now.year, now.month, now.day));
  }

  Future<Map<String, dynamic>> seasonDetails(int id, int seasonNumber) async {
    final response = await _dio.get('/tv/$id/season/$seasonNumber');
    return Map<String, dynamic>.from(response.data);
  }
  Future<Map<String, dynamic>> watchProviders(int id, {String type = 'movie', String region = 'NL'}) async {
    final response = await _dio.get('/$type/$id/watch/providers');
    final results = response.data['results'] as Map? ?? const {};
    final country = results[region] as Map? ?? const {};
    return {
      'link': country['link']?.toString(),
      'flatrate': (country['flatrate'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      'rent': (country['rent'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      'buy': (country['buy'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
    };
  }
  Future<List<MediaItem>> _list(String path, {Map<String, dynamic> extra = const {}}) async {
    final response = await _dio.get(path, queryParameters: extra);
    final results = (response.data['results'] as List? ?? const []);
    return results.whereType<Map>().map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
      .where((e) => e.id != 0 && e.hasRussianTitle && e.hasConfirmedRelease &&
        (e.mediaType == 'movie' || e.mediaType == 'tv')).toList();
  }
}
