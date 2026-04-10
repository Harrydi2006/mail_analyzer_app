import '../../core/network/api_client.dart';

class SettingsRepository {
  final ApiClient _client = ApiClient.instance;

  Future<Map<String, dynamic>> fetchConfig() async {
    final res = await _client.get('/api/config');
    final body = res.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('配置响应格式异常');
    }
    if (body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '加载配置失败');
    }
    return body;
  }

  Future<void> saveKeywords(Map<String, dynamic> keywords) async {
    final res = await _client.post('/api/config', data: {'keywords': keywords});
    _ensureSuccess(res.data, '保存关键词失败');
  }

  Future<void> saveDedupBeta(Map<String, dynamic> dedupBeta) async {
    final res = await _client.post('/api/config', data: {'dedup_beta': dedupBeta});
    _ensureSuccess(res.data, '保存去重配置失败');
  }

  Future<Map<String, dynamic>> fetchTagSettings() async {
    final res = await _client.get('/api/tags');
    final body = _asMap(res.data);
    _ensureSuccess(body, '加载标签配置失败');
    return body;
  }

  Future<void> saveTagSettings({
    required List<Map<String, dynamic>> subscriptions,
    required int historyRetentionDays,
  }) async {
    final res = await _client.post('/api/tags', data: {
      'subscriptions': subscriptions,
      'history_retention_days': historyRetentionDays,
    });
    _ensureSuccess(res.data, '保存标签配置失败');
  }

  Future<void> subscribeTag({
    required int level,
    required String value,
    bool applyNow = true,
  }) async {
    final res = await _client.post('/api/tags/subscribe', data: {
      'level': level,
      'value': value,
      'apply_now': applyNow,
    });
    _ensureSuccess(res.data, '订阅标签失败');
  }

  Future<void> unsubscribeTag({
    required int level,
    required String value,
    bool applyNow = true,
  }) async {
    final res = await _client.post('/api/tags/unsubscribe', data: {
      'level': level,
      'value': value,
      'apply_now': applyNow,
    });
    _ensureSuccess(res.data, '取消订阅失败');
  }

  Future<void> reapplySubscriptions() async {
    final res = await _client.post('/api/tags/reapply-subscriptions', data: {});
    _ensureSuccess(res.data, '重应用订阅失败');
  }

  Future<Map<String, dynamic>> fetchHistoryCandidates() async {
    final res = await _client.get('/api/tags/history-candidates');
    final body = _asMap(res.data);
    _ensureSuccess(body, '加载历史候选失败');
    return body;
  }

  Future<void> addManualHistoryCandidate({
    required int level,
    required String value,
  }) async {
    final res = await _client.post('/api/tags/history-candidates/add-manual', data: {
      'level': level,
      'value': value,
    });
    _ensureSuccess(res.data, '添加手工历史标签失败');
  }

  Future<void> deleteHistoryCandidate({
    required int level,
    required String value,
    required bool manual,
  }) async {
    final res = await _client.post('/api/tags/history-candidates/delete', data: {
      'level': level,
      'value': value,
      'manual': manual,
    });
    _ensureSuccess(res.data, '删除历史候选失败');
  }

  Future<List<Map<String, dynamic>>> fetchNotionArchived({int limit = 30}) async {
    final res = await _client.get('/api/notion/archived', query: {'limit': limit});
    final body = _asMap(res.data);
    _ensureSuccess(body, '加载Notion归档失败');
    final list = body['emails'];
    if (list is! List) return [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> searchNotion({
    required String query,
    int limit = 10,
  }) async {
    final res = await _client.get('/api/notion/search', query: {'q': query, 'limit': limit});
    final body = _asMap(res.data);
    _ensureSuccess(body, '搜索Notion失败');
    final list = body['results'];
    if (list is! List) return [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw Exception('响应格式异常');
  }

  void _ensureSuccess(dynamic data, String fallback) {
    if (data is Map<String, dynamic> && data['success'] == false) {
      throw Exception(data['error']?.toString() ?? fallback);
    }
  }
}
