class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    this.overview = '',
    this.posterPath,
    this.backdropPath,
    this.releaseDate = '',
    this.voteAverage = 0,
    this.voteCount = 0,
    this.popularity = 0,
    this.genreIds = const [],
    this.mediaType = 'movie',
  });
  final int id;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String releaseDate;
  final double voteAverage;
  final int voteCount;
  final double popularity;
  final List<int> genreIds;
  final String mediaType;

  static String _validatedReleaseDate(dynamic value) {
    final date = (value ?? '').toString().trim();
    if (date.length < 4) return '';
    final year = int.tryParse(date.substring(0, 4));
    if (year == null || year < 1888 || year > DateTime.now().year + 2) return '';
    if (date.length >= 10) {
      final parsed = DateTime.tryParse(date.substring(0, 10));
      if (parsed == null || parsed.year != year) return '';
    }
    return date;
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
    id: json['id'] as int? ?? 0,
    title: (json['title'] ?? json['name'] ?? 'Без названия').toString(),
    overview: (json['overview'] ?? '').toString(),
    posterPath: json['poster_path'] as String?,
    backdropPath: json['backdrop_path'] as String?,
    releaseDate: _validatedReleaseDate(json['release_date'] ?? json['first_air_date']),
    voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
    voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
    popularity: (json['popularity'] as num?)?.toDouble() ?? 0,
    genreIds: (json['genre_ids'] as List? ?? const []).whereType<num>().map((e) => e.toInt()).toList(),
    mediaType: ((json['media_type']?.toString() == 'tv' || json.containsKey('first_air_date') || json.containsKey('number_of_episodes') || json.containsKey('name'))
      ? 'tv'
      : 'movie'),
  );
}
