class LegalVideoSource {
  const LegalVideoSource({
    required this.id, required this.name, required this.url,
    this.requiresUserAuthorization = true,
  });
  final String id;
  final String name;
  final Uri url;
  final bool requiresUserAuthorization;
}

class LegalSourceService {
  // No pirate indexes, scraping, torrent sources or copyrighted streams are bundled.
  // The user/admin must supply a URL they are authorized to play.
  Uri validateAuthorizedStream(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw FormatException('Разрешены только корректные HTTPS-ссылки на легальный поток.');
    }
    return uri;
  }
}
