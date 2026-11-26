import 'package:dio/dio.dart';

/// Watchmode supplies availability metadata and provider links, not video streams.
class WatchmodeService {
  WatchmodeService()
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://kinokino-tmdb.get46-get47.workers.dev/watchmode/v1',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        ));

  final Dio _dio;

  Future<List<Map<String, dynamic>>> freeSources({
    required int tmdbId,
    required String mediaType,
    String region = 'NL',
  }) async {
    final field = mediaType == 'tv' ? 'tmdb_tv_id' : 'tmdb_movie_id';
    final search = await _dio.get(
      '/search/',
      queryParameters: {'search_field': field, 'search_value': tmdbId},
    );
    final results = (search.data is Map ? search.data['title_results'] ?? search.data['results'] : null);
    final rows = results is List ? results.whereType<Map>().toList() : <Map>[];
    if (rows.isEmpty) return const [];

    final match = rows.firstWhere(
      (row) => row['tmdb_id']?.toString() == tmdbId.toString(),
      orElse: () => rows.first,
    );
    final watchmodeId = match['id'];
    if (watchmodeId == null) return const [];

    final response = await _dio.get(
      '/title/$watchmodeId/sources/',
      queryParameters: {'regions': region},
    );
    final sourceRows = response.data is List ? response.data : const [];
    return sourceRows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => row['type']?.toString().toLowerCase() == 'free')
        .toList();
  }
}
