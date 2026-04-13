import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/notifications/notification_service.dart';
import 'tasks_repository.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _repo = TasksRepository();
  List<Map<String, dynamic>> _tasks = [];
  final Map<String, String> _lastStatuses = {};
  Timer? _timer;
  bool _loading = true;
  String? _error;
  bool _hasSnapshot = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final incoming = await _repo.fetchActiveTasks();
      await _notifyTaskChanges(incoming);
      _tasks = incoming;
    } catch (e) {
      _error = e.toString();
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('加载失败: $_error'));
    if (_tasks.isEmpty) return const Center(child: Text('暂无后台任务'));

    return ListView.builder(
      itemCount: _tasks.length,
      itemBuilder: (_, i) {
        final t = _tasks[i];
        final title = t['task_name']?.toString() ?? '后台任务';
        final status = t['status']?.toString() ?? 'unknown';
        final percent = (t['percent'] is num) ? (t['percent'] as num).toDouble() : 0.0;
        final msg = t['message']?.toString() ?? '';
        return ListTile(
          leading: const Icon(Icons.task_alt),
          title: Text('$title ($status)'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              LinearProgressIndicator(value: (percent / 100).clamp(0.0, 1.0)),
              const SizedBox(height: 6),
              Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _notifyTaskChanges(List<Map<String, dynamic>> incoming) async {
    final taskNotifyEnabled =
        await NotificationService.instance.isPushTypeEnabled(NotificationService.pushTypeTask);
    if (!taskNotifyEnabled) {
      _lastStatuses
        ..clear()
        ..addEntries(
          incoming.map(
            (task) => MapEntry(_taskKey(task), task['status']?.toString() ?? 'unknown'),
          ),
        );
      _hasSnapshot = true;
      return;
    }

    if (!_hasSnapshot) {
      _lastStatuses
        ..clear()
        ..addEntries(
          incoming.map(
            (task) => MapEntry(_taskKey(task), task['status']?.toString() ?? 'unknown'),
          ),
        );
      _hasSnapshot = true;
      return;
    }

    for (final task in incoming) {
      final key = _taskKey(task);
      final next = task['status']?.toString() ?? 'unknown';
      final prev = _lastStatuses[key];
      if (prev != null && prev != next) {
        final title = task['task_name']?.toString() ?? '后台任务';
        final msg = task['message']?.toString() ?? '';
        if (next == 'done' || next == 'success' || next == 'completed') {
          await NotificationService.instance.showTaskNotification(
            title: '任务完成：$title',
            body: msg.isEmpty ? '后台任务已完成' : msg,
          );
        } else if (next == 'failed' || next == 'error') {
          await NotificationService.instance.showTaskNotification(
            title: '任务失败：$title',
            body: msg.isEmpty ? '请进入应用查看详情' : msg,
          );
        }
      }
      _lastStatuses[key] = next;
    }
  }

  String _taskKey(Map<String, dynamic> task) {
    final id = task['id']?.toString();
    if (id != null && id.isNotEmpty) return id;
    return '${task['task_name'] ?? 'task'}-${task['created_at'] ?? ''}';
  }
}
