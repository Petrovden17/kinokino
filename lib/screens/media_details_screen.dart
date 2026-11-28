import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
import '../services/kinopoisk_service.dart';
import '../services/watchmode_service.dart';
import '../services/internet_archive_service.dart';
import '../services/local_database.dart';
import '../widgets/poster_card.dart';
import 'player_screen.dart';
import 'zagonka_screen.dart';
class MediaDetailsScreen extends StatefulWidget {
  const MediaDetailsScreen({super.key, required this.item, this.preferredAudioLanguage = 'auto', this.preferredVideoQuality = 'auto'});
  final MediaItem item;
  final String preferredAudioLanguage;
  final String preferredVideoQuality;
  @override State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}
class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  final _tmdb = TmdbService();
  final _kinopoisk = KinopoiskService();
  Map<String, dynamic>? _kpFilm;
  int? _kinopoiskId;
  String? _imdbId;
  List<Map<String, dynamic>> _kpSeasons = [];
  List<Map<String, dynamic>> _kpVideos = [];

  Map<String, dynamic>? _details;
  List<MediaItem> _recommendations = [];
  List<MediaItem> _similar = [];
  bool _loading = true;
  String? _error;
  double _rating = 0;
  String get _type => ['tv', 'animated_tv'].contains(widget.item.mediaType.toLowerCase()) ? 'tv' : 'movie';
  String get _displayTitle {
    final d = _details ?? {};
    final localized = (d['title'] ?? d['name'] ?? '').toString().trim();
    return RegExp(r'[А-Яа-яЁё]').hasMatch(localized) ? localized : widget.item.title;
  }
  int get _releaseYear {
    final date = (_details?['release_date'] ?? _details?['first_air_date'] ?? widget.item.releaseDate).toString();
    final year = int.tryParse(date.length >= 4 ? date.substring(0, 4) : '') ?? 0;
    return year >= 1888 && year <= DateTime.now().year ? year : 0;
  }
  String get _preferredArchiveLanguage => widget.preferredAudioLanguage == 'original'
      ? (_details?['original_language']?.toString() ?? 'auto')
      : widget.preferredAudioLanguage;
  String get _playbackSearchTitle {
    final d = _details ?? {};
    return (d['original_title'] ?? d['original_name'] ?? d['title'] ?? d['name'] ?? widget.item.title).toString();
  }
  @override
  void initState() {
    super.initState();
    _load();
    LocalDatabase.recordOpen(widget.item.id, widget.item.title, widget.item.posterPath, mediaType: _type).catchError((_) {});
  }

  int _yearFromDetails(Map<String, dynamic>? details, String fallbackDate) {
    final raw = (details?['release_date'] ?? details?['first_air_date'] ?? fallbackDate).toString();
    return raw.length >= 4 ? int.tryParse(raw.substring(0, 4)) ?? 0 : 0;
  }

  Future<Map<String, dynamic>?> _findKinopoiskMatch(
    Map<String, dynamic>? details,
  ) async {
    final title = (details?['title'] ?? details?['name'] ?? widget.item.title).toString().trim();
    final year = _yearFromDetails(details, widget.item.releaseDate);

    // A cached mapping is optional. Playback resolution must never depend on
    // the private Kinopoisk API or its token.
    try {
      final cached = await _kinopoisk.cachedMatch(
        widget.item.id, mediaType: _type, fallbackTitle: title,
      ).timeout(const Duration(seconds: 4));
      final rawId = cached?['filmId'] ?? cached?['kinopoiskId'] ?? cached?['id'];
      final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0;
      if (id > 0) return cached;
    } catch (e) {
      debugPrint('[KinoKino] optional mapping cache unavailable: $e');
    }

    // TMDB supplies public Wikidata identifiers. Resolve the Kinopoisk ID
    // from Wikidata's public P2603 property, without a Kinopoisk API key.
    try {
      final external = await _tmdb.externalIds(widget.item.id, type: _type)
          .timeout(const Duration(seconds: 8));
      final imdbId = external['imdb_id']?.toString() ?? '';
      _imdbId = imdbId.isEmpty ? null : imdbId;
      if (imdbId.isNotEmpty) {
          if (mounted) setState(() {});
        final imdbMatches = await _kinopoisk.byImdbId(imdbId)
            .timeout(const Duration(seconds: 10));
        final selectedByImdb = _selectKinopoiskMatch(
          imdbMatches, details: details, year: year, isSeries: _type == 'tv',
        );
        if (selectedByImdb != null) {
          _saveKinopoiskMatch(selectedByImdb, title, year, 'imdb_wikidata', 99);
          return selectedByImdb;
        }
      }
      final wikidataId = external['wikidata_id']?.toString() ?? '';
      if (wikidataId.startsWith('Q')) {
        final matches = await _kinopoisk.byWikidataId(wikidataId)
            .timeout(const Duration(seconds: 10));
        final selected = _selectKinopoiskMatch(
          matches, details: details, year: year, isSeries: _type == 'tv',
        );
        if (selected != null) {
          _saveKinopoiskMatch(selected, title, year, 'wikidata', 97);
          return selected;
        }
      }
    } catch (e) {
      debugPrint('[KinoKino] TMDB Wikidata ID lookup failed: $e');
    }

    // IMDb/Wikidata properties are incomplete for many catalogue entries.
    // As a final connected-source lookup, search Wikidata labels in Russian
    // and English and keep only candidates passing the title/year/type matcher.
    try {
      final candidates = await _kinopoisk.searchWikidata(title)
          .timeout(const Duration(seconds: 10));
      final selected = _selectKinopoiskMatch(
        candidates, details: details, year: year, isSeries: _type == 'tv',
      );
      if (selected != null) {
        _saveKinopoiskMatch(selected, title, year, 'wikidata_label_search', 80);
        return selected;
      }
    } catch (e) {
      debugPrint('[KinoKino] Kinopoisk label lookup unavailable: $e');
    }
    return null;
  }

  void _saveKinopoiskMatch(
    Map<String, dynamic> selected,
    String title,
    int year,
    String method,
    double confidence,
  ) {
    final rawId = selected['filmId'] ?? selected['kinopoiskId'] ??
        selected['kinopoisk_id'] ?? selected['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0;
    if (id <= 0) return;
    unawaited(_kinopoisk.cacheMatch(
      tmdbId: widget.item.id,
      mediaType: _type,
      kinopoiskId: id,
      title: title,
      releaseYear: year > 0 ? year : null,
      imdbId: selected['imdbId']?.toString(),
      wikidataId: selected['wikidataId']?.toString(),
      matchMethod: method,
      confidence: confidence,
    ));
  }

  Map<String, dynamic>? _selectKinopoiskMatch(
    List<Map<String, dynamic>> candidates, {
    required Map<String, dynamic>? details,
    required int year,
    required bool isSeries,
  }) {
    String norm(dynamic value) => (value ?? '').toString().toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё0-9]+', unicode: true), ' ')
        .trim();
    final expectedTitles = <String>{
      norm(details?['title']), norm(details?['name']),
      norm(details?['original_title']), norm(details?['original_name']),
      norm(widget.item.title),
    }..remove('');
    final unique = <int, Map<String, dynamic>>{};
    for (final candidate in candidates) {
      final rawId = candidate['filmId'] ?? candidate['kinopoiskId'] ??
          candidate['kinopoisk_id'] ?? candidate['id'];
      final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0;
      if (id > 0) unique[id] = candidate;
    }
    final ranked = unique.values.map((candidate) {
      final candidateTitles = <String>{
        norm(candidate['nameRu']), norm(candidate['nameEn']),
        norm(candidate['nameOriginal']), norm(candidate['name']),
      }..remove('');
      var titleScore = 0.0;
      for (final expected in expectedTitles) {
        final expectedWords = expected.split(' ').where((word) => word.length > 1).toSet();
        for (final actual in candidateTitles) {
          if (actual == expected) {
            titleScore = 100;
          } else if (actual.contains(expected) || expected.contains(actual)) {
            titleScore = titleScore < 85 ? 85 : titleScore;
          } else {
            final actualWords = actual.split(' ').where((word) => word.length > 1).toSet();
            if (expectedWords.isNotEmpty && actualWords.isNotEmpty) {
              final overlap = expectedWords.intersection(actualWords).length /
                  expectedWords.union(actualWords).length;
              final score = overlap * 80;
              if (score > titleScore) titleScore = score;
            }
          }
        }
      }
      final candidateYear = int.tryParse((candidate['year'] ??
          candidate['startYear'] ?? '').toString()) ?? 0;
      final rawType = (candidate['type'] ?? '').toString().toUpperCase();
      final candidateIsSeries = rawType.contains('TV') ||
          rawType.contains('SERIES') || rawType.contains('MINI');
      final typeKnown = rawType.isNotEmpty;
      final yearScore = year == 0 || candidateYear == 0
          ? 0 : (candidateYear == year ? 20 : -35);
      final typeScore = !typeKnown ? 0 : (candidateIsSeries == isSeries ? 15 : -35);
      return (candidate: candidate, score: titleScore + yearScore + typeScore);
    }).where((entry) => entry.score >= 65).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return ranked.isEmpty ? null : ranked.first.candidate;
  }

  Future<void> _load() async {
    // These are independent endpoints. A failure in the full details request
    // must not suppress recommendations or similar titles.
    final results = await Future.wait<dynamic>([
      _tmdb.details(widget.item.id, type: _type)
          .then<dynamic>((value) => value)
          .catchError((_) => null),
      _tmdb.recommendations(widget.item.id, type: _type)
          .then<dynamic>((value) => value)
          .catchError((_) => <MediaItem>[]),
      _tmdb.similar(widget.item.id, type: _type)
          .then<dynamic>((value) => value)
          .catchError((_) => <MediaItem>[]),
    ]);
    final details = results[0] is Map
        ? Map<String, dynamic>.from(results[0] as Map) : null;
    var recommendations = results[1] is List<MediaItem>
        ? List<MediaItem>.from(results[1] as List<MediaItem>) : <MediaItem>[];
    var similar = results[2] is List<MediaItem>
        ? List<MediaItem>.from(results[2] as List<MediaItem>) : <MediaItem>[];
    // Use appended results only as a fallback; the dedicated endpoints above
    // are requested regardless of whether the details endpoint succeeds.
    if (details != null) {
      if (recommendations.isEmpty) {
        recommendations = _relatedFallback(details, const ['recommendations']);
      }
      if (similar.isEmpty) {
        similar = _relatedFallback(details, const ['similar']);
      }
    }

    final recommendationsById = <String, MediaItem>{
      for (final item in recommendations)
        if (item.id > 0 && item.id != widget.item.id)
          '${item.mediaType}:${item.id}': item,
    };
    final similarById = <String, MediaItem>{
      for (final item in similar)
        if (item.id > 0 && item.id != widget.item.id)
          '${item.mediaType}:${item.id}': item,
    };
    // These optional fields are loaded by the playback flow, not by related
    // catalogue requests.
    if (mounted) setState(() {
      _details = details;
      _recommendations = recommendationsById.values.toList();
      _similar = similarById.values.toList();
      _error = details == null ? 'Не удалось загрузить подробности фильма.' : null;
      _loading = false;
    });

    if (_similar.length < 20) {
      unawaited(_loadKinopoiskSimilar(details));
    }
    if (_recommendations.isEmpty || _similar.length < 20) {
      unawaited(_loadWatchmodeSimilar());
    }
  }

  Future<MediaItem?> _mapRelatedCandidate(Map<String, dynamic> source) async {
    // Watchmode may already return the TMDB identifier. Prefer this exact
    // cross-catalogue mapping over fuzzy title matching.
    final rawTmdbId = source['tmdb_id'] ??
        (_type == 'tv' ? source['tmdb_tv_id'] : source['tmdb_movie_id']);
    final tmdbId = rawTmdbId is num
        ? rawTmdbId.toInt() : int.tryParse('$rawTmdbId') ?? 0;
    if (tmdbId > 0) {
      try {
        final details = await _tmdb.details(tmdbId, type: _type);
        details['media_type'] = _type;
        final exact = MediaItem.fromJson(details);
        if (exact.id > 0) return exact;
      } catch (_) {
        // Fall through to IMDb/title matching if the exact TMDB lookup fails.
      }
    }

    final imdbId = (source['imdbId'] ?? source['imdb_id'] ?? '').toString();
    final rawTitle = source['nameRu'] ?? source['nameEn'] ??
        source['nameOriginal'] ?? source['name'] ?? source['title'] ??
        source['title_name'] ?? '';
    final title = rawTitle.toString().trim();
    final rawYear = source['year'] ?? source['startYear'] ??
        source['release_year'];
    final year = rawYear is num ? rawYear.toInt() : int.tryParse('$rawYear');
    List<MediaItem> matches = const [];
    if (RegExp(r'^tt[0-9]{5,12}$').hasMatch(imdbId)) {
      try {
        matches = await _tmdb.findByExternalId(imdbId, mediaType: _type)
            .timeout(const Duration(seconds: 12));
      } catch (e) {
        debugPrint('[KinoKino] IMDb-to-TMDB mapping failed: $e');
      }
    }
    if (matches.isNotEmpty) {
      return matches.firstWhere(
        (item) => item.id != widget.item.id,
        orElse: () => matches.first,
      );
    }

    if (title.isNotEmpty) {
      try {
        matches = await _tmdb.searchRelated(
          title,
          mediaType: _type,
          year: year,
        ).timeout(const Duration(seconds: 12));
      } catch (e) {
        debugPrint('[KinoKino] Related title search failed: $e');
      }
    }
    final validMatches = matches.where((item) => item.id != widget.item.id).toList();
    return validMatches.isEmpty ? null : validMatches.first;
  }

  Future<void> _mergeExternalSimilar(
    List<Map<String, dynamic>> sourceItems,
    String sourceName, {
    bool useAsRecommendations = false,
  }) async {
    final tasks = sourceItems.take(15).map(_mapRelatedCandidate);
    final mapped = (await Future.wait(tasks)).whereType<MediaItem>()
        .where((item) => item.id != widget.item.id).toList();
    if (!mounted || mapped.isEmpty) return;

    if (useAsRecommendations && _recommendations.isEmpty) {
      final merged = <String, MediaItem>{
        for (final item in mapped)
          '${item.mediaType}:${item.id}': item,
      };
      setState(() => _recommendations = merged.values.take(20).toList());
      debugPrint('[KinoKino] Filled recommendations from $sourceName: ${mapped.length}');
      return;
    }

    final merged = <String, MediaItem>{
      for (final item in _similar)
        '${item.mediaType}:${item.id}': item,
      for (final item in mapped)
        '${item.mediaType}:${item.id}': item,
    };
    if (merged.length > _similar.length) {
      setState(() => _similar = merged.values.take(24).toList());
      debugPrint('[KinoKino] Added similar titles from $sourceName: ${mapped.length}');
    }
  }

  Future<void> _loadKinopoiskSimilar(Map<String, dynamic>? details) async {
    try {
      final match = await _findKinopoiskMatch(details)
          .timeout(const Duration(seconds: 15));
      final rawId = match?['filmId'] ?? match?['kinopoiskId'] ??
          match?['kinopoisk_id'] ?? match?['id'];
      final kinopoiskId = rawId is num
          ? rawId.toInt()
          : int.tryParse('$rawId') ?? 0;
      if (kinopoiskId <= 0) return;
      final sourceItems = await _kinopoisk.similars(kinopoiskId)
          .timeout(const Duration(seconds: 15));
      await _mergeExternalSimilar(sourceItems, 'Kinopoisk');
    } catch (e) {
      debugPrint('[KinoKino] Kinopoisk related titles unavailable: $e');
    }
  }

  Future<void> _loadWatchmodeSimilar() async {
    try {
      final sourceItems = await WatchmodeService().similarTitles(
        tmdbId: widget.item.id,
        mediaType: _type,
      ).timeout(const Duration(seconds: 20));
      await _mergeExternalSimilar(
        sourceItems,
        'Watchmode',
        useAsRecommendations: _recommendations.isEmpty,
      );
    } catch (e) {
      debugPrint('[KinoKino] Watchmode related titles unavailable: $e');
    }
  }

  List<MediaItem> _relatedFallback(Map<String, dynamic> details, List<String> keys) {
    final found = <int, MediaItem>{};
    for (final key in keys) {
      final section = details[key];
      final rows = section is Map ? section['results'] : null;
      if (rows is! List) continue;
      for (final row in rows.whereType<Map>()) {
        final data = Map<String, dynamic>.from(row);
        // The details endpoint determines the media type even when TMDB omits
        // media_type from its nested related-results payload.
        data['media_type'] = _type;
        final item = MediaItem.fromJson(data);
        final rawDate = (data['release_date'] ?? data['first_air_date'] ?? '').toString();
        final parsedDate = rawDate.length >= 10
            ? DateTime.tryParse(rawDate.substring(0, 10))
            : null;
        final now = DateTime.now();
        final isFuture = parsedDate != null &&
            DateTime(parsedDate.year, parsedDate.month, parsedDate.day)
                .isAfter(DateTime(now.year, now.month, now.day));
        if (item.id != widget.item.id && item.id > 0 && !isFuture) {
          found[item.id] = item;
        }
      }
    }
    return found.values.toList();
  }

  Widget _relatedSection(String title, List<MediaItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      SizedBox(height: 250, child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => PosterCard(
          item: items[i],
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
            MediaDetailsScreen(
              item: items[i],
              preferredAudioLanguage: widget.preferredAudioLanguage,
              preferredVideoQuality: widget.preferredVideoQuality,
            ))),
        ),
      )),
    ]);
  }

  Future<Map<String, dynamic>?> _chooseEpisode() async {
    final tmdbSeasons = (_details?['seasons'] as List? ?? const [])
        .whereType<Map>()
        .where((s) => (s['episode_count'] as num? ?? 0) > 0)
        .toList();
    final seasons = tmdbSeasons.isNotEmpty
        ? tmdbSeasons
        : _kpSeasons.where((s) => (s['episodes'] as List? ?? const []).isNotEmpty)
            .map((s) => <String, dynamic>{
              'season_number': s['number'],
              'episode_count': (s['episodes'] as List? ?? const []).length,
              'name': 'Сезон ${s['number']}',
              '_kinopoisk_season': s,
            }).toList();
    if (seasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TMDB пока не содержит список сезонов этого сериала.')));
      return null;
    }
    final season = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выбери сезон'),
        content: SizedBox(width: 420, child: ListView(
          shrinkWrap: true,
          children: seasons.map((s) => ListTile(
            title: Text((s['name'] ?? 'Сезон ${s['season_number']}').toString()),
            subtitle: Text('${s['episode_count']} эпизодов'),
            onTap: () => Navigator.pop(ctx, Map<String, dynamic>.from(s)),
          )).toList(),
        )),
      ),
    );
    if (season == null || !mounted) return null;
    final seasonNumber = (season['season_number'] as num?)?.toInt() ?? 1;
    final kpSeason = season['_kinopoisk_season'];
    List<Map<String, dynamic>> episodes;
    if (kpSeason is Map) {
      final today = DateTime.now();
      episodes = (kpSeason['episodes'] as List? ?? const [])
          .whereType<Map>()
          .map((episode) => <String, dynamic>{
            'episode_number': episode['episodeNumber'],
            'name': episode['nameRu'] ?? episode['nameEn'] ?? 'Эпизод',
            'air_date': episode['releaseDate'] ?? '',
            'season_number': episode['seasonNumber'] ?? seasonNumber,
            'runtime': 0,
            'overview': episode['synopsis'] ?? '',
          })
          .where((episode) {
            final raw = (episode['air_date'] ?? '').toString();
            if (raw.length < 10) return false;
            final date = DateTime.tryParse(raw.substring(0, 10));
            return date != null && !DateTime(date.year, date.month, date.day)
                .isAfter(DateTime(today.year, today.month, today.day));
          }).toList();
    } else {
      Map<String, dynamic> seasonData;
      try {
        seasonData = await _tmdb.seasonDetails(widget.item.id, seasonNumber);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить список эпизодов. Попробуй ещё раз.')));
        return null;
      }
      final today = DateTime.now();
      episodes = (seasonData['episodes'] as List? ?? const [])
          .whereType<Map>()
          .where((episode) {
            final raw = (episode['air_date'] ?? '').toString();
            if (raw.length < 10) return false;
            final date = DateTime.tryParse(raw.substring(0, 10));
            if (date == null) return false;
            return !DateTime(date.year, date.month, date.day)
                .isAfter(DateTime(today.year, today.month, today.day));
          }).map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (episodes.isEmpty || !mounted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('В этом сезоне нет доступных данных об эпизодах.')));
      return null;
    }
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text((season['name'] ?? 'Сезон $seasonNumber').toString()),
        content: SizedBox(width: 520, height: 420, child: ListView.builder(
          itemCount: episodes.length,
          itemBuilder: (_, i) {
            final ep = Map<String, dynamic>.from(episodes[i]);
            final number = (ep['episode_number'] as num?)?.toInt() ?? i + 1;
            final runtimeList = _details?['episode_run_time'] as List? ?? const [];
            final defaultRuntime = runtimeList.whereType<num>().isEmpty
                ? 0 : runtimeList.whereType<num>().first.toInt();
            final runtime = (ep['runtime'] as num?)?.toInt() ?? defaultRuntime;
            return ListTile(
              title: Text('$number. ${ep['name'] ?? 'Эпизод $number'}'),
              subtitle: Text(runtime > 0 ? '$runtime мин.' : 'Хронометраж не указан'),
              onTap: () => Navigator.pop(ctx, {
                ...ep,
                'season_number': seasonNumber,
                'runtime': runtime,
              }),
            );
          },
        )),
      ),
    );
  }
  Future<void> _saveRating(double value) async {
    setState(() => _rating = value);
    await LocalDatabase.setRating(widget.item.id, widget.item.title, widget.item.posterPath, value, mediaType: _type);
  }
  Future<ArchiveVideo?> _resolveEpisodeSource(Map<String, dynamic> episode) async {
    final runtime = (episode['runtime'] as num?)?.toInt() ?? 0;
    final date = (episode['air_date'] ?? '').toString();
    final year = int.tryParse(date.length >= 4 ? date.substring(0, 4) : '') ?? _releaseYear;
    final episodeName = (episode['name'] ?? '').toString().trim();
    if (episodeName.isEmpty || year <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для этой серии не хватает названия или года выпуска.')),
      );
      return null;
    }
    final season = (episode['season_number'] as num?)?.toInt() ?? 1;
    final number = (episode['episode_number'] as num?)?.toInt() ?? 1;
    final source = await InternetArchiveService().findLicensedVideo(
      episodeName,
      expectedRuntimeMinutes: runtime,
      expectedYear: year,
      displayTitle: '$_displayTitle · Сезон $season · Серия $number',
      preferredLanguage: _preferredArchiveLanguage,
      seriesTitle: _displayTitle,
      seasonNumber: season,
      episodeNumber: number,
    );
    if (!mounted || source == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лицензированная запись этой серии не найдена.')),
      );
      return null;
    }
    final resolvedSource = source;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Найден вариант серии'),
        content: Text(
          'Название в архиве: ${resolvedSource.archiveTitle}\n'
          'Год в метаданных: ${resolvedSource.releaseYear}\n'
          'Длительность: ${resolvedSource.durationSeconds > 0 ? '${(resolvedSource.durationSeconds / 60).round()} мин.' : 'не указана'}\n'
          'Лицензия: ${resolvedSource.license}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не та серия')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Это та серия')),
        ],
      ),
    );
    return approved == true ? resolvedSource : null;
  }

  bool _searchingPlayback = false;

  Future<Map<String, dynamic>?> _firstEpisode() async {
    final tmdbSeasons = (_details?['seasons'] as List? ?? const [])
        .whereType<Map>()
        .where((s) => (s['episode_count'] as num? ?? 0) > 0)
        .toList()
      ..sort((a, b) => ((a['season_number'] as num?)?.toInt() ?? 0)
          .compareTo((b['season_number'] as num?)?.toInt() ?? 0));
    if (tmdbSeasons.isEmpty) {
      final kpSeasons = [..._kpSeasons]
        ..sort((a, b) => ((a['number'] as num?)?.toInt() ?? 0)
            .compareTo((b['number'] as num?)?.toInt() ?? 0));
      final today = DateTime.now();
      for (final season in kpSeasons) {
        final episodes = (season['episodes'] as List? ?? const [])
            .whereType<Map>()
            .map((episode) => <String, dynamic>{
              'episode_number': episode['episodeNumber'],
              'name': episode['nameRu'] ?? episode['nameEn'] ?? 'Эпизод',
              'air_date': episode['releaseDate'] ?? '',
              'season_number': episode['seasonNumber'] ?? season['number'],
              'runtime': 0,
              'overview': episode['synopsis'] ?? '',
            }).where((episode) {
              final raw = (episode['air_date'] ?? '').toString();
              if (raw.length < 10) return false;
              final date = DateTime.tryParse(raw.substring(0, 10));
              return date != null && !DateTime(date.year, date.month, date.day)
                  .isAfter(DateTime(today.year, today.month, today.day));
            }).toList()
          ..sort((a, b) => ((a['episode_number'] as num?)?.toInt() ?? 0)
              .compareTo((b['episode_number'] as num?)?.toInt() ?? 0));
        if (episodes.isNotEmpty) return episodes.first;
      }
      return null;
    }
    final seasons = tmdbSeasons;
    final seasonNumber = (seasons.first['season_number'] as num?)?.toInt() ?? 1;
    try {
      final data = await _tmdb.seasonDetails(widget.item.id, seasonNumber);
      final today = DateTime.now();
      final episodes = (data['episodes'] as List? ?? const [])
          .whereType<Map>()
          .where((episode) {
            final raw = (episode['air_date'] ?? '').toString();
            if (raw.length < 10) return false;
            final date = DateTime.tryParse(raw.substring(0, 10));
            return date != null && !DateTime(date.year, date.month, date.day)
                .isAfter(DateTime(today.year, today.month, today.day));
          }).toList()
        ..sort((a, b) => ((a['episode_number'] as num?)?.toInt() ?? 0)
            .compareTo((b['episode_number'] as num?)?.toInt() ?? 0));
      if (episodes.isEmpty) return null;
      final ep = Map<String, dynamic>.from(episodes.first);
      final runtimeList = _details?['episode_run_time'] as List? ?? const [];
      final defaultRuntime = runtimeList.whereType<num>().isEmpty
          ? 0 : runtimeList.whereType<num>().first.toInt();
      return {
        ...ep,
        'season_number': seasonNumber,
        'runtime': (ep['runtime'] as num?)?.toInt() ?? defaultRuntime,
      };
    } catch (_) {
      return null;
    }
  }

  // ignore: unused_element
  Future<void> _startPlayback() async {
    if (_searchingPlayback) return;
    String sourceTitle = _playbackSearchTitle;
    int expectedRuntime = (_details?['runtime'] as num?)?.toInt() ?? 0;
    int expectedYear = _releaseYear;
    Map<String, dynamic>? selectedEpisode;
    if (_type == 'tv') {
      selectedEpisode = await _firstEpisode();
      if (!mounted) return;
      selectedEpisode ??= await _chooseEpisode();
      if (!mounted) return;
      if (selectedEpisode == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось определить вышедшую серию. Выбери сезон и серию вручную.'),
        ));
        return;
      }
      sourceTitle = (selectedEpisode['name'] ?? '').toString();
      expectedRuntime = (selectedEpisode['runtime'] as num?)?.toInt() ?? 0;
      final episodeDate = (selectedEpisode['air_date'] ?? '').toString();
      expectedYear = int.tryParse(episodeDate.length >= 4 ? episodeDate.substring(0, 4) : '') ?? _releaseYear;
    }
    if (!widget.item.hasConfirmedRelease) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Эта карточка не прошла проверку даты выхода и недоступна для просмотра.'),
      ));
      return;
    }
    final cancelToken = CancelToken();
    setState(() => _searchingPlayback = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => WillPopScope(
        onWillPop: () async {
          cancelToken.cancel('Пользователь вернулся назад');
          return true;
        },
        child: AlertDialog(
        content: const Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Подготавливаем просмотр…')),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () {
              cancelToken.cancel('Пользователь отменил поиск');
              Navigator.of(dialogContext).pop();
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Назад'),
          ),
        ],
      )),
    );
    var dialogClosed = false;
    try {
      final archive = InternetArchiveService();
      var source = await archive.findLicensedVideo(
        sourceTitle,
        expectedRuntimeMinutes: expectedRuntime,
        expectedYear: expectedYear,
        displayTitle: _displayTitle,
        preferredLanguage: _preferredArchiveLanguage,
        seriesTitle: _type == 'tv' ? _displayTitle : null,
        seasonNumber: selectedEpisode == null ? null : (selectedEpisode['season_number'] as num?)?.toInt(),
        episodeNumber: selectedEpisode == null ? null : (selectedEpisode['episode_number'] as num?)?.toInt(),
        cancelToken: cancelToken,
      );
      // Try the localized display title too: public archives often catalogue
      // dubbed releases under their translated title rather than the original.
      if (source == null && sourceTitle.toLowerCase() != _displayTitle.toLowerCase()) {
        source = await archive.findLicensedVideo(
          _displayTitle,
          expectedRuntimeMinutes: expectedRuntime,
          expectedYear: expectedYear,
          displayTitle: _displayTitle,
          preferredLanguage: widget.preferredAudioLanguage,
          seriesTitle: _type == 'tv' ? _displayTitle : null,
          seasonNumber: selectedEpisode == null ? null : (selectedEpisode['season_number'] as num?)?.toInt(),
          episodeNumber: selectedEpisode == null ? null : (selectedEpisode['episode_number'] as num?)?.toInt(),
          cancelToken: cancelToken,
        );
      }
      if (!mounted || cancelToken.isCancelled) return;
      Navigator.of(context, rootNavigator: true).pop();
      dialogClosed = true;
      if (source == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Встроенный плеер пока не нашёл доступный легальный видеопоток.'),
        ));
        return;
      }
      final playableSource = source;
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_type == 'tv' ? 'Вариант серии найден' : 'Вариант фильма найден'),
          content: Text(
            'Название в архиве: ${playableSource.archiveTitle}\n'
            'Год в метаданных: ${playableSource.releaseYear}\n'
            'Длительность: ${playableSource.durationSeconds > 0 ? '${(playableSource.durationSeconds / 60).round()} мин.' : 'не указана'}\n'
            'Лицензия: ${playableSource.license}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Не то видео'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_type == 'tv' ? 'Это та серия' : 'Это тот фильм'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(
        streamUrl: playableSource.url.toString(),
        title: selectedEpisode == null ? _displayTitle : '$_displayTitle · S${(selectedEpisode['season_number'] as num?)?.toInt() ?? 1}E${(selectedEpisode['episode_number'] as num?)?.toInt() ?? 1} — ${selectedEpisode['name'] ?? ''}',
        variants: playableSource.variants,
        preferredVideoQuality: widget.preferredVideoQuality,
        onChooseEpisode: _type == 'tv' ? _chooseEpisode : null,
        onResolveEpisode: _type == 'tv' ? _resolveEpisodeSource : null,
        onResolveAudio: (language) async {
          final isEpisode = selectedEpisode != null;
          final title = isEpisode ? (selectedEpisode['name'] ?? '').toString() : _playbackSearchTitle;
          final runtime = isEpisode ? (selectedEpisode['runtime'] as num?)?.toInt() ?? 0 : expectedRuntime;
          final date = isEpisode ? (selectedEpisode['air_date'] ?? '').toString() : '';
          final year = isEpisode ? int.tryParse(date.length >= 4 ? date.substring(0, 4) : '') ?? _releaseYear : _releaseYear;
          final languageCode = language == 'original' ? (_details?['original_language']?.toString() ?? 'auto') : language;
          return InternetArchiveService().findLicensedVideo(
            title,
            expectedRuntimeMinutes: runtime,
            expectedYear: year,
            displayTitle: _displayTitle,
            preferredLanguage: languageCode,
            seriesTitle: isEpisode ? _displayTitle : null,
            seasonNumber: isEpisode ? (selectedEpisode['season_number'] as num?)?.toInt() : null,
            episodeNumber: isEpisode ? (selectedEpisode['episode_number'] as num?)?.toInt() : null,
          );
        },
      )));
    } catch (e) {
      if (!mounted) return;
      if (cancelToken.isCancelled) return;
      if (!dialogClosed) Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось подготовить источник видео. Попробуйте ещё раз.')),
      );
    } finally {
      if (mounted) setState(() => _searchingPlayback = false);
    }
  }

  bool _resolvingKinopoisk = false;

  Future<void> _openKinoKino() async {
    if (_resolvingKinopoisk) return;
    var id = _kinopoiskId;
    if (id == null || id <= 0) {
      setState(() => _resolvingKinopoisk = true);
      try {
        final selected = await _findKinopoiskMatch(_details);
        final rawId = selected?['filmId'] ?? selected?['kinopoiskId'] ??
            selected?['kinopoisk_id'] ?? selected?['id'];
        id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
        if (id != null && id > 0 && mounted) {
          setState(() => _kinopoiskId = id);
        }
      } catch (e) {
        debugPrint('[KinoKino] could not resolve Kinopoisk ID: $e');
        if (mounted) {
          debugPrint('[KinoKino] ID lookup failed; no user-facing error dialog shown.');
        }
      } finally {
        if (mounted) setState(() => _resolvingKinopoisk = false);
      }
    }
    if (!mounted) return;
    if (id == null || id <= 0) {
      debugPrint('[KinoKino] no Kinopoisk ID for TMDB item ${widget.item.id}; trying title/IMDb search in KinoBox.');
    }
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ZagonkaScreen(
        title: _displayTitle,
        kinopoiskId: id,
        imdbId: _imdbId,
        year: _releaseYear,
        isSeries: _type == 'tv',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final d = _details ?? {};
    final genres = (d['genres'] as List? ?? const []).whereType<Map>().map((e) => e['name'].toString()).join(' · ');
    final cast = ((d['credits'] as Map?)?['cast'] as List? ?? const []).take(8).whereType<Map>().map((e) => e['name'].toString()).join(', ');
    final backdrop = d['backdrop_path'] ?? item.backdropPath;
    final poster = d['poster_path'] ?? item.posterPath;
    return Scaffold(
      appBar: AppBar(title: Text(_displayTitle)),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(children: [
        SizedBox(
          height: 290,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: backdrop != null
                  ? CachedNetworkImage(
                      imageUrl: 'https://image.tmdb.org/t/p/w780$backdrop',
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF172235)),
                    )
                  : const ColoredBox(color: Color(0xFF172235)),
              ),
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withOpacity(0.58)),
              ),
              if (poster != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: CachedNetworkImage(
                    imageUrl: 'https://image.tmdb.org/t/p/w500$poster',
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                    errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 64),
                  ),
                )
              else
                const Icon(Icons.movie, size: 64),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_displayTitle, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 12, children: [
            Chip(label: Text(item.mediaType == 'tv' ? 'Сериал' : 'Фильм')),
            if (item.releaseDate.isNotEmpty) Chip(label: Text(item.releaseDate.split('-').first)),
            if (_type == 'movie' && (_details?['runtime'] as num? ?? 0) > 0) Chip(label: Text('${_details!['runtime']} мин.')),
          ]),
          if (genres.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(genres)),
          const SizedBox(height: 16),
          Text(((d['overview'] ?? item.overview).toString().isNotEmpty
              ? (d['overview'] ?? item.overview).toString()
              : (_kpFilm?['description'] ?? _kpFilm?['shortDescription'] ?? 'Описание отсутствует.').toString())),
          if (cast.isNotEmpty) ...[
            const SizedBox(height: 18), const Text('В ролях', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6), Text(cast),
          ],
          const SizedBox(height: 12),
          const SizedBox(height: 20), const Text('Твоя оценка', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 4, children: List.generate(10, (i) {
            final value = (i + 1).toDouble();
            return IconButton(tooltip: '$value из 10', onPressed: () => _saveRating(value),
              icon: Icon(value <= _rating ? Icons.star : Icons.star_border, color: Colors.amber));
          })),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _resolvingKinopoisk ? null : _openKinoKino,
              icon: _resolvingKinopoisk
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: const Text('Начать просмотр'),
            ),
            OutlinedButton.icon(onPressed: () async {
              await LocalDatabase.setFavorite(item.id, item.title, item.posterPath, true, mediaType: _type);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Добавлено в избранное')));
            }, icon: const Icon(Icons.favorite), label: const Text('В избранное')),
          ]),
          if (_error != null) const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Некоторые сведения временно недоступны. Попробуйте обновить страницу позже.'),
          ),
        ])),
        if (_kpVideos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Видео-материалы (${_kpVideos.length})'),
              subtitle: const Text('Трейлеры и дополнительные ролики из каталога'),
              children: _kpVideos.take(8).map((video) {
                final name = (video['name'] ?? video['site'] ?? 'Видео').toString();
                final site = (video['site'] ?? '').toString();
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.video_library_outlined),
                  title: Text(name),
                  subtitle: site.isEmpty ? null : Text(site),
                );
              }).toList(),
            ),
          ),
        _relatedSection('Рекомендации', _recommendations),
        _relatedSection('Похожие', _similar),
      ]),
    );
  }
}
).hasMatch(imdbId)) {
      matches = await _tmdb.findByExternalId(imdbId, mediaType: _type);
    }
    if (matches.isEmpty && title.length >= 2) {
      matches = await _tmdb.searchRelated(
        title, mediaType: _type, year: year,
      );
    }
    if (matches.isEmpty) return null;
    return matches.first;
  }

  Future<void> _mergeExternalSimilar(
    List<Map<String, dynamic>> sourceItems,
    String sourceName, {
    bool useAsRecommendations = false,
  }) async {
    final tasks = sourceItems.take(15).map(_mapRelatedCandidate);
    final mapped = (await Future.wait(tasks)).whereType<MediaItem>()
        .where((item) => item.id != widget.item.id).toList();
    if (!mounted || mapped.isEmpty) return;

    if (useAsRecommendations && _recommendations.isEmpty) {
      final merged = <String, MediaItem>{
        for (final item in mapped)
          '${item.mediaType}:${item.id}': item,
      };
      setState(() => _recommendations = merged.values.take(20).toList());
      debugPrint('[KinoKino] Filled recommendations from $sourceName: ${mapped.length}');
      return;
    }

    final merged = <String, MediaItem>{
      for (final item in _similar)
        '${item.mediaType}:${item.id}': item,
      for (final item in mapped)
        '${item.mediaType}:${item.id}': item,
    };
    if (merged.length > _similar.length) {
      setState(() => _similar = merged.values.take(24).toList());
      debugPrint('[KinoKino] Added similar titles from $sourceName: ${mapped.length}');
    }
  }

  Future<void> _loadKinopoiskSimilar(Map<String, dynamic>? details) async {
    try {
      final match = await _findKinopoiskMatch(details)
          .timeout(const Duration(seconds: 15));
      final rawId = match?['filmId'] ?? match?['kinopoiskId'] ??
          match?['kinopoisk_id'] ?? match?['id'];
      final kinopoiskId = rawId is num
          ? rawId.toInt()
          : int.tryParse('$rawId') ?? 0;
      if (kinopoiskId <= 0) return;
      final sourceItems = await _kinopoisk.similars(kinopoiskId)
          .timeout(const Duration(seconds: 15));
      await _mergeExternalSimilar(sourceItems, 'Kinopoisk');
    } catch (e) {
      debugPrint('[KinoKino] Kinopoisk related titles unavailable: $e');
    }
  }

  Future<void> _loadWatchmodeSimilar() async {
    try {
      final sourceItems = await WatchmodeService().similarTitles(
        tmdbId: widget.item.id,
        mediaType: _type,
      ).timeout(const Duration(seconds: 20));
      await _mergeExternalSimilar(
        sourceItems,
        'Watchmode',
        useAsRecommendations: _recommendations.isEmpty,
      );
    } catch (e) {
      debugPrint('[KinoKino] Watchmode related titles unavailable: $e');
    }
  }

  List<MediaItem> _relatedFallback(Map<String, dynamic> details, List<String> keys) {
    final found = <int, MediaItem>{};
    for (final key in keys) {
      final section = details[key];
      final rows = section is Map ? section['results'] : null;
      if (rows is! List) continue;
      for (final row in rows.whereType<Map>()) {
        final data = Map<String, dynamic>.from(row);
        // The details endpoint determines the media type even when TMDB omits
        // media_type from its nested related-results payload.
        data['media_type'] = _type;
        final item = MediaItem.fromJson(data);
        final rawDate = (data['release_date'] ?? data['first_air_date'] ?? '').toString();
        final parsedDate = rawDate.length >= 10
            ? DateTime.tryParse(rawDate.substring(0, 10))
            : null;
        final now = DateTime.now();
        final isFuture = parsedDate != null &&
            DateTime(parsedDate.year, parsedDate.month, parsedDate.day)
                .isAfter(DateTime(now.year, now.month, now.day));
        if (item.id != widget.item.id && item.id > 0 && !isFuture) {
          found[item.id] = item;
        }
      }
    }
    return found.values.toList();
  }

  Widget _relatedSection(String title, List<MediaItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      SizedBox(height: 250, child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => PosterCard(
          item: items[i],
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
            MediaDetailsScreen(
              item: items[i],
              preferredAudioLanguage: widget.preferredAudioLanguage,
              preferredVideoQuality: widget.preferredVideoQuality,
            ))),
        ),
      )),
    ]);
  }

  Future<Map<String, dynamic>?> _chooseEpisode() async {
    final tmdbSeasons = (_details?['seasons'] as List? ?? const [])
        .whereType<Map>()
        .where((s) => (s['episode_count'] as num? ?? 0) > 0)
        .toList();
    final seasons = tmdbSeasons.isNotEmpty
        ? tmdbSeasons
        : _kpSeasons.where((s) => (s['episodes'] as List? ?? const []).isNotEmpty)
            .map((s) => <String, dynamic>{
              'season_number': s['number'],
              'episode_count': (s['episodes'] as List? ?? const []).length,
              'name': 'Сезон ${s['number']}',
              '_kinopoisk_season': s,
            }).toList();
    if (seasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TMDB пока не содержит список сезонов этого сериала.')));
      return null;
    }
    final season = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выбери сезон'),
        content: SizedBox(width: 420, child: ListView(
          shrinkWrap: true,
          children: seasons.map((s) => ListTile(
            title: Text((s['name'] ?? 'Сезон ${s['season_number']}').toString()),
            subtitle: Text('${s['episode_count']} эпизодов'),
            onTap: () => Navigator.pop(ctx, Map<String, dynamic>.from(s)),
          )).toList(),
        )),
      ),
    );
    if (season == null || !mounted) return null;
    final seasonNumber = (season['season_number'] as num?)?.toInt() ?? 1;
    final kpSeason = season['_kinopoisk_season'];
    List<Map<String, dynamic>> episodes;
    if (kpSeason is Map) {
      final today = DateTime.now();
      episodes = (kpSeason['episodes'] as List? ?? const [])
          .whereType<Map>()
          .map((episode) => <String, dynamic>{
            'episode_number': episode['episodeNumber'],
            'name': episode['nameRu'] ?? episode['nameEn'] ?? 'Эпизод',
            'air_date': episode['releaseDate'] ?? '',
            'season_number': episode['seasonNumber'] ?? seasonNumber,
            'runtime': 0,
            'overview': episode['synopsis'] ?? '',
          })
          .where((episode) {
            final raw = (episode['air_date'] ?? '').toString();
            if (raw.length < 10) return false;
            final date = DateTime.tryParse(raw.substring(0, 10));
            return date != null && !DateTime(date.year, date.month, date.day)
                .isAfter(DateTime(today.year, today.month, today.day));
          }).toList();
    } else {
      Map<String, dynamic> seasonData;
      try {
        seasonData = await _tmdb.seasonDetails(widget.item.id, seasonNumber);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить список эпизодов. Попробуй ещё раз.')));
        return null;
      }
      final today = DateTime.now();
      episodes = (seasonData['episodes'] as List? ?? const [])
          .whereType<Map>()
          .where((episode) {
            final raw = (episode['air_date'] ?? '').toString();
            if (raw.length < 10) return false;
            final date = DateTime.tryParse(raw.substring(0, 10));
            if (date == null) return false;
            return !DateTime(date.year, date.month, date.day)
                .isAfter(DateTime(today.year, today.month, today.day));
          }).map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (episodes.isEmpty || !mounted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('В этом сезоне нет доступных данных об эпизодах.')));
      return null;
    }
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text((season['name'] ?? 'Сезон $seasonNumber').toString()),
        content: SizedBox(width: 520, height: 420, child: ListView.builder(
          itemCount: episodes.length,
          itemBuilder: (_, i) {
            final ep = Map<String, dynamic>.from(episodes[i]);
            final number = (ep['episode_number'] as num?)?.toInt() ?? i + 1;
            final runtimeList = _details?['episode_run_time'] as List? ?? const [];
            final defaultRuntime = runtimeList.whereType<num>().isEmpty
                ? 0 : runtimeList.whereType<num>().first.toInt();
            final runtime = (ep['runtime'] as num?)?.toInt() ?? defaultRuntime;
            return ListTile(
              title: Text('$number. ${ep['name'] ?? 'Эпизод $number'}'),
              subtitle: Text(runtime > 0 ? '$runtime мин.' : 'Хронометраж не указан'),
              onTap: () => Navigator.pop(ctx, {
                ...ep,
                'season_number': seasonNumber,
                'runtime': runtime,
              }),
            );
          },
        )),
      ),
    );
  }
  Future<void> _saveRating(double value) async {
    setState(() => _rating = value);
    await LocalDatabase.setRating(widget.item.id, widget.item.title, widget.item.posterPath, value, mediaType: _type);
  }
  Future<ArchiveVideo?> _resolveEpisodeSource(Map<String, dynamic> episode) async {
    final runtime = (episode['runtime'] as num?)?.toInt() ?? 0;
    final date = (episode['air_date'] ?? '').toString();
    final year = int.tryParse(date.length >= 4 ? date.substring(0, 4) : '') ?? _releaseYear;
    final episodeName = (episode['name'] ?? '').toString().trim();
    if (episodeName.isEmpty || year <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для этой серии не хватает названия или года выпуска.')),
      );
      return null;
    }
    final season = (episode['season_number'] as num?)?.toInt() ?? 1;
    final number = (episode['episode_number'] as num?)?.toInt() ?? 1;
    final source = await InternetArchiveService().findLicensedVideo(
      episodeName,
      expectedRuntimeMinutes: runtime,
      expectedYear: year,
      displayTitle: '$_displayTitle · Сезон $season · Серия $number',
      preferredLanguage: _preferredArchiveLanguage,
      seriesTitle: _displayTitle,
      seasonNumber: season,
      episodeNumber: number,
    );
    if (!mounted || source == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лицензированная запись этой серии не найдена.')),
      );
      return null;
    }
    final resolvedSource = source;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Найден вариант серии'),
        content: Text(
          'Название в архиве: ${resolvedSource.archiveTitle}\n'
          'Год в метаданных: ${resolvedSource.releaseYear}\n'
          'Длительность: ${resolvedSource.durationSeconds > 0 ? '${(resolvedSource.durationSeconds / 60).round()} мин.' : 'не указана'}\n'
          'Лицензия: ${resolvedSource.license}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не та серия')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Это та серия')),
        ],
      ),
    );
    return approved == true ? resolvedSource : null;
  }

  bool _searchingPlayback = false;

  Future<Map<String, dynamic>?> _firstEpisode() async {
    final tmdbSeasons = (_details?['seasons'] as List? ?? const [])
        .whereType<Map>()
        .where((s) => (s['episode_count'] as num? ?? 0) > 0)
        .toList()
      ..sort((a, b) => ((a['season_number'] as num?)?.toInt() ?? 0)
          .compareTo((b['season_number'] as num?)?.toInt() ?? 0));
    if (tmdbSeasons.isEmpty) {
      final kpSeasons = [..._kpSeasons]
        ..sort((a, b) => ((a['number'] as num?)?.toInt() ?? 0)
            .compareTo((b['number'] as num?)?.toInt() ?? 0));
      final today = DateTime.now();
      for (final season in kpSeasons) {
        final episodes = (season['episodes'] as List? ?? const [])
            .whereType<Map>()
            .map((episode) => <String, dynamic>{
              'episode_number': episode['episodeNumber'],
              'name': episode['nameRu'] ?? episode['nameEn'] ?? 'Эпизод',
              'air_date': episode['releaseDate'] ?? '',
              'season_number': episode['seasonNumber'] ?? season['number'],
              'runtime': 0,
              'overview': episode['synopsis'] ?? '',
            }).where((episode) {
              final raw = (episode['air_date'] ?? '').toString();
              if (raw.length < 10) return false;
              final date = DateTime.tryParse(raw.substring(0, 10));
              return date != null && !DateTime(date.year, date.month, date.day)
                  .isAfter(DateTime(today.year, today.month, today.day));
            }).toList()
          ..sort((a, b) => ((a['episode_number'] as num?)?.toInt() ?? 0)
              .compareTo((b['episode_number'] as num?)?.toInt() ?? 0));
        if (episodes.isNotEmpty) return episodes.first;
      }
      return null;
    }
    final seasons = tmdbSeasons;
    final seasonNumber = (seasons.first['season_number'] as num?)?.toInt() ?? 1;
    try {
      final data = await _tmdb.seasonDetails(widget.item.id, seasonNumber);
      final today = DateTime.now();
      final episodes = (data['episodes'] as List? ?? const [])
          .whereType<Map>()
          .where((episode) {
            final raw = (episode['air_date'] ?? '').toString();
            if (raw.length < 10) return false;
            final date = DateTime.tryParse(raw.substring(0, 10));
            return date != null && !DateTime(date.year, date.month, date.day)
                .isAfter(DateTime(today.year, today.month, today.day));
          }).toList()
        ..sort((a, b) => ((a['episode_number'] as num?)?.toInt() ?? 0)
            .compareTo((b['episode_number'] as num?)?.toInt() ?? 0));
      if (episodes.isEmpty) return null;
      final ep = Map<String, dynamic>.from(episodes.first);
      final runtimeList = _details?['episode_run_time'] as List? ?? const [];
      final defaultRuntime = runtimeList.whereType<num>().isEmpty
          ? 0 : runtimeList.whereType<num>().first.toInt();
      return {
        ...ep,
        'season_number': seasonNumber,
        'runtime': (ep['runtime'] as num?)?.toInt() ?? defaultRuntime,
      };
    } catch (_) {
      return null;
    }
  }

  // ignore: unused_element
  Future<void> _startPlayback() async {
    if (_searchingPlayback) return;
    String sourceTitle = _playbackSearchTitle;
    int expectedRuntime = (_details?['runtime'] as num?)?.toInt() ?? 0;
    int expectedYear = _releaseYear;
    Map<String, dynamic>? selectedEpisode;
    if (_type == 'tv') {
      selectedEpisode = await _firstEpisode();
      if (!mounted) return;
      selectedEpisode ??= await _chooseEpisode();
      if (!mounted) return;
      if (selectedEpisode == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось определить вышедшую серию. Выбери сезон и серию вручную.'),
        ));
        return;
      }
      sourceTitle = (selectedEpisode['name'] ?? '').toString();
      expectedRuntime = (selectedEpisode['runtime'] as num?)?.toInt() ?? 0;
      final episodeDate = (selectedEpisode['air_date'] ?? '').toString();
      expectedYear = int.tryParse(episodeDate.length >= 4 ? episodeDate.substring(0, 4) : '') ?? _releaseYear;
    }
    if (!widget.item.hasConfirmedRelease) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Эта карточка не прошла проверку даты выхода и недоступна для просмотра.'),
      ));
      return;
    }
    final cancelToken = CancelToken();
    setState(() => _searchingPlayback = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => WillPopScope(
        onWillPop: () async {
          cancelToken.cancel('Пользователь вернулся назад');
          return true;
        },
        child: AlertDialog(
        content: const Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Подготавливаем просмотр…')),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () {
              cancelToken.cancel('Пользователь отменил поиск');
              Navigator.of(dialogContext).pop();
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Назад'),
          ),
        ],
      )),
    );
    var dialogClosed = false;
    try {
      final archive = InternetArchiveService();
      var source = await archive.findLicensedVideo(
        sourceTitle,
        expectedRuntimeMinutes: expectedRuntime,
        expectedYear: expectedYear,
        displayTitle: _displayTitle,
        preferredLanguage: _preferredArchiveLanguage,
        seriesTitle: _type == 'tv' ? _displayTitle : null,
        seasonNumber: selectedEpisode == null ? null : (selectedEpisode['season_number'] as num?)?.toInt(),
        episodeNumber: selectedEpisode == null ? null : (selectedEpisode['episode_number'] as num?)?.toInt(),
        cancelToken: cancelToken,
      );
      // Try the localized display title too: public archives often catalogue
      // dubbed releases under their translated title rather than the original.
      if (source == null && sourceTitle.toLowerCase() != _displayTitle.toLowerCase()) {
        source = await archive.findLicensedVideo(
          _displayTitle,
          expectedRuntimeMinutes: expectedRuntime,
          expectedYear: expectedYear,
          displayTitle: _displayTitle,
          preferredLanguage: widget.preferredAudioLanguage,
          seriesTitle: _type == 'tv' ? _displayTitle : null,
          seasonNumber: selectedEpisode == null ? null : (selectedEpisode['season_number'] as num?)?.toInt(),
          episodeNumber: selectedEpisode == null ? null : (selectedEpisode['episode_number'] as num?)?.toInt(),
          cancelToken: cancelToken,
        );
      }
      if (!mounted || cancelToken.isCancelled) return;
      Navigator.of(context, rootNavigator: true).pop();
      dialogClosed = true;
      if (source == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Встроенный плеер пока не нашёл доступный легальный видеопоток.'),
        ));
        return;
      }
      final playableSource = source;
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_type == 'tv' ? 'Вариант серии найден' : 'Вариант фильма найден'),
          content: Text(
            'Название в архиве: ${playableSource.archiveTitle}\n'
            'Год в метаданных: ${playableSource.releaseYear}\n'
            'Длительность: ${playableSource.durationSeconds > 0 ? '${(playableSource.durationSeconds / 60).round()} мин.' : 'не указана'}\n'
            'Лицензия: ${playableSource.license}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Не то видео'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_type == 'tv' ? 'Это та серия' : 'Это тот фильм'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(
        streamUrl: playableSource.url.toString(),
        title: selectedEpisode == null ? _displayTitle : '$_displayTitle · S${(selectedEpisode['season_number'] as num?)?.toInt() ?? 1}E${(selectedEpisode['episode_number'] as num?)?.toInt() ?? 1} — ${selectedEpisode['name'] ?? ''}',
        variants: playableSource.variants,
        preferredVideoQuality: widget.preferredVideoQuality,
        onChooseEpisode: _type == 'tv' ? _chooseEpisode : null,
        onResolveEpisode: _type == 'tv' ? _resolveEpisodeSource : null,
        onResolveAudio: (language) async {
          final isEpisode = selectedEpisode != null;
          final title = isEpisode ? (selectedEpisode['name'] ?? '').toString() : _playbackSearchTitle;
          final runtime = isEpisode ? (selectedEpisode['runtime'] as num?)?.toInt() ?? 0 : expectedRuntime;
          final date = isEpisode ? (selectedEpisode['air_date'] ?? '').toString() : '';
          final year = isEpisode ? int.tryParse(date.length >= 4 ? date.substring(0, 4) : '') ?? _releaseYear : _releaseYear;
          final languageCode = language == 'original' ? (_details?['original_language']?.toString() ?? 'auto') : language;
          return InternetArchiveService().findLicensedVideo(
            title,
            expectedRuntimeMinutes: runtime,
            expectedYear: year,
            displayTitle: _displayTitle,
            preferredLanguage: languageCode,
            seriesTitle: isEpisode ? _displayTitle : null,
            seasonNumber: isEpisode ? (selectedEpisode['season_number'] as num?)?.toInt() : null,
            episodeNumber: isEpisode ? (selectedEpisode['episode_number'] as num?)?.toInt() : null,
          );
        },
      )));
    } catch (e) {
      if (!mounted) return;
      if (cancelToken.isCancelled) return;
      if (!dialogClosed) Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось подготовить источник видео. Попробуйте ещё раз.')),
      );
    } finally {
      if (mounted) setState(() => _searchingPlayback = false);
    }
  }

  bool _resolvingKinopoisk = false;

  Future<void> _openKinoKino() async {
    if (_resolvingKinopoisk) return;
    var id = _kinopoiskId;
    if (id == null || id <= 0) {
      setState(() => _resolvingKinopoisk = true);
      try {
        final selected = await _findKinopoiskMatch(_details);
        final rawId = selected?['filmId'] ?? selected?['kinopoiskId'] ??
            selected?['kinopoisk_id'] ?? selected?['id'];
        id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
        if (id != null && id > 0 && mounted) {
          setState(() => _kinopoiskId = id);
        }
      } catch (e) {
        debugPrint('[KinoKino] could not resolve Kinopoisk ID: $e');
        if (mounted) {
          debugPrint('[KinoKino] ID lookup failed; no user-facing error dialog shown.');
        }
      } finally {
        if (mounted) setState(() => _resolvingKinopoisk = false);
      }
    }
    if (!mounted) return;
    if (id == null || id <= 0) {
      debugPrint('[KinoKino] no Kinopoisk ID for TMDB item ${widget.item.id}; trying title/IMDb search in KinoBox.');
    }
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ZagonkaScreen(
        title: _displayTitle,
        kinopoiskId: id,
        imdbId: _imdbId,
        year: _releaseYear,
        isSeries: _type == 'tv',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final d = _details ?? {};
    final genres = (d['genres'] as List? ?? const []).whereType<Map>().map((e) => e['name'].toString()).join(' · ');
    final cast = ((d['credits'] as Map?)?['cast'] as List? ?? const []).take(8).whereType<Map>().map((e) => e['name'].toString()).join(', ');
    final backdrop = d['backdrop_path'] ?? item.backdropPath;
    final poster = d['poster_path'] ?? item.posterPath;
    return Scaffold(
      appBar: AppBar(title: Text(_displayTitle)),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(children: [
        SizedBox(
          height: 290,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: backdrop != null
                  ? CachedNetworkImage(
                      imageUrl: 'https://image.tmdb.org/t/p/w780$backdrop',
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF172235)),
                    )
                  : const ColoredBox(color: Color(0xFF172235)),
              ),
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withOpacity(0.58)),
              ),
              if (poster != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: CachedNetworkImage(
                    imageUrl: 'https://image.tmdb.org/t/p/w500$poster',
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                    errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 64),
                  ),
                )
              else
                const Icon(Icons.movie, size: 64),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_displayTitle, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 12, children: [
            Chip(label: Text(item.mediaType == 'tv' ? 'Сериал' : 'Фильм')),
            if (item.releaseDate.isNotEmpty) Chip(label: Text(item.releaseDate.split('-').first)),
            if (_type == 'movie' && (_details?['runtime'] as num? ?? 0) > 0) Chip(label: Text('${_details!['runtime']} мин.')),
          ]),
          if (genres.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(genres)),
          const SizedBox(height: 16),
          Text(((d['overview'] ?? item.overview).toString().isNotEmpty
              ? (d['overview'] ?? item.overview).toString()
              : (_kpFilm?['description'] ?? _kpFilm?['shortDescription'] ?? 'Описание отсутствует.').toString())),
          if (cast.isNotEmpty) ...[
            const SizedBox(height: 18), const Text('В ролях', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6), Text(cast),
          ],
          const SizedBox(height: 12),
          const SizedBox(height: 20), const Text('Твоя оценка', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 4, children: List.generate(10, (i) {
            final value = (i + 1).toDouble();
            return IconButton(tooltip: '$value из 10', onPressed: () => _saveRating(value),
              icon: Icon(value <= _rating ? Icons.star : Icons.star_border, color: Colors.amber));
          })),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _resolvingKinopoisk ? null : _openKinoKino,
              icon: _resolvingKinopoisk
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: const Text('Начать просмотр'),
            ),
            OutlinedButton.icon(onPressed: () async {
              await LocalDatabase.setFavorite(item.id, item.title, item.posterPath, true, mediaType: _type);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Добавлено в избранное')));
            }, icon: const Icon(Icons.favorite), label: const Text('В избранное')),
          ]),
          if (_error != null) const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Некоторые сведения временно недоступны. Попробуйте обновить страницу позже.'),
          ),
        ])),
        if (_kpVideos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Видео-материалы (${_kpVideos.length})'),
              subtitle: const Text('Трейлеры и дополнительные ролики из каталога'),
              children: _kpVideos.take(8).map((video) {
                final name = (video['name'] ?? video['site'] ?? 'Видео').toString();
                final site = (video['site'] ?? '').toString();
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.video_library_outlined),
                  title: Text(name),
                  subtitle: site.isEmpty ? null : Text(site),
                );
              }).toList(),
            ),
          ),
        _relatedSection('Рекомендации', _recommendations),
        _relatedSection('Похожие', _similar),
      ]),
    );
  }
}
