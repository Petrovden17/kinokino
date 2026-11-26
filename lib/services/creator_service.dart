import 'package:supabase_flutter/supabase_flutter.dart';

class CreatorService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<bool> isCreator() async {
    final result = await _client.rpc('is_kinokino_creator');
    return result == true;
  }

  Future<Map<String, dynamic>> loadStats() async {
    final result = await _client.rpc('kinokino_creator_stats');
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> announcements() async {
    final result = await _client.from('creator_announcements').select().order('created_at', ascending: false);
    return (result as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> createAnnouncement({required String title, required String body, required bool published}) async {
    await _client.from('creator_announcements').insert({'title': title.trim(), 'body': body.trim(), 'is_published': published});
  }

  Future<void> setAnnouncementPublished(String id, bool published) async {
    await _client.from('creator_announcements').update({'is_published': published, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  Future<List<Map<String, dynamic>>> loadAccounts({int page = 1}) async {
    final response = await _client.functions.invoke(
      'creator-account-admin',
      body: {'action': 'list', 'page': page},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    if (response.status < 200 || response.status >= 300) {
      throw Exception(data['error'] ?? 'Не удалось загрузить аккаунты');
    }
    return (data['users'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> setAccountBanned(String userId, {required bool banned}) async {
    final response = await _client.functions.invoke(
      'creator-account-admin',
      body: {'action': banned ? 'ban' : 'unban', 'user_id': userId},
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      throw Exception(data['error'] ?? 'Не удалось изменить состояние аккаунта');
    }
  }

  Future<void> deleteAnnouncement(String id) async {
    await _client.from('creator_announcements').delete().eq('id', id);
  }
}
