import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Routes catalogue API traffic through Supabase first, then falls back to the
/// existing Cloudflare Worker if the regional edge route is unavailable.
class CatalogApiGateway {
  static const String _supabaseUrl =
      'https://rsubtcrfnpqijpwjcbyc.supabase.co';
  static const String _publishableKey =
      'sb_publishable_A9NQcq9Umjv5yjcYyIWEZQ_5CKetTKu';
  static const String _workerUrl =
      'https://kinokino-tmdb.get46-get47.workers.dev';

  late final Dio _edge = _createDio(baseUrl: _supabaseUrl, useSupabaseAuth: true);
  late final Dio _worker = _createDio(baseUrl: _workerUrl);

  Dio _createDio({required String baseUrl, bool useSupabaseAuth = false}) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 25),
      sendTimeout: const Duration(seconds: 10),
      headers: const {'Accept': 'application/json'},
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (useSupabaseAuth) {
          options.headers['apikey'] = _publishableKey;
          try {
            final session = Supabase.instance.client.auth.currentSession;
            final token = session?.accessToken;
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          } catch (_) {
            // The direct Worker fallback remains available during app startup.
          }
        }
        handler.next(options);
      },
    ));
    return dio;
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final edgePath = '/functions/v1/tmdb-catalog-proxy$path';
      return await _edge.get<dynamic>(
        edgePath,
        queryParameters: queryParameters,
      );
    } on DioException {
      // A failed/blocked regional edge route must not strand the catalogue.
      return _worker.get<dynamic>(
        path,
        queryParameters: queryParameters,
      );
    }
  }
}
