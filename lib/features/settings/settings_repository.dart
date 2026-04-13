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

  Future<Map<String, dynamic>> saveNotificationPrefs({
    required Map<String, dynamic> notificationPrefs,
    required String baseRevision,
    bool force = false,
  }) async {
    const mobilePrefKeys = <String>{
      'task_notification',
      'reminder_notification',
      'email_new_notification',
      'email_analysis_notification',
      'event_notification',
      'system_notification',
    };
    final mobilePushPrefs = <String, dynamic>{};
    final serverNotification = <String, dynamic>{};
    notificationPrefs.forEach((key, value) {
      if (mobilePrefKeys.contains(key)) {
        mobilePushPrefs[key] = value;
      } else {
        serverNotification[key] = value;
      }
    });
    final res = await _client.post('/api/config', data: {
      '_base_revision': baseRevision,
      if (force) '_force': true,
      'notification': {
        ...serverNotification,
        'mobile_push_prefs': mobilePushPrefs,
      },
    });
    final body = res.data;
    if (res.statusCode == 409 && body is Map<String, dynamic>) {
      return {
        'success': false,
        'conflict': true,
        'error': body['error']?.toString() ?? '配置冲突',
        'current_revision': body['current_revision']?.toString() ?? '',
      };
    }
    _ensureSuccess(body, '保存通知偏好失败');
    final result = <String, dynamic>{'success': true};
    if (body is Map<String, dynamic>) {
      result['revision'] = body['revision']?.toString() ?? '';
    }
    return result;
  }

  Future<Map<String, dynamic>> saveConfigSection({
    required String section,
    required Map<String, dynamic> payload,
    required String baseRevision,
    bool force = false,
  }) async {
    final res = await _client.post('/api/config', data: {
      '_base_revision': baseRevision,
      if (force) '_force': true,
      section: payload,
    });
    final body = res.data;
    if (res.statusCode == 409 && body is Map<String, dynamic>) {
      return {
        'success': false,
        'conflict': true,
        'error': body['error']?.toString() ?? '配置冲突',
        'current_revision': body['current_revision']?.toString() ?? '',
      };
    }
    _ensureSuccess(body, '保存配置失败');
    final result = <String, dynamic>{'success': true};
    if (body is Map<String, dynamic>) {
      result['revision'] = body['revision']?.toString() ?? '';
    }
    return result;
  }

  Future<void> uploadFcmToken({
    required String token,
    String platform = 'android',
  }) async {
    final res = await _client.post('/api/mobile/fcm-token', data: {
      'token': token,
      'platform': platform,
    });
    _ensureSuccess(res.data, '上传FCM Token失败');
  }

  Future<void> uploadGetuiClientId({
    required String clientId,
    String platform = 'android',
  }) async {
    final res = await _client.post('/api/mobile/push-token', data: {
      'provider': 'getui',
      'token': clientId,
      'platform': platform,
    });
    _ensureSuccess(res.data, '上传Getui ClientID失败');
  }

  Future<void> testFcmPush({
    required String title,
    required String body,
  }) async {
    await testPush(channel: 'fcm', title: title, body: body);
  }

  Future<void> testPush({
    required String channel,
    required String title,
    required String body,
  }) async {
    final res = await _client.post('/api/notifications/test', data: {
      'channel': channel,
      'config': {'title': title, 'body': body},
    });
    _ensureSuccess(res.data, '测试推送失败');
  }

  Future<void> saveKeywords(Map<String, dynamic> keywords) async {
    final res = await _client.post('/api/config', data: {'keywords': keywords});
    _ensureSuccess(res.data, '保存关键词失败');
  }

  Future<void> saveDedupBeta(Map<String, dynamic> dedupBeta) async {
    final res =
        await _client.post('/api/config', data: {'dedup_beta': dedupBeta});
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
    String baseRevision = '',
    bool force = false,
  }) async {
    final res = await _client.post('/api/tags', data: {
      if (baseRevision.trim().isNotEmpty) '_base_revision': baseRevision.trim(),
      if (force) '_force': true,
      'subscriptions': subscriptions,
      'history_retention_days': historyRetentionDays,
    });
    if (res.statusCode == 409 && res.data is Map<String, dynamic>) {
      final body = Map<String, dynamic>.from(res.data as Map);
      throw Exception('CONFLICT:${body['error'] ?? '标签配置冲突'}');
    }
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
    final res =
        await _client.post('/api/tags/history-candidates/add-manual', data: {
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
    final res =
        await _client.post('/api/tags/history-candidates/delete', data: {
      'level': level,
      'value': value,
      'manual': manual,
    });
    _ensureSuccess(res.data, '删除历史候选失败');
  }

  Future<List<Map<String, dynamic>>> fetchNotionArchived(
      {int limit = 30}) async {
    final res =
        await _client.get('/api/notion/archived', query: {'limit': limit});
    final body = _asMap(res.data);
    _ensureSuccess(body, '加载Notion归档失败');
    final list = body['emails'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchNotion({
    required String query,
    int limit = 10,
  }) async {
    final res = await _client
        .get('/api/notion/search', query: {'q': query, 'limit': limit});
    final body = _asMap(res.data);
    _ensureSuccess(body, '搜索Notion失败');
    final list = body['results'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw Exception('响应格式异常');
  }

  void _ensureSuccess(dynamic data, String fallback) {
    if (data is Map<String, dynamic> && data['success'] == false) {
      throw Exception(data['error']?.toString() ?? fallback);
    }
    if (data is! Map<String, dynamic>) {
      throw Exception(fallback);
    }
  }
}
