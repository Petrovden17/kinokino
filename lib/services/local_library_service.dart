import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

/// Локальные списки профиля. Данные хранятся на устройстве пользователя.
class LocalLibraryService {
  static const _favoritesKey = 'kinokino_favorites_v1';
  static const _historyKey = 'kinokino_history_v1';

  Future<List<MediaItem>> getFavorites() async => _readItems(_favoritesKey);

  Future<List<MediaItem>> getHistory() async => _readItems(_historyKey);

  Future<bool> isFavorite(MediaItem item) async {
    final items = await getFavorites();
    return items.any((saved) => _identity(saved) == _identity(item));
  }

  Future<void> toggleFavorite(MediaItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _readItems(_favoritesKey);
    final exists = items.any((saved) => _identity(saved) == _identity(item));
    if (exists) {
      items.removeWhere((saved) => _identity(saved) == _identity(item));
    } else {
      items.insert(0, item);
    }
    await prefs.setString(_favoritesKey, jsonEncode(items.map(_toJson).toList()));
  }

  Future<void> addToHistory(MediaItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _readItems(_historyKey);
    items.removeWhere((saved) => _identity(saved) == _identity(item));
    items.insert(0, item);
    if (items.length > 100) items.removeRange(100, items.length);
    await prefs.setString(_historyKey, jsonEncode(items.map(_toJson).toList()));
  }

  Future<void> removeFromHistory(MediaItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _readItems(_historyKey);
    items.removeWhere((saved) => _identity(saved) == _identity(item));
    await prefs.setString(_historyKey, jsonEncode(items.map(_toJson).toList()));
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<List<MediaItem>> _readItems(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .toList();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  String _identity(MediaItem item) => '${item.mediaType}:${item.id}';

  Map<String, dynamic> _toJson(MediaItem item) => {
        'id': item.id,
        'title': item.title,
        'overview': item.overview,
        'mediaType': item.mediaType,
        'posterPath': item.posterPath,
        'backdropPath': item.backdropPath,
        'releaseDate': item.releaseDate,
        'voteAverage': item.voteAverage,
        'genreIds': item.genreIds,
      };

  MediaItem _fromJson(Map<String, dynamic> json) => MediaItem(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String? ?? 'Без названия',
        overview: json['overview'] as String? ?? '',
        mediaType: (json['mediaType'] ?? json['type'] ?? 'movie').toString(),
        posterPath: json['posterPath'] as String?,
        backdropPath: json['backdropPath'] as String?,
        releaseDate: json['releaseDate'] as String? ?? '',
        voteAverage: (json['voteAverage'] as num?)?.toDouble() ?? 0,
        genreIds: (json['genreIds'] as List<dynamic>? ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList(),
      );
}
