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

  bool get hasRussianTitle => RegExp(r'[А-Яа-яЁё]').hasMatch(title);

  bool get hasConfirmedRelease {
    if (releaseDate.length != 10) return false;
    final parsed = DateTime.tryParse(releaseDate);
    if (parsed == null || parsed.year < 1888) return false;
    final today = DateTime.now();
    final releaseDay = DateTime(parsed.year, parsed.month, parsed.day);
    final currentDay = DateTime(today.year, today.month, today.day);
    return !releaseDay.isAfter(currentDay);
  }

  static String _validatedReleaseDate(dynamic value) {
    final date = (value ?? '').toString().trim();
    // Require a complete calendar date. A year-only or missing date is not
    // sufficient evidence that a title has actually been released.
    if (date.length < 10) return '';
    final day = date.substring(0, 10);
    final parsed = DateTime.tryParse(day);
    if (parsed == null || parsed.year < 1888 ||
        parsed.year.toString().padLeft(4, '0') != day.substring(0, 4) ||
        parsed.month.toString().padLeft(2, '0') != day.substring(5, 7) ||
        parsed.day.toString().padLeft(2, '0') != day.substring(8, 10)) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (DateTime(parsed.year, parsed.month, parsed.day).isAfter(today)) return '';
    return day;
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
    mediaType: json['media_type']?.toString() == 'tv'
      ? 'tv'
      : json['media_type']?.toString() == 'movie'
          ? 'movie'
          : ((json.containsKey('first_air_date') || json.containsKey('number_of_episodes') || json.containsKey('name'))
              ? 'tv'
              : 'movie'),
  );
}
