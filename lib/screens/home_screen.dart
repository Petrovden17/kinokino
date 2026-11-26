import 'dart:math';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/creator_service.dart';
import '../services/beta_release_service.dart';
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
  const HomeScreen({super.key, required this.profileService, required this.settingsService});
  final ProfileService profileService;
  final SettingsService settingsService;
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
  bool _betaLoading = false;
  Map<String, dynamic>? _betaRelease;
  String? _error;
  String _type = 'all';
  String _sort = 'popularity.desc';
  int? _genreId;
  double _minRating = 0;

  String get _apiType => _type == 'tv' || _type == 'animated_tv' ? 'tv' : 'movie';
  int? get _effectiveGenre => _type == 'animation' || _type == 'animated_tv' ? 16 : _genreId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadGenres();
    _loadTrending();
    _loadCreatorAccess();
    _loadBetaRelease();
  }

  Future<void> _loadCreatorAccess() async {
    try {
      final allowed = await CreatorService().isCreator();
      if (mounted) setState(() => _isCreator = allowed);
    } catch (_) {}
  }

  Future<void> _loadBetaRelease() async {
    if (mounted) setState(() => _betaLoading = true);
    try {
      final release = await BetaReleaseService().latest();
      if (mounted) setState(() => _betaRelease = release);
    } catch (_) {
      // Beta discovery is optional and must not interrupt catalogue loading.
    } finally {
      if (mounted) setState(() => _betaLoading = false);
    }
  }

  Future<void> _openBetaWorkflow() async {
    final uri = Uri.parse('https://github.com/Petrovden17/kinokino/actions/workflows/build-windows.yml');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть GitHub Actions.')),
      );
    }
  }

  Future<void> _openBetaRelease() async {
    final url = (_betaRelease?['html_url'] ?? '').toString();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть бета-версию.')),
      );
    }
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
      final results = await _tmdb.trending(page: 1);
      if (mounted) setState(() {
        _items = results;
        _page = 1;
        _hasMore = results.isNotEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось загрузить каталог. Проверьте подключение и попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyFilters() async {
    setState(() => _loading = true);
    _error = null;
    try {
      final r = _type == 'all' && _genreId == null && _minRating == 0 && _sort == 'popularity.desc'
          ? await _tmdb.trending(page: 1)
          : _type == 'all' ? await _loadAllTypesPage(1)
          : await _tmdb.discover(type: _apiType, genreId: _effectiveGenre,
              sortBy: _sort == 'primary_release_date.desc' && _apiType == 'tv' ? 'first_air_date.desc' : _sort,
              minRating: _minRating == 0 ? null : _minRating);
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
    var candidates = _items.where((item) => item.hasRussianTitle).toList();
    if (candidates.isEmpty) {
      try {
        candidates = (await _tmdb.trending(page: 1))
            .where((item) => item.hasRussianTitle).toList();
      } catch (_) {}
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пока нет подходящих фильмов для случайного выбора.')),
      );
      return;
    }
    final item = candidates[Random().nextInt(candidates.length)];
    await _open(item);
  }

  Future<void> _showSearchDialog() async {
    final controller = TextEditingController(text: _search.text);
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Найти фильм или сериал'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
          decoration: const InputDecoration(
            hintText: 'Введите название',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            icon: const Icon(Icons.search),
            label: const Text('Найти'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query == null) return;
    _search.text = query;
    await _searchMedia(query);
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _open(MediaItem item) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailsScreen(
      item: item,
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

  Widget _betaPanel() {
    final release = _betaRelease;
    final tag = (release?['tag_name'] ?? '').toString();
    final name = (release?['name'] ?? tag).toString();
    final notes = (release?['body'] ?? '').toString().trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xE52B2447), Color(0xE5121D31)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF9B7BFF).withValues(alpha: .42)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.science_outlined, color: Color(0xFFB9A5FF), size: 26),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Бета-версии KinoKino', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 4),
          Text(_betaLoading
            ? 'Проверяем новые тестовые сборки…'
            : release == null
              ? 'Тестовых сборок пока нет.'
              : 'Последняя сборка: $name',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(notes, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (release != null)
              OutlinedButton.icon(
                onPressed: _isCreator ? _openBetaRelease : null,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text(_isCreator ? 'Скачать бета-версию' : 'Доступно создателю'),
              ),
            if (_isCreator)
              FilledButton.tonalIcon(
                onPressed: _openBetaWorkflow,
                icon: const Icon(Icons.rocket_launch_outlined, size: 16),
                label: const Text('Собрать в Actions'),
              ),
            if (!_isCreator)
              const Text('Тестирование и загрузка доступны только создателю.',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ])),
        IconButton(
          tooltip: 'Обновить список бета-версий',
          onPressed: _betaLoading ? null : _loadBetaRelease,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profileService.activeProfile;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0xEE080D19),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('KinoKino', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(_isCreator ? 'by Osirisvectory · Создатель' : 'by Osirisvectory',
              style: const TextStyle(fontSize: 10, color: Colors.white60)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Удиви меня',
            onPressed: _loading ? null : _surpriseMe,
            icon: const Icon(Icons.shuffle_rounded),
          ),
          if (_showTopSearch)
            IconButton(
              tooltip: 'Поиск',
              onPressed: _showSearchDialog,
              icon: const Icon(Icons.search_rounded),
            ),
          if (profile != null)
            Padding(padding: const EdgeInsets.only(right: 6),
              child: Center(child: Text(profile.name, style: const TextStyle(color: Colors.white70)))),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'profiles': await _openPage(ProfilesScreen(service: widget.profileService)); break;
                case 'creator': await _openPage(const CreatorConsoleScreen()); break;
                case 'library': await _openPage(const LibraryScreen()); break;
                case 'settings': await _openPage(SettingsScreen(service: widget.settingsService)); break;
                case 'about': await _openPage(const AboutScreen()); break;
                case 'logout': await AuthService().signOut(); break;
              }
            },
            itemBuilder: (context) => [
              if (_isCreator) const PopupMenuItem(value: 'creator',
                  child: ListTile(leading: Icon(Icons.admin_panel_settings_outlined), title: Text('Панель создателя'))),
              const PopupMenuItem(value: 'profiles', child: ListTile(leading: Icon(Icons.people), title: Text('Профили'))),
              const PopupMenuItem(value: 'library', child: ListTile(leading: Icon(Icons.video_library), title: Text('Библиотека'))),
              const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings), title: Text('Настройки'))),
              const PopupMenuItem(value: 'about', child: ListTile(leading: Icon(Icons.info_outline), title: Text('О приложении'))),
              const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Выйти из аккаунта'))),
            ],
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF101B30), Color(0xFF080D19), Color(0xFF171329)],
            stops: [0, .55, 1],
          ),
        ),
        child: Stack(children: [
          Positioned(top: 30, right: -120, child: IgnorePointer(child: Container(
            width: 340, height: 340,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Theme.of(context).colorScheme.primary.withValues(alpha: .13), Colors.transparent])),
          ))),
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).top + kToolbarHeight + 8)),
              SliverToBoxAdapter(child: _filters()),
              SliverToBoxAdapter(child: _betaPanel()),
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 5, 18, 10),
                child: Row(children: [
                  const Text('Популярное сейчас', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.secondary, size: 18),
                ]),
              )),
              if (_loading)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                SliverFillRemaining(hasScrollBody: false, child: Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: _loadTrending, icon: const Icon(Icons.refresh), label: const Text('Повторить')),
                  ]),
                )))
              else if (_items.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Ничего не найдено.')))
              else
                SliverLayoutBuilder(builder: (context, constraints) {
                  final width = MediaQuery.sizeOf(context).width;
                  final columns = width > 1200 ? 6 : width > 900 ? 5 : width > 650 ? 4 : 2;
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns, childAspectRatio: .58,
                        crossAxisSpacing: 14, mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => i >= _items.length
                            ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                            : TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0, end: 1),
                                duration: Duration(milliseconds: 320 + (i % 8) * 35),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, child) => Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, (1 - value) * 18),
                                    child: child,
                                  ),
                                ),
                                child: PosterCard(item: _items[i], onTap: () => _open(_items[i])),
                              ),
                        childCount: _items.length + (_hasMore ? 1 : 0),
                      ),
                    ),
                  );
                }),
              const SliverToBoxAdapter(child: SizedBox(height: 22)),
            ],
          ),
        ]),
      ),
    );
  }
}
