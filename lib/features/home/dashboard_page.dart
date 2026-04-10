import 'package:flutter/material.dart';

import 'dashboard_repository.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _repo = DashboardRepository();
  bool _loading = true;
  String? _error;

  Map<String, bool> _status = {'email': false, 'ai': false, 'notion': false};
  Map<String, dynamic> _stats = const {
    'total_emails': 0,
    'total_events': 0,
    'important_events': 0,
    'pending_reminders': 0,
  };
  List<Map<String, dynamic>> _recentEmails = [];
  List<Map<String, dynamic>> _upcomingEvents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _repo.fetchSystemStatus(),
        _repo.fetchStatistics(),
        _repo.fetchRecentEmails(limit: 5),
        _repo.fetchUpcomingEvents(days: 7),
      ]);
      _status = results[0] as Map<String, bool>;
      _stats = results[1] as Map<String, dynamic>;
      _recentEmails = results[2] as List<Map<String, dynamic>>;
      _upcomingEvents = results[3] as List<Map<String, dynamic>>;
    } catch (e) {
      _error = e.toString();
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('首页加载失败: $_error'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('系统配置状态', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusChip('邮箱', _status['email'] == true),
              _statusChip('AI', _status['ai'] == true),
              _statusChip('Notion', _status['notion'] == true),
            ],
          ),
          const SizedBox(height: 16),
          const Text('核心统计', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _statsGrid(_stats),
          const SizedBox(height: 16),
          const Text('最近邮件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _recentEmails.isEmpty
              ? const Card(child: ListTile(title: Text('暂无邮件')))
              : Card(
                  child: Column(
                    children: _recentEmails
                        .map(
                          (e) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.mail_outline),
                            title: Text(
                              e['subject']?.toString() ?? '(无主题)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              e['sender']?.toString() ?? '-',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
          const SizedBox(height: 16),
          const Text('近期日程（7天）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _upcomingEvents.isEmpty
              ? const Card(child: ListTile(title: Text('未来 7 天暂无日程')))
              : Card(
                  child: Column(
                    children: _upcomingEvents
                        .take(5)
                        .map(
                          (e) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.event_note),
                            title: Text(
                              e['title']?.toString() ?? '(未命名事件)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              e['start_time']?.toString() ?? '-',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, bool ok) {
    return Chip(
      avatar: Icon(ok ? Icons.check_circle : Icons.error_outline, size: 16, color: ok ? Colors.green : Colors.orange),
      label: Text('$label${ok ? '已配置' : '未配置'}'),
    );
  }

  Widget _statsGrid(Map<String, dynamic> stats) {
    final cards = <MapEntry<String, String>>[
      MapEntry('邮件总数', '${stats['total_emails'] ?? 0}'),
      MapEntry('事件总数', '${stats['total_events'] ?? 0}'),
      MapEntry('重要事件', '${stats['important_events'] ?? 0}'),
      MapEntry('7天内提醒', '${stats['pending_reminders'] ?? 0}'),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 88,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (_, index) {
        final item = cards[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(item.key, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                Text(item.value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        );
      },
    );
  }
}
