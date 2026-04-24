import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'emails_repository.dart';

class EmailsPage extends StatefulWidget {
  const EmailsPage({super.key});

  @override
  State<EmailsPage> createState() => _EmailsPageState();
}

class _EmailsPageState extends State<EmailsPage> {
  final _repo = EmailsRepository();
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final _searchController = TextEditingController();
  String _importance = '';
  String _status = '';
  DateTime? _startDate;
  DateTime? _endDate;
  int _page = 1;
  int _perPage = 20;
  int _total = 0;
  bool _runningAction = false;
  bool _streamRunning = false;
  bool _streamConnecting = false;
  int _streamMaxCount = 0;
  final _streamMaxCountController = TextEditingController(text: '0');
  Timer? _streamStatusTimer;
  CancelToken? _streamCancelToken;
  List<String> _streamLogs = [];
  Set<String> _subscribedTagKeys = <String>{};
  bool _syncingTagSubs = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadTagSubscriptions());
    _load(reset: true);
  }

  Future<void> _load({int? page, bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final targetPage = reset ? 1 : (page ?? _page);
      final result = await _repo.fetchEmails(
        page: targetPage,
        perPage: _perPage,
        importance: _importance,
        status: _status,
        search: _searchController.text.trim(),
        startDate: _startDate == null ? null : _fmtDate(_startDate!),
        endDate: _endDate == null ? null : _fmtDate(_endDate!),
      );
      final incoming = (result['items'] as List<Map<String, dynamic>>?) ??
          <Map<String, dynamic>>[];
      _items = incoming;
      _page = (result['page'] as int?) ?? targetPage;
      _perPage = (result['per_page'] as int?) ?? 20;
      _total = (result['total'] as int?) ?? incoming.length;
      _hasMore = _items.length < _total;
    } catch (e) {
      _error = e.toString();
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final result = await _repo.fetchEmails(
        page: nextPage,
        perPage: _perPage,
        importance: _importance,
        status: _status,
        search: _searchController.text.trim(),
        startDate: _startDate == null ? null : _fmtDate(_startDate!),
        endDate: _endDate == null ? null : _fmtDate(_endDate!),
      );
      final incoming = (result['items'] as List<Map<String, dynamic>>?) ??
          <Map<String, dynamic>>[];
      _page = (result['page'] as int?) ?? nextPage;
      _perPage = (result['per_page'] as int?) ?? _perPage;
      _total = (result['total'] as int?) ?? _total;
      if (incoming.isNotEmpty) {
        _items = [..._items, ...incoming];
      }
      _hasMore = _items.length < _total && incoming.isNotEmpty;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 180) {
      unawaited(_loadMore());
    }
  }

  String _fmtDate(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }

  String _dateLabel(DateTime? dt) => dt == null ? '不限' : _fmtDate(dt);

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_startDate ?? now) : (_endDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = picked;
        if (_startDate != null && _startDate!.isAfter(_endDate!)) {
          _startDate = _endDate;
        }
      }
    });
  }

  @override
  void dispose() {
    _streamStatusTimer?.cancel();
    _streamCancelToken?.cancel('dispose');
    _scrollController.dispose();
    _searchController.dispose();
    _streamMaxCountController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _streamStatusTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshStreamStatus(silent: true),
    );
    unawaited(_refreshStreamStatus(silent: true));
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

  String _tagKey(int level, String value) => '$level|${value.trim()}';

  Future<void> _loadTagSubscriptions() async {
    if (_syncingTagSubs) return;
    setState(() => _syncingTagSubs = true);
    try {
      final subs = await _repo.fetchTagSubscriptions();
      final keys = <String>{};
      for (final s in subs) {
        final level = (s['level'] is num) ? (s['level'] as num).toInt() : 0;
        final value = (s['value'] ?? '').toString().trim();
        if ((level == 2 || level == 3 || level == 4) && value.isNotEmpty) {
          keys.add(_tagKey(level, value));
        }
      }
      if (!mounted) return;
      setState(() => _subscribedTagKeys = keys);
    } catch (_) {
      // Keep page usable even if tag subscription fetch fails.
    } finally {
      if (mounted) setState(() => _syncingTagSubs = false);
    }
  }

  List<Map<String, dynamic>> _extractTags(dynamic rawTags) {
    if (rawTags is! Map) return const [];
    final tags = Map<String, dynamic>.from(rawTags);
    final out = <Map<String, dynamic>>[];
    final level2 = (tags['level2'] ?? '').toString().trim();
    final level2Custom = (tags['level2_custom'] ?? '').toString().trim();
    if (level2.isNotEmpty) {
      final value = (level2 == '其他' && level2Custom.isNotEmpty)
          ? '其他[$level2Custom]'
          : level2;
      out.add({'level': 2, 'value': value, 'label': '二级:$value'});
    }
    final level3 = (tags['level3'] ?? '').toString().trim();
    if (level3.isNotEmpty) {
      out.add({'level': 3, 'value': level3, 'label': '三级:$level3'});
    }
    final level4 = (tags['level4'] ?? '').toString().trim();
    if (level4.isNotEmpty) {
      out.add({'level': 4, 'value': level4, 'label': '四级:$level4'});
    }
    return out;
  }

  Future<void> _toggleEmailTagSubscription(Map<String, dynamic> tag) async {
    if (_runningAction) return;
    final level = (tag['level'] as int?) ?? 0;
    final value = (tag['value'] ?? '').toString().trim();
    if ((level != 2 && level != 3 && level != 4) || value.isEmpty) return;
    final key = _tagKey(level, value);
    final subscribed = _subscribedTagKeys.contains(key);
    setState(() => _runningAction = true);
    try {
      if (subscribed) {
        await _repo.unsubscribeTag(level: level, value: value);
      } else {
        await _repo.subscribeTag(level: level, value: value);
      }
      if (!mounted) return;
      setState(() {
        if (subscribed) {
          _subscribedTagKeys.remove(key);
        } else {
          _subscribedTagKeys.add(key);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(subscribed ? '已取消订阅标签：$value' : '已订阅标签：$value')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标签订阅操作失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  Widget _tagChip(Map<String, dynamic> tag) {
    final level = (tag['level'] as int?) ?? 0;
    final value = (tag['value'] ?? '').toString().trim();
    final label = (tag['label'] ?? value).toString();
    final subscribed = _subscribedTagKeys.contains(_tagKey(level, value));
    return InputChip(
      label: Text(label),
      avatar: Icon(
        subscribed
            ? Icons.notifications_active_outlined
            : Icons.notifications_none_outlined,
        size: 16,
        color: subscribed ? Colors.red : Colors.blueGrey,
      ),
      selected: subscribed,
      selectedColor: Colors.red.shade100,
      onPressed: () => _toggleEmailTagSubscription(tag),
    );
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successText)));
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  Future<void> _copyText(String text, String successText) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(successText)));
  }

  void _showImagePreview(String imageUrl, String title) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                title.isEmpty ? '图片预览' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('图片加载失败'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _appendStreamLog(String text) {
    final ts = DateTime.now();
    final line =
        '[${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}] $text';
    setState(() {
      _streamLogs = [..._streamLogs, line];
      if (_streamLogs.length > 200) {
        _streamLogs = _streamLogs.sublist(_streamLogs.length - 200);
      }
    });
  }

  Future<void> _refreshStreamStatus({bool silent = false}) async {
    try {
      final status = await _repo.fetchStreamStatus();
      final running = status['running'] == true;
      final params = (status['params'] is Map)
          ? Map<String, dynamic>.from(status['params'] as Map)
          : {};
      final lastEvent = (status['last_event'] is Map)
          ? Map<String, dynamic>.from(status['last_event'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _streamRunning = running;
        final maxCount = params['max_count'];
        if (maxCount is num) {
          _streamMaxCount = maxCount.toInt();
          _streamMaxCountController.text = _streamMaxCount.toString();
        }
      });
      final msg = (lastEvent['message'] ?? '').toString().trim();
      final st = (lastEvent['status'] ?? '').toString().trim();
      if (!silent && msg.isNotEmpty) {
        _appendStreamLog('${st.isNotEmpty ? '[$st] ' : ''}$msg');
      }
    } catch (e) {
      if (!silent && mounted) {
        _appendStreamLog('获取流式状态失败: $e');
      }
    }
  }

  Future<void> _startStream() async {
    if (_streamConnecting) return;
    setState(() => _streamConnecting = true);
    _appendStreamLog('开始连接流式处理...');
    _streamCancelToken?.cancel('restart');
    final token = CancelToken();
    _streamCancelToken = token;

    unawaited(
      _repo.connectStream(
        start: true,
        maxCount: _streamMaxCount > 0 ? _streamMaxCount : null,
        cancelToken: token,
        onEvent: (ev) {
          final st = (ev['status'] ?? '').toString();
          if (st == 'keepalive') return;
          final msg = (ev['message'] ?? '').toString();
          _appendStreamLog('${st.isNotEmpty ? '[$st] ' : ''}$msg');
          if (st == 'completed' ||
              st == 'cancelled' ||
              (st == 'error' && ev['fatal'] == true)) {
            if (mounted) {
              setState(() {
                _streamRunning = false;
                _streamConnecting = false;
              });
            }
            unawaited(_load(page: 1));
          } else if (mounted) {
            setState(() => _streamRunning = true);
          }
        },
        onError: (err) {
          if (!mounted) return;
          _appendStreamLog('流式连接异常: $err');
          setState(() {
            _streamConnecting = false;
            _streamRunning = false;
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _streamConnecting = false);
        },
      ),
    );
  }

  Future<void> _stopStream() async {
    await _runAction(
      () async {
        await _repo.stopStream();
        _streamCancelToken?.cancel('stop');
        _streamCancelToken = null;
        await _refreshStreamStatus();
      },
      successText: '已发送终止流式任务请求',
    );
  }

  Widget _streamPanel() {
    final statusText =
        _streamConnecting ? '连接中' : (_streamRunning ? '运行中' : '未运行');
    final statusColor = _streamConnecting
        ? Colors.orange
        : (_streamRunning ? Colors.green : Colors.grey);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              const Text(
                '流式处理邮件',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(statusText),
                visualDensity: VisualDensity.compact,
                backgroundColor: statusColor.withOpacity(0.12),
              ),
              const Spacer(),
              IconButton(
                tooltip: '刷新状态',
                onPressed: () => _refreshStreamStatus(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '前 N 封（0=不限）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    controller: _streamMaxCountController,
                    onChanged: (v) =>
                        _streamMaxCount = int.tryParse(v.trim()) ?? 0,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: (_runningAction || _streamConnecting)
                      ? null
                      : _startStream,
                  child: const Text('开始'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: (_runningAction ||
                          (!_streamRunning && !_streamConnecting))
                      ? null
                      : _stopStream,
                  child: const Text('终止'),
                ),
              ],
            ),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    const Text(
                      '处理日志',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 6),
                    if (_streamLogs.isNotEmpty)
                      Text(
                        '(${_streamLogs.length} 条)',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
                children: [
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    constraints:
                        const BoxConstraints(minHeight: 60, maxHeight: 200),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _streamLogs.isEmpty
                        ? const Text('暂无日志', style: TextStyle(color: Colors.grey))
                        : ListView(
                            children: _streamLogs.reversed
                                .map(
                                  (l) => Text(
                                    l,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEmailDetail(int emailId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: FutureBuilder<Map<String, dynamic>>(
              future: _repo.fetchEmailDetail(emailId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('加载详情失败: ${snapshot.error}'));
                }
                final d = snapshot.data ?? <String, dynamic>{};
                final events =
                    (d['events'] is List) ? (d['events'] as List) : const [];
                final attachments = (d['attachments'] is List)
                    ? (d['attachments'] as List)
                    : const [];
                final images =
                    (d['images'] is List) ? (d['images'] as List) : const [];
                final tags = _extractTags(d['tags']);
                final notionUrl = d['notion_url']?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ListView(
                    children: [
                      Text(
                        d['subject']?.toString() ?? '(无主题)',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text('发件人: ${d['sender'] ?? '-'}'),
                      Text(
                          '收件时间: ${_safeDate(d['received_date']?.toString())}'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          Chip(
                            label: Text(_importanceText(
                                d['importance_level']?.toString() ?? '')),
                            backgroundColor: _importanceColor(
                                    d['importance_level']?.toString() ?? '')
                                .withOpacity(0.14),
                          ),
                          Chip(
                            label:
                                Text(d['is_processed'] == true ? '已处理' : '未处理'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('标签（点击可订阅/退订）',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      if (tags.isEmpty)
                        const Card(
                          child: ListTile(
                            dense: true,
                            title: Text('无标签'),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: tags.map(_tagChip).toList(),
                        ),
                      const SizedBox(height: 8),
                      const Text('AI总结',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                              d['summary']?.toString().isNotEmpty == true
                                  ? d['summary'].toString()
                                  : '暂无总结'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('提取事件 (${events.length})',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      if (events.isEmpty)
                        const Card(child: ListTile(title: Text('无事件')))
                      else
                        ...events.whereType<Map>().map((e) {
                          final m = Map<String, dynamic>.from(e);
                          return Card(
                            child: ListTile(
                              title: Text(m['title']?.toString() ?? '(未命名)'),
                              subtitle: Text(
                                '${m['start_time'] ?? '-'}\n${m['location'] ?? '-'}',
                              ),
                              isThreeLine: true,
                            ),
                          );
                        }),
                      const SizedBox(height: 8),
                      Text('图片 (${images.length})',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      if (images.isEmpty)
                        const Card(child: ListTile(title: Text('无图片')))
                      else
                        ...images.whereType<Map>().map((img) {
                          final imageMap = Map<String, dynamic>.from(img);
                          final imageUrl = _repo.buildAttachmentUrl(imageMap);
                          final name = (imageMap['filename'] ??
                                  imageMap['unique_filename'] ??
                                  '图片')
                              .toString();
                          return Card(
                            child: ListTile(
                              leading: imageUrl.isNotEmpty
                                  ? SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                                Icons.broken_image_outlined),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.image_not_supported_outlined),
                              title: Text(name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  imageUrl.isEmpty ? '无可用链接' : imageUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              onTap: imageUrl.isEmpty
                                  ? null
                                  : () => _showImagePreview(imageUrl, name),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy_outlined),
                                onPressed: imageUrl.isEmpty
                                    ? null
                                    : () => _copyText(imageUrl, '图片链接已复制'),
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 8),
                      Text('附件 (${attachments.length})',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (attachments.isEmpty)
                        const Card(child: ListTile(title: Text('无附件')))
                      else
                        ...attachments.whereType<Map>().map((att) {
                          final attachmentMap = Map<String, dynamic>.from(att);
                          final fileUrl =
                              _repo.buildAttachmentUrl(attachmentMap);
                          final name = (attachmentMap['filename'] ??
                                  attachmentMap['unique_filename'] ??
                                  '附件')
                              .toString();
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.attach_file_outlined),
                              title: Text(name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  fileUrl.isEmpty ? '无可用链接' : fileUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy_outlined),
                                onPressed: fileUrl.isEmpty
                                    ? null
                                    : () => _copyText(fileUrl, '附件链接已复制'),
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: _runningAction
                                ? null
                                : () => _runAction(
                                      () => _repo.reanalyzeEmail(emailId),
                                      successText: '已触发重新分析',
                                    ),
                            child: const Text('重新分析'),
                          ),
                          FilledButton.tonal(
                            onPressed: _runningAction
                                ? null
                                : () => _runAction(
                                      () => _repo.retryAnalysis(emailId),
                                      successText: '已触发失败重试分析',
                                    ),
                            child: const Text('重试分析'),
                          ),
                          FilledButton.tonal(
                            onPressed: _runningAction
                                ? null
                                : () => _runAction(
                                      () => _repo.archiveToNotion(emailId),
                                      successText: '已归档到 Notion',
                                    ),
                            child: Text(notionUrl.isNotEmpty
                                ? '重新归档Notion'
                                : '归档到Notion'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('邮件正文',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            d['content']?.toString().isNotEmpty == true
                                ? d['content'].toString()
                                : '无正文',
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
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
                  child: DropdownButtonFormField<String>(
                    value: _importance,
                    decoration: const InputDecoration(
                      labelText: '重要性',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('全部')),
                      DropdownMenuItem(value: 'important', child: Text('重要')),
                      DropdownMenuItem(value: 'normal', child: Text('普通')),
                      DropdownMenuItem(
                          value: 'unimportant', child: Text('不重要')),
                    ],
                    onChanged: (v) => setState(() => _importance = v ?? ''),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _status,
                    decoration: const InputDecoration(
                      labelText: '状态',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('全部')),
                      DropdownMenuItem(value: 'processed', child: Text('已处理')),
                      DropdownMenuItem(
                          value: 'unprocessed', child: Text('未处理')),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? ''),
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
                      hintText: '搜索主题或发件人',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) {
                      _load(reset: true);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () {
                    _load(reset: true);
                  },
                  child: const Text('筛选'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isStart: true),
                    child: Text('开始：${_dateLabel(_startDate)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isStart: false),
                    child: Text('结束：${_dateLabel(_endDate)}'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _startDate = null;
                      _endDate = null;
                    });
                    _load(reset: true);
                  },
                  child: const Text('清空'),
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('加载失败: $_error'));
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        controller: _scrollController,
        children: [
          _streamPanel(),
          _filters(),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('暂无邮件')),
            )
          else
            ..._items.map((item) {
              final subject = item['subject']?.toString() ?? '(无主题)';
              final sender = item['sender']?.toString() ?? '-';
              final received = _safeDate(item['received_date']?.toString());
              final importance = item['importance_level']?.toString() ?? '';
              final summary = item['summary']?.toString() ?? '';
              final eventsCount =
                  item['events'] is List ? (item['events'] as List).length : 0;
              final tags = _extractTags(item['tags']);
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: ListTile(
                  onTap: () {
                    final id = (item['id'] is num)
                        ? (item['id'] as num).toInt()
                        : null;
                    if (id != null) _showEmailDetail(id);
                  },
                  leading: const Icon(Icons.mail_outline),
                  title: Text(subject,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$sender  |  $received',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        summary.isNotEmpty ? summary : '暂无AI总结',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Chip(
                            label: Text(_importanceText(importance)),
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                _importanceColor(importance).withOpacity(0.14),
                          ),
                          Chip(
                            label: Text(
                                item['is_processed'] == true ? '已处理' : '未处理'),
                            visualDensity: VisualDensity.compact,
                          ),
                          if (eventsCount > 0)
                            Chip(
                              label: Text('$eventsCount 个事件'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: tags.map(_tagChip).toList(),
                        ),
                      ],
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            }),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : Text(
                      _hasMore
                          ? '上拉自动加载更多（已加载 ${_items.length}/$_total）'
                          : '已加载全部 $_total 封邮件',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
