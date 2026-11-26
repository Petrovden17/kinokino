import 'package:supabase_flutter/supabase_flutter.dart';

/// Kinopoisk API client. The private API token is stored server-side.
class KinopoiskService {
  KinopoiskService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

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
    final data = await _invoke('search', query: query);
    final items = data['films'] as List? ?? const [];
    return items.whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item)).toList();
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
