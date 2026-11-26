import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/profile_service.dart';
import 'services/settings_service.dart';

class KinoKinoApp extends StatefulWidget {
  const KinoKinoApp({super.key});
  @override
  State<KinoKinoApp> createState() => _KinoKinoAppState();
}
class _KinoKinoAppState extends State<KinoKinoApp> {
  final ProfileService _profiles = ProfileService();
  final SettingsService _settings = SettingsService();
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    Future.wait([_profiles.initialize(), _settings.initialize()]).then((_) {
      if (mounted) setState(() => _ready = true);
    });
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
