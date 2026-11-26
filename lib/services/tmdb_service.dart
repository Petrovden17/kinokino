import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/media_item.dart';

class TmdbException implements Exception {
  const TmdbException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Клиент TMDB API. Ключ передаётся при запуске через --dart-define=TMDB_API_KEY=...
class TmdbService {
  TmdbService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://api.themoviedb.org/3';
  static const _imageBaseUrl = 'https://image.tmdb.org/t/p';
  static const apiKey = String.fromEnvironment('TMDB_API_KEY');

  final http.Client _client;

  String imageUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBaseUrl/$size$path';
  }

  Future<List<MediaItem>> trending({MediaType type = MediaType.movie}) {
    return _getMedia('/trending/${type == MediaType.movie ? 'movie' : 'tv'}/week', type);
  }

  Future<List<MediaItem>> popular({MediaType type = MediaType.movie}) {
    return _getMedia('/${type == MediaType.movie ? 'movie' : 'tv'}/popular', type);
  }

  Future<List<MediaItem>> search(String query) async {
    final value = query.trim();
    if (value.isEmpty) return [];
    final movieResults = await _getMedia(
      '/search/multi',
      MediaType.movie,
      queryParameters: {'query': value, 'include_adult': 'false'},
      mixed: true,
    );
    return movieResults;
  }

  Future<List<MediaItem>> _getMedia(
    String path,
    MediaType type, {
    Map<String, String>? queryParameters,
    bool mixed = false,
  }) async {
    if (apiKey.isEmpty) {
      throw const TmdbException(
        'Не задан TMDB API key. Запустите приложение с --dart-define=TMDB_API_KEY=ВАШ_КЛЮЧ.',
      );
    }

    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: {
      'api_key': apiKey,
      'language': 'ru-RU',
      ...?queryParameters,
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw TmdbException('TMDB вернул ошибку ${response.statusCode}.');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final results = decoded['results'] as List<dynamic>? ?? const [];
    return results.whereType<Map<String, dynamic>>().where((item) {
      if (!mixed) return true;
      return item['media_type'] == 'movie' || item['media_type'] == 'tv';
    }).map((item) {
      final itemType = mixed && item['media_type'] == 'tv' ? MediaType.tv : type;
      return MediaItem.fromJson(item, itemType);
    }).toList();
  }

  void dispose() => _client.close();
}
