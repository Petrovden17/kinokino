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
  static const int currentBuild = int.fromEnvironment('APP_BUILD', defaultValue: 6);
  static const String releasesApi = 'https://api.github.com/repos/Petrovden17/kinokino/releases/latest';
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(minutes: 5)));

  Future<AppUpdateInfo?> checkForUpdate() async {
    if (!Platform.isWindows) return null;
    final response = await _dio.get(releasesApi, options: Options(headers: {'Accept': 'application/vnd.github+json'}));
    final data = response.data;
    if (data is! Map || data['draft'] == true || data['prerelease'] == true) return null;
    final tag = (data['tag_name'] ?? '').toString();
    final match = RegExp(r'^build-(\d+).firstMatch(tag);
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
    await _dio.download(update.downloadUrl, zipPath,
      options: Options(headers: {'Accept': 'application/octet-stream'}));
    final script = File(scriptPath);
    await script.writeAsString(r'''
param([string]$Archive, [string]$InstallDir, [string]$Exe, [int]$ParentPid)
$ErrorActionPreference = 'Stop'
$stage = Join-Path $env:TEMP ("KinoKino-stage-" + [guid]::NewGuid().ToString("N"))
$backup = Join-Path $env:TEMP ("KinoKino-backup-" + [guid]::NewGuid().ToString("N"))
try {
  try {
    if (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
      Wait-Process -Id $ParentPid -Timeout 60 -ErrorAction SilentlyContinue
    }
  } catch {}
  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  Expand-Archive -LiteralPath $Archive -DestinationPath $stage -Force
  $exeName = [IO.Path]::GetFileName($Exe)
  $newExe = Get-ChildItem -LiteralPath $stage -Filter $exeName -Recurse -File | Select-Object -First 1
  if ($null -eq $newExe) { throw "В архиве отсутствует $exeName" }
  $sourceDir = $newExe.Directory.FullName
  if (-not (Test-Path -LiteralPath $InstallDir)) { throw "Папка приложения не найдена: $InstallDir" }
  Copy-Item -LiteralPath $InstallDir -Destination $backup -Recurse -Force
  try {
    Copy-Item -Path (Join-Path $sourceDir '*') -Destination $InstallDir -Recurse -Force
  } catch {
    Copy-Item -Path (Join-Path $backup '*') -Destination $InstallDir -Recurse -Force
    throw
  }
  Start-Process -FilePath $Exe -WorkingDirectory $InstallDir
  Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show("Не удалось установить обновление KinoKino: $($_.Exception.Message)")
  if (Test-Path -LiteralPath $Exe) {
    Start-Process -FilePath $Exe -WorkingDirectory $InstallDir
  }
}
''');
    await Process.start('powershell.exe', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath,
      '-Archive', zipPath,
      '-InstallDir', installDir,
      '-Exe', executable,
      '-ParentPid', pid.toString(),
    ], mode: ProcessStartMode.detached);
    exit(0);
  }
}
).firstMatch(tag);
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
    final zipPath = '${temp.path}\\\\KinoKino-update.zip';
    final scriptPath = '${temp.path}\\\\kinokino-update.ps1';
    await _dio.download(update.downloadUrl, zipPath,
      options: Options(headers: {'Accept': 'application/octet-stream'}));
    final script = File(scriptPath);
    await script.writeAsString(r'''
param([string]$Archive, [string]$InstallDir, [string]$Exe, [int]$ParentPid)
$ErrorActionPreference = 'Stop'
$stage = Join-Path $env:TEMP ("KinoKino-stage-" + [guid]::NewGuid().ToString("N"))
$backup = Join-Path $env:TEMP ("KinoKino-backup-" + [guid]::NewGuid().ToString("N"))
try {
  try {
    if (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
      Wait-Process -Id $ParentPid -Timeout 60 -ErrorAction SilentlyContinue
    }
  } catch {}
  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  Expand-Archive -LiteralPath $Archive -DestinationPath $stage -Force
  $exeName = [IO.Path]::GetFileName($Exe)
  $newExe = Get-ChildItem -LiteralPath $stage -Filter $exeName -Recurse -File | Select-Object -First 1
  if ($null -eq $newExe) { throw "В архиве отсутствует $exeName" }
  $sourceDir = $newExe.Directory.FullName
  if (-not (Test-Path -LiteralPath $InstallDir)) { throw "Папка приложения не найдена: $InstallDir" }
  Copy-Item -LiteralPath $InstallDir -Destination $backup -Recurse -Force
  try {
    Copy-Item -Path (Join-Path $sourceDir '*') -Destination $InstallDir -Recurse -Force
  } catch {
    Copy-Item -Path (Join-Path $backup '*') -Destination $InstallDir -Recurse -Force
    throw
  }
  Start-Process -FilePath $Exe -WorkingDirectory $InstallDir
  Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show("Не удалось установить обновление KinoKino: $($_.Exception.Message)")
  if (Test-Path -LiteralPath $Exe) {
    Start-Process -FilePath $Exe -WorkingDirectory $InstallDir
  }
}
''');
    await Process.start('powershell.exe', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath,
      '-Archive', zipPath,
      '-InstallDir', installDir,
      '-Exe', executable,
      '-ParentPid', pid.toString(),
    ], mode: ProcessStartMode.detached);
    exit(0);
  }
}
