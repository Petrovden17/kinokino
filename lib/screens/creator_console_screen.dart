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
  String? _error;
  String? _diagnostics;

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
      final values = await Future.wait([_creator.loadStats(), _creator.announcements()]);
      if (!mounted) return;
      setState(() {
        _stats = values[0] as Map<String, dynamic>;
        _announcements = values[1] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          const Text('Статистика KinoKino', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          _stat('Аккаунты', 'users', Icons.people_outline),
          _stat('Избранное', 'favorites', Icons.favorite_outline),
          _stat('Оценки', 'ratings', Icons.star_outline),
          _stat('Записи истории', 'watch_history', Icons.history),
          _stat('Объявления', 'announcements', Icons.campaign_outlined),
          const SizedBox(height: 18),
          const Text('Диагностика сервисов', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          OutlinedButton.icon(onPressed: _checking ? null : _checkServices,
            icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.health_and_safety_outlined),
            label: const Text('Проверить Supabase и TMDB')),
          if (_diagnostics != null) Card(child: Padding(
            padding: const EdgeInsets.all(12), child: Text(_diagnostics!))),
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
