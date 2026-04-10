import '../../core/network/api_client.dart';

class TasksRepository {
  final ApiClient _client = ApiClient.instance;

  Future<List<Map<String, dynamic>>> fetchActiveTasks() async {
    final res = await _client.get('/api/tasks/active');
    final body = res.data;
    if (body is! Map<String, dynamic>) return [];
    if (body['success'] == false) {
      throw Exception(body['error']?.toString() ?? '获取任务失败');
    }
    final tasks = body['tasks'];
    if (tasks is! List) return [];
    return tasks.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
