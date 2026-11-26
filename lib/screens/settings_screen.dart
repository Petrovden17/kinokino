import 'dart:io';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../services/backup_service.dart';
import '../services/app_update_service.dart';
import '../services/auth_service.dart';

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

  Widget _colorChoice(Color color, String label) {
    final selected = _value.accentColorValue == color.value;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _save(_value.copyWith(accentColorValue: color.value)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: .16) : Colors.white.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : Colors.white24, width: selected ? 1.6 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 18, height: 18, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(label),
          if (selected) ...[const SizedBox(width: 5), Icon(Icons.check, size: 15, color: color)],
        ]),
      ),
    );
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

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Синхронизация избранного, оценок и истории доступна после повторного входа.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthService().signOut();
    } catch (e) {
      if (mounted) setState(() => _notice = 'Не удалось выйти: $e');
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
      await widget.service.markUpdateCheck();
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
      if (_notice != null) Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (_notice!.contains('последняя версия') ? Colors.green : Theme.of(context).colorScheme.primary).withValues(alpha: .13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: (_notice!.contains('последняя версия') ? Colors.green : Theme.of(context).colorScheme.primary).withValues(alpha: .45)),
          ),
          child: Row(children: [
            Icon(_notice!.contains('последняя версия') ? Icons.check_circle_outline : Icons.info_outline,
                color: _notice!.contains('последняя версия') ? Colors.greenAccent : Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: SelectableText(_notice!, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
      const Text('Цвет приложения', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 5),
      const Text('Выбери акцентный цвет для кнопок, выделений и элементов интерфейса.'),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _colorChoice(const Color(0xFFFF765E), 'Коралловый'),
        _colorChoice(const Color(0xFF5B9BFF), 'Синий'),
        _colorChoice(const Color(0xFF9B7BFF), 'Фиолетовый'),
        _colorChoice(const Color(0xFF35C99A), 'Изумрудный'),
        _colorChoice(const Color(0xFFFFC45C), 'Золотой'),
        _colorChoice(const Color(0xFFFF5C9A), 'Розовый'),
        _colorChoice(const Color(0xFF5ED8D0), 'Бирюзовый'),
      ]),
      const SizedBox(height: 14),
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
        leading: const Icon(Icons.logout),
        title: const Text('Выйти из аккаунта'),
        subtitle: const Text('Завершить текущий сеанс'),
        onTap: _signOut,
      ),
      SwitchListTile(
        title: const Text('Автоматическая проверка обновлений'),
        subtitle: const Text('Проверять наличие новых версий автоматически по выбранному интервалу'),
        value: _value.autoUpdatesEnabled,
        onChanged: (v) => _save(_value.copyWith(autoUpdatesEnabled: v)),
      ),
      ListTile(
        title: const Text('Интервал автоматической проверки'),
        subtitle: const Text('Как часто KinoKino обращается к GitHub, пока приложение запущено'),
        trailing: DropdownButton<int>(
          value: _value.updateIntervalHours,
          items: const [
            DropdownMenuItem(value: 1, child: Text('1 час')),
            DropdownMenuItem(value: 3, child: Text('3 часа')),
            DropdownMenuItem(value: 6, child: Text('6 часов')),
            DropdownMenuItem(value: 12, child: Text('12 часов')),
            DropdownMenuItem(value: 24, child: Text('24 часа')),
            DropdownMenuItem(value: 48, child: Text('2 дня')),
            DropdownMenuItem(value: 168, child: Text('7 дней')),
          ],
          onChanged: _value.autoUpdatesEnabled
            ? (v) { if (v != null) _save(_value.copyWith(updateIntervalHours: v)); }
            : null,
        ),
      ),
      ListTile(
        title: const Text('Проверить обновления сейчас'),
        subtitle: Text(_checkingUpdates ? 'Связываемся с GitHub…' : 'Проверить наличие новой версии KinoKino'),
        trailing: _checkingUpdates
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.system_update_alt),
        onTap: _checkingUpdates ? null : _checkForUpdates,
      ),
    ]),
  );
}
