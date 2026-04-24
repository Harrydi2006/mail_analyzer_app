import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';

class AuthRepository {
  final ApiClient _client = ApiClient.instance;

  Future<bool> hasLocalSession() {
    return _client.hasLocalSession();
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    try {
      final res = await _client.post(
        '/api/auth/login',
        data: {
          'username': username,
          'password': password,
          'remember_me': true,
        },
      );

      final body = res.data;
      if (body is! Map<String, dynamic>) {
        return false;
      }
      if (body['success'] != true) {
        return false;
      }

      final cookieBundle = _extractCookieBundle(res);
      final csrfToken =
          body['csrf_token']?.toString() ?? cookieBundle['csrfToken'];
      final setCookie = cookieBundle['cookieHeader'];
      await _client.saveSession(csrfToken: csrfToken, setCookie: setCookie);
      return true;
    } on DioException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _client.post('/api/auth/logout');
    } catch (_) {
      // ignore network error on local cleanup
    }
    await _client.clearSession();
  }

  Future<bool> checkAuth() async {
    try {
      await _client.loadSessionIntoHeaders();
      final res = await _client.get('/api/auth/check');
      final body = res.data;
      if (body is! Map<String, dynamic>) return false;
      final authenticated = body['success'] == true && body['authenticated'] == true;
      if (authenticated) {
        // 服务端每次 /check 都会滚动刷新 session，客户端同步持久化最新 cookie
        final cookieBundle = _extractCookieBundle(res);
        final csrfToken =
            body['csrf_token']?.toString() ?? cookieBundle['csrfToken'];
        final setCookie = cookieBundle['cookieHeader'];
        await _client.saveSession(csrfToken: csrfToken, setCookie: setCookie);
      }
      return authenticated;
    } on DioException {
      // 网络抖动时，如果本地仍有会话，允许保持登录态并交给后续请求校验。
      return await _client.hasLocalSession();
    } catch (_) {
      return await _client.hasLocalSession();
    }
  }

  Map<String, String?> _extractCookieBundle(Response<dynamic> response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) {
      return {'cookieHeader': null, 'csrfToken': null};
    }
    String? sessionPair;
    String? csrfPair;
    final allPairs = <String>[];
    // Convert `Set-Cookie` to `Cookie` header format: keep only `name=value`.
    for (final item in raw) {
      final firstPart = item.split(';').first.trim();
      if (firstPart.isEmpty) continue;
      allPairs.add(firstPart);
      final lower = firstPart.toLowerCase();
      if (lower.startsWith('session=')) {
        sessionPair = firstPart;
      } else if (lower.startsWith('csrf_token=')) {
        csrfPair = firstPart;
      }
    }
    final cookieHeader = <String>[
      if (sessionPair != null) sessionPair,
      if (csrfPair != null) csrfPair,
    ];
    if (cookieHeader.isEmpty && allPairs.isNotEmpty) {
      cookieHeader.addAll(allPairs);
    }
    final csrfToken =
        csrfPair != null ? csrfPair.split('=').skip(1).join('=').trim() : null;
    return {
      'cookieHeader': cookieHeader.isEmpty ? null : cookieHeader.join('; '),
      'csrfToken': (csrfToken == null || csrfToken.isEmpty) ? null : csrfToken,
    };
  }
}
