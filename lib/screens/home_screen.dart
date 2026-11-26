import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../repositories/catalog_repository.dart';
import '../services/tmdb_service.dart';
import '../widgets/poster_card.dart';
import 'media_details_screen.dart';
import 'library_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tmdb = TmdbService();
  late final _repository = CatalogRepository(_tmdb);
  int _selectedNav = 0;
  late Future<List<MediaItem>> _movies;
  late Future<List<MediaItem>> _shows;

  static const _sections = [
    ('Главная', Icons.home_rounded),
    ('Фильмы', Icons.movie_rounded),
    ('Сериалы', Icons.live_tv_rounded),
    ('Поиск', Icons.search_rounded),
    ('Избранное', Icons.favorite_rounded),
    ('История', Icons.history_rounded),
    ('Загрузки', Icons.download_rounded),
    ('Премьеры', Icons.calendar_month_rounded),
    ('Настройки', Icons.settings_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _movies = _repository.getTrendingMovies();
    _shows = _repository.getTrendingShows();
  }

  @override
  void dispose() {
    _tmdb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      return Scaffold(
        body: Row(
          children: [
            if (wide) _sidebar(),
            Expanded(
              child: Column(
                children: [
                  _topBar(wide),
                  Expanded(child: _content()),
                  if (!wide) _bottomNavigation(),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _sidebar() => Container(
        width: 224,
        padding: const EdgeInsets.fromLTRB(18, 30, 12, 18),
        decoration: const BoxDecoration(
          color: Color(0xFF0D1421),
          border: Border(right: BorderSide(color: Colors.white10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 32),
              child: Text('KinoKino', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.8)),
            ),
            for (var i = 0; i < _sections.length; i++)
              if (i != 3)
                _navItem(i),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('KinoKino 1.0 • Основа проекта', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          ],
        ),
      );

  Widget _navItem(int index) {
    final selected = _selectedNav == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected,
        selectedTileColor: const Color(0xFF1B3762),
        leading: Icon(_sections[index].$2, size: 20),
        title: Text(_sections[index].$1, style: const TextStyle(fontSize: 13)),
        onTap: () => setState(() => _selectedNav = index),
      ),
    );
  }

  Widget _topBar(bool wide) => Padding(
        padding: EdgeInsets.fromLTRB(wide ? 30 : 18, 20, 24, 14),
        child: Row(
          children: [
            if (!wide)
              const Text('KinoKino', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            if (!wide) const Spacer(),
            if (wide)
              Text(
                _sections[_selectedNav].$1,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            const Spacer(),
            IconButton(onPressed: () => setState(() => _selectedNav = 3), icon: const Icon(Icons.search)),
            IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
            const CircleAvatar(radius: 17, backgroundColor: Color(0xFF244A80), child: Icon(Icons.person, size: 18)),
          ],
        ),
      );

  Widget _content() {
    if (_selectedNav == 4 || _selectedNav == 5) {
      return LibraryScreen(history: _selectedNav == 5);
    }
    if (_selectedNav != 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_sections[_selectedNav].$2, size: 48, color: const Color(0xFF3984FF)),
              const SizedBox(height: 14),
              Text(_sections[_selectedNav].$1, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Раздел подготовлен в навигации. Его функциональность будет добавляться следующими этапами.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
              if (_selectedNav == 3) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: 420,
                  child: TextField(
                    onSubmitted: (value) => _runSearch(value),
                    decoration: const InputDecoration(
                      hintText: 'Название фильма, сериала или актёра',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _hero(),
        _mediaSection('Популярные фильмы', _movies),
        _mediaSection('Популярные сериалы', _shows),
        _genreSection(),
      ],
    );
  }

  Widget _hero() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 26),
        child: Container(
          height: 245,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFF193D70), Color(0xFF111827), Color(0xFF20243A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned(right: 26, top: 22, child: Icon(Icons.local_movies_rounded, size: 150, color: Colors.white.withValues(alpha: .08))),
              Padding(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('ТВОЙ ДОМАШНИЙ КИНОТЕАТР', style: TextStyle(color: Color(0xFF8DBBFF), letterSpacing: 2, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      const Text('Большие истории\nначинаются здесь', style: TextStyle(fontSize: 30, height: 1.08, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      const Text('Фильмы, сериалы и персональная коллекция в одном месте.', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => setState(() => _selectedNav = 1),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Открыть каталог'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _mediaSection(String title, Future<List<MediaItem>> future) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
              child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 265,
              child: FutureBuilder<List<MediaItem>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(snapshot.error.toString(), style: const TextStyle(color: Colors.white60)),
                      ),
                    );
                  }
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) return const Center(child: Text('Пока нет данных'));
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, index) => PosterCard(
                      item: items[index],
                      service: _tmdb,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MediaDetailsScreen(item: items[index], tmdb: _tmdb),
                      )),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );

  Widget _genreSection() {
    const genres = ['Боевики', 'Комедии', 'Фантастика', 'Ужасы', 'Драмы', 'Триллеры', 'Мультфильмы', 'Приключения', 'Детективы', 'Мелодрамы'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Жанры', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: genres.map((genre) => ActionChip(
              label: Text(genre),
              backgroundColor: const Color(0xFF182235),
              onPressed: () {},
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _bottomNavigation() => NavigationBar(
        selectedIndex: _selectedNav > 4 ? 0 : _selectedNav,
        onDestinationSelected: (index) => setState(() => _selectedNav = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.movie_outlined), label: 'Фильмы'),
          NavigationDestination(icon: Icon(Icons.live_tv_outlined), label: 'Сериалы'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Поиск'),
          NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Избранное'),
        ],
      );

  Future<void> _runSearch(String query) async {
    setState(() => _selectedNav = 3);
    try {
      final results = await _repository.search(query);
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * .75,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Результаты: $query', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                for (final item in results)
                  ListTile(
                    leading: const Icon(Icons.movie_outlined),
                    title: Text(item.title),
                    subtitle: Text('${item.typeLabel} • ${item.year}'),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
