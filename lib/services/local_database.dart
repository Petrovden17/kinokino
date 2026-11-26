import 'package:supabase_flutter/supabase_flutter.dart';

/// Облачная библиотека пользователя. Доступ ограничен RLS-политиками Supabase.
class LocalDatabase {
  static SupabaseClient get _client => Supabase.instance.client;
  static String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Войди в аккаунт, чтобы открыть библиотеку.');
    return id;
  }

  static Map<String, dynamic> _mediaJson(
    int id, String title, String? poster, String mediaType,
  ) => {
    'id': id,
    'title': title,
    'posterPath': poster,
    'mediaType': mediaType,
  };

  static Map<String, Object?> _libraryRow(Map<String, dynamic> row, {String? ratingField, String? dateField}) {
    final media = Map<String, dynamic>.from(row['media'] as Map? ?? const {});
    return {
      'id': row['media_id'],
      'title': media['title'] ?? 'Без названия',
      'poster_path': media['posterPath'],
      'media_type': row['media_type'] ?? 'movie',
      'is_favorite': ratingField == null ? 1 : 0,
      'user_rating': ratingField == null ? null : row[ratingField],
      'last_opened': dateField == null ? null : row[dateField],
    };
  }

  static Future<void> setFavorite(
    int id, String title, String? poster, bool value, {String mediaType = 'movie'}
  ) async {
    final userId = _userId;
    final query = _client.from('favorites');
    if (value) {
      await query.upsert({
        'user_id': userId,
        'media_id': id,
        'media_type': mediaType,
        'media': _mediaJson(id, title, poster, mediaType),
      }, onConflict: 'user_id,media_id,media_type');
    } else {
      await query.delete()
        .eq('user_id', userId).eq('media_id', id).eq('media_type', mediaType);
    }
  }

  static Future<void> recordOpen(
    int id, String title, String? poster, {String mediaType = 'movie'}
  ) async {
    await _client.from('watch_history').insert({
      'user_id': _userId,
      'media_id': id,
      'media_type': mediaType,
      'media': _mediaJson(id, title, poster, mediaType),
      'watched_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> setRating(
    int id, String title, String? poster, double rating, {String mediaType = 'movie'}
  ) async {
    await _client.from('ratings').upsert({
      'user_id': _userId,
      'media_id': id,
      'media_type': mediaType,
      'rating': rating,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,media_id,media_type');
  }

  static Future<List<Map<String, Object?>>> favorites() async {
    final rows = await _client.from('favorites').select()
      .eq('user_id', _userId).order('created_at', ascending: false);
    return (rows as List).map((e) => _libraryRow(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<List<Map<String, Object?>>> history() async {
    final rows = await _client.from('watch_history').select()
      .eq('user_id', _userId).order('watched_at', ascending: false).limit(100);
    return (rows as List).map((e) => _libraryRow(
      Map<String, dynamic>.from(e as Map), dateField: 'watched_at',
    )).toList();
  }

  static Future<List<Map<String, Object?>>> ratings() async {
    final rows = await _client.from('ratings').select()
      .eq('user_id', _userId).order('rating', ascending: false);
    return (rows as List).map((e) => _libraryRow(
      Map<String, dynamic>.from(e as Map), ratingField: 'rating',
    )).toList();
  }
}
