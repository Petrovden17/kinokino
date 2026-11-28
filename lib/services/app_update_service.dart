import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class AppUpdateInfo {
  const AppUpdateInfo({required this.tag, required this.downloadUrl, required this.notes});
  final String tag;
  final String downloadUrl;
  final String notes;
}

class AppUpdateService {
  static const int currentBuild = int.fromEnvironment('APP_BUILD', defaultValue: 8);
  static const String releasesApi = 'https://api.github.com/repos/Petrovden17/kinokino/releases?per_page=30';
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(minutes: 5)));

  Future<AppUpdateInfo?> checkForUpdate() async {
    if (!Platform.isWindows && !Platform.isAndroid) {
      throw UnsupportedError('Проверка обновлений недоступна на этой платформе.');
    }
    final response = await _dio.get(
      releasesApi,
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
    final data = response.data;
    if (data is! List) throw const FormatException('GitHub вернул некорректный список релизов.');

    final isAndroid = Platform.isAndroid;
    final tagPattern = isAndroid ? RegExp(r'^build-(\d+)$') : RegExp(r'^beta-(\d+)$');
    final assetName = isAndroid ? 'app-release.apk' : 'KinoKino-Beta-Windows-x64.zip';
    Map? latestRelease;
    var latestBuild = -1;
    for (final release in data.whereType<Map>().where((release) => release['draft'] != true)) {
      final tag = (release['tag_name'] ?? '').toString();
      final match = tagPattern.firstMatch(tag);
      final build = int.tryParse(match?.group(1) ?? '');
      if (build != null && build > latestBuild) {
        latestBuild = build;
        latestRelease = release;
      }
    }
    if (latestRelease == null || latestBuild <= currentBuild) return null;

    final tag = (latestRelease['tag_name'] ?? '').toString();
    final assets = latestRelease['assets'] as List? ?? const [];
    for (final asset in assets.whereType<Map>()) {
      if (asset['name'] == assetName && asset['browser_download_url'] != null) {
        return AppUpdateInfo(
          tag: tag,
          downloadUrl: asset['browser_download_url'].toString(),
          notes: (latestRelease['body'] ?? '').toString(),
        );
      }
    }
    throw StateError('Релиз $tag найден, но файл $assetName не опубликован.');
  }

  static const MethodChannel _androidInstaller =
      MethodChannel('kinokino/android_installer');

  Future<String> downloadAndroidApk(
    AppUpdateInfo update, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Загрузка APK доступна только на Android.');
    }
    final temp = await getTemporaryDirectory();
    final directory = Directory('${temp.path}/apk_updates');
    await directory.create(recursive: true);
    final safeTag = update.tag.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '${directory.path}/kinokino-$safeTag.apk';
    await _dio.download(
      update.downloadUrl,
      path,
      onReceiveProgress: onProgress,
      deleteOnError: true,
      options: Options(
        headers: const {'Accept': 'application/octet-stream'},
      ),
    );
    final apk = File(path);
    if (!await apk.exists() || await apk.length() < 1024 * 1024) {
      await apk.delete().catchError((_) => apk);
      throw StateError('Скачанный APK повреждён или слишком мал.');
    }
    final handle = await apk.open();
    final signature = await handle.read(4);
    await handle.close();
    if (signature.length < 4 || signature[0] != 0x50 || signature[1] != 0x4b) {
      await apk.delete().catchError((_) => apk);
      throw const FormatException('Загруженный файл не является APK-архивом.');
    }
    return path;
  }

  Future<bool> installAndroidApk(String path) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Установка APK доступна только на Android.');
    }
    return await _androidInstaller.invokeMethod<bool>(
          'installApk',
          {'path': path},
        ) ??
        false;
  }

  Future<void> downloadAndInstall(AppUpdateInfo update) async {
    if (!Platform.isWindows) throw UnsupportedError('Автообновление доступно только в Windows.');
    final executable = Platform.resolvedExecutable;
    final installDir = File(executable).parent.path;
    final temp = await getTemporaryDirectory();
    final zipPath = temp.path + r'\KinoKino-update.zip';
    final scriptPath = temp.path + r'\kinokino-update.ps1';
    await _dio.download(update.downloadUrl, zipPath, options: Options(headers: {'Accept': 'application/octet-stream'}));
    final script = File(scriptPath);
    await script.writeAsString(r'''
param([string]$Archive, [string]$InstallDir, [string]$Exe, [int]$ParentPid)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  $q = [char]34
  $argsLine = '-NoProfile -ExecutionPolicy Bypass -File ' + $q + $PSCommandPath + $q + ' -Archive ' + $q + $Archive + $q + ' -InstallDir ' + $q + $InstallDir + $q + ' -Exe ' + $q + $Exe + $q + ' -ParentPid ' + $ParentPid
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argsLine
  exit 0
}
$stage = Join-Path $env:TEMP ("KinoKino-stage-" + [guid]::NewGuid().ToString("N"))
$backup = Join-Path $env:TEMP ("KinoKino-backup-" + [guid]::NewGuid().ToString("N"))
$installStarted = $false
try {
  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  Expand-Archive -LiteralPath $Archive -DestinationPath $stage -Force
  $exeName = [IO.Path]::GetFileName($Exe)
  $newExe = Get-ChildItem -LiteralPath $stage -Filter $exeName -Recurse -File | Select-Object -First 1
  if ($null -eq $newExe) { throw "В архиве отсутствует $exeName" }
  $sourceDir = $newExe.Directory.FullName
  if (-not (Test-Path -LiteralPath $InstallDir)) { throw "Папка приложения не найдена: $InstallDir" }
  if (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
    try { Wait-Process -Id $ParentPid -Timeout 90 -ErrorAction Stop }
    catch { if (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) { throw "KinoKino не завершилось перед установкой. Обновление отменено." } }
  }
  Copy-Item -Path (Join-Path $InstallDir '*') -Destination $backup -Recurse -Force
  try {
    Copy-Item -Path (Join-Path $sourceDir '*') -Destination $InstallDir -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $InstallDir $exeName))) { throw "После копирования не найден исполняемый файл $exeName" }
  } catch {
    Get-ChildItem -LiteralPath $InstallDir -Force | Remove-Item -Recurse -Force
    Copy-Item -Path (Join-Path $backup '*') -Destination $InstallDir -Recurse -Force
    throw
  }
  $installStarted = $true
  Start-Process -FilePath $Exe -WorkingDirectory $InstallDir
  Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show("Не удалось установить обновление KinoKino: $($_.Exception.Message)")
  if (-not $installStarted -and (Test-Path -LiteralPath $Exe)) { Start-Process -FilePath $Exe -WorkingDirectory $InstallDir }
  Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
''' );
    await Process.start('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, '-Archive', zipPath, '-InstallDir', installDir, '-Exe', executable, '-ParentPid', pid.toString()], mode: ProcessStartMode.detached);
    exit(0);
  }
}
