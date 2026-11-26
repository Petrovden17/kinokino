import 'package:dio/dio.dart';

class ArchiveVideo {
  const ArchiveVideo({
    required this.identifier,
    required this.title,
    required this.creator,
    required this.license,
    required this.fileName,
    required this.url,
  });
  final String identifier;
  final String title;
  final String creator;
  final String license;
  final String fileName;
  final Uri url;
}

class InternetArchiveService {
  InternetArchiveService() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 35),
    responseType: ResponseType.plain,
    headers: const {'User-Agent': 'KinoKino/1.0 (public-domain and openly-licensed media)'},
  ));

  final Dio _dio;

  static const _moviePlaylist =
      'https://raw.githubusercontent.com/OnlineM3U/publicdomainm3u/main/movies.m3u';
  static const _seriesPlaylist =
      'https://raw.githubusercontent.com/OnlineM3U/publicdomainm3u/main/series.m3u';

  bool _isAllowedLicense(String value) {
    final license = value.toLowerCase();
    return license.contains('creativecommons.org/licenses/by/3.0') ||
        license.contains('creativecommons.org/licenses/by/4.0') ||
        license.contains('creativecommons.org/licenses/by-sa/3.0') ||
        license.contains('creativecommons.org/licenses/by-sa/4.0') ||
        license.contains('creativecommons.org/publicdomain/zero/1.0') ||
        license.contains('creativecommons.org/publicdomain/mark/1.0') ||
        license.contains('creativecommons.org/licenses/publicdomain');
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\(\d{4}\)'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9а-яё]+', unicode: true), ' ')
      .trim();

  Future<ArchiveVideo?> _findInPlaylist(String title, {required bool isSeries}) async {
    final response = await _dio.get<String>(isSeries ? _seriesPlaylist : _moviePlaylist);
    final text = response.data ?? '';
    final lines = text.split(RegExp(r'\r?\n'));
    final wanted = _normalize(title);
    if (wanted.isEmpty) return null;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXTINF:')) continue;
      final comma = line.lastIndexOf(',');
      if (comma < 0 || i + 1 >= lines.length) continue;
      final name = line.substring(comma + 1).trim();
      final urlLine = lines.skip(i + 1).firstWhere(
        (candidate) => candidate.trim().isNotEmpty && !candidate.trim().startsWith('#'),
        orElse: () => '',
      ).trim();
      if (urlLine.isEmpty) continue;
      final normalized = _normalize(name);
      final matches = normalized == wanted ||
          normalized.startsWith('$wanted ') ||
          wanted.startsWith('$normalized ');
      if (!matches) continue;
      final uri = Uri.tryParse(urlLine);
      if (uri == null || uri.scheme != 'https' || uri.host != 'archive.org') continue;
      return ArchiveVideo(
        identifier: uri.pathSegments.length > 1 ? uri.pathSegments[1] : 'public-domain-playlist',
        title: name,
        creator: 'Internet Archive',
        license: 'Подборка PublicDomainM3U (публичный каталог; проверяйте статус в своей стране)',
        fileName: uri.pathSegments.isNotEmpty ? Uri.decodeComponent(uri.pathSegments.last) : name,
        url: uri,
      );
    }
    return null;
  }

  Future<ArchiveVideo?> findLicensedVideo(String title, {bool isSeries = false}) async {
    // Prefer a maintained, curated M3U feed with direct MP4 links.
    try {
      final curated = await _findInPlaylist(title, isSeries: isSeries);
      if (curated != null) return curated;
    } catch (_) {
      // Continue to the Internet Archive search for films if the feed is unavailable.
    }
    // If the curated series playlist has no exact match, search the Archive metadata too.

    final query = 'title:"${title.replaceAll('"', '').trim()}"';
    final search = await _dio.get<dynamic>('https://archive.org/advancedsearch.php',
      queryParameters: {
        'q': query,
        'fl[]': ['identifier', 'title'],
        'rows': 12,
        'page': 1,
        'output': 'json',
      },
      options: Options(responseType: ResponseType.json),
    );
    final docs = (search.data['response']?['docs'] as List? ?? const [])
        .whereType<Map>().toList();

    for (final doc in docs) {
      final id = doc['identifier']?.toString();
      if (id == null || id.isEmpty) continue;
      try {
        final response = await _dio.get<dynamic>('https://archive.org/metadata/$id',
          options: Options(responseType: ResponseType.json));
        final data = response.data as Map<String, dynamic>;
        final metadata = data['metadata'] as Map<String, dynamic>? ?? {};
        final license = (metadata['licenseurl'] ?? metadata['rights'] ?? '').toString();
        if (!_isAllowedLicense(license)) continue;

        final files = (data['files'] as List? ?? const []).whereType<Map>().toList()
          ..sort((a, b) {
            int rank(Map f) {
              final n = (f['name'] ?? '').toString().toLowerCase();
              final format = (f['format'] ?? '').toString().toLowerCase();
              if (n.endsWith('.mp4') && (n.contains('h264') || format.contains('h.264'))) return 0;
              if (n.endsWith('.mp4')) return 1;
              if (n.endsWith('.mov')) return 2;
              return 3;
            }
            return rank(a).compareTo(rank(b));
          });
        for (final file in files) {
          final name = file['name']?.toString() ?? '';
          final lower = name.toLowerCase();
          final width = int.tryParse(file['width']?.toString() ?? '') ?? 0;
          final height = int.tryParse(file['height']?.toString() ?? '') ?? 0;
          final video = lower.endsWith('.mp4') || lower.endsWith('.mov');
          if (!video || (width == 0 && height == 0)) continue;
          final encodedName = Uri.encodeComponent(name);
          return ArchiveVideo(
            identifier: id,
            title: (metadata['title'] ?? doc['title'] ?? title).toString(),
            creator: (metadata['creator'] ?? 'Не указан').toString(),
            license: license,
            fileName: name,
            url: Uri.parse('https://archive.org/download/$id/$encodedName'),
          );
        }
      } catch (_) {
        // Skip unavailable or malformed archive items.
      }
    }
    return null;
  }
}
