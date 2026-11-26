import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
import '../services/internet_archive_service.dart';
import '../services/watchmode_service.dart';
import '../services/local_database.dart';
import '../widgets/poster_card.dart';
import 'player_screen.dart';
class MediaDetailsScreen extends StatefulWidget {
  const MediaDetailsScreen({super.key, required this.item, this.preferredAudioLanguage = 'auto', this.preferredVideoQuality = 'auto'});
  final MediaItem item;
  final String preferredAudioLanguage;
  final String preferredVideoQuality;
  @override State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}
class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  final _tmdb = TmdbService();
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
  Future<void> _load() async {
    Map<String, dynamic>? details;
    String? error;
    try {
      details = await _tmdb.details(widget.item.id, type: _type);
    } catch (e) {
      error = e.toString();
    }
    // Keep similar titles and recommendations separate so neither endpoint
    // can hide the other and each section can be loaded independently.
    List<MediaItem> recommendations = [];
    List<MediaItem> similar = [];
    try {
      recommendations = await _tmdb.recommendations(widget.item.id, type: _type);
    } catch (_) {}
    try {
      similar = await _tmdb.similar(widget.item.id, type: _type);
    } catch (_) {}
    if (details != null) {
      if (recommendations.isEmpty) {
        recommendations = _relatedFallback(details, 'recommendations');
      }
      if (similar.isEmpty) {
        similar = _relatedFallback(details, 'similar');
      }
    }
    final recommendationsById = <String, MediaItem>{
      for (final item in recommendations)
        if (item.id != widget.item.id) '${item.mediaType}:${item.id}': item,
    };
    final similarById = <String, MediaItem>{
      for (final item in similar)
        if (item.id != widget.item.id) '${item.mediaType}:${item.id}': item,
    };
    if (mounted) setState(() {
      _details = details;
      _recommendations = recommendationsById.values.toList();
      _similar = similarById.values.toList();
      _error = error;
      _loading = false;
    });
  }

  List<MediaItem> _relatedFallback(Map<String, dynamic> details, String key) {
    final section = details[key];
    final rows = (section is Map ? section['results'] : null) as List? ?? const [];
    final found = <String, MediaItem>{};
    for (final row in rows.whereType<Map>()) {
      final data = Map<String, dynamic>.from(row);
      data.putIfAbsent('media_type', () => _type);
      final item = MediaItem.fromJson(data);
      if (item.id != widget.item.id && item.hasRussianTitle &&
          item.hasConfirmedRelease &&
          (item.mediaType == 'movie' || item.mediaType == 'tv')) {
        found['${item.mediaType}:${item.id}'] = item;
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
    final today = DateTime.now();
    final episodes = (seasonData['episodes'] as List? ?? const [])
        .whereType<Map>()
        .where((episode) {
          final raw = (episode['air_date'] ?? '').toString();
          if (raw.length < 10) return false;
          final date = DateTime.tryParse(raw.substring(0, 10));
          if (date == null) return false;
          return !DateTime(date.year, date.month, date.day)
              .isAfter(DateTime(today.year, today.month, today.day));
        }).toList();
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
  Future<void> _openExternalPage(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть страницу.')));
    }
  }

  Future<void> _openRatingPage(Uri uri) => _openExternalPage(uri);
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
    final seasons = (_details?['seasons'] as List? ?? const [])
        .whereType<Map>()
        .where((s) => (s['episode_count'] as num? ?? 0) > 0)
        .toList()
      ..sort((a, b) => ((a['season_number'] as num?)?.toInt() ?? 0)
          .compareTo((b['season_number'] as num?)?.toInt() ?? 0));
    if (seasons.isEmpty) return null;
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

  Future<void> _showLegalViewingOptions() async {
    final options = <Map<String, dynamic>>[];
    String? guideUrl;
    try {
      final free = await WatchmodeService().freeSources(
        tmdbId: widget.item.id,
        mediaType: _type,
        region: 'NL',
      );
      options.addAll(free);
    } catch (_) {}
    try {
      final providers = await _tmdb.watchProviders(widget.item.id, type: _type, region: 'NL');
      guideUrl = providers['link']?.toString();
      for (final group in ['flatrate', 'rent', 'buy']) {
        for (final provider in providers[group] as List? ?? const []) {
          if (provider is Map) {
            options.add({
              'name': provider['provider_name'] ?? 'Видеосервис',
              'type': group,
              'web_url': guideUrl,
            });
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    if (options.isEmpty && (guideUrl == null || guideUrl.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Легальный источник не найден. Для этого названия нет доступного потока или подтверждённого сервиса.'),
      ));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Где посмотреть легально'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (options.isNotEmpty)
                ...options.map((option) {
                  final name = (option['name'] ?? option['source'] ?? 'Видеосервис').toString();
                  final type = (option['type'] ?? '').toString();
                  final url = (option['web_url'] ?? option['url'] ?? guideUrl ?? '').toString();
                  return ListTile(
                    leading: const Icon(Icons.ondemand_video_outlined),
                    title: Text(name),
                    subtitle: Text(type == 'free' ? 'Бесплатно' : type == 'rent' ? 'Аренда' : type == 'buy' ? 'Покупка' : 'Подписка'),
                    onTap: url.startsWith('https://') ? () {
                      Navigator.pop(ctx);
                      _openExternalPage(Uri.parse(url));
                    } : null,
                  );
                }),
              if (guideUrl != null && guideUrl.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Открыть список всех сервисов'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openExternalPage(Uri.parse(guideUrl!));
                  },
                ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Эти сервисы открываются на своих официальных страницах; встроенный плеер не получает от них видеопоток.'),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
      ),
    );
  }

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
        await _showLegalViewingOptions();
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
          if (_error != null) const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Некоторые сведения временно недоступны. Попробуйте обновить страницу позже.'),
          ),
        ])),
        _relatedSection('Рекомендации', _recommendations),
        _relatedSection('Похожие', _similar),
      ]),
    );
  }
}
