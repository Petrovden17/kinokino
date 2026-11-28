import 'dart:io';
import 'package:dio/dio.dart';

class BetaReleaseService {
  BetaReleaseService() : _dio = Dio(BaseOptions(
    baseUrl: 'https://api.github.com/repos/Petrovden17/kinokino',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: const {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'KinoKino-App',
    },
  ));

  final Dio _dio;

  Future<Map<String, dynamic>?> latest() async {
    final isAndroid = Platform.isAndroid;
    final tagPattern = isAndroid ? RegExp(r'^build-(\d+)$') : RegExp(r'^beta-(\d+)$');
    final assetName = isAndroid ? 'app-release.apk' : 'KinoKino-Beta-Windows-x64.zip';
    final response = await _dio.get('/releases', queryParameters: {'per_page': 30});
    final releases = response.data as List? ?? const [];
    Map<String, dynamic>? latestRelease;
    var latestBuild = -1;
    for (final value in releases) {
      if (value is! Map || value['prerelease'] != true || value['draft'] == true) continue;
      final release = Map<String, dynamic>.from(value);
      final tag = (release['tag_name'] ?? '').toString();
      final match = tagPattern.firstMatch(tag);
      final build = int.tryParse(match?.group(1) ?? '');
      if (build == null || build <= latestBuild) continue;
      final assets = (release['assets'] as List? ?? const [])
          .whereType<Map>()
          .map((asset) => Map<String, dynamic>.from(asset));
      Map<String, dynamic>? matchingAsset;
      for (final asset in assets) {
        if (asset['name'] == assetName && asset['browser_download_url'] != null) {
          matchingAsset = asset;
          break;
        }
      }
      if (matchingAsset == null) continue;
      release['beta_asset'] = matchingAsset;
      latestBuild = build;
      latestRelease = release;
    }
    return latestRelease;
  }
}
