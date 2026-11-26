import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../services/local_library_service.dart';
import '../services/tmdb_service.dart';

class MediaDetailsScreen extends StatefulWidget {
  const MediaDetailsScreen({
    required this.item,
    required this.tmdb,
    super.key,
  });

  final MediaItem item;
  final TmdbService tmdb;

  @override
  State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}

class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  final _library = LocalLibraryService();
  bool _favorite = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _library.addToHistory(widget.item);
    final favorite = await _library.isFavorite(widget.item);
    if (!mounted) return;
    setState(() {
      _favorite = favorite;
      _loading = false;
    });
  }

  Future<void> _toggleFavorite() async {
    await _library.toggleFavorite(widget.item);
    if (!mounted) return;
    setState(() => _favorite = !_favorite);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_favorite ? 'Добавлено в избранное' : 'Удалено из избранного')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final backdrop = widget.tmdb.imageUrl(item.backdropPath, size: 'w1280');
    final poster = widget.tmdb.imageUrl(item.posterPath, size: 'w500');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            backgroundColor: const Color(0xFF090D16),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdrop.isNotEmpty)
                    Image.network(backdrop, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _backdropFallback())
                  else
                    _backdropFallback(),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black26, Color(0xFF090D16)],
                        stops: [0.1, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (poster.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(poster, width: 112, height: 168, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _posterFallback()),
                        )
                      else
                        _posterFallback(),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            Text('${item.typeLabel}  •  ${item.year}', style: const TextStyle(color: Colors.white60)),
                            const SizedBox(height: 8),
                            Row(children: [
                              const Icon(Icons.star_rounded, color: Color(0xFFFFC857), size: 19),
                              const SizedBox(width: 4),
                              Text(item.voteAverage.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
                              const Text(' / 10', style: TextStyle(color: Colors.white54)),
                            ]),
                            const SizedBox(height: 16),
                            FilledButton.tonalIcon(
                              onPressed: _loading ? null : _toggleFavorite,
                              icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border),
                              label: Text(_favorite ? 'В избранном' : 'В избранное'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text('Описание', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(
                    item.overview.isEmpty ? 'Описание для этого материала пока отсутствует.' : item.overview,
                    style: const TextStyle(color: Colors.white70, height: 1.55, fontSize: 15),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF182235),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF8DBBFF)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Полное видео не предоставляется TMDB. Здесь отображаются метаданные каталога; просмотр будет доступен только при подключении разрешённого источника.',
                            style: TextStyle(color: Colors.white70, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backdropFallback() => Container(
        color: const Color(0xFF182235),
        child: const Center(child: Icon(Icons.movie_outlined, size: 72, color: Colors.white24)),
      );

  Widget _posterFallback() => Container(
        width: 112,
        height: 168,
        decoration: BoxDecoration(color: const Color(0xFF182235), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.movie_outlined, color: Colors.white38, size: 38),
      );
}
