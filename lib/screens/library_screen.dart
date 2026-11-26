import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../services/local_library_service.dart';
import '../services/tmdb_service.dart';
import '../widgets/poster_card.dart';
import 'media_details_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.history, super.key});

  final bool history;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _library = LocalLibraryService();
  final _tmdb = TmdbService();
  late Future<List<MediaItem>> _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _tmdb.dispose();
    super.dispose();
  }

  void _reload() {
    _items = widget.history ? _library.getHistory() : _library.getFavorites();
  }

  Future<void> _clearHistory() async {
    await _library.clearHistory();
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.history ? 'История просмотра' : 'Избранное';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.history)
            IconButton(
              tooltip: 'Очистить историю',
              onPressed: _clearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          IconButton(onPressed: () => setState(_reload), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<MediaItem>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.history ? Icons.history : Icons.favorite_border, size: 52, color: Colors.white30),
                  const SizedBox(height: 12),
                  Text(widget.history ? 'История пока пуста' : 'В избранном пока ничего нет',
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 175,
              mainAxisExtent: 278,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => PosterCard(
              item: items[index],
              service: _tmdb,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MediaDetailsScreen(item: items[index], tmdb: _tmdb),
              )).then((_) {
                if (mounted) setState(_reload);
              }),
            ),
          );
        },
      ),
    );
  }
}
