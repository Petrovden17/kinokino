import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads and caches maintained ABP-style network filter lists.
///
/// The matcher intentionally handles the common network-rule subset used by
/// EasyList and AdGuard. Existing hard-coded player protections remain active.
class AdFilterEngine {
  AdFilterEngine._();

  static final AdFilterEngine instance = AdFilterEngine._();

  static const _listUrls = <String, String>{
    'adguard-base':
        'https://filters.adtidy.org/extension/chromium/filters/2.txt',
    'adguard-russian':
        'https://filters.adtidy.org/extension/chromium/filters/1.txt',
    'adguard-popups':
        'https://filters.adtidy.org/extension/chromium/filters/19.txt',
    'adguard-mobile-ads':
        'https://filters.adtidy.org/extension/chromium/filters/11.txt',
    'easyprivacy': 'https://easylist.to/easylist/easyprivacy.txt',
  };

  static const _refreshInterval = Duration(hours: 24);
  static const _mediaExtensions = <String>{
    'm3u8', 'mpd', 'mp4', 'm4v', 'webm', 'mkv', 'ts', 'm4s',
    'aac', 'mp3', 'm4a', 'key', 'vtt',
  };

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 12),
    responseType: ResponseType.plain,
    headers: const {'User-Agent': 'KinoKino/1.0 (Android WebView)'},
  ));

  final Map<String, List<_AdRule>> _blockedByHost = {};
  final Map<String, List<_AdRule>> _allowedByHost = {};
  bool _ready = false;
  Future<void>? _initializing;
  DateTime? _lastRefresh;

  bool get isReady => _ready;
  int get ruleCount => _blockedByHost.values.fold<int>(
        0, (total, rules) => total + rules.length,
      );

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    final directory = await getApplicationSupportDirectory();
    final cacheDirectory = Directory('${directory.path}/ad_filter_cache');
    await cacheDirectory.create(recursive: true);

    final cachedLists = <String, String>{};
    for (final id in _listUrls.keys) {
      final file = File('${cacheDirectory.path}/$id.txt');
      if (await file.exists()) {
        try {
          cachedLists[id] = await file.readAsString();
        } catch (_) {
          // A damaged cache entry is ignored; the other lists remain usable.
        }
      }
    }

    _rebuild(cachedLists);
    final stamp = File('${cacheDirectory.path}/last_refresh.txt');
    if (await stamp.exists()) {
      try {
        _lastRefresh = DateTime.tryParse((await stamp.readAsString()).trim());
      } catch (_) {}
    }

    if (_lastRefresh == null ||
        DateTime.now().difference(_lastRefresh!) >= _refreshInterval) {
      unawaited(_refresh(cacheDirectory, stamp));
    }
  }

  Future<void> _refresh(Directory directory, File stamp) async {
    var updatedAny = false;
    final retained = <String, String>{};

    for (final entry in _listUrls.entries) {
      final file = File('${directory.path}/${entry.key}.txt');
      try {
        final response = await _dio.get<String>(entry.value);
        final body = response.data ?? '';
        if (response.statusCode == 200 && body.length > 1000) {
          await file.writeAsString(body, flush: true);
          retained[entry.key] = body;
          updatedAny = true;
        } else if (await file.exists()) {
          retained[entry.key] = await file.readAsString();
        }
      } catch (error) {
        // Keep the last known good list if a source is temporarily unavailable.
        if (await file.exists()) {
          try {
            retained[entry.key] = await file.readAsString();
          } catch (_) {}
        }
      }
    }

    if (retained.isNotEmpty) {
      _rebuild(retained);
    }
    if (updatedAny) {
      _lastRefresh = DateTime.now();
      await stamp.writeAsString(_lastRefresh!.toIso8601String(), flush: true);
    }
  }

  void _rebuild(Map<String, String> lists) {
    final blocked = <String, List<_AdRule>>{};
    final allowed = <String, List<_AdRule>>{};

    for (final text in lists.values) {
      for (final rawLine in const LineSplitter().convert(text)) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('!') || line.startsWith('[') ||
            line.contains('##') || line.contains('#@#') ||
            line.contains('#?#') || line.startsWith('#')) {
          continue;
        }

        final exception = line.startsWith('@@');
        final networkRule = exception ? line.substring(2) : line;
        final parsed = _parseRule(networkRule);
        if (parsed == null) continue;
        final target = exception ? allowed : blocked;
        target.putIfAbsent(parsed.host, () => <_AdRule>[]).add(parsed);
      }
    }

    _blockedByHost
      ..clear()
      ..addAll(blocked);
    _allowedByHost
      ..clear()
      ..addAll(allowed);
    _ready = true;
  }

  _AdRule? _parseRule(String line) {
    if (!line.startsWith('||')) return null;
    final optionIndex = line.indexOf(r'$');
    final pattern = optionIndex < 0 ? line : line.substring(0, optionIndex);
    final options = optionIndex < 0
        ? const <String>[]
        : line.substring(optionIndex + 1).split(',');

    const knownTypes = {
      'document', 'subdocument', 'script', 'stylesheet', 'image',
      'font', 'media', 'xmlhttprequest', 'other',
    };
    const supportedOptions = {
      ...knownTypes,
      'third-party', '~third-party', 'domain', 'important', 'all',
    };
    for (final option in options) {
      final name = option.split('=').first;
      if (!supportedOptions.contains(name) ||
          (name.startsWith('~') && name != '~third-party')) {
        // Skip rules with modifiers this lightweight matcher cannot safely honor.
        return null;
      }
    }

    final match = RegExp(r'^\|\|([^\^/|*]+)(.*)$').firstMatch(pattern);
    if (match == null) return null;
    final host = match.group(1)!.toLowerCase();
    if (!host.contains('.') || host.contains(' ')) return null;

    var pathPattern = match.group(2) ?? '';
    if (pathPattern.startsWith('^')) pathPattern = pathPattern.substring(1);
    if (pathPattern.isNotEmpty &&
        !pathPattern.startsWith('/') &&
        !pathPattern.startsWith('?')) return null;

    final resourceTypes = <String>{};
    for (final option in options) {
      final name = option.split('=').first;
      if (knownTypes.contains(name)) resourceTypes.add(name);
    }

    String? includedDomains;
    String? excludedDomains;
    for (final option in options) {
      if (option.startsWith('domain=')) {
        final values = option.substring(7).split('|');
        final included = values.where((v) => !v.startsWith('~')).join('|');
        includedDomains = included.isEmpty ? null : included;
        excludedDomains = values.where((v) => v.startsWith('~'))
            .map((v) => v.substring(1)).join('|');
      }
    }

    final thirdParty = options.contains('third-party')
        ? true
        : options.contains('~third-party')
            ? false
            : null;

    RegExp? pathRegex;
    if (pathPattern.isNotEmpty) {
      final buffer = StringBuffer('^');
      for (final rune in pathPattern.runes) {
        final char = String.fromCharCode(rune);
        if (char == '*') {
          buffer.write('.*');
        } else if (char == '^') {
          buffer.write(r'(?:[^A-Za-z0-9_.%-]|$)');
        } else {
          buffer.write(RegExp.escape(char));
        }
      }
      pathRegex = RegExp(buffer.toString(), caseSensitive: false);
    }

    return _AdRule(
      host: host,
      pathRegex: pathRegex,
      resourceTypes: resourceTypes,
      thirdParty: thirdParty,
      includedDomains: includedDomains,
      excludedDomains: excludedDomains,
    );
  }

  bool shouldBlock({
    required String rawUrl,
    required String sourceUrl,
    required bool isMainFrame,
    required Map<String, String>? headers,
  }) {
    if (!_ready) return false;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }

    final extension = uri.path.split('.').last.toLowerCase();
    if (_mediaExtensions.contains(extension)) return false;

    final host = uri.host.toLowerCase();
    final sourceHost = Uri.tryParse(sourceUrl)?.host.toLowerCase() ?? '';
    final resourceType = _resourceType(uri, isMainFrame, headers);
    final thirdParty = _isThirdParty(host, sourceHost);

    final exceptions = _matchingRules(
      _allowedByHost, host, uri, sourceHost, resourceType, thirdParty,
    );
    if (exceptions.isNotEmpty) return false;

    return _matchingRules(
      _blockedByHost, host, uri, sourceHost, resourceType, thirdParty,
    ).isNotEmpty;
  }

  List<_AdRule> _matchingRules(
    Map<String, List<_AdRule>> rules,
    String host,
    Uri uri,
    String sourceHost,
    String resourceType,
    bool thirdParty,
  ) {
    final matches = <_AdRule>[];
    var suffixStart = 0;
    while (suffixStart < host.length) {
      final domain = host.substring(suffixStart);
      final domainRules = rules[domain];
      if (domainRules != null) {
        for (final rule in domainRules) {
          if (rule.pathRegex != null &&
              !rule.pathRegex!.hasMatch(
                uri.path + (uri.hasQuery ? '?${uri.query}' : ''))) continue;
          if (rule.resourceTypes.isNotEmpty &&
              !rule.resourceTypes.contains(resourceType)) continue;
          if (rule.thirdParty != null && rule.thirdParty != thirdParty) continue;
          if (rule.includedDomains != null &&
              !_domainOptionMatches(sourceHost, rule.includedDomains!)) continue;
          if (rule.excludedDomains != null &&
              _domainOptionMatches(sourceHost, rule.excludedDomains!)) continue;
          matches.add(rule);
        }
      }
      final dot = host.indexOf('.', suffixStart);
      if (dot < 0) break;
      suffixStart = dot + 1;
    }
    return matches;
  }

  bool _domainOptionMatches(String sourceHost, String domains) {
    if (domains.isEmpty) return false;
    return domains.split('|').any((domain) =>
        sourceHost == domain || sourceHost.endsWith('.$domain'));
  }

  bool _isThirdParty(String host, String sourceHost) {
    if (host.isEmpty || sourceHost.isEmpty) return false;
    if (host == sourceHost) return false;
    final hostParts = host.split('.');
    final sourceParts = sourceHost.split('.');
    if (hostParts.length < 2 || sourceParts.length < 2) return host != sourceHost;
    return hostParts.sublist(hostParts.length - 2).join('.') !=
        sourceParts.sublist(sourceParts.length - 2).join('.');
  }

  String _resourceType(Uri uri, bool isMainFrame, Map<String, String>? headers) {
    if (isMainFrame) return 'document';
    final accept = headers?['Accept'] ?? headers?['accept'] ?? '';
    final path = uri.path.toLowerCase();
    if (accept.contains('XMLHttpRequest') ||
        accept.contains('application/json') || path.endsWith('.json') ||
        path.endsWith('.xml')) return 'xmlhttprequest';
    if (accept.contains('text/html') || path.endsWith('.html')) return 'subdocument';
    if (accept.contains('text/css') || path.endsWith('.css')) return 'stylesheet';
    if (accept.contains('javascript') || path.endsWith('.js') ||
        path.endsWith('.ts')) return 'script';
    if (accept.contains('image/') ||
        RegExp(r'\.(png|jpe?g|gif|webp|svg|ico)$').hasMatch(path)) return 'image';
    if (accept.contains('font/') ||
        RegExp(r'\.(woff2?|ttf|otf)$').hasMatch(path)) return 'font';
    if (accept.contains('video/') || accept.contains('audio/') ||
        _mediaExtensions.contains(path.split('.').last)) return 'media';
    return 'other';
  }
}

class _AdRule {
  const _AdRule({
    required this.host,
    required this.pathRegex,
    required this.resourceTypes,
    required this.thirdParty,
    required this.includedDomains,
    required this.excludedDomains,
  });

  final String host;
  final RegExp? pathRegex;
  final Set<String> resourceTypes;
  final bool? thirdParty;
  final String? includedDomains;
  final String? excludedDomains;
}
