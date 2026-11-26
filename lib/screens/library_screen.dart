import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../services/local_database.dart';
import 'media_details_screen.dart';
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override State<LibraryScreen> createState() => _LibraryScreenState();
}
class _LibraryScreenState extends State<LibraryScreen> {
  String _tab = 'favorites';
  Future<List<Map<String, Object?>>> _load() {
    if (_tab == 'history') return LocalDatabase.history();
    if (_tab == 'ratings') return LocalDatabase.ratings();
    return LocalDatabase.favorites();
  }
  String _formatDate(Object? value) {
    if (value == null) return 'Дата не указана';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day.$month.${date.year} $hour:$minute';
  }
  Future<void> _openRow(Map<String, Object?> row) async {
    final id = (row['id'] as num?)?.toInt() ?? 0;
    if (id == 0) return;
    final item = MediaItem(
      id: id,
      title: row['title'] as String? ?? 'Без названия',
      posterPath: row['poster_path'] as String?,
      mediaType: row['media_type'] as String? ?? 'movie',
    );
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailsScreen(item: item)));
    if (mounted) setState(() {});
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Моя библиотека')),
    body: Column(children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'favorites', label: Text('Избранное'), icon: Icon(Icons.favorite)),
            ButtonSegment(value: 'history', label: Text('История'), icon: Icon(Icons.history)),
            ButtonSegment(value: 'ratings', label: Text('Оценки'), icon: Icon(Icons.star)),
          ],
          selected: {_tab}, onSelectionChanged: (v) => setState(() => _tab = v.first),
        )),
      Expanded(child: FutureBuilder(future: _load(), builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data!;
        if (rows.isEmpty) return const Center(child: Text('Здесь пока пусто.'));
        return ListView.separated(itemCount: rows.length, separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final row = rows[i];
            final subtitle = _tab == 'favorites' ? 'В избранном'
              : _tab == 'ratings' ? 'Твоя оценка: ${row['user_rating']}/10'
              : 'Просмотрено: ${_formatDate(row['last_opened'])}';
            final poster = row['poster_path'] as String?;
            return ListTile(onTap: () => _openRow(row),
              leading: SizedBox(width: 48, height: 68, child: poster == null
                ? const ColoredBox(color: Color(0xFF202B3D), child: Icon(Icons.movie))
                : CachedNetworkImage(imageUrl: 'https://image.tmdb.org/t/p/w185$poster', fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Icon(Icons.movie))),
              title: Text(row['title'] as String? ?? 'Без названия'),
              subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right));
          },
        );
      })),
    ]),
  );
}
