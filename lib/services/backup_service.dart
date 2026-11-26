import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/app_settings.dart';

class BackupService {
  // Export only app settings here. Profile secrets and secure-storage values
  // are intentionally excluded from plaintext backups.
  Future<File> exportSettings(AppSettings settings) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/kinokino-settings-backup.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'format': 'kinokino-settings-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings.toJson(),
    }));
    return file;
  }

  Future<AppSettings> importSettings(File file) async {
    final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (decoded['format'] != 'kinokino-settings-backup' || decoded['version'] != 1) {
      throw const FormatException('Неподдерживаемый файл резервной копии.');
    }
    return AppSettings.fromJson(Map<String, dynamic>.from(decoded['settings'] as Map));
  }
}
