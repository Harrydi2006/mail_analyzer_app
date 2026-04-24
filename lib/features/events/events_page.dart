import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'events_repository.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final _repo = EventsRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final _searchController = TextEditingController();
  int _days = 30;
  String _importance = '';
  bool _runningAction = false;
  bool _loadingSubscribe = false;
  String? _subscribeKey;
  int _subscribeDays = 365;
  String _subscribeImportance = '';
  bool _icalUrlVisible = false;
  bool _subscribeUrlVisible = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSubscribeKey();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _items = await _repo.fetchEvents(
        days: _days,
        importance: _importance,
        search: _searchController.text.trim(),
      );
    } catch (e) {
      _error = e.toString();
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadSubscribeKey() async {
    setState(() => _loadingSubscribe = true);
    try {
      _subscribeKey = await _repo.fetchSubscribeKey();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载订阅信息失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingSubscribe = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _importanceText(String level) {
    switch (level) {
      case 'important':
        return '重要';
      case 'subscribed':
        return '订阅';
      case 'normal':
        return '普通';
      case 'unimportant':
        return '不重要';
      default:
        return '未知';
    }
  }

  Color _importanceColor(String level) {
    switch (level) {
      case 'important':
        return Colors.red;
      case 'subscribed':
        return Colors.green;
      case 'normal':
        return Colors.blue;
      case 'unimportant':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _safeDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} '
        '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successText,
  }) async {
    if (_runningAction) return;
    setState(() => _runningAction = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successText)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  String get _icalUrl => _repo.buildIcalExportUrl(
        days: _subscribeDays,
        importance: _subscribeImportance,
      );

  String get _subscribeUrl => (_subscribeKey == null || _subscribeKey!.isEmpty)
      ? ''
      : _repo.buildSubscribeUrl(
          subscribeKey: _subscribeKey!,
          days: _subscribeDays,
          importance: _subscribeImportance,
        );

  Future<void> _copyText(String text, String successText) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(successText)),
    );
  }

  String _fmtDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showBulkDeleteDialog() async {
    bool deleteAll = false;
    DateTime? start;
    DateTime? end;

    Future<DateTime?> pickDateTime(DateTime? current) async {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        initialDate: current ?? now,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 5),
      );
      if (d == null) return null;
      if (!mounted) return null;
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(current ?? now),
      );
      if (t == null) return DateTime(d.year, d.month, d.day);
      return DateTime(d.year, d.month, d.day, t.hour, t.minute);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) => AlertDialog(
            title: const Text('批量删除日程'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('删除全部日程'),
                  value: deleteAll,
                  onChanged: (v) => setModal(() => deleteAll = v),
                ),
                if (!deleteAll) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开始时间（可选）'),
                    subtitle: Text(start == null ? '未设置' : _fmtDateTime(start!)),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final v = await pickDateTime(start);
                      if (v != null) setModal(() => start = v);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('结束时间（可选）'),
                    subtitle: Text(end == null ? '未设置' : _fmtDateTime(end!)),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final v = await pickDateTime(end);
                      if (v != null) setModal(() => end = v);
                    },
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认删除'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) return;
    await _runAction(
      () => _repo.bulkDelete(
        all: deleteAll,
        start: start?.toIso8601String(),
        end: end?.toIso8601String(),
      ),
      successText: deleteAll ? '已删除全部日程' : '批量删除完成',
    );
  }

  Widget _calendarExportPanel() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: const Text(
            '日历导出与订阅',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _subscribeDays,
                    decoration: const InputDecoration(
                      labelText: '导出/订阅时间范围',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('未来30天')),
                      DropdownMenuItem(value: 90, child: Text('未来90天')),
                      DropdownMenuItem(value: 365, child: Text('未来一年')),
                    ],
                    onChanged: (v) => setState(() => _subscribeDays = v ?? 365),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _subscribeImportance,
                    decoration: const InputDecoration(
                      labelText: '重要性筛选',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('全部')),
                      DropdownMenuItem(
                          value: 'important', child: Text('仅重要')),
                      DropdownMenuItem(value: 'normal', child: Text('仅普通')),
                      DropdownMenuItem(
                          value: 'unimportant', child: Text('仅不重要')),
                    ],
                    onChanged: (v) =>
                        setState(() => _subscribeImportance = v ?? ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('iCal 导出链接',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _icalUrlVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _icalUrlVisible ? '隐藏链接' : '显示链接',
                  onPressed: () =>
                      setState(() => _icalUrlVisible = !_icalUrlVisible),
                ),
                FilledButton.tonal(
                  onPressed: () => _copyText(_icalUrl, 'iCal 链接已复制'),
                  child: const Text('复制'),
                ),
              ],
            ),
            if (_icalUrlVisible) ...[
              const SizedBox(height: 4),
              SelectableText(
                _icalUrl,
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('订阅链接',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const Spacer(),
                if (_loadingSubscribe)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton(
                    onPressed: _loadSubscribeKey,
                    child: const Text('刷新key'),
                  ),
                IconButton(
                  icon: Icon(
                    _subscribeUrlVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _subscribeUrlVisible ? '隐藏链接' : '显示链接',
                  onPressed: () => setState(
                      () => _subscribeUrlVisible = !_subscribeUrlVisible),
                ),
                FilledButton.tonal(
                  onPressed: _subscribeUrl.isEmpty
                      ? null
                      : () => _copyText(_subscribeUrl, '订阅链接已复制'),
                  child: const Text('复制'),
                ),
              ],
            ),
            if (_subscribeUrlVisible) ...[
              const SizedBox(height: 4),
              SelectableText(
                _subscribeUrl.isEmpty ? '订阅key未就绪' : _subscribeUrl,
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: _runningAction ? null : _showBulkDeleteDialog,
                child: const Text('批量删除日程'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEventDetail(Map<String, dynamic> e) {
    final eventId = (e['id'] is num) ? (e['id'] as num).toInt() : null;
    if (eventId == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        String selectedImportance = (e['importance_level']?.toString() ?? 'normal');
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView(
                  children: [
                    Text(
                      e['title']?.toString() ?? '(未命名事件)',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          label: Text(_importanceText(selectedImportance)),
                          backgroundColor: _importanceColor(selectedImportance).withOpacity(0.14),
                        ),
                        if ((e['email_id']?.toString() ?? '').isNotEmpty)
                          const Chip(label: Text('来自邮件')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: const Text('开始时间'),
                      subtitle: Text(_safeDate(e['start_time']?.toString())),
                    ),
                    if ((e['end_time']?.toString() ?? '').isNotEmpty)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.flag_outlined),
                        title: const Text('结束时间'),
                        subtitle: Text(_safeDate(e['end_time']?.toString())),
                      ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.place_outlined),
                      title: const Text('地点'),
                      subtitle: Text((e['location']?.toString().isNotEmpty == true)
                          ? e['location'].toString()
                          : '-'),
                    ),
                    const SizedBox(height: 6),
                    const Text('描述', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text((e['description']?.toString().isNotEmpty == true)
                            ? e['description'].toString()
                            : '无描述'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedImportance,
                      decoration: const InputDecoration(
                        labelText: '调整重要性',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'important', child: Text('重要')),
                        DropdownMenuItem(value: 'normal', child: Text('普通')),
                        DropdownMenuItem(value: 'unimportant', child: Text('不重要')),
                        DropdownMenuItem(value: 'subscribed', child: Text('订阅')),
                      ],
                      onChanged: (v) {
                        setModalState(() => selectedImportance = v ?? 'normal');
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: _runningAction
                              ? null
                              : () => _runAction(
                                    () => _repo.updateImportance(eventId, selectedImportance),
                                    successText: '日程重要性已更新',
                                  ),
                          child: const Text('保存重要性'),
                        ),
                        FilledButton.tonal(
                          onPressed: _runningAction
                              ? null
                              : () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('确认删除'),
                                      content: const Text('该操作不可撤销，确定删除此日程吗？'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('取消'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    if (!mounted) return;
                                    Navigator.of(context).pop();
                                    await _runAction(
                                      () => _repo.deleteEvent(eventId),
                                      successText: '日程已删除',
                                    );
                                  }
                                },
                          child: const Text('删除日程'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _filters() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _days,
                    decoration: const InputDecoration(labelText: '时间范围', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('未来7天')),
                      DropdownMenuItem(value: 30, child: Text('未来30天')),
                      DropdownMenuItem(value: 90, child: Text('未来90天')),
                      DropdownMenuItem(value: 365, child: Text('未来一年')),
                    ],
                    onChanged: (v) => setState(() => _days = v ?? 30),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _importance,
                    decoration: const InputDecoration(labelText: '重要性', isDense: true),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('全部')),
                      DropdownMenuItem(value: 'important', child: Text('重要')),
                      DropdownMenuItem(value: 'normal', child: Text('普通')),
                      DropdownMenuItem(value: 'unimportant', child: Text('不重要')),
                    ],
                    onChanged: (v) => setState(() => _importance = v ?? ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: '搜索标题或描述',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _load,
                  child: const Text('筛选'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('加载失败: $_error'));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          _calendarExportPanel(),
          _filters(),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('暂无日程')),
            )
          else
            ..._items.map((e) {
              final level = e['importance_level']?.toString() ?? '';
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: ListTile(
                  onTap: () => _showEventDetail(e),
                  leading: const Icon(Icons.event_available),
                  title: Text(
                    e['title']?.toString() ?? '(未命名事件)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_safeDate(e['start_time']?.toString())}  |  ${e['location'] ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          Chip(
                            label: Text(_importanceText(level)),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: _importanceColor(level).withOpacity(0.14),
                          ),
                        ],
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            }),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
