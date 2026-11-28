import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../services/backup_service.dart';
import '../services/app_update_service.dart';
import '../services/beta_release_service.dart';
import '../services/creator_service.dart';
import '../services/auth_service.dart';
import '../services/tmdb_service.dart';

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
  bool _isCreator = false;
  bool _betaLoading = false;
  bool _betaInstalling = false;
  bool _diagnosticsRunning = false;
  String? _diagnosticsResult;
  Map<String, dynamic>? _betaRelease;
  final AppUpdateService _updates = AppUpdateService();

  @override
  void initState() {
    super.initState();
    _value = widget.service.settings;
    _loadBetaAccess();
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


  String _languageLabel(String code) => switch (code) {
    'en' => 'English',
    'de' => 'Deutsch',
    _ => 'Русский',
  };

  Future<void> _changeLanguage(String? language) async {
    if (language == null || language == _value.language) return;
    final previous = _value.language;
    await _save(_value.copyWith(language: language));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(previous == 'ru' ? 'Язык изменён' : 'Language changed'),
        content: Text(previous == 'ru'
          ? 'Выбран язык: ${_languageLabel(language)}. Подтвердить изменение?'
          : 'Selected language: ${_languageLabel(language)}. Confirm?'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _save(_value.copyWith(language: previous));
            },
            child: Text(previous == 'ru' ? 'Вернуть ${_languageLabel(previous)}' : 'Restore ${_languageLabel(previous)}'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(previous == 'ru' ? 'Подтвердить' : 'Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _runDiagnostics() async {
    if (_diagnosticsRunning) return;
    setState(() { _diagnosticsRunning = true; _diagnosticsResult = 'Проверяем…'; });
    final lines = <String>[];
    try {
      await Supabase.instance.client.auth.getUser();
      lines.add('Supabase: соединение успешно');
    } catch (e) {
      lines.add('Supabase: ошибка — $e');
    }
    try {
      final items = await TmdbService().trending();
      lines.add('TMDB: доступен (${items.length} карточек получено)');
    } catch (e) {
      lines.add('TMDB: ошибка — $e');
    }
    if (!mounted) return;
    setState(() {
      _diagnosticsResult = lines.join('\\n');
      _diagnosticsRunning = false;
    });
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

  Future<void> _loadBetaAccess() async {
    try {
      final creator = await CreatorService().isCreator();
      if (!mounted) return;
      setState(() => _isCreator = creator);
      if (!creator) return;
      setState(() => _betaLoading = true);
      final release = await BetaReleaseService().latest();
      if (mounted) setState(() => _betaRelease = release);
    } catch (_) {
      // Beta controls are optional and remain hidden if creator access cannot be verified.
    } finally {
      if (mounted) setState(() => _betaLoading = false);
    }
  }


  Future<void> _installBetaRelease() async {
    if (!Platform.isWindows) {
      setState(() => _notice = 'Установка бета-версий сейчас доступна только в Windows.');
      return;
    }
    final release = _betaRelease;
    final asset = release?['beta_asset'];
    final url = asset is Map ? (asset['browser_download_url'] ?? '').toString() : '';
    final tag = (release?['tag_name'] ?? '').toString();
    if (url.isEmpty || tag.isEmpty) {
      setState(() => _notice = 'Бета-сборка пока не опубликована. Нажми «Проверить» позже.');
      return;
    }
    setState(() { _betaInstalling = true; _notice = 'Загружаем и устанавливаем бета-версию…'; });
    try {
      await _updates.downloadAndInstall(AppUpdateInfo(
        tag: tag,
        downloadUrl: url,
        notes: (release?['body'] ?? '').toString(),
      ));
    } catch (e) {
      if (mounted) setState(() => _notice = 'Не удалось установить бета-версию: $e');
    } finally {
      if (mounted) setState(() => _betaInstalling = false);
    }
  }

  Widget _betaSettingsSection() {
    final release = _betaRelease;
    final tag = (release?['tag_name'] ?? '').toString();
    final name = (release?['name'] ?? tag).toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.science_outlined),
            SizedBox(width: 10),
            Text('Бета-версии', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          Text(_betaLoading
              ? 'Проверяем тестовые сборки…'
              : release == null
                  ? 'Пока нет опубликованной тестовой сборки. Новая бета появится после успешной сборки Windows.'
                  : 'Последняя сборка: $name'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _betaLoading || _betaInstalling ? null : _loadBetaAccess,
              icon: const Icon(Icons.refresh),
              label: const Text('Проверить'),
            ),
            FilledButton.icon(
              onPressed: release == null || _betaLoading || _betaInstalling
                  ? null : _installBetaRelease,
              icon: _betaInstalling
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
              label: Text(_betaInstalling ? 'Устанавливаем…' : 'Установить бета-версию'),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    if (_checkingUpdates) return;
    if (!Platform.isWindows && !Platform.isAndroid) {
      setState(() => _notice = 'Проверка обновлений для этой платформы пока не поддерживается.');
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
      if (Platform.isAndroid) {
        final download = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Доступно обновление KinoKino'),
            content: SingleChildScrollView(child: Text(
              'Найдена версия ${update.tag}. APK будет загружен через браузер. После загрузки откройте файл и подтвердите установку.\\n\\n${update.notes.isEmpty ? 'Исправления и улучшения.' : update.notes}',
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Позже')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.download),
                label: const Text('Скачать APK'),
              ),
            ],
          ),
        );
        if (download == true) {
          final uri = Uri.tryParse(update.downloadUrl);
          if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            throw StateError('Не удалось открыть ссылку загрузки APK.');
          }
          if (mounted) setState(() => _notice = 'Откройте загруженный APK и подтвердите обновление приложения.');
        }
      } else {
        setState(() => _notice = 'Доступно обновление ${update.tag}.');
        final install = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Доступно обновление KinoKino'),
            content: SingleChildScrollView(
              child: Text('Найдена версия ${update.tag}. Приложение скачает архив и перезапустится автоматически.\\n\\n${update.notes.isEmpty ? 'Исправления и улучшения.' : update.notes}'),
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
        if (install == true) await _updates.downloadAndInstall(update);
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
    body: SafeArea(top: false, child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
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
      if (_isCreator) ...[
        _betaSettingsSection(),
        const SizedBox(height: 14),
      ],
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
        initialValue: _value.language,
        items: const [
          DropdownMenuItem(value: 'ru', child: Text('Русский')),
          DropdownMenuItem(value: 'en', child: Text('English')),
          DropdownMenuItem(value: 'de', child: Text('Deutsch')),
        ],
        onChanged: _changeLanguage,
      ),
      SwitchListTile(title: const Text('Уведомления'), value: _value.notificationsEnabled,
        onChanged: (v) => _save(_value.copyWith(notificationsEnabled: v))),
      SwitchListTile(title: const Text('Автовоспроизведение'), value: _value.autoplay,
        onChanged: (v) => _save(_value.copyWith(autoplay: v))),
      const Divider(height: 28),
      SwitchListTile(
        secondary: const Icon(Icons.animation),
        title: const Text('Анимации интерфейса'),
        subtitle: const Text('Плавное появление экранов и переходы между элементами'),
        value: _value.animationsEnabled,
        onChanged: (v) => _save(_value.copyWith(animationsEnabled: v)),
      ),
      ListTile(
        contentPadding: const EdgeInsets.only(left: 16, right: 8),
        title: const Text('Скорость анимаций'),
        subtitle: const Text('Можно замедлить или ускорить переходы'),
        trailing: DropdownButton<double>(
          value: _value.animationSpeed,
          items: const [
            DropdownMenuItem(value: 0.5, child: Text('0,5×')),
            DropdownMenuItem(value: 0.75, child: Text('0,75×')),
            DropdownMenuItem(value: 1.0, child: Text('1×')),
            DropdownMenuItem(value: 1.25, child: Text('1,25×')),
            DropdownMenuItem(value: 1.5, child: Text('1,5×')),
            DropdownMenuItem(value: 2.0, child: Text('2×')),
          ],
          onChanged: _value.animationsEnabled
              ? (v) { if (v != null) _save(_value.copyWith(animationSpeed: v)); }
              : null,
        ),
      ),
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
      Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.health_and_safety_outlined),
            SizedBox(width: 8),
            Text('Диагностика', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          const Text('Проверить подключение к Supabase и каталогу TMDB.'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _diagnosticsRunning ? null : _runDiagnostics,
            icon: _diagnosticsRunning
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow),
            label: Text(_diagnosticsRunning ? 'Проверяем…' : 'Запустить диагностику'),
          ),
          if (_diagnosticsResult != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_diagnosticsResult!)),
        ]),
      )),
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
    ])),
  );
}
