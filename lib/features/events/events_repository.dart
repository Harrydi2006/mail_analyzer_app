import '../../core/network/api_client.dart';
import '../../core/config/app_config.dart';

class EventsRepository {
  final ApiClient _client = ApiClient.instance;

  Future<List<Map<String, dynamic>>> fetchEvents({
    int days = 30,
    String? importance,
    String? search,
  }) async {
    final query = <String, dynamic>{'days': days};
    if ((importance ?? '').trim().isNotEmpty) {
      query['importance'] = importance!.trim();
    }
    if ((search ?? '').trim().isNotEmpty) {
      query['search'] = search!.trim();
    }
    final res = await _client.get('/api/events/upcoming', query: query);
    final body = res.data;
    if (body is! Map<String, dynamic>) return [];
    if (body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '获取日程失败');
    }
    final list = body['events'];
    if (list is! List) return [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> updateImportance(int eventId, String importanceLevel) async {
    final res = await _client.put(
      '/api/events/$eventId',
      data: {'importance_level': importanceLevel},
    );
    final body = res.data;
    if (body is Map<String, dynamic> && body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '更新日程失败');
    }
  }

  Future<void> deleteEvent(int eventId) async {
    final res = await _client.delete('/api/events/$eventId');
    final body = res.data;
    if (body is Map<String, dynamic> && body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '删除日程失败');
    }
  }

  Future<Map<String, dynamic>> bulkDelete({
    required bool all,
    String? start,
    String? end,
  }) async {
    final payload = <String, dynamic>{'all': all};
    if (!all) {
      if ((start ?? '').trim().isNotEmpty) payload['start'] = start;
      if ((end ?? '').trim().isNotEmpty) payload['end'] = end;
    }
    final res = await _client.post('/api/events/bulk_delete', data: payload);
    final body = res.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('批量删除响应格式异常');
    }
    if (body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '批量删除失败');
    }
    return body;
  }

  Future<String> fetchSubscribeKey() async {
    final res = await _client.get('/api/user/profile');
    final body = res.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('用户信息格式异常');
    }
    if (body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '获取用户信息失败');
    }
    final user = (body['user'] is Map) ? Map<String, dynamic>.from(body['user'] as Map) : const {};
    final key = (user['subscribe_key'] ?? '').toString();
    if (key.isEmpty) {
      throw Exception('订阅key为空');
    }
    return key;
  }

  String buildIcalExportUrl({
    required int days,
    String importance = '',
  }) {
    final uri = Uri.parse('${AppConfig.baseUrl}/api/calendar/export.ics').replace(
      queryParameters: {
        'days': '$days',
        if (importance.trim().isNotEmpty) 'importance': importance.trim(),
      },
    );
    return uri.toString();
  }

  String buildSubscribeUrl({
    required String subscribeKey,
    required int days,
    String importance = '',
  }) {
    final uri = Uri.parse('${AppConfig.baseUrl}/api/calendar/subscribe').replace(
      queryParameters: {
        'key': subscribeKey,
        'days': '$days',
        if (importance.trim().isNotEmpty) 'importance': importance.trim(),
      },
    );
    return uri.toString();
  }
}
