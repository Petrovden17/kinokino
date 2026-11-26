import '../models/media_item.dart';
import '../services/tmdb_service.dart';

class CatalogRepository {
  CatalogRepository(this._tmdb);

  final TmdbService _tmdb;

  Future<List<MediaItem>> getTrendingMovies() =>
      _tmdb.trending(type: MediaType.movie);

  Future<List<MediaItem>> getTrendingShows() =>
      _tmdb.trending(type: MediaType.tv);

  Future<List<MediaItem>> search(String query) => _tmdb.search(query);
}
