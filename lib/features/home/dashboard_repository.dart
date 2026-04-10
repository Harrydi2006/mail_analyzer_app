import '../../core/network/api_client.dart';

class DashboardRepository {
  final ApiClient _client = ApiClient.instance;

  Future<Map<String, bool>> fetchSystemStatus() async {
    final res = await _client.get('/api/system/status_basic');
    final body = _asMap(res.data);
    _ensureSuccess(body);
    final status = body['status'];
    if (status is! Map) {
      return {'email': false, 'ai': false, 'notion': false};
    }
    return {
      'email': status['email'] == true,
      'ai': status['ai'] == true,
      'notion': status['notion'] == true,
    };
  }

  Future<Map<String, dynamic>> fetchStatistics() async {
    final res = await _client.get('/api/statistics');
    final body = _asMap(res.data);
    _ensureSuccess(body);
    final stats = body['statistics'];
    if (stats is! Map) {
      return const {
        'total_emails': 0,
        'total_events': 0,
        'important_events': 0,
        'pending_reminders': 0,
      };
    }
    return Map<String, dynamic>.from(stats);
  }

  Future<List<Map<String, dynamic>>> fetchRecentEmails({int limit = 5}) async {
    final res = await _client.get('/api/emails/recent', query: {'limit': limit});
    final body = _asMap(res.data);
    _ensureSuccess(body);
    final list = body['emails'];
    if (list is! List) return [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchUpcomingEvents({int days = 7}) async {
    final res = await _client.get('/api/events/upcoming', query: {'days': days});
    final body = _asMap(res.data);
    _ensureSuccess(body);
    final list = body['events'];
    if (list is! List) return [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw Exception('响应格式异常');
  }

  void _ensureSuccess(Map<String, dynamic> body) {
    if (body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '请求失败');
    }
  }
}
