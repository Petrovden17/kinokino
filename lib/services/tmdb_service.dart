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
  Future<List<MediaItem>> recommendations(int id, {String type = 'movie'}) => _list('/$type/$id/recommendations');
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
      .where((e) => e.posterPath != null && e.id != 0 && (e.mediaType == 'movie' || e.mediaType == 'tv')).toList();
  }
}
