import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/profile_service.dart';
import 'services/settings_service.dart';
import 'services/app_update_service.dart';

class KinoKinoApp extends StatefulWidget {
  const KinoKinoApp({super.key});
  @override
  State<KinoKinoApp> createState() => _KinoKinoAppState();
}
class _KinoKinoAppState extends State<KinoKinoApp> {
  final ProfileService _profiles = ProfileService();
  final SettingsService _settings = SettingsService();
  final AppUpdateService _updates = AppUpdateService();
  bool _ready = false;
  bool _updatePromptShown = false;

  @override
  void initState() {
    super.initState();
    Future.wait([_profiles.initialize(), _settings.initialize()]).then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      if (_settings.settings.autoUpdatesEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
      }
    });
  }

  Future<void> _checkForUpdates() async {
    if (_updatePromptShown) return;
    try {
      final update = await _updates.checkForUpdate();
      if (!mounted || update == null) return;
      _updatePromptShown = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Доступно обновление KinoKino'),
          content: SingleChildScrollView(child: Text(
            'Найдена новая версия ${update.tag}. Приложение скачает её и перезапустится автоматически.\n\n${update.notes.isEmpty ? 'Исправления и улучшения.' : update.notes}',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Позже'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await _updates.downloadAndInstall(update);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Не удалось установить обновление: $e')),
                  );
                }
              },
              icon: const Icon(Icons.download),
              label: const Text('Обновить'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Не мешаем запуску приложения, если GitHub временно недоступен.
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'KinoKino',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: _ready
      ? HomeScreen(profileService: _profiles, settingsService: _settings)
      : const Scaffold(body: Center(child: CircularProgressIndicator())),
  );
}
