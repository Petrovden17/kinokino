import 'package:dio/dio.dart';

class ArchiveVideoVariant {
  const ArchiveVideoVariant({required this.label, required this.url, required this.height, required this.durationSeconds});
  final String label;
  final Uri url;
  final int height;
  final double durationSeconds;
}

class ArchiveVideo {
  const ArchiveVideo({
    required this.identifier,
    required this.title,
    required this.creator,
    required this.license,
    required this.fileName,
    required this.url,
    this.variants = const [],
    this.durationSeconds = 0,
  });
  final String identifier;
  final String title;
  final String creator;
  final String license;
  final String fileName;
  final Uri url;
  final List<ArchiveVideoVariant> variants;
  final double durationSeconds;
}

class InternetArchiveService {
  InternetArchiveService() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 35),
    headers: const {'User-Agent': 'KinoKino/1.0 (licensed public-domain media)'},
  ));

  final Dio _dio;

  bool _isAllowedLicense(String value) {
    final license = value.toLowerCase();
    return license.contains('creativecommons.org/publicdomain/zero/1.0') ||
        license.contains('creativecommons.org/publicdomain/mark/1.0') ||
        license.contains('creativecommons.org/licenses/by/3.0') ||
        license.contains('creativecommons.org/licenses/by/4.0') ||
        license.contains('creativecommons.org/licenses/by-sa/3.0') ||
        license.contains('creativecommons.org/licenses/by-sa/4.0');
  }

  String _normalize(String value, int expectedYear) => value.toLowerCase()
      .replaceAll(RegExp('\\\\(?\\\\s*$expectedYear\\\\s*\\\\)?'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9а-яё]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\\s+'), ' ')
      .trim();

  double? _seconds(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    final numeric = double.tryParse(raw);
    if (numeric != null) return numeric;
    final parts = raw.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    try {
      final nums = parts.map((p) => double.parse(p)).toList();
      if (nums.length == 2) return nums[0] * 60 + nums[1];
      return nums[0] * 3600 + nums[1] * 60 + nums[2];
    } catch (_) {
      return null;
    }
  }

  bool _durationMatches(double? actualSeconds, int expectedMinutes) {
    if (actualSeconds == null || actualSeconds <= 0 || expectedMinutes <= 0) return false;
    final expected = expectedMinutes * 60.0;
    // Tight duration matching prevents short clips and unrelated edits from passing.
    final tolerance = (expected * .06).clamp(90.0, 240.0);
    return (actualSeconds - expected).abs() <= tolerance;
  }

  int? _yearFrom(dynamic value) {
    if (value == null) return null;
    final match = RegExp(r'(?<!\d)(19\d{2}|20\d{2})(?!\d)').firstMatch(value.toString());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  int _qualityRank(Map file) {
    final h = int.tryParse(file['height']?.toString() ?? '') ?? 0;
    final name = (file['name'] ?? '').toString().toLowerCase();
    if (h >= 2160 || name.contains('2160')) return 2160;
    if (h >= 1440 || name.contains('1440')) return 1440;
    if (h >= 1080 || name.contains('1080')) return 1080;
    if (h >= 720 || name.contains('720')) return 720;
    if (h >= 480 || name.contains('480')) return 480;
    return h;
  }

  Future<ArchiveVideo?> findLicensedVideo(String title, {
    required int expectedRuntimeMinutes,
    required int expectedYear,
    String? displayTitle,
    CancelToken? cancelToken,
    bool isSeries = false,
  }) async {
    // A series title is not an episode. Never select an arbitrary clip as an episode.
    if (isSeries || expectedRuntimeMinutes <= 0 || expectedYear <= 0) return null;
    final wanted = _normalize(title, expectedYear);
    if (wanted.isEmpty) return null;
    final cleanTitle = title.replaceAll('"', '').trim();
    final words = cleanTitle.split(RegExp(r'\s+')).where((word) => word.length > 1).toList();
    final tokenQuery = words.isEmpty ? cleanTitle : words.map((word) => 'title:"$word"').join(' AND ');
    final queries = <String>[
      'title:"$cleanTitle" AND year:$expectedYear AND mediatype:movies',
      '($tokenQuery) AND year:$expectedYear AND mediatype:movies',
    ];
    final seen = <String>{};
    final docs = <Map>[];
    for (final query in queries) {
      try {
        if (cancelToken?.isCancelled == true) return null;
        final response = await _dio.get<dynamic>(
          'https://archive.org/advancedsearch.php',
          queryParameters: {
            'q': query,
            'fl[]': ['identifier', 'title'],
            'rows': 60,
            'page': 1,
            'output': 'json',
            'sort[]': ['downloads desc'],
          },
          options: Options(responseType: ResponseType.json),
          cancelToken: cancelToken,
        );
        final results = (response.data['response']?['docs'] as List? ?? const []);
        for (final row in results.whereType<Map>()) {
          final id = row['identifier']?.toString() ?? '';
          if (id.isNotEmpty && seen.add(id)) docs.add(row);
        }
      } catch (_) { if (cancelToken?.isCancelled == true) rethrow; }
    }

    for (final doc in docs) {
      if (cancelToken?.isCancelled == true) return null;
      final id = doc['identifier']?.toString();
      if (id == null || id.isEmpty) continue;
      try {
        final response = await _dio.get<dynamic>('https://archive.org/metadata/$id',
          options: Options(responseType: ResponseType.json), cancelToken: cancelToken);
        final data = response.data as Map<String, dynamic>;
        final metadata = data['metadata'] as Map<String, dynamic>? ?? {};
        final archiveTitle = (metadata['title'] ?? doc['title'] ?? '').toString();
        // Search results are fuzzy. Require an exact normalized title match.
        if (_normalize(archiveTitle, expectedYear) != wanted) continue;
        // Never infer a release year from an archive identifier: IDs often contain
        // upload dates or unrelated event years. Prefer explicit metadata, then title.
        final titleYear = _yearFrom(archiveTitle);
        final metadataYear = _yearFrom(metadata['year']) ?? _yearFrom(metadata['date']);
        if (titleYear != null && titleYear != expectedYear) continue;
        final archiveYear = metadataYear ?? titleYear;
        if (archiveYear != expectedYear) continue;
        final license = (metadata['licenseurl']?.toString().trim().isNotEmpty == true
            ? metadata['licenseurl'] : metadata['rights'] ?? '').toString();
        if (!_isAllowedLicense(license)) continue;

        final files = (data['files'] as List? ?? const []).whereType<Map>().toList();
        final variants = <ArchiveVideoVariant>[];
        for (final file in files) {
          final name = file['name']?.toString() ?? '';
          final lower = name.toLowerCase();
          if (!(lower.endsWith('.mp4') || lower.endsWith('.mov'))) continue;
          final format = (file['format'] ?? '').toString().toLowerCase();
          if (format.contains('mpeg4') == false && format.contains('h.264') == false &&
              !lower.endsWith('.mp4')) continue;
          final duration = _seconds(file['length']);
          if (!_durationMatches(duration, expectedRuntimeMinutes)) continue;
          final height = int.tryParse(file['height']?.toString() ?? '') ?? _qualityRank(file);
          final encodedName = Uri.encodeComponent(name);
          variants.add(ArchiveVideoVariant(
            label: height >= 2160 ? '4K' : height >= 1440 ? '1440p' : height >= 1080 ? '1080p' :
                height >= 720 ? '720p' : height >= 480 ? '480p' : 'Исходное качество',
            height: height,
            durationSeconds: duration!,
            url: Uri.parse('https://archive.org/download/$id/$encodedName'),
          ));
        }
        if (variants.isEmpty) continue;
        variants.sort((a, b) => b.height.compareTo(a.height));
        final chosen = variants.first;
        return ArchiveVideo(
          identifier: id,
          title: displayTitle?.trim().isNotEmpty == true ? displayTitle!.trim() : archiveTitle,
          creator: (metadata['creator'] ?? 'Не указан').toString(),
          license: license,
          fileName: Uri.decodeComponent(chosen.url.pathSegments.last),
          url: chosen.url,
          variants: variants,
          durationSeconds: chosen.durationSeconds,
        );
      } catch (_) {
        if (cancelToken?.isCancelled == true) rethrow;
        // Skip malformed, unlicensed, mismatched or unavailable items.
      }
    }
    return null;
  }
}
