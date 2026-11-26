import 'package:flutter/material.dart';
import '../services/creator_service.dart';
import '../services/tmdb_service.dart';

class CreatorConsoleScreen extends StatefulWidget {
  const CreatorConsoleScreen({super.key});
  @override
  State<CreatorConsoleScreen> createState() => _CreatorConsoleScreenState();
}

class _CreatorConsoleScreenState extends State<CreatorConsoleScreen> {
  final _creator = CreatorService();
  bool _loading = true;
  bool _checking = false;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _accounts = [];
  final _accountSearch = TextEditingController();
  int _accountPage = 1;
  bool _accountsHasMore = true;
  bool _accountsLoadingMore = false;
  String? _error;
  String? _diagnostics;
  bool _showExtraInfo = false;
  bool _statsLoaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (!await _creator.isCreator()) {
        throw Exception('У этого аккаунта нет прав создателя.');
      }
      final values = await Future.wait([_creator.announcements(), _creator.loadAccounts()]);
      if (!mounted) return;
      setState(() {
        _announcements = values[0];
        _accounts = values[1];
        _accountPage = 1;
        _accountsHasMore = _accounts.length == 100;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visibleAccounts {
    final query = _accountSearch.text.trim().toLowerCase();
    if (query.isEmpty) return _accounts;
    return _accounts.where((account) =>
      (account['email']?.toString().toLowerCase().contains(query) ?? false) ||
      (account['display_name']?.toString().toLowerCase().contains(query) ?? false) ||
      account['id'].toString().toLowerCase().contains(query)).toList();
  }

  String _dateLabel(dynamic value, {String fallback = '—'}) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return fallback;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return fallback;
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  bool _isBanned(Map<String, dynamic> account) {
    final raw = account['banned_until']?.toString();
    if (raw == null || raw.isEmpty) return false;
    final date = DateTime.tryParse(raw);
    return date != null && date.isAfter(DateTime.now().toUtc());
  }

  Future<void> _toggleExtraInfo() async {
    final show = !_showExtraInfo;
    setState(() => _showExtraInfo = show);
    if (!show || _statsLoaded) return;
    try {
      final stats = await _creator.loadStats();
      if (mounted) setState(() { _stats = stats; _statsLoaded = true; });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подробная статистика пока недоступна.')),
      );
    }
  }

  Future<void> _loadMoreAccounts() async {
    if (_accountsLoadingMore || !_accountsHasMore) return;
    setState(() => _accountsLoadingMore = true);
    try {
      final nextPage = _accountPage + 1;
      final rows = await _creator.loadAccounts(page: nextPage);
      if (!mounted) return;
      setState(() {
        _accounts.addAll(rows);
        _accountPage = nextPage;
        _accountsHasMore = rows.length == 100;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось загрузить следующие аккаунты: $e');
    } finally {
      if (mounted) setState(() => _accountsLoadingMore = false);
    }
  }

  Future<void> _toggleAccountBan(Map<String, dynamic> account) async {
    final banned = _isBanned(account);
    final email = account['email']?.toString() ?? 'Без email';
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(banned ? 'Разблокировать аккаунт?' : 'Заблокировать аккаунт?'),
        content: Text(banned
          ? 'Пользователь $email снова сможет входить в KinoKino.'
          : 'Пользователь $email не сможет входить в KinoKino, пока блокировка не будет снята.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(banned ? 'Разблокировать' : 'Заблокировать')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _creator.setAccountBanned(account['id'].toString(), banned: !banned);
      final updated = await _creator.loadAccounts(page: 1);
      if (!mounted) return;
      setState(() {
        _accounts = updated;
        _accountPage = 1;
        _accountsHasMore = updated.length == 100;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(banned ? 'Аккаунт разблокирован.' : 'Аккаунт заблокирован.'),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось изменить аккаунт: $e');
    }
  }

  @override
  void dispose() {
    _accountSearch.dispose();
    super.dispose();
  }

  Future<void> _checkServices() async {
    setState(() { _checking = true; _diagnostics = 'Проверяем сервисы…'; });
    final lines = <String>[];
    try { await _creator.loadStats(); lines.add('Supabase: работает'); }
    catch (e) { lines.add('Supabase: ошибка — $e'); }
    try { await TmdbService().trending(); lines.add('TMDB: работает'); }
    catch (e) { lines.add('TMDB: ошибка — $e'); }
    if (mounted) setState(() { _diagnostics = lines.join('\n'); _checking = false; });
  }

  Future<void> _newAnnouncement() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool published = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: const Text('Новое объявление'),
        content: Form(key: formKey, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: title, maxLength: 100,
              decoration: const InputDecoration(labelText: 'Заголовок'),
              validator: (v) => v == null || v.trim().length < 3 ? 'Минимум 3 символа' : null),
            TextFormField(controller: body, minLines: 3, maxLines: 6, maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Текст'),
              validator: (v) => v == null || v.trim().length < 3 ? 'Минимум 3 символа' : null),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Опубликовать сразу'),
              value: published, onChanged: (v) => setDialog(() => published = v)),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
          }, child: const Text('Сохранить')),
        ],
      )),
    );
    if (save == true) {
      try {
        await _creator.createAnnouncement(title: title.text, body: body.text, published: published);
        await _refresh();
      } catch (e) {
        if (mounted) setState(() => _error = 'Не удалось сохранить: $e');
      }
    }
    title.dispose();
    body.dispose();
  }

  Future<void> _delete(String id) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить объявление?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
      ],
    ));
    if (yes != true) return;
    try { await _creator.deleteAnnouncement(id); await _refresh(); }
    catch (e) { if (mounted) setState(() => _error = 'Не удалось удалить: $e'); }
  }

  Widget _stat(String label, String key, IconData icon) => Card(child: ListTile(
    leading: Icon(icon), title: Text(label),
    trailing: Text((_stats[key] ?? '—').toString(),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
  ));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Панель создателя'),
      actions: [IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh))]),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : _newAnnouncement,
      icon: const Icon(Icons.add), label: const Text('Объявление')),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _refresh, child: const Text('Повторить')),
          ])))
      : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          OutlinedButton.icon(
            onPressed: _toggleExtraInfo,
            icon: Icon(_showExtraInfo ? Icons.visibility_off_outlined : Icons.analytics_outlined),
            label: Text(_showExtraInfo ? 'Скрыть подробную информацию' : 'Показать подробную информацию'),
          ),
          const SizedBox(height: 10),
          const Text('Статистика KinoKino', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (_showExtraInfo) _stat('Аккаунты', 'users', Icons.people_outline),
          _stat('Записи истории', 'watch_history', Icons.history),
          _stat('Объявления', 'announcements', Icons.campaign_outlined),
          const SizedBox(height: 12),
          const SizedBox(height: 18),
          if (_showExtraInfo) ...[
          const Text('Управление аккаунтами', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _accountSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Поиск по email, имени или ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          if (_showExtraInfo)
            Text('Загружено аккаунтов: ${_accounts.length}',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          if (_visibleAccounts.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Аккаунты не найдены.')),
          for (final account in _visibleAccounts)
            Card(child: ListTile(
              leading: CircleAvatar(
                child: Icon(account['is_creator'] == true
                  ? Icons.shield_outlined
                  : _isBanned(account) ? Icons.block : Icons.person_outline),
              ),
              title: Text(
                (account['display_name']?.toString().trim().isNotEmpty == true)
                  ? account['display_name'].toString()
                  : (account['email']?.toString().isNotEmpty == true
                      ? account['email'].toString() : 'Аккаунт без имени'),
              ),
              subtitle: Text([
                account['is_creator'] == true ? 'Создатель — защищённый аккаунт'
                  : _isBanned(account) ? 'Заблокирован' : 'Активен',
                if (_showExtraInfo) account['email']?.toString() ?? '',
                if (_showExtraInfo) 'Регистрация: ${_dateLabel(account['created_at'])}',
                if (_showExtraInfo) 'Последний вход: ${_dateLabel(account['last_sign_in_at'], fallback: 'ещё не входил')}',
                if (_showExtraInfo) account['email_confirmed_at'] == null ? 'Email не подтверждён' : 'Email подтверждён',
              ].where((part) => part.isNotEmpty).join(' • ')),
              isThreeLine: _showExtraInfo,
              trailing: account['is_creator'] == true
                ? const Icon(Icons.verified_user_outlined, color: Colors.amber)
                : PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'toggle_ban') _toggleAccountBan(account);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'toggle_ban',
                        child: Text(_isBanned(account) ? 'Разблокировать' : 'Заблокировать'),
                      ),
                    ],
                  ),
            )),
          if (_accountsHasMore && _accountSearch.text.trim().isEmpty)
            Center(child: OutlinedButton(
              onPressed: _accountsLoadingMore ? null : _loadMoreAccounts,
              child: _accountsLoadingMore
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Загрузить ещё'),
            )),
          ],
          if (_showExtraInfo) ...[
          const SizedBox(height: 18),
          const Text('Диагностика сервисов', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          OutlinedButton.icon(onPressed: _checking ? null : _checkServices,
            icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.health_and_safety_outlined),
            label: const Text('Проверить Supabase и TMDB')),
          if (_diagnostics != null) Card(child: Padding(
            padding: const EdgeInsets.all(12), child: Text(_diagnostics!))),
          ],
          const SizedBox(height: 18),
          const Text('Объявления и обновления', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (_announcements.isEmpty) const Text('Объявлений пока нет.'),
          for (final item in _announcements) Card(child: ListTile(
            leading: Icon(item['is_published'] == true ? Icons.campaign : Icons.drafts_outlined),
            title: Text(item['title']?.toString() ?? ''),
            subtitle: Text(item['body']?.toString() ?? ''),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'toggle') {
                  await _creator.setAnnouncementPublished(item['id'].toString(), item['is_published'] != true);
                  await _refresh();
                } else if (value == 'delete') { await _delete(item['id'].toString()); }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'toggle', child: Text(item['is_published'] == true ? 'Снять с публикации' : 'Опубликовать')),
                const PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
          )),
          const SizedBox(height: 12),
          const Text('Каталог KinoKino использует TMDB для метаданных. Панель проверяет его доступность, но не изменяет и не размещает видеопотоки TMDB.',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
  );
}
