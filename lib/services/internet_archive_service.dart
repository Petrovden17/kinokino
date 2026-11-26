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
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    headers: const {'User-Agent': 'KinoKino/1.0 (legal public-domain and Creative-Commons media search)'},
  ));

  final Dio _dio;

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

  Future<ArchiveVideo?> findLicensedVideo(String title) async {
    final query = 'title:"${title.replaceAll('"', '').trim()}"';
    final search = await _dio.get('https://archive.org/advancedsearch.php', queryParameters: {
      'q': query,
      'fl[]': ['identifier', 'title'],
      'rows': 8,
      'page': 1,
      'output': 'json',
    });
    final docs = (search.data['response']?['docs'] as List? ?? const [])
        .whereType<Map>().toList();

    for (final doc in docs) {
      final id = doc['identifier']?.toString();
      if (id == null || id.isEmpty) continue;
      try {
        final response = await _dio.get('https://archive.org/metadata/$id');
        final data = response.data as Map<String, dynamic>;
        final metadata = data['metadata'] as Map<String, dynamic>? ?? {};
        final license = (metadata['licenseurl'] ?? metadata['rights'] ?? '').toString();
        if (!_isAllowedLicense(license)) continue;

        final files = (data['files'] as List? ?? const []).whereType<Map>();
        for (final file in files) {
          final name = file['name']?.toString() ?? '';
          final format = (file['format'] ?? '').toString().toLowerCase();
          final width = int.tryParse(file['width']?.toString() ?? '') ?? 0;
          final height = int.tryParse(file['height']?.toString() ?? '') ?? 0;
          final looksLikeVideo = width > 0 && height > 0 &&
              (name.toLowerCase().endsWith('.mp4') ||
               name.toLowerCase().endsWith('.mov') ||
               name.toLowerCase().endsWith('.mkv'));
          final h264 = name.toLowerCase().contains('h264') ||
              format.contains('h.264') || format.contains('mpeg4');
          if (!looksLikeVideo || !h264) continue;
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
        // Skip malformed, unavailable, or unverifiable archive items.
      }
    }
    return null;
  }
}
