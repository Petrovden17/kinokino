import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:dpad/dpad.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/local_database.dart';
import '../services/auth_service.dart';
import '../services/creator_service.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';
import '../widgets/poster_card.dart';
import '../core/theme/app_theme.dart';
import 'profiles_screen.dart';
import 'settings_screen.dart';
import 'library_screen.dart';
import 'about_screen.dart';
import 'media_details_screen.dart';
import 'creator_console_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.profileService, required this.settingsService, this.tvMode = false});
  final ProfileService profileService;
  final SettingsService settingsService;
  final bool tvMode;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tmdb = TmdbService();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _showTopSearch = false;
  List<MediaItem> _items = [];
  List<Map<String, dynamic>> _genres = [];
  bool _loading = false;
  bool _isCreator = false;
  String? _error;
  String _type = 'all';
  String _sort = 'popularity.desc';
  int? _genreId;
  double _minRating = 0;
  int _selectedTab = 0;

  String get _apiType => _type == 'tv' || _type == 'animated_tv' ? 'tv' : 'movie';
  int? get _effectiveGenre => _type == 'animation' || _type == 'animated_tv' ? 16 : _genreId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadGenres();
    _loadTrending();
    _loadCreatorAccess();
  }

  Future<void> _loadCreatorAccess() async {
    try {
      final allowed = await CreatorService().isCreator();
      if (mounted) setState(() => _isCreator = allowed);
    } catch (_) {}
  }

  Future<void> _resetFilters() async {
    _search.clear();
    setState(() {
      _type = 'all';
      _sort = 'popularity.desc';
      _genreId = null;
      _minRating = 0;
    });
    await _loadGenres();
    await _loadTrending();
  }

  void _onScroll() {
    if (_scroll.hasClients) {
      final compact = _scroll.offset > 150;
      if (compact != _showTopSearch && mounted) setState(() => _showTopSearch = compact);
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 700) _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    _loadingMore = true;
    final next = _page + 1;
    try {
      final results = _search.text.trim().isNotEmpty
          ? await _tmdb.search(_search.text, page: next)
          : _type == 'all' && _genreId == null && _minRating == 0 && _sort == 'popularity.desc'
              ? await _tmdb.trending(page: next)
              : _type == 'all' ? await _loadAllTypesPage(next)
          : await _tmdb.discover(type: _apiType, genreId: _effectiveGenre,
              sortBy: _sort == 'primary_release_date.desc' && _apiType == 'tv' ? 'first_air_date.desc' : _sort,
              minRating: _minRating == 0 ? null : _minRating, page: next);
      if (!mounted) return;
      setState(() {
        final seen = _items.map((e) => '${e.mediaType}:${e.id}').toSet();
        _items.addAll(results.where((e) => !seen.contains('${e.mediaType}:${e.id}')));
        if (_type == 'all' && _sort != 'popularity.desc') _sortMediaItems(_items);
        _page = next;
        _hasMore = results.isNotEmpty;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadGenres() async {
    try {
      final lists = _type == 'all'
          ? await Future.wait([_tmdb.genres(type: 'movie'), _tmdb.genres(type: 'tv')])
          : [await _tmdb.genres(type: _apiType)];
      final unique = <int, Map<String, dynamic>>{};
      for (final list in lists) {
        for (final genre in list) {
          unique[genre['id'] as int] = genre;
        }
      }
      if (mounted) setState(() => _genres = unique.values.toList()
        ..sort((a, b) => a['name'].toString().compareTo(b['name'].toString())));
    } catch (_) {}
  }

  Future<List<MediaItem>> _loadAllTypesPage(int page) async {
    final results = await Future.wait([
      _tmdb.discover(type: 'movie', genreId: _genreId, sortBy: _sort,
        minRating: _minRating == 0 ? null : _minRating, page: page),
      _tmdb.discover(type: 'tv', genreId: _genreId,
        sortBy: _sort == 'primary_release_date.desc' ? 'first_air_date.desc' : _sort,
        minRating: _minRating == 0 ? null : _minRating, page: page),
    ]);
    final unique = <String, MediaItem>{};
    for (final group in results) {
      for (final item in group) {
        unique['${item.mediaType}:${item.id}'] = item;
      }
    }
    final merged = unique.values.toList();
    _sortMediaItems(merged);
    return merged;
  }

  int _releaseYear(MediaItem item) {
    final date = item.releaseDate;
    if (date.length < 4) return 0;
    final year = int.tryParse(date.substring(0, 4)) ?? 0;
    return year <= DateTime.now().year ? year : 0;
  }

  void _sortMediaItems(List<MediaItem> items) {
    if (_sort == 'primary_release_date.desc') {
      items.sort((a, b) => _releaseYear(b).compareTo(_releaseYear(a)));
    } else if (_sort == 'vote_average.desc') {
      items.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    } else {
      items.sort((a, b) => b.popularity.compareTo(a.popularity));
    }
  }

  Future<void> _loadTrending() async {
    setState(() => _loading = true);
    _error = null;
    _page = 1;
    _hasMore = true;
    try {
      List<MediaItem> results;
      try {
        results = await _tmdb.trending(page: 1);
      } catch (_) {
        // Some proxy deployments do not expose the trending endpoint.
        // Popular movie and TV lists are a safe first-page fallback.
        final popular = await Future.wait([
          _tmdb.popular(type: 'movie', page: 1),
          _tmdb.popular(type: 'tv', page: 1),
        ]);
        final unique = <String, MediaItem>{};
        for (final item in [...popular[0], ...popular[1]]) {
          unique['${item.mediaType}:${item.id}'] = item;
        }
        results = unique.values.toList()..sort((a, b) => b.popularity.compareTo(a.popularity));
      }
      if (mounted) setState(() {
        _items = results;
        _page = 1;
        _hasMore = results.isNotEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Каталог сейчас недоступен. Проверьте интернет на телевизоре и нажмите «Повторить».');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyFilters() async {
    setState(() => _loading = true);
    _error = null;
    try {
      var r = _type == 'all' && _genreId == null && _minRating == 0 && _sort == 'popularity.desc'
          ? await _tmdb.trending(page: 1)
          : _type == 'all' ? await _loadAllTypesPage(1)
          : await _tmdb.discover(type: _apiType, genreId: _effectiveGenre,
              sortBy: _sort == 'primary_release_date.desc' && _apiType == 'tv' ? 'first_air_date.desc' : _sort,
              minRating: _minRating == 0 ? null : _minRating);
      // If the date-sorted discover query is empty, retry the released catalogue
      // and sort its returned dates locally instead of showing an empty screen.
      if (r.isEmpty && _sort == 'primary_release_date.desc') {
        if (_type == 'all') {
          final pages = await Future.wait([
            _tmdb.popular(type: 'movie', page: 1),
            _tmdb.popular(type: 'tv', page: 1),
          ]);
          r = [...pages[0], ...pages[1]];
        } else {
          r = await _tmdb.popular(type: _apiType, page: 1);
        }
      }
      if (_sort == 'primary_release_date.desc') _sortMediaItems(r);
      if (mounted) setState(() { _items = r; _page = 1; _hasMore = r.isNotEmpty; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось применить фильтры.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchMedia(String value) async {
    if (value.trim().isEmpty) { _loadTrending(); return; }
    setState(() => _loading = true);
    _error = null;
    try {
      final r = await _tmdb.search(value);
      if (mounted) setState(() { _items = r; _page = 1; _hasMore = r.isNotEmpty; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Ошибка поиска. Проверьте подключение к интернету.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _surpriseMe() async {
    if (_items.isEmpty) {
      await _loadTrending();
    }
    if (!mounted || _items.isEmpty) return;
    final candidates = _items;
    final item = candidates[math.Random().nextInt(candidates.length)];
    await _open(item);
  }

  Future<void> _open(MediaItem item) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailsScreen(
      item: item,
      tvMode: widget.tvMode,
    )));
    if (mounted) setState(() {});
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  Widget _filters() => Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
    padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xE51A2C49), Color(0xE5121D31), Color(0xE52D2541)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: .09)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .2), blurRadius: 18, offset: const Offset(0, 7))],
    ),
    child: Column(children: [
      Row(children: [
        const Expanded(child: Text('КАТАЛОГ', style: TextStyle(fontSize: 11, letterSpacing: 1.6,
            color: AppTheme.aqua, fontWeight: FontWeight.w900))),
        Text('Подбери по настроению', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: .62))),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        onSubmitted: _searchMedia,
        decoration: InputDecoration(
          hintText: 'Поиск по каталогу',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Очистить поиск',
            icon: const Icon(Icons.close),
            onPressed: () { _search.clear(); _loadTrending(); },
          ),
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'all', label: Text('Популярное')),
            ButtonSegment(value: 'movie', label: Text('Фильмы')),
            ButtonSegment(value: 'tv', label: Text('Сериалы')),
            ButtonSegment(value: 'animation', label: Text('Мультфильмы')),
            ButtonSegment(value: 'animated_tv', label: Text('Мультсериалы')),
          ],
          selected: {_type},
          onSelectionChanged: (v) {
            setState(() { _type = v.first; _genreId = (v.first == 'animation' || v.first == 'animated_tv') ? 16 : null; });
            _loadGenres();
            _applyFilters();
          },
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: DropdownButtonFormField<int?>(
          value: _genreId,
          decoration: const InputDecoration(labelText: 'Жанр', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Все жанры')),
            ..._genres.map((g) => DropdownMenuItem<int?>(value: g['id'] as int, child: Text(g['name'].toString()))),
          ],
          onChanged: (v) { setState(() => _genreId = v); _applyFilters(); },
        )),
        const SizedBox(width: 10),
        Expanded(child: DropdownButtonFormField<double>(
          value: _minRating,
          decoration: const InputDecoration(labelText: 'Рейтинг от', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          items: [0.0, 5.0, 6.0, 7.0, 8.0, 9.0].map((v) =>
              DropdownMenuItem(value: v, child: Text(v == 0 ? 'Любой' : '$v+'))).toList(),
          onChanged: (v) { setState(() => _minRating = v ?? 0); _applyFilters(); },
        )),
        const SizedBox(width: 6),
        PopupMenuButton<String>(
          tooltip: 'Сортировка',
          icon: const Icon(Icons.sort_rounded),
          onSelected: (v) { setState(() => _sort = v); _applyFilters(); },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'popularity.desc', child: Text('Популярные')),
            PopupMenuItem(value: 'vote_average.desc', child: Text('По рейтингу')),
            PopupMenuItem(value: 'primary_release_date.desc', child: Text('По году выпуска · новые сначала')),
            PopupMenuItem(value: 'revenue.desc', child: Text('По сборам')),
          ],
        ),
      ]),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _loading ? null : _resetFilters,
          icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
          label: const Text('Сбросить фильтры'),
        ),
      ),
    ]),
  );


  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
    child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
  );

  Widget _strip(List<MediaItem> list) {
    final tvLayout = widget.tvMode || MediaQuery.sizeOf(context).width >= 900;
    return DpadRegion(
      child: SizedBox(
    height: tvLayout ? 292 : 236,
    child: ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      scrollDirection: Axis.horizontal,
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(width: 11),
      itemBuilder: (_, i) => SizedBox(width: tvLayout ? 174 : 136, child: PosterCard(item: list[i], onTap: () => _open(list[i]))),
    ),
  ));
  }

  Widget _grid() {
    if (_loading) return const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()));
    if (_error != null) return SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(_error!)));
    if (_items.isEmpty) return const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Ничего не найдено.')));
    final width = MediaQuery.sizeOf(context).width;
    final tvLayout = width >= 900;
    final cols = width >= 1600 ? 8 : width >= 1100 ? 7 : tvLayout ? 5 : width > 700 ? 4 : width > 500 ? 3 : 2;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 22),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols, childAspectRatio: tvLayout ? .62 : .57,
          crossAxisSpacing: tvLayout ? 18 : 12, mainAxisSpacing: tvLayout ? 20 : 14),
        delegate: SliverChildBuilderDelegate(
          (_, i) => i >= _items.length ? const Center(child: CircularProgressIndicator())
            : PosterCard(item: _items[i], onTap: () => _open(_items[i])),
          childCount: _items.length + (_hasMore ? 1 : 0)),
      ),
    );
  }

  Widget _homePage() {
    final feature = _items.isEmpty ? null : _items.first;
    Widget genre(String title, IconData icon, int id) => Padding(
      padding: const EdgeInsets.only(right: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () { setState(() { _genreId = id; _type = 'all'; _selectedTab = 1; }); _applyFilters(); },
        child: Container(width: 112, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF202124), borderRadius: BorderRadius.circular(13)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: const Color(0xFFFFD21F)), const SizedBox(height: 5),
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
    final tvLayout = MediaQuery.sizeOf(context).width >= 900;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(
        padding: EdgeInsets.fromLTRB(tvLayout ? 32 : 18, tvLayout ? 22 : 12, tvLayout ? 28 : 14, tvLayout ? 22 : 14),
        child: Row(children: [
          Text('KinoKino', style: TextStyle(fontSize: tvLayout ? 32 : 25, fontWeight: FontWeight.w900)),
          const Spacer(),
          IconButton(
            tooltip: 'Удиви меня',
            onPressed: _surpriseMe,
            icon: const Icon(Icons.casino_outlined, color: Color(0xFFFFD21F)),
          ),
          IconButton(onPressed: () => setState(() => _selectedTab = 2), icon: const Icon(Icons.search)),
          IconButton(onPressed: () => _openPage(SettingsScreen(service: widget.settingsService)), icon: const Icon(Icons.settings_outlined)),
        ]),
      )),
      SliverToBoxAdapter(child: Container(
        height: tvLayout ? 300 : 222, margin: EdgeInsets.symmetric(horizontal: tvLayout ? 28 : 14),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: const Color(0xFF252525), borderRadius: BorderRadius.circular(18)),
        child: Stack(fit: StackFit.expand, children: [
          if (feature?.backdropPath != null)
            CachedNetworkImage(imageUrl: 'https://image.tmdb.org/t/p/w1280${feature!.backdropPath}', fit: BoxFit.cover)
          else const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF512C1D), Color(0xFF141414)]))),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.centerLeft, end: Alignment.centerRight,
            colors: [Color(0xDD000000), Color(0x66000000), Color(0x11000000)]))),
          Positioned(left: 20, bottom: 18, right: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ВЫБОР KINOKINO', style: TextStyle(color: Color(0xFFFFD21F), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            Text(feature?.title ?? 'Открой мир кино', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: tvLayout ? 32 : 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: feature == null ? () => setState(() => _selectedTab = 1) : () => _open(feature),
              icon: const Icon(Icons.play_arrow, color: Colors.black),
              label: const Text('Смотреть', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFD21F),
                minimumSize: Size(tvLayout ? 180 : 130, tvLayout ? 52 : 40)),
            ),
          ])),
        ]),
      )),
      SliverToBoxAdapter(child: _heading('Подборки')),
      SliverToBoxAdapter(child: SizedBox(height: 88, child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14), scrollDirection: Axis.horizontal,
        children: [
          genre('Боевики', Icons.bolt, 28), genre('Комедии', Icons.mood, 35),
          genre('Драмы', Icons.theater_comedy, 18), genre('Фантастика', Icons.rocket_launch, 878),
          genre('Ужасы', Icons.dark_mode, 27), genre('Триллеры', Icons.visibility, 53),
        ],
      ))),
      SliverToBoxAdapter(child: _heading('Популярные новинки')),
      if (_loading) const SliverToBoxAdapter(child: SizedBox(height: 150, child: Center(child: CircularProgressIndicator())))
      else if (_items.isNotEmpty) SliverToBoxAdapter(child: _strip(_items.take(12).toList())),
      SliverToBoxAdapter(child: _heading('Популярное сейчас')),
      if (_items.length > 12) SliverToBoxAdapter(child: _strip(_items.skip(12).take(12).toList())),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }

  Widget _catalogPage() => CustomScrollView(slivers: [
    const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(18, 20, 18, 8),
      child: Text('Каталог', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)))),
    SliverToBoxAdapter(child: _filters()),
    SliverToBoxAdapter(child: _heading('Фильмы и сериалы')),
    _grid(),
  ]);

  Widget _searchPage() => CustomScrollView(slivers: [
    const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Text('Поиск', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)))),
    SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(controller: _search, textInputAction: TextInputAction.search, onSubmitted: _searchMedia,
        decoration: InputDecoration(hintText: 'Введите название фильма...', prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(onPressed: () { _search.clear(); _loadTrending(); }, icon: const Icon(Icons.close)))))),
    SliverToBoxAdapter(child: _heading('Быстрые жанры')),
    SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Wrap(spacing: 8, runSpacing: 8,
      children: [
        for (final g in const [('Боевики',28),('Комедии',35),('Драмы',18),('Фантастика',878),('Ужасы',27),('Триллеры',53)])
          ActionChip(label: Text(g.$1), backgroundColor: const Color(0xFF202124), side: BorderSide.none,
            onPressed: () { setState(() { _genreId = g.$2; _type = 'all'; _selectedTab = 1; }); _applyFilters(); }),
      ]))),
    SliverToBoxAdapter(child: _heading(_search.text.isEmpty ? 'Популярное' : 'Результаты поиска')),
    _grid(),
  ]);

  Widget _favoritesPage() => CustomScrollView(slivers: [
    const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(18, 20, 18, 12),
      child: Text('Избранное', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)))),
    SliverToBoxAdapter(child: FutureBuilder<List<Map<String, Object?>>>(
      future: LocalDatabase.favorites(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
        final rows = snap.data!;
        if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('Здесь пока пусто. Добавляй фильмы в избранное.')));
        return Column(children: rows.map((row) {
          final poster = row['poster_path'] as String?;
          final item = MediaItem(id: (row['id'] as num?)?.toInt() ?? 0,
            title: row['title'] as String? ?? 'Без названия', posterPath: poster,
            mediaType: row['media_type'] as String? ?? 'movie');
          return ListTile(onTap: () => _open(item), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 52, height: 70,
              child: poster == null ? const ColoredBox(color: Color(0xFF202124), child: Icon(Icons.movie))
                : CachedNetworkImage(imageUrl: 'https://image.tmdb.org/t/p/w185${poster}', fit: BoxFit.cover))),
            title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(item.mediaType == 'tv' ? 'Сериал' : 'Фильм'),
            trailing: const Icon(Icons.chevron_right));
        }).toList());
      },
    )),
  ]);

  Widget _profilePage() {
    final profile = widget.profileService.activeProfile;
    Widget action(IconData icon, String title, VoidCallback callback) => ListTile(
      leading: Icon(icon, color: const Color(0xFFFFD21F)), title: Text(title),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54), onTap: callback);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 24), children: [
      const Text('Профиль', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
      const SizedBox(height: 18),
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xFF202124), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const CircleAvatar(radius: 28, backgroundColor: Color(0xFF3A3B3D), child: Icon(Icons.person, size: 34)),
          const SizedBox(width: 14),
          Text(profile?.name ?? 'Гость', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ])),
      const SizedBox(height: 14),
      Card(child: Column(children: [
        action(Icons.settings_outlined, 'Настройки', () => _openPage(SettingsScreen(service: widget.settingsService))),
        const Divider(height: 1),
        action(Icons.people_outline, 'Профили', () => _openPage(ProfilesScreen(service: widget.profileService))),
        const Divider(height: 1),
        action(Icons.history, 'История просмотров', () => _openPage(const LibraryScreen())),
        const Divider(height: 1),
        action(Icons.info_outline, 'О приложении', () => _openPage(const AboutScreen())),
        if (_isCreator) action(Icons.admin_panel_settings_outlined, 'Панель создателя', () => _openPage(const CreatorConsoleScreen())),
        const Divider(height: 1),
        action(Icons.logout, 'Выйти', () => AuthService().signOut()),
      ])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_homePage(), _catalogPage(), _searchPage(), _favoritesPage(), _profilePage()];
    const names = ['Главная', 'Каталог', 'Поиск', 'Избранное', 'Профиль'];
    const icons = [Icons.home_rounded, Icons.grid_view_rounded, Icons.search_rounded, Icons.favorite_border_rounded, Icons.person_outline_rounded];
    final tvLayout = MediaQuery.sizeOf(context).width >= 900;
    final content = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_selectedTab == 1 || _selectedTab == 2) {
          if (notification.metrics.pixels > 150 && !_showTopSearch) {
            setState(() => _showTopSearch = true);
          } else if (notification.metrics.pixels <= 150 && _showTopSearch) {
            setState(() => _showTopSearch = false);
          }
          if (notification.metrics.extentAfter < 700) _loadMore();
        }
        return false;
      },
      child: FocusTraversalGroup(
        child: SafeArea(child: IndexedStack(index: _selectedTab, children: pages)),
      ),
    );
    return Scaffold(
      backgroundColor: const Color(0xFF090A0C),
      body: tvLayout
          ? Row(children: [
              NavigationRail(
                selectedIndex: _selectedTab,
                onDestinationSelected: (i) => setState(() => _selectedTab = i),
                labelType: NavigationRailLabelType.all,
                backgroundColor: const Color(0xFF111214),
                indicatorColor: const Color(0x22FFD21F),
                minWidth: 92,
                destinations: [for (var i = 0; i < names.length; i++) NavigationRailDestination(
                  icon: Icon(icons[i], size: 25),
                  selectedIcon: Icon(icons[i], color: const Color(0xFFFFD21F), size: 26),
                  label: Text(names[i]),
                )],
              ),
              Expanded(child: content),
            ])
          : content,
      bottomNavigationBar: tvLayout ? null : NavigationBar(
        selectedIndex: _selectedTab, onDestinationSelected: (i) => setState(() => _selectedTab = i),
        backgroundColor: const Color(0xFF111214), indicatorColor: const Color(0x22FFD21F), height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [for (var i = 0; i < names.length; i++) NavigationDestination(
          icon: Icon(icons[i], size: 22), selectedIcon: Icon(icons[i], color: const Color(0xFFFFD21F), size: 23), label: names[i])],
      ),
    );
  }
}
