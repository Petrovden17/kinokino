enum MediaType { movie, tv }

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.overview,
    required this.type,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage = 0,
    this.genreIds = const [],
  });

  final int id;
  final String title;
  final String overview;
  final MediaType type;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double voteAverage;
  final List<int> genreIds;

  factory MediaItem.fromJson(Map<String, dynamic> json, MediaType type) {
    return MediaItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (type == MediaType.movie ? json['title'] : json['name']) as String? ?? 'Без названия',
      overview: json['overview'] as String? ?? '',
      type: type,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: (type == MediaType.movie ? json['release_date'] : json['first_air_date']) as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
      genreIds: (json['genre_ids'] as List<dynamic>? ?? const [])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList(),
    );
  }

  String get year => releaseDate != null && releaseDate!.length >= 4
      ? releaseDate!.substring(0, 4)
      : '—';

  String get typeLabel => type == MediaType.movie ? 'Фильм' : 'Сериал';
}
