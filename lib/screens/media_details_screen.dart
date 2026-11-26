import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
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
  bool _loading = true;
  String? _error;
  double _rating = 0;
  Map<String, dynamic> _providers = {};
  String _region = 'NL';
  String get _type => widget.item.mediaType == 'tv' ? 'tv' : 'movie';
  String get _displayTitle {
    final d = _details ?? {};
    return (d['title'] ?? d['name'] ?? widget.item.title).toString();
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
    try {
      final d = await _tmdb.details(widget.item.id, type: _type);
      final r = await _tmdb.recommendations(widget.item.id, type: _type);
      final providers = await _tmdb.watchProviders(widget.item.id, type: _type, region: _region).catchError((_) => <String, dynamic>{});
      if (mounted) setState(() {
        _details = d;
        _recommendations = r;
        _providers = providers;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  Future<void> _saveRating(double value) async {
    setState(() => _rating = value);
    await LocalDatabase.setRating(widget.item.id, widget.item.title, widget.item.posterPath, value, mediaType: _type);
  }
  bool _searchingPlayback = false;

  Future<void> _startPlayback() async {
    if (_searchingPlayback) return;
    setState(() => _searchingPlayback = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Ищем доступное видео…')),
        ]),
      ),
    );
    var dialogClosed = false;
    try {
      final source = await InternetArchiveService().findLicensedVideo(
        _playbackSearchTitle,
        isSeries: _type == 'tv',
      );
      if (!mounted) return;
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
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        PlayerScreen(streamUrl: source.url.toString(), title: source.title)));
    } catch (e) {
      if (!mounted) return;
      if (!dialogClosed) Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось найти видео: $e')),
      );
    } finally {
      if (mounted) setState(() => _searchingPlayback = false);
    }
  }

  Widget _buildProviders() {
    final groups = <String, List<Map<String, dynamic>>>{
      'Подписка': (_providers['flatrate'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      'Аренда': (_providers['rent'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      'Покупка': (_providers['buy'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
    };
    final all = groups.values.expand((e) => e).toList();
    final link = _providers['link']?.toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Где смотреть легально', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: _region,
        decoration: const InputDecoration(labelText: 'Страна доступности'),
        items: const [
          DropdownMenuItem(value: 'NL', child: Text('Нидерланды')),
          DropdownMenuItem(value: 'US', child: Text('США')),
          DropdownMenuItem(value: 'GB', child: Text('Великобритания')),
          DropdownMenuItem(value: 'DE', child: Text('Германия')),
          DropdownMenuItem(value: 'FR', child: Text('Франция')),
          DropdownMenuItem(value: 'RU', child: Text('Россия')),
        ],
        onChanged: (value) async {
          if (value == null) return;
          setState(() { _region = value; _providers = {}; });
          try {
            final result = await _tmdb.watchProviders(widget.item.id, type: _type, region: value);
            if (mounted) setState(() => _providers = result);
          } catch (_) {}
        },
      ),
      const SizedBox(height: 8),
      if (all.isEmpty)
        const Text('TMDB не нашёл подтверждённых вариантов для выбранной страны. Это не означает, что фильм нигде недоступен.'),
      ...groups.entries.where((e) => e.value.isNotEmpty).map((group) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group.key, style: const TextStyle(color: Colors.white70)),
          Wrap(spacing: 8, children: group.value.map((provider) => ActionChip(
            avatar: provider['logo_path'] != null
              ? CircleAvatar(backgroundImage: CachedNetworkImageProvider('https://image.tmdb.org/t/p/w92${provider['logo_path']}'))
              : const Icon(Icons.play_circle_outline),
            label: Text(provider['provider_name']?.toString() ?? 'Сервис'),
            onPressed: link == null ? null : () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
          )).toList()),
        ]),
      )),
      if (link != null)
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(
          onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new), label: const Text('Открыть все варианты на TMDB'),
        )),
    ]);
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
          ]),
          if (genres.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(genres)),
          const SizedBox(height: 16),
          Text((d['overview'] ?? item.overview).toString().isEmpty ? 'Описание отсутствует.' : (d['overview'] ?? item.overview).toString()),
          if (cast.isNotEmpty) ...[
            const SizedBox(height: 18), const Text('В ролях', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6), Text(cast),
          ],
          const SizedBox(height: 20), const Text('Твоя оценка', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 4, children: List.generate(10, (i) {
            final value = (i + 1).toDouble();
            return IconButton(tooltip: '$value из 10', onPressed: () => _saveRating(value),
              icon: Icon(value <= _rating ? Icons.star : Icons.star_border, color: Colors.amber));
          })),
          _buildProviders(),
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
