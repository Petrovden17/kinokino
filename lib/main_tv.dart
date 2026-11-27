import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'services/secure_auth_local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await Supabase.initialize(
    url: 'https://rsubtcrfnpqijpwjcbyc.supabase.co',
    publishableKey: 'sb_publishable_A9NQcq9Umjv5yjcYyIWEZQ_5CKetTKu',
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureAuthLocalStorage(),
    ),
  );
  runApp(const KinoKinoApp(tvMode: true));
}
