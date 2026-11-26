import 'package:flutter/material.dart';
import '../services/local_database.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}
class _LibraryScreenState extends State<LibraryScreen> {
  String _tab = 'favorites';
  Future<List<Map<String, Object?>>> _load() {
    if (_tab == 'history') return LocalDatabase.history();
    if (_tab == 'ratings') return LocalDatabase.ratings();
    return LocalDatabase.favorites();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Моя библиотека')),
    body: Column(children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'favorites', label: Text('Избранное'), icon: Icon(Icons.favorite)),
            ButtonSegment(value: 'history', label: Text('История'), icon: Icon(Icons.history)),
            ButtonSegment(value: 'ratings', label: Text('Оценки'), icon: Icon(Icons.star)),
          ],
          selected: {_tab}, onSelectionChanged: (v) => setState(() => _tab = v.first),
        )),
      Expanded(child: FutureBuilder(
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          if (rows.isEmpty) return const Center(child: Text('Здесь пока пусто.'));
          return ListView.builder(itemCount: rows.length, itemBuilder: (_, i) {
            final row = rows[i];
            final subtitle = _tab == 'favorites' ? 'В избранном'
              : _tab == 'ratings' ? 'Твоя оценка: \${row['user_rating']}/10'
              : 'Последний просмотр: \${row['last_opened'] ?? ''}';
            return ListTile(leading: const Icon(Icons.movie_outlined),
              title: Text(row['title'] as String? ?? 'Без названия'),
              subtitle: Text(subtitle));
          });
        },
      )),
    ]),
  );
}
