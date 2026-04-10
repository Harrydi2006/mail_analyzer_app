import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/notifications/notification_service.dart';
import 'settings_repository.dart';
import '../tasks/tasks_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _client = ApiClient.instance;
  final _repo = SettingsRepository();
  bool _taskNotification = true;
  bool _reminderNotification = true;
  bool _notificationPermissionGranted = false;
  bool _checkingNotificationPermission = false;
  bool _runningAction = false;
  bool _loadingAdvanced = true;

  Map<String, List<String>> _keywords = {
    'important': [],
    'normal': [],
    'unimportant': [],
  };
  final _keywordInput = {
    'important': TextEditingController(),
    'normal': TextEditingController(),
    'unimportant': TextEditingController(),
  };

  bool _dedupEnabled = true;
  final _dedupWindowController = TextEditingController(text: '72');
  final _dedupThresholdController = TextEditingController(text: '0.85');
  final _dedupWeights = {
    'title': TextEditingController(text: '0.35'),
    'time': TextEditingController(text: '0.30'),
    'tags': TextEditingController(text: '0.20'),
    'sender': TextEditingController(text: '0.10'),
    'location': TextEditingController(text: '0.05'),
  };

  List<Map<String, dynamic>> _subscriptions = [];
  final _retentionController = TextEditingController(text: '30');
  final _subInputs = {
    2: TextEditingController(),
    3: TextEditingController(),
    4: TextEditingController(),
  };
  final _manualInputs = {
    2: TextEditingController(),
    3: TextEditingController(),
    4: TextEditingController(),
  };
  Map<int, List<Map<String, dynamic>>> _historyCandidates = {
    2: [],
    3: [],
    4: [],
  };
  final _notionSearchController = TextEditingController();
  bool _loadingNotion = false;
  List<Map<String, dynamic>> _notionArchived = [];
  List<Map<String, dynamic>> _notionSearchResults = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pref = await SharedPreferences.getInstance();
    setState(() {
      _taskNotification = pref.getBool('task_notification') ?? true;
      _reminderNotification = pref.getBool('reminder_notification') ?? true;
    });
    await _refreshNotificationPermission(silent: true);
    await _loadAdvancedSettings();
  }

  Future<void> _refreshNotificationPermission({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _checkingNotificationPermission = true);
    }
    try {
      final granted = await NotificationService.instance.isPermissionGranted();
      if (!mounted) return;
      setState(() => _notificationPermissionGranted = granted);
    } finally {
      if (!silent && mounted) {
        setState(() => _checkingNotificationPermission = false);
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (_checkingNotificationPermission) return;
    setState(() => _checkingNotificationPermission = true);
    try {
      final granted = await NotificationService.instance.requestPermissionIfNeeded();
      if (!mounted) return;
      setState(() => _notificationPermissionGranted = granted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(granted ? '通知权限已开启' : '通知权限未开启，请到系统设置中允许')),
      );
    } finally {
      if (mounted) setState(() => _checkingNotificationPermission = false);
    }
  }

  Future<void> _save() async {
    final pref = await SharedPreferences.getInstance();
    await pref.setBool('task_notification', _taskNotification);
    await pref.setBool('reminder_notification', _reminderNotification);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存')),
    );
  }

  Future<void> _loadAdvancedSettings() async {
    setState(() => _loadingAdvanced = true);
    try {
      final cfg = await _repo.fetchConfig();
      final kw = (cfg['keywords'] is Map) ? Map<String, dynamic>.from(cfg['keywords'] as Map) : {};
      _keywords = {
        'important': _stringList(kw['important']),
        'normal': _stringList(kw['normal']),
        'unimportant': _stringList(kw['unimportant']),
      };

      final dedup = (cfg['dedup_beta'] is Map) ? Map<String, dynamic>.from(cfg['dedup_beta'] as Map) : {};
      final weights = (dedup['weights'] is Map) ? Map<String, dynamic>.from(dedup['weights'] as Map) : {};
      _dedupEnabled = dedup['enabled'] != false;
      _dedupWindowController.text = (dedup['time_window_hours'] ?? 72).toString();
      _dedupThresholdController.text = (dedup['auto_merge_threshold'] ?? 0.85).toString();
      _dedupWeights['title']!.text = (weights['title'] ?? 0.35).toString();
      _dedupWeights['time']!.text = (weights['time'] ?? 0.30).toString();
      _dedupWeights['tags']!.text = (weights['tags'] ?? 0.20).toString();
      _dedupWeights['sender']!.text = (weights['sender'] ?? 0.10).toString();
      _dedupWeights['location']!.text = (weights['location'] ?? 0.05).toString();

      final tagSettings = await _repo.fetchTagSettings();
      _subscriptions = _normalizeSubscriptions(tagSettings['subscriptions']);
      final retention =
          (tagSettings['history_retention_days'] is num) ? (tagSettings['history_retention_days'] as num).toInt() : 30;
      _retentionController.text = retention.toString();

      await _loadHistoryCandidates();
      await _loadNotionData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载高级设置失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingAdvanced = false);
    }
  }

  Future<void> _loadNotionData() async {
    setState(() => _loadingNotion = true);
    try {
      _notionArchived = await _repo.fetchNotionArchived(limit: 30);
      _notionSearchResults = [];
    } finally {
      if (mounted) setState(() => _loadingNotion = false);
    }
  }

  Future<void> _loadHistoryCandidates() async {
    final resp = await _repo.fetchHistoryCandidates();
    final candidates = (resp['candidates'] is Map) ? Map<String, dynamic>.from(resp['candidates'] as Map) : {};
    _historyCandidates = {
      2: _normalizeHistoryList(candidates['other_level2']),
      3: _normalizeHistoryList(candidates['level3']),
      4: _normalizeHistoryList(candidates['level4']),
    };
    if (resp['history_retention_days'] is num) {
      _retentionController.text = (resp['history_retention_days'] as num).toInt().toString();
    }
  }

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }

  List<Map<String, dynamic>> _normalizeSubscriptions(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final level = (m['level'] is num) ? (m['level'] as num).toInt() : -1;
      final value = (m['value'] ?? '').toString().trim();
      if ((level == 2 || level == 3 || level == 4) && value.isNotEmpty) {
        out.add({'level': level, 'value': value});
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _normalizeHistoryList(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        out.add({
          'value': (item['value'] ?? '').toString(),
          'manual': item['manual'] == true,
          'subscribed': item['subscribed'] == true,
        });
      } else {
        out.add({'value': item.toString(), 'manual': false, 'subscribed': false});
      }
    }
    return out.where((e) => (e['value'] ?? '').toString().trim().isNotEmpty).toList();
  }

  Future<void> _runServerAction({
    required String endpoint,
    required String successText,
    Object? data,
  }) async {
    if (_runningAction) return;
    setState(() => _runningAction = true);
    try {
      final res = await _client.post(endpoint, data: data);
      final body = res.data;
      if (body is Map<String, dynamic> && body['success'] == false) {
        throw Exception(body['error']?.toString() ?? '执行失败');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successText)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('执行失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  Future<void> _runRepoAction(
    Future<void> Function() action, {
    required String successText,
    bool reloadAdvanced = false,
  }) async {
    if (_runningAction) return;
    setState(() => _runningAction = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successText)));
      if (reloadAdvanced) {
        await _loadAdvancedSettings();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('执行失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  Future<void> _searchNotion() async {
    final q = _notionSearchController.text.trim();
    if (q.isEmpty) {
      setState(() => _notionSearchResults = []);
      return;
    }
    setState(() => _loadingNotion = true);
    try {
      _notionSearchResults = await _repo.searchNotion(query: q, limit: 10);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notion搜索失败: $e')));
    } finally {
      if (mounted) setState(() => _loadingNotion = false);
    }
  }

  String _pickField(Map<String, dynamic> item, List<String> keys, {String fallback = '-'}) {
    for (final k in keys) {
      final v = item[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return fallback;
  }

  Future<void> _copyText(String text, String successText) async {
    if (text.trim().isEmpty || text == '-') return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successText)));
  }

  Future<void> _saveKeywords() async {
    await _runRepoAction(
      () => _repo.saveKeywords(_keywords),
      successText: '关键词已保存',
    );
  }

  Future<void> _saveDedupBeta() async {
    final payload = {
      'enabled': _dedupEnabled,
      'time_window_hours': int.tryParse(_dedupWindowController.text.trim()) ?? 72,
      'auto_merge_threshold': double.tryParse(_dedupThresholdController.text.trim()) ?? 0.85,
      'weights': {
        'title': double.tryParse(_dedupWeights['title']!.text.trim()) ?? 0.35,
        'time': double.tryParse(_dedupWeights['time']!.text.trim()) ?? 0.30,
        'tags': double.tryParse(_dedupWeights['tags']!.text.trim()) ?? 0.20,
        'sender': double.tryParse(_dedupWeights['sender']!.text.trim()) ?? 0.10,
        'location': double.tryParse(_dedupWeights['location']!.text.trim()) ?? 0.05,
      },
    };
    await _runRepoAction(
      () => _repo.saveDedupBeta(payload),
      successText: '去重 Beta 设置已保存',
    );
  }

  Future<void> _saveTagSettings() async {
    final retention = int.tryParse(_retentionController.text.trim()) ?? 30;
    await _runRepoAction(
      () => _repo.saveTagSettings(
        subscriptions: _subscriptions,
        historyRetentionDays: retention,
      ),
      successText: '标签配置已保存',
      reloadAdvanced: true,
    );
  }

  void _addKeyword(String type) {
    final input = _keywordInput[type]!;
    final value = input.text.trim();
    if (value.isEmpty) return;
    final list = _keywords[type] ?? [];
    if (!list.contains(value)) {
      setState(() => list.add(value));
    }
    input.clear();
  }

  void _removeKeyword(String type, String value) {
    setState(() => _keywords[type]?.remove(value));
  }

  List<Map<String, dynamic>> _subsByLevel(int level) =>
      _subscriptions.where((s) => (s['level'] as int?) == level).toList();

  Future<void> _addSubscription(int level) async {
    final ctrl = _subInputs[level]!;
    final value = ctrl.text.trim();
    if (value.isEmpty) return;
    await _runRepoAction(
      () => _repo.subscribeTag(level: level, value: value, applyNow: true),
      successText: '订阅成功',
      reloadAdvanced: true,
    );
    ctrl.clear();
  }

  Future<void> _removeSubscription(int level, String value) async {
    await _runRepoAction(
      () => _repo.unsubscribeTag(level: level, value: value, applyNow: true),
      successText: '已取消订阅',
      reloadAdvanced: true,
    );
  }

  Future<void> _toggleCandidateSubscription(int level, Map<String, dynamic> item) async {
    final value = (item['value'] ?? '').toString().trim();
    if (value.isEmpty) return;
    final subscribed = item['subscribed'] == true;
    if (subscribed) {
      await _removeSubscription(level, value);
      return;
    }
    await _runRepoAction(
      () => _repo.subscribeTag(level: level, value: value, applyNow: true),
      successText: '订阅成功',
      reloadAdvanced: true,
    );
  }

  Future<void> _addManualHistory(int level) async {
    final ctrl = _manualInputs[level]!;
    final value = ctrl.text.trim();
    if (value.isEmpty) return;
    await _runRepoAction(
      () => _repo.addManualHistoryCandidate(level: level, value: value),
      successText: '已添加手工历史标签',
      reloadAdvanced: true,
    );
    ctrl.clear();
  }

  Future<void> _deleteHistory(int level, Map<String, dynamic> item) async {
    final value = (item['value'] ?? '').toString().trim();
    if (value.isEmpty) return;
    await _runRepoAction(
      () => _repo.deleteHistoryCandidate(
        level: level,
        value: value,
        manual: item['manual'] == true,
      ),
      successText: '历史候选已删除',
      reloadAdvanced: true,
    );
  }

  Widget _keywordSection() {
    Widget block(String type, String label, Color color) {
      final list = _keywords[type] ?? [];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
              const SizedBox(height: 8),
              if (list.isEmpty)
                const Text('暂无关键词', style: TextStyle(color: Colors.grey))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: list
                      .map((e) => InputChip(
                            label: Text(e),
                            onDeleted: () => _removeKeyword(type, e),
                          ))
                      .toList(),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keywordInput[type],
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '输入关键词',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addKeyword(type),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () => _addKeyword(type),
                    child: const Text('添加'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('关键词管理', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              block('important', '重要关键词', Colors.red),
              block('normal', '普通关键词', Colors.blue),
              block('unimportant', '不重要关键词', Colors.grey),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _runningAction ? null : _saveKeywords,
                  child: const Text('保存关键词'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dedupSection() {
    Widget weightInput(String key, String label) {
      return Expanded(
        child: TextField(
          controller: _dedupWeights[key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('去重 Beta 设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用智能去重'),
                    value: _dedupEnabled,
                    onChanged: (v) => setState(() => _dedupEnabled = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dedupWindowController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '时间窗口(小时)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _dedupThresholdController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: '自动合并阈值',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(children: [weightInput('title', '标题权重'), const SizedBox(width: 8), weightInput('time', '时间权重')]),
                  const SizedBox(height: 8),
                  Row(children: [weightInput('tags', '标签权重'), const SizedBox(width: 8), weightInput('sender', '发件人权重')]),
                  const SizedBox(height: 8),
                  Row(children: [weightInput('location', '地点权重'), const Spacer()]),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: _runningAction ? null : _saveDedupBeta,
                      child: const Text('保存去重设置'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubGroup(int level, String title) {
    final subs = _subsByLevel(level);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (subs.isEmpty)
              const Text('暂无订阅', style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subs
                    .map(
                      (s) => InputChip(
                        label: Text(s['value'].toString()),
                        onDeleted: () => _removeSubscription(level, s['value'].toString()),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subInputs[level],
                    decoration: const InputDecoration(
                      hintText: '新增订阅标签',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addSubscription(level),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _runningAction ? null : () => _addSubscription(level),
                  child: const Text('订阅'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryGroup(int level, String title) {
    final items = _historyCandidates[level] ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text('暂无历史候选', style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items.map((item) {
                  final value = item['value'].toString();
                  final manual = item['manual'] == true;
                  final subscribed = item['subscribed'] == true;
                  Color? bg;
                  if (manual) bg = Colors.lightBlue.shade100;
                  if (subscribed) bg = Colors.red.shade100;
                  return InputChip(
                    label: Text(value),
                    backgroundColor: bg,
                    avatar: Icon(
                      subscribed ? Icons.notifications_active_outlined : Icons.notifications_none_outlined,
                      size: 16,
                      color: subscribed ? Colors.red : Colors.blueGrey,
                    ),
                    onPressed: _runningAction ? null : () => _toggleCandidateSubscription(level, item),
                    onDeleted: _runningAction ? null : () => _deleteHistory(level, item),
                  );
                }).toList(),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualInputs[level],
                    decoration: const InputDecoration(
                      hintText: '手工添加历史标签',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addManualHistory(level),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _runningAction ? null : () => _addManualHistory(level),
                  child: const Text('添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('标签订阅与历史', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _retentionController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '历史候选清理天数',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: _runningAction ? null : _saveTagSettings,
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              ),
              _buildSubGroup(2, '二级订阅'),
              _buildSubGroup(3, '三级订阅'),
              _buildSubGroup(4, '四级订阅'),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _runningAction
                      ? null
                      : () => _runRepoAction(
                            () => _repo.reapplySubscriptions(),
                            successText: '已触发重应用订阅规则',
                          ),
                  child: const Text('重应用订阅规则'),
                ),
              ),
              const SizedBox(height: 8),
              _buildHistoryGroup(2, '历史候选（二级）'),
              _buildHistoryGroup(3, '历史候选（三级）'),
              _buildHistoryGroup(4, '历史候选（四级）'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _notionSection() {
    Widget resultCard(Map<String, dynamic> item) {
      final title = _pickField(item, ['title', 'subject', 'name', 'page_title'], fallback: '(无标题)');
      final url = _pickField(item, ['url', 'page_url', 'notion_url'], fallback: '-');
      final date = _pickField(item, ['archived_at', 'archive_date', 'created_time', 'last_edited_time'], fallback: '-');
      return Card(
        child: ListTile(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('$date\n$url', maxLines: 2, overflow: TextOverflow.ellipsis),
          isThreeLine: true,
          trailing: IconButton(
            icon: const Icon(Icons.copy_outlined),
            onPressed: url == '-' ? null : () => _copyText(url, 'Notion链接已复制'),
          ),
        ),
      );
    }

    final showing = _notionSearchController.text.trim().isNotEmpty ? _notionSearchResults : _notionArchived;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Notion归档', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _notionSearchController,
                          decoration: const InputDecoration(
                            hintText: '搜索Notion页面',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _searchNotion(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: _loadingNotion ? null : _searchNotion,
                        child: const Text('搜索'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: _loadingNotion
                            ? null
                            : () {
                                _notionSearchController.clear();
                                _loadNotionData();
                              },
                        child: const Text('刷新'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loadingNotion)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                )
              else if (showing.isEmpty)
                const Card(child: ListTile(title: Text('暂无Notion数据')))
              else
                ...showing.take(20).map(resultCard),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    for (final c in _keywordInput.values) {
      c.dispose();
    }
    _dedupWindowController.dispose();
    _dedupThresholdController.dispose();
    for (final c in _dedupWeights.values) {
      c.dispose();
    }
    _retentionController.dispose();
    for (final c in _subInputs.values) {
      c.dispose();
    }
    for (final c in _manualInputs.values) {
      c.dispose();
    }
    _notionSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Future<void> openSection(String title, Widget body) async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: body,
          ),
        ),
      );
    }

    Widget sectionEntry({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback? onTap,
      bool loading = false,
    }) {
      return Card(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: loading ? null : onTap,
        ),
      );
    }

    return ListView(
      children: [
        const SizedBox(height: 8),
        Card(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: ListTile(
            title: const Text('后端地址'),
            subtitle: Text(AppConfig.baseUrl),
            leading: const Icon(Icons.cloud_outlined),
          ),
        ),
        sectionEntry(
          icon: Icons.notifications_outlined,
          title: '通知设置',
          subtitle: '任务通知、日程提醒通知',
          onTap: () => openSection(
            '通知设置',
            ListView(
              children: [
                SwitchListTile(
                  title: const Text('任务通知'),
                  subtitle: const Text('任务失败/完成时推送通知'),
                  value: _taskNotification,
                  onChanged: (v) => setState(() => _taskNotification = v),
                ),
                SwitchListTile(
                  title: const Text('日程提醒通知'),
                  subtitle: const Text('事件提醒时弹出系统通知'),
                  value: _reminderNotification,
                  onChanged: (v) => setState(() => _reminderNotification = v),
                ),
                ListTile(
                  leading: Icon(
                    _notificationPermissionGranted ? Icons.check_circle_outline : Icons.error_outline,
                    color: _notificationPermissionGranted ? Colors.green : Colors.orange,
                  ),
                  title: const Text('系统通知权限'),
                  subtitle: Text(_notificationPermissionGranted ? '已允许' : '未允许（国产安卓常需手动开启）'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _checkingNotificationPermission ? null : _requestNotificationPermission,
                          child: const Text('申请通知权限'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _checkingNotificationPermission
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok =
                                      await NotificationService.instance.openSystemNotificationSettings();
                                  if (!mounted) return;
                                  if (!ok) {
                                    messenger.showSnackBar(
                                      const SnackBar(content: Text('无法打开系统设置')),
                                    );
                                    return;
                                  }
                                  await _refreshNotificationPermission(silent: true);
                                },
                          child: const Text('打开系统设置'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('保存设置'),
                  ),
                ),
              ],
            ),
          ),
        ),
        sectionEntry(
          icon: Icons.key_outlined,
          title: '关键词管理',
          subtitle: '重要/普通/不重要关键词',
          loading: _loadingAdvanced,
          onTap: () => openSection('关键词管理', ListView(children: [_keywordSection()])),
        ),
        sectionEntry(
          icon: Icons.merge_type_outlined,
          title: '去重 Beta 设置',
          subtitle: '时间窗口、阈值与权重',
          loading: _loadingAdvanced,
          onTap: () => openSection('去重 Beta 设置', ListView(children: [_dedupSection()])),
        ),
        sectionEntry(
          icon: Icons.label_outline,
          title: '标签订阅与历史',
          subtitle: '订阅规则、候选标签、手工标签',
          loading: _loadingAdvanced,
          onTap: () => openSection('标签订阅与历史', ListView(children: [_tagSection()])),
        ),
        sectionEntry(
          icon: Icons.notes_outlined,
          title: 'Notion 归档',
          subtitle: '查看归档与搜索',
          loading: _loadingAdvanced,
          onTap: () => openSection('Notion 归档', ListView(children: [_notionSection()])),
        ),
        sectionEntry(
          icon: Icons.build_outlined,
          title: '系统操作',
          subtitle: '重应用订阅、重抓取、全量重分析',
          onTap: () => openSection(
            '系统操作',
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _runningAction
                          ? null
                          : () => _runServerAction(
                                endpoint: '/api/tags/reapply-subscriptions',
                                successText: '已触发：重新应用订阅规则',
                              ),
                      child: const Text('重应用订阅规则'),
                    ),
                    FilledButton.tonal(
                      onPressed: _runningAction
                          ? null
                          : () => _runServerAction(
                                endpoint: '/api/emails/refetch_all',
                                successText: '已触发：重新抓取全部邮件',
                              ),
                      child: const Text('重新抓取邮件'),
                    ),
                    FilledButton.tonal(
                      onPressed: _runningAction
                          ? null
                          : () => _runServerAction(
                                endpoint: '/api/emails/reanalyze_all',
                                successText: '已触发：全量重新分析',
                              ),
                      child: const Text('全量重分析'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        sectionEntry(
          icon: Icons.task_alt_outlined,
          title: '任务进度',
          subtitle: '查看后台任务执行状态',
          onTap: () => openSection(
            '任务进度',
            const Padding(
              padding: EdgeInsets.all(8),
              child: TasksPage(),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
