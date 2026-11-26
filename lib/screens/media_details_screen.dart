import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
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
  String get _type => widget.item.mediaType == 'tv' ? 'tv' : 'movie';
  String get _displayTitle {
    final d = _details ?? {};
    return (d['title'] ?? d['name'] ?? widget.item.title).toString();
  }
  @override
  void initState() {
    super.initState();
    _load();
    LocalDatabase.recordOpen(widget.item.id, widget.item.title, widget.item.posterPath, mediaType: _type);
  }
  Future<void> _load() async {
    try {
      final d = await _tmdb.details(widget.item.id, type: _type);
      final r = await _tmdb.recommendations(widget.item.id, type: _type);
      if (mounted) setState(() {
        _details = d;
        _recommendations = r;
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
  Future<void> _startPlayback() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Источник видео'),
      content: TextField(controller: controller, keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'HTTPS-ссылка на разрешённый поток', hintText: 'https://example.com/video.m3u8')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Продолжить')),
      ],
    ));
    controller.dispose();
    if (url == null || url.isEmpty || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(streamUrl: url, title: _displayTitle)));
  }
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final d = _details ?? {};
    final genres = (d['genres'] as List? ?? const []).whereType<Map>().map((e) => e['name'].toString()).join(' · ');
    final cast = ((d['credits'] as Map?)?['cast'] as List? ?? const []).take(8).whereType<Map>().map((e) => e['name'].toString()).join(', ');
    final backdrop = d['backdrop_path'] ?? item.backdropPath;
    return Scaffold(
      appBar: AppBar(title: Text(_displayTitle)),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(children: [
        if (backdrop != null) SizedBox(height: 220, child: CachedNetworkImage(
          imageUrl: 'https://image.tmdb.org/t/p/w780$backdrop', fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF172235)))),
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
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _startPlayback, icon: const Icon(Icons.play_arrow), label: const Text('Начать просмотр')),
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
