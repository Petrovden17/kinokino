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
  static const _nexonicMovies =
      'https://raw.githubusercontent.com/nexonic-technologies/nexonic-iptv/main/playlists/vod/movies.m3u';
  static const _nexonicSeries =
      'https://raw.githubusercontent.com/nexonic-technologies/nexonic-iptv/main/playlists/vod/series.m3u';

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
      .replaceAll(RegExp(r'\(?\s*\d{4}\s*\)?'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9а-яё]+', unicode: true), ' ')
      .trim();

  Future<ArchiveVideo?> _findInPlaylist(String title, {required bool isSeries}) async {
    final wanted = _normalize(title);
    if (wanted.isEmpty) return null;
    final urls = isSeries
        ? <String>[_nexonicSeries, _seriesPlaylist]
        : <String>[_nexonicMovies, _moviePlaylist];
    for (final playlistUrl in urls) {
      try {
        final response = await _dio.get<String>(playlistUrl);
        final lines = (response.data ?? '').split(RegExp(r'\r?\n'));
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (!line.startsWith('#EXTINF:')) continue;
          final comma = line.lastIndexOf(',');
          if (comma < 0 || i + 1 >= lines.length) continue;
          final entryTitle = line.substring(comma + 1).trim();
          final groupMatch = RegExp(r'group-title="([^"]+)"').firstMatch(line);
          final groupTitle = groupMatch?.group(1) ?? '';
          final normalizedTitle = _normalize(entryTitle);
          final normalizedGroup = _normalize(groupTitle);
          final matches = normalizedTitle == wanted ||
              normalizedTitle.startsWith('$wanted ') ||
              wanted.startsWith('$normalizedTitle ') ||
              (normalizedGroup.isNotEmpty &&
                (normalizedGroup == wanted ||
                 normalizedGroup.startsWith('$wanted ') ||
                 wanted.startsWith('$normalizedGroup ')));
          if (!matches) continue;
          var next = i + 1;
          while (next < lines.length &&
              (lines[next].trim().isEmpty || lines[next].trim().startsWith('#'))) {
            next++;
          }
          if (next >= lines.length) continue;
          final uri = Uri.tryParse(lines[next].trim());
          if (uri == null || uri.scheme != 'https' || uri.host != 'archive.org') continue;
          final licenseMatch = RegExp(r'x-licen[cs]e="([^"]+)"').firstMatch(line);
          final license = licenseMatch?.group(1) ??
              'Public Domain (curated PublicDomainM3U listing; confirm local copyright status)';
          if (playlistUrl == _nexonicMovies || playlistUrl == _nexonicSeries) {
            final lowerLicense = license.toLowerCase();
            if (!(lowerLicense.contains('public domain') ||
                  lowerLicense.contains('creative commons') ||
                  lowerLicense.contains('cc0'))) continue;
          }
          return ArchiveVideo(
            identifier: uri.pathSegments.length > 1 ? uri.pathSegments[1] : 'public-domain-playlist',
            title: entryTitle,
            creator: 'Internet Archive',
            license: license,
            fileName: uri.pathSegments.isNotEmpty ? Uri.decodeComponent(uri.pathSegments.last) : entryTitle,
            url: uri,
          );
        }
      } catch (_) {
        // Try the next public catalogue if this feed is temporarily unavailable.
      }
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
