import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
import '../services/internet_archive_service.dart';
import '../services/local_database.dart';
import '../widgets/poster_card.dart';
import 'player_screen.dart';
class MediaDetailsScreen extends StatefulWidget {
  const MediaDetailsScreen({super.key, required this.item});
  final MediaItem item;
  @override State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}
class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  final _tmdb = TmdbService();
  Map<String, dynamic>? _details;
  List<MediaItem> _recommendations = [];
  Map<String, dynamic> _externalIds = {};
  bool _loading = true;
  String? _error;
  double _rating = 0;
  String get _type => ['tv', 'animated_tv'].contains(widget.item.mediaType.toLowerCase()) ? 'tv' : 'movie';
  String get _displayTitle {
    final d = _details ?? {};
    return (d['title'] ?? d['name'] ?? widget.item.title).toString();
  }
  int get _releaseYear {
    final date = (_details?['release_date'] ?? _details?['first_air_date'] ?? widget.item.releaseDate).toString();
    return int.tryParse(date.length >= 4 ? date.substring(0, 4) : '') ?? 0;
  }
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
  Future<void> _load() async {
    Map<String, dynamic>? details;
    List<MediaItem> picks = [];
    String? error;
    Map<String, dynamic> externalIds = {};
    try {
      details = await _tmdb.details(widget.item.id, type: _type);
      try { externalIds = await _tmdb.externalIds(widget.item.id, type: _type); } catch (_) {}
    } catch (e) {
      error = e.toString();
    }
    // Recommendations are loaded independently: a failure in one endpoint
    // must not hide the rest of the details page.
    try {
      picks = await _tmdb.recommendations(widget.item.id, type: _type);
    } catch (_) {}
    if (picks.isEmpty) {
      try { picks = await _tmdb.similar(widget.item.id, type: _type); } catch (_) {}
    }
    if (picks.isEmpty && details != null) {
      final section = details['recommendations'] ?? details['similar'];
      final rows = (section is Map ? section['results'] : null) as List? ?? const [];
      picks = rows.whereType<Map>().map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)
        ..putIfAbsent('media_type', () => _type))).where((e) => e.id != widget.item.id).toList();
    }
    if (mounted) setState(() {
      _details = details;
      _recommendations = picks;
      _externalIds = externalIds;
      _error = error;
      _loading = false;
    });
  }

  Future<Map<String, dynamic>?> _chooseEpisode() async {
    final seasons = (_details?['seasons'] as List? ?? const [])
        .whereType<Map>()
        .where((s) => (s['episode_count'] as num? ?? 0) > 0)
        .toList();
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
    Map<String, dynamic> seasonData;
    try {
      seasonData = await _tmdb.seasonDetails(widget.item.id, seasonNumber);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить список эпизодов. Попробуй ещё раз.')));
      return null;
    }
    final episodes = (seasonData['episodes'] as List? ?? const []).whereType<Map>().toList();
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
  Future<void> _openRatingPage(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть страницу рейтинга.')));
    }
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
    if (episodeName.isEmpty || runtime <= 0 || year <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для этой серии не хватает названия, года или длительности.')),
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
      isSeries: true,
    );
    if (!mounted || source == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лицензированная запись этой серии не найдена.')),
      );
      return null;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Проверь найденную серию'),
        content: Text(
          'Название в архиве: ${source.archiveTitle}\\n'
          'Год в метаданных: ${source.releaseYear}\\n'
          'Длительность: ${(source.durationSeconds / 60).round()} мин.\\n'
          'Лицензия: ${source.license}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не та серия')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Это та серия')),
        ],
      ),
    );
    return approved == true ? source : null;
  }

  bool _searchingPlayback = false;

  Future<void> _startPlayback() async {
    if (_searchingPlayback) return;
    String sourceTitle = _playbackSearchTitle;
    int expectedRuntime = (_details?['runtime'] as num?)?.toInt() ?? 0;
    int expectedYear = _releaseYear;
    Map<String, dynamic>? selectedEpisode;
    if (_type == 'tv') {
      selectedEpisode = await _chooseEpisode();
      if (selectedEpisode == null || !mounted) return;
      sourceTitle = (selectedEpisode['name'] ?? '').toString();
      expectedRuntime = (selectedEpisode['runtime'] as num?)?.toInt() ?? 0;
      final episodeDate = (selectedEpisode['air_date'] ?? '').toString();
      expectedYear = int.tryParse(episodeDate.length >= 4 ? episodeDate.substring(0, 4) : '') ?? _releaseYear;
    }
    if (expectedYear <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неизвестен год выхода. Не буду запускать неподтверждённую версию.')));
      return;
    }
    if (expectedRuntime <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неизвестен хронометраж. Не буду запускать непроверенный ролик.')));
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
          Expanded(child: Text('Ищем точное совпадение по названию, году и длительности…')),
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
      final source = await InternetArchiveService().findLicensedVideo(
        sourceTitle,
        expectedRuntimeMinutes: expectedRuntime,
        expectedYear: expectedYear,
        displayTitle: _displayTitle,
        cancelToken: cancelToken,
        isSeries: _type == 'tv',
      );
      if (!mounted || cancelToken.isCancelled) return;
      Navigator.of(context, rootNavigator: true).pop();
      dialogClosed = true;
      if (source == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_type == 'tv'
            ? 'В открытом каталоге пока не найден эпизод этого сериала.'
            : 'В открытом каталоге пока не найден совместимый фильм.'),
        ));
        return;
      }
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Проверь найденное видео'),
          content: Text(
            'Название в архиве: ${source.archiveTitle}\n'
            'Год в метаданных: ${source.releaseYear}\n'
            'Длительность: ${(source.durationSeconds / 60).round()} мин.\n'
            'Лицензия: ${source.license}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Не то видео'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Это тот фильм'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        PlayerScreen(streamUrl: source.url.toString(), title: selectedEpisode == null ? _displayTitle : '$_displayTitle · S${(selectedEpisode['season_number'] as num?)?.toInt() ?? 1}E${(selectedEpisode['episode_number'] as num?)?.toInt() ?? 1} — ${selectedEpisode['name'] ?? ''}', variants: source.variants, onChooseEpisode: _type == 'tv' ? _chooseEpisode : null, onResolveEpisode: _type == 'tv' ? _resolveEpisodeSource : null)));
    } catch (e) {
      if (!mounted) return;
      if (cancelToken.isCancelled) return;
      if (!dialogClosed) Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось найти видео: $e')),
      );
    } finally {
      if (mounted) setState(() => _searchingPlayback = false);
    }
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
            Chip(label: Text('TMDB ★ ${item.voteAverage.toStringAsFixed(1)}')),
            Chip(label: Text(item.mediaType == 'tv' ? 'Сериал' : 'Фильм')),
            if (item.releaseDate.isNotEmpty) Chip(label: Text(item.releaseDate.split('-').first)),
            if (_type == 'movie' && (_details?['runtime'] as num? ?? 0) > 0) Chip(label: Text('${_details!['runtime']} мин.')),
          ]),
          if (genres.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(genres)),
          const SizedBox(height: 16),
          Text((d['overview'] ?? item.overview).toString().isEmpty ? 'Описание отсутствует.' : (d['overview'] ?? item.overview).toString()),
          if (cast.isNotEmpty) ...[
            const SizedBox(height: 18), const Text('В ролях', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6), Text(cast),
          ],
          const SizedBox(height: 12),
          const Text('Внешние рейтинги', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if ((_externalIds['imdb_id'] ?? '').toString().startsWith('tt'))
              OutlinedButton.icon(
                onPressed: () => _openRatingPage(Uri.parse('https://www.imdb.com/title/${_externalIds['imdb_id']}/')),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Оценка IMDb'),
              ),
            OutlinedButton.icon(
              onPressed: () => _openRatingPage(Uri.https('www.google.com', '/search', {
                'q': 'Кинопоиск $_displayTitle $_releaseYear рейтинг',
              })),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Найти оценку Кинопоиска'),
            ),
          ]),
          const SizedBox(height: 20), const Text('Твоя оценка', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 4, children: List.generate(10, (i) {
            final value = (i + 1).toDouble();
            return IconButton(tooltip: '$value из 10', onPressed: () => _saveRating(value),
              icon: Icon(value <= _rating ? Icons.star : Icons.star_border, color: Colors.amber));
          })),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _searchingPlayback ? null : _startPlayback, icon: _searchingPlayback ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow), label: const Text('Начать просмотр')),
            OutlinedButton.icon(onPressed: () async {
              await LocalDatabase.setFavorite(item.id, item.title, item.posterPath, true, mediaType: _type);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Добавлено в избранное')));
            }, icon: const Icon(Icons.favorite), label: const Text('В избранное')),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Не удалось загрузить дополнительные данные: $_error')),
        ])),
        if (_recommendations.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(18, 8, 18, 12), child: Text('Похожие и рекомендованные', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          SizedBox(height: 250, child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18), scrollDirection: Axis.horizontal,
            itemCount: _recommendations.length, separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => PosterCard(item: _recommendations[i], onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => MediaDetailsScreen(item: _recommendations[i])))),
          )),
        ],
      ]),
    );
  }
}
