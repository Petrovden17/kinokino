import 'package:dio/dio.dart';

class BetaReleaseService {
  BetaReleaseService() : _dio = Dio(BaseOptions(
    baseUrl: 'https://api.github.com/repos/Petrovden17/kinokino',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: const {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'KinoKino-Windows-App',
    },
  ));

  final Dio _dio;

  Future<Map<String, dynamic>?> latest() async {
    final response = await _dio.get('/releases', queryParameters: {'per_page': 10});
    final releases = response.data as List? ?? const [];
    for (final value in releases) {
      if (value is! Map || value['prerelease'] != true || value['draft'] == true) {
        continue;
      }
      final release = Map<String, dynamic>.from(value);
      final assets = (release['assets'] as List? ?? const [])
          .whereType<Map>()
          .map((asset) => Map<String, dynamic>.from(asset))
          .where((asset) => (asset['name'] ?? '').toString().toLowerCase().endsWith('.zip'))
          .toList();
      if (assets.isEmpty) continue;
      release['beta_asset'] = assets.first;
      return release;
    }
    return null;
  }
}
