import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  const AppUpdateInfo({required this.tag, required this.downloadUrl, required this.notes});
  final String tag;
  final String downloadUrl;
  final String notes;
}

class AppUpdateService {
  static const int currentBuild = int.fromEnvironment('APP_BUILD', defaultValue: 5);
  static const String releasesApi = 'https://api.github.com/repos/Petrovden17/kinokino/releases/latest';
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(minutes: 5)));

  Future<AppUpdateInfo?> checkForUpdate() async {
    if (!Platform.isWindows) return null;
    final response = await _dio.get(releasesApi, options: Options(headers: {'Accept': 'application/vnd.github+json'}));
    final data = response.data;
    if (data is! Map || data['draft'] == true || data['prerelease'] == true) return null;
    final tag = (data['tag_name'] ?? '').toString();
    final match = RegExp(r'^build-(\d+)$').firstMatch(tag);
    final latestBuild = int.tryParse(match?.group(1) ?? '');
    if (latestBuild == null || latestBuild <= currentBuild) return null;
    final assets = data['assets'] as List? ?? const [];
    for (final asset in assets.whereType<Map>()) {
      if (asset['name'] == 'KinoKino-Windows-x64.zip' && asset['browser_download_url'] != null) {
        return AppUpdateInfo(tag: tag, downloadUrl: asset['browser_download_url'].toString(), notes: (data['body'] ?? '').toString());
      }
    }
    return null;
  }

  Future<void> downloadAndInstall(AppUpdateInfo update) async {
    if (!Platform.isWindows) throw UnsupportedError('Автообновление доступно только в Windows.');
    final executable = Platform.resolvedExecutable;
    final installDir = File(executable).parent.path;
    final temp = await getTemporaryDirectory();
    final zipPath = '${temp.path}\\KinoKino-update.zip';
    final scriptPath = '${temp.path}\\kinokino-update.ps1';
    await _dio.download(update.downloadUrl, zipPath, options: Options(headers: {'Accept': 'application/octet-stream'}));
    final script = File(scriptPath);
    await script.writeAsString(r'''
param([string]$Archive, [string]$InstallDir, [string]$Exe)
$ErrorActionPreference = 'Stop'
try {
  Start-Sleep -Seconds 2
  Expand-Archive -LiteralPath $Archive -DestinationPath $InstallDir -Force
  Start-Process -FilePath $Exe -WorkingDirectory $InstallDir
  Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
} catch {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show("Не удалось установить обновление KinoKino: $($_.Exception.Message)")
}
''');
    await Process.start('powershell.exe', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath,
      '-Archive', zipPath,
      '-InstallDir', installDir, '-Exe', executable,
    ], mode: ProcessStartMode.detached);
    exit(0);
  }
}
