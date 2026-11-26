import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'services/secure_auth_local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://rsubtcrfnpqijpwjcbyc.supabase.co',
    publishableKey: 'sb_publishable_A9NQcq9Umjv5yjcYyIWEZQ_5CKetTKu',
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureAuthLocalStorage(),
    ),
  );
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    await windowManager.ensureInitialized();
    await windowManager.setFullScreen(false);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const KinoKinoApp());
}
