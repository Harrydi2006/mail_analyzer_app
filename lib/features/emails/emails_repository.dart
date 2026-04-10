import '../../core/network/api_client.dart';
import '../../core/config/app_config.dart';
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

class EmailsRepository {
  final ApiClient _client = ApiClient.instance;

  Future<Map<String, dynamic>> fetchEmails({
    int page = 1,
    int perPage = 20,
    String? importance,
    String? status,
    String? search,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };
    if ((importance ?? '').trim().isNotEmpty) {
      query['importance'] = importance!.trim();
    }
    if ((status ?? '').trim().isNotEmpty) {
      query['status'] = status!.trim();
    }
    if ((search ?? '').trim().isNotEmpty) {
      query['search'] = search!.trim();
    }
    final res = await _client.get('/api/emails', query: query);
    final body = res.data;
    if (body is! Map<String, dynamic>) {
      return const {
        'items': <Map<String, dynamic>>[],
        'total': 0,
        'page': 1,
        'per_page': 20,
      };
    }
    if (body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '获取邮件失败');
    }
    final list = body['emails'];
    final items = (list is List)
        ? list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    return {
      'items': items,
      'total': body['total'] is num ? (body['total'] as num).toInt() : items.length,
      'page': body['page'] is num ? (body['page'] as num).toInt() : page,
      'per_page': body['per_page'] is num ? (body['per_page'] as num).toInt() : perPage,
    };
  }

  Future<Map<String, dynamic>> fetchEmailDetail(int emailId) async {
    final res = await _client.get('/api/email/$emailId');
    final body = res.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('邮件详情格式异常');
    }
    if (body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '获取邮件详情失败');
    }
    if (body['error'] != null && body['id'] == null) {
      throw Exception(body['error']?.toString() ?? '获取邮件详情失败');
    }
    return body;
  }

  Future<void> reanalyzeEmail(int emailId) async {
    final res = await _client.post('/api/email/$emailId/reanalyze');
    final body = res.data;
    if (body is Map<String, dynamic> && body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '重分析失败');
    }
  }

  Future<void> retryAnalysis(int emailId) async {
    final res = await _client.post('/api/email/$emailId/retry-analysis', data: {'debug': true});
    final body = res.data;
    if (body is Map<String, dynamic> && body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '重试分析失败');
    }
  }

  Future<void> archiveToNotion(int emailId) async {
    final res = await _client.post('/api/notion/archive/$emailId');
    final body = res.data;
    if (body is Map<String, dynamic> && body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '归档到Notion失败');
    }
  }

  String buildAttachmentUrl(dynamic attachment) {
    final m = (attachment is Map) ? Map<String, dynamic>.from(attachment) : const <String, dynamic>{};
    final unique = (m['unique_filename'] ?? '').toString().trim();
    final id = m['id'];
    if (unique.isNotEmpty) {
      final encoded = Uri.encodeComponent(unique);
      return '${AppConfig.baseUrl}/attachments/$encoded';
    }
    if (id is num) {
      return '${AppConfig.baseUrl}/attachments/${id.toInt()}';
    }
    return '';
  }

  Future<Map<String, dynamic>> fetchStreamStatus() async {
    final res = await _client.get('/api/emails/stream-status');
    final body = res.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('流式状态格式异常');
    }
    if (body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '获取流式状态失败');
    }
    return (body['status'] is Map<String, dynamic>)
        ? Map<String, dynamic>.from(body['status'] as Map<String, dynamic>)
        : const {};
  }

  Future<void> stopStream() async {
    final res = await _client.post('/api/emails/stop-stream', data: {});
    final body = res.data;
    if (body is Map<String, dynamic> && body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '终止流式失败');
    }
  }

  Future<void> connectStream({
    required bool start,
    int? maxCount,
    required void Function(Map<String, dynamic>) onEvent,
    void Function(Object error)? onError,
    void Function()? onDone,
    CancelToken? cancelToken,
  }) async {
    final query = <String, dynamic>{
      'days_back': 1,
      'analysis_workers': 3,
    };
    if (start) query['start'] = 1;
    if (maxCount != null && maxCount > 0) {
      query['max_count'] = maxCount;
    }

    try {
      final res = await _client.dio.get<dynamic>(
        '/api/emails/fetch-stream',
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.stream),
      );

      final data = res.data;
      if (data is ResponseBody) {
        final lines = data.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          if (cancelToken?.isCancelled == true) break;
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload.isEmpty) continue;
          try {
            final parsed = jsonDecode(payload);
            if (parsed is Map<String, dynamic>) {
              onEvent(parsed);
            } else if (parsed is Map) {
              onEvent(Map<String, dynamic>.from(parsed));
            }
          } catch (_) {
            // Ignore malformed frames, keep stream alive.
          }
        }
      } else if (data is String) {
        for (final line in const LineSplitter().convert(data)) {
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload.isEmpty) continue;
          final parsed = jsonDecode(payload);
          if (parsed is Map<String, dynamic>) {
            onEvent(parsed);
          }
        }
      }
      onDone?.call();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        onDone?.call();
        return;
      }
      onError?.call(e);
    } catch (e) {
      onError?.call(e);
    }
  }
}
