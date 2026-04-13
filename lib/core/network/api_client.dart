import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import 'dio_web_adapter_config_stub.dart'
    if (dart.library.js_interop) 'dio_web_adapter_config_web.dart';

class ApiClient {
  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: 'application/json',
        // 让 401/403/404 不抛异常，由业务层自行判断，避免 Flutter Web 出现未捕获 DioException
        validateStatus: (_) => true,
      ),
    );
    // Web 下开启凭据，其他平台此调用为空实现（通过条件导入避免引入 web 依赖）。
    configureWebAdapter(_dio);
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Web 场景由浏览器自动管理 Cookie，手动注入会被浏览器拦截
          if (kIsWeb) {
            final csrfToken = await _storage.read(key: _csrfTokenKey);
            if (csrfToken != null && csrfToken.isNotEmpty) {
              options.headers['X-CSRF-Token'] = csrfToken;
            }
            handler.next(options);
            return;
          }
          final cookie = await _storage.read(key: _sessionCookieKey);
          if (cookie != null && cookie.isNotEmpty) {
            options.headers['Cookie'] = cookie;
          }
          final csrfToken = await _storage.read(key: _csrfTokenKey);
          if (csrfToken != null && csrfToken.isNotEmpty) {
            options.headers['X-CSRF-Token'] = csrfToken;
          }
          handler.next(options);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._internal();
  static const _storage = FlutterSecureStorage();
  static const _csrfTokenKey = 'csrf_token';
  static const _sessionCookieKey = 'session_cookie';

  late final Dio _dio;
  Dio get dio => _dio;

  void setBaseUrl(String baseUrl) {
    _dio.options.baseUrl = baseUrl;
  }

  Future<void> saveSession({
    required String? csrfToken,
    required String? setCookie,
  }) async {
    if (csrfToken != null && csrfToken.isNotEmpty) {
      await _storage.write(key: _csrfTokenKey, value: csrfToken);
    }
    if (!kIsWeb && setCookie != null && setCookie.isNotEmpty) {
      await _storage.write(key: _sessionCookieKey, value: setCookie);
      _dio.options.headers['Cookie'] = setCookie;
    }
  }

  Future<void> loadSessionIntoHeaders() async {
    if (kIsWeb) return;
    final cookie = await _storage.read(key: _sessionCookieKey);
    if (cookie != null && cookie.isNotEmpty) {
      _dio.options.headers['Cookie'] = cookie;
    }
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _csrfTokenKey);
    if (!kIsWeb) {
      await _storage.delete(key: _sessionCookieKey);
      _dio.options.headers.remove('Cookie');
    }
  }

  Future<bool> hasLocalSession() async {
    if (kIsWeb) {
      final csrf = await _storage.read(key: _csrfTokenKey);
      return csrf != null && csrf.isNotEmpty;
    }
    final cookie = await _storage.read(key: _sessionCookieKey);
    return cookie != null && cookie.isNotEmpty;
  }

  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) {
    return _dio.get(path, queryParameters: query);
  }

  Future<Response<dynamic>> post(String path, {Object? data}) {
    return _dio.post(path, data: data);
  }

  Future<Response<dynamic>> put(String path, {Object? data}) {
    return _dio.put(path, data: data);
  }

  Future<Response<dynamic>> delete(String path, {Object? data}) {
    return _dio.delete(path, data: data);
  }
}
