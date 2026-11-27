import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/zagonka_screen.dart';
import 'services/auth_service.dart';
import 'services/profile_service.dart';
import 'services/settings_service.dart';
import 'services/app_update_service.dart';

class KinoKinoApp extends StatefulWidget {
  const KinoKinoApp({super.key, this.tvMode = false});
  final bool tvMode;
  @override
  State<KinoKinoApp> createState() => _KinoKinoAppState();
}
class _KinoKinoAppState extends State<KinoKinoApp> {
  final ProfileService _profiles = ProfileService();
  final SettingsService _settings = SettingsService();
  final AppUpdateService _updates = AppUpdateService();
  bool _ready = false;
  bool _updatePromptShown = false;
  String? _profileEnsuredForUser;
  Timer? _updateTimer;
  bool _updateCheckRunning = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // TV firmware can lack secure-storage services. A local storage failure
    // must not strand a successfully authenticated user on a loading screen.
    try { await _profiles.initialize(); } catch (_) {}
    try { await _settings.initialize(); } catch (_) {}
    if (!mounted) return;
    setState(() => _ready = true);
    _scheduleUpdateChecks();
  }

  void _scheduleUpdateChecks() {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    _checkIfUpdateCheckDue();
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkIfUpdateCheckDue());
  }

  Future<void> _checkIfUpdateCheckDue() async {
    if (_updateCheckRunning || !_settings.settings.autoUpdatesEnabled || _updatePromptShown) return;
    _updateCheckRunning = true;
    try {
      final due = await _settings.isUpdateCheckDue(_settings.settings.updateIntervalHours);
      if (due && mounted) await _checkForUpdates();
    } finally {
      _updateCheckRunning = false;
    }
  }

  Future<void> _checkForUpdates() async {
    if (_updatePromptShown) return;
    try {
      final update = await _updates.checkForUpdate();
      await _settings.markUpdateCheck();
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
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _settings,
    builder: (context, _) {
      final settings = _settings.settings;
      timeDilation = settings.animationsEnabled ? 1 / settings.animationSpeed : 1.0;
      return MaterialApp(
    title: 'KinoKino',
    debugShowCheckedModeBanner: false,
    locale: Locale(settings.language),
    supportedLocales: const [Locale('ru'), Locale('en'), Locale('de')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.darkWithAccent(Color(settings.accentColorValue)),
    builder: (context, child) {
      final media = MediaQuery.of(context);
      return TickerMode(
        enabled: settings.animationsEnabled,
        child: MediaQuery(
          data: media.copyWith(disableAnimations: !settings.animationsEnabled || media.disableAnimations),
          child: child ?? const SizedBox.shrink(),
        ),
      );
    },
    home: const bool.fromEnvironment('KINO_PLAYER_SMOKE_TEST')
        ? const ZagonkaScreen(
            title: 'KinoKino Android player smoke test',
            kinopoiskId: 258687,
          )
        : StreamBuilder<AuthState>(
            stream: Supabase.instance.client.auth.onAuthStateChange,
            builder: (context, snapshot) {
              final user = Supabase.instance.client.auth.currentUser;
              if (user == null) return AuthScreen(tvMode: widget.tvMode);
              if (_profileEnsuredForUser != user.id) {
                _profileEnsuredForUser = user.id;
                AuthService().ensureProfile(user.id, user.userMetadata?['display_name'] as String?)
                  .catchError((_) { _profileEnsuredForUser = null; });
              }
              return _ready
                ? HomeScreen(profileService: _profiles, settingsService: _settings)
                : const Scaffold(body: Center(child: CircularProgressIndicator()));
            },
          ),
    );
    },
  );
}
