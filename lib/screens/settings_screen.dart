import 'dart:io';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../services/backup_service.dart';
import '../services/app_update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.service});
  final SettingsService service;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _value;
  String? _notice;
  bool _checkingUpdates = false;
  final AppUpdateService _updates = AppUpdateService();

  @override
  void initState() {
    super.initState();
    _value = widget.service.settings;
  }

  Future<void> _save(AppSettings next) async {
    await widget.service.update(next);
    if (mounted) setState(() { _value = next; _notice = 'Настройки сохранены.'; });
  }

  Future<void> _backup() async {
    try {
      final file = await BackupService().exportSettings(_value);
      if (mounted) setState(() => _notice = 'Резервная копия настроек создана: ${file.path}');
    } catch (e) {
      if (mounted) setState(() => _notice = 'Не удалось создать копию: $e');
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checkingUpdates) return;
    if (!Platform.isWindows) {
      setState(() => _notice = 'Автоматическая проверка обновлений доступна в Windows.');
      return;
    }
    setState(() {
      _checkingUpdates = true;
      _notice = 'Проверяем обновления на GitHub…';
    });
    try {
      final update = await _updates.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        setState(() => _notice = 'У вас установлена последняя версия KinoKino.');
        return;
      }
      setState(() => _notice = 'Доступно обновление ${update.tag}.');
      final install = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Доступно обновление KinoKino'),
          content: SingleChildScrollView(
            child: Text('Найдена версия ${update.tag}. Приложение скачает архив и перезапустится автоматически.\n\n${update.notes.isEmpty ? 'Исправления и улучшения.' : update.notes}'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Позже')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.download),
              label: const Text('Установить'),
            ),
          ],
        ),
      );
      if (install == true) {
        await _updates.downloadAndInstall(update);
      }
    } catch (e) {
      if (mounted) setState(() => _notice = 'Не удалось проверить обновления: $e');
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Настройки')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_notice != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: SelectableText(_notice!)),
      const Text('Язык', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: _value.language,
        items: const [
          DropdownMenuItem(value: 'ru', child: Text('Русский')),
          DropdownMenuItem(value: 'en', child: Text('English')),
          DropdownMenuItem(value: 'de', child: Text('Deutsch')),
        ],
        onChanged: (v) { if (v != null) _save(_value.copyWith(language: v)); },
      ),
      SwitchListTile(title: const Text('Уведомления'), value: _value.notificationsEnabled,
        onChanged: (v) => _save(_value.copyWith(notificationsEnabled: v))),
      SwitchListTile(title: const Text('Автовоспроизведение'), value: _value.autoplay,
        onChanged: (v) => _save(_value.copyWith(autoplay: v))),
      SwitchListTile(title: const Text('Показывать взрослый контент в обычных профилях'),
        value: _value.adultContentAllowed,
        onChanged: (v) => _save(_value.copyWith(adultContentAllowed: v))),
      const SizedBox(height: 10),
      const Text('Максимальный возрастной рейтинг для детского профиля'),
      Slider(value: _value.maxChildRating.toDouble(), min: 0, max: 18, divisions: 6,
        label: '${_value.maxChildRating}+',
        onChanged: (v) => setState(() => _value = _value.copyWith(maxChildRating: v.round())),
        onChangeEnd: (_) => _save(_value)),
      ListTile(title: const Text('Резервная копия настроек'),
        subtitle: const Text('Создаёт JSON-файл без паролей и PIN'),
        trailing: const Icon(Icons.backup), onTap: _backup),
      const ListTile(title: Text('Диагностика'), subtitle: Text('Проверка соединения и доступности сервисов будет расширена в следующем обновлении.')),
      ListTile(
        title: const Text('Проверить обновления'),
        subtitle: Text(_checkingUpdates ? 'Связываемся с GitHub…' : 'Проверить наличие новой версии KinoKino'),
        trailing: _checkingUpdates
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.system_update_alt),
        onTap: _checkingUpdates ? null : _checkForUpdates,
      ),
    ]),
  );
}
