import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  bool _emailNewNotification = true;
  bool _emailAnalysisNotification = true;
  bool _eventNotification = true;
  bool _systemNotification = true;
  bool _notificationPermissionGranted = false;
  bool _checkingNotificationPermission = false;
  bool _loadingFcmToken = false;
  bool _loadingGetuiClientId = false;
  String? _fcmToken;
  String? _getuiClientId;
  bool _enableServerFcmPush = false;
  bool _enableServerGetuiPush = false;
  String _mobilePushPriority = 'fcm_first';
  bool _serverFcmReminder = true;
  bool _serverFcmTask = true;
  bool _serverFcmSystem = true;
  bool _serverFcmEmailNew = true;
  bool _serverFcmEmailAnalysis = true;
  bool _serverFcmEvent = true;
  bool _serverFcmWeekend = true;
  bool _serverFcmQuietHours = false;
  final _serverFcmStartController = TextEditingController(text: '08:00');
  final _serverFcmEndController = TextEditingController(text: '22:00');
  String _configRevision = '';
  String _tagRevision = '';
  bool _notificationDirty = false;
  bool _tagDirty = false;
  bool _keywordDirty = false;
  bool _dedupDirty = false;
  bool _emailDirty = false;
  bool _aiDirty = false;
  bool _savingNotificationPrefs = false;
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
  final _emailAddressController = TextEditingController();
  final _emailPasswordController = TextEditingController();
  final _emailImapServerController = TextEditingController();
  final _emailImapPortController = TextEditingController(text: '993');
  final _emailFetchIntervalController = TextEditingController(text: '1800');
  final _emailMaxPerFetchController = TextEditingController(text: '50');
  bool _emailUseSsl = true;
  bool _emailAutoFetch = true;
  final _aiProviderController = TextEditingController(text: 'openai');
  final _aiApiKeyController = TextEditingController();
  final _aiModelController = TextEditingController(text: 'gpt-3.5-turbo');
  final _aiBaseUrlController = TextEditingController();
  final _aiMaxTokensController = TextEditingController(text: '2000');
  final _aiTemperatureController = TextEditingController(text: '0.7');
  bool _aiEnableAnalysis = true;
  bool _aiEnableEventExtraction = true;
  bool _aiEnableSummary = true;

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
      _emailNewNotification = pref.getBool('email_new_notification') ?? true;
      _emailAnalysisNotification =
          pref.getBool('email_analysis_notification') ?? true;
      _eventNotification = pref.getBool('event_notification') ?? true;
      _systemNotification = pref.getBool('system_notification') ?? true;
    });
    await _refreshNotificationPermission(silent: true);
    await _refreshFcmToken(silent: true);
    await _refreshGetuiClientId(silent: true);
    await _loadAdvancedSettings();
    if (mounted) setState(() => _notificationDirty = false);
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
      final granted =
          await NotificationService.instance.requestPermissionIfNeeded();
      if (!mounted) return;
      setState(() => _notificationPermissionGranted = granted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(granted ? '通知权限已开启' : '通知权限未开启，请到系统设置中允许')),
      );
    } finally {
      if (mounted) setState(() => _checkingNotificationPermission = false);
    }
  }

  Future<void> _refreshFcmToken({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loadingFcmToken = true);
    try {
      final token =
          await NotificationService.instance.getFcmToken(refresh: true);
      if ((token ?? '').isNotEmpty) {
        final platform = switch (defaultTargetPlatform) {
          TargetPlatform.iOS => 'ios',
          TargetPlatform.android => 'android',
          _ => 'unknown',
        };
        await _repo.uploadFcmToken(token: token!, platform: platform);
      }
      if (!mounted) return;
      setState(() => _fcmToken = token);
    } finally {
      if (!silent && mounted) setState(() => _loadingFcmToken = false);
    }
  }

  Future<void> _refreshGetuiClientId({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loadingGetuiClientId = true);
    try {
      final clientId =
          await NotificationService.instance.getGetuiClientId(refresh: true);
      if ((clientId ?? '').isNotEmpty) {
        final platform = switch (defaultTargetPlatform) {
          TargetPlatform.iOS => 'ios',
          TargetPlatform.android => 'android',
          _ => 'unknown',
        };
        await _repo.uploadGetuiClientId(clientId: clientId!, platform: platform);
      }
      if (!mounted) return;
      setState(() => _getuiClientId = clientId);
    } finally {
      if (!silent && mounted) setState(() => _loadingGetuiClientId = false);
    }
  }

  Future<void> _sendFcmTestPush() async {
    try {
      final channel = _mobilePushPriority == 'getui_first' ? 'getui' : 'fcm';
      await _repo.testPush(
        channel: channel,
        title: '测试主动推送',
        body: '如果你看到这条通知，表示服务端主动推送链路可用',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('测试推送请求已发送（$channel）')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('测试推送失败: $e')),
      );
    }
  }

  Map<String, dynamic> _notificationPrefsPayload() {
    return {
      'task_notification': _taskNotification,
      'reminder_notification': _reminderNotification,
      'email_new_notification': _emailNewNotification,
      'email_analysis_notification': _emailAnalysisNotification,
      'event_notification': _eventNotification,
      'system_notification': _systemNotification,
      'enable_fcm_notifications': _enableServerFcmPush,
      'enable_getui_notifications': _enableServerGetuiPush,
      'mobile_push_priority': _mobilePushPriority,
      'fcm_push_reminder': _serverFcmReminder,
      'fcm_push_task': _serverFcmTask,
      'fcm_push_system': _serverFcmSystem,
      'fcm_push_email_new': _serverFcmEmailNew,
      'fcm_push_email_analysis': _serverFcmEmailAnalysis,
      'fcm_push_event': _serverFcmEvent,
      'fcm_push_on_weekend': _serverFcmWeekend,
      'fcm_push_quiet_hours_enabled': _serverFcmQuietHours,
      'fcm_push_start_time': _serverFcmStartController.text.trim(),
      'fcm_push_end_time': _serverFcmEndController.text.trim(),
    };
  }

  Future<void> _saveNotificationPrefs({bool force = false}) async {
    if (_savingNotificationPrefs) return;
    setState(() => _savingNotificationPrefs = true);
    try {
      final pref = await SharedPreferences.getInstance();
      await pref.setBool('task_notification', _taskNotification);
      await pref.setBool('reminder_notification', _reminderNotification);
      await pref.setBool('email_new_notification', _emailNewNotification);
      await pref.setBool(
          'email_analysis_notification', _emailAnalysisNotification);
      await pref.setBool('event_notification', _eventNotification);
      await pref.setBool('system_notification', _systemNotification);
      final saveResult = await _repo.saveNotificationPrefs(
        notificationPrefs: _notificationPrefsPayload(),
        baseRevision: _configRevision,
        force: force,
      );
      if (!mounted) return;
      if (saveResult['conflict'] == true) {
        final shouldForce = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('检测到多端配置冲突'),
            content: Text(
              '${saveResult['error'] ?? '配置已被其他端修改'}\n'
              '是否覆盖为当前手机上的设置？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消并刷新'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('强制覆盖'),
              ),
            ],
          ),
        );
        if (shouldForce == true) {
          setState(() => _savingNotificationPrefs = false);
          await _saveNotificationPrefs(force: true);
        } else {
          await _load();
        }
        return;
      }
      if ((saveResult['revision'] ?? '').toString().isNotEmpty) {
        setState(() => _configRevision = saveResult['revision'].toString());
      }
      setState(() => _notificationDirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通知设置已保存')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingNotificationPrefs = false);
    }
  }

  Future<void> _loadAdvancedSettings() async {
    setState(() => _loadingAdvanced = true);
    try {
      final cfg = await _repo.fetchConfig();
      final meta = (cfg['_meta'] is Map)
          ? Map<String, dynamic>.from(cfg['_meta'] as Map)
          : const {};
      _configRevision = (meta['revision'] ?? '').toString();
      final kw = (cfg['keywords'] is Map)
          ? Map<String, dynamic>.from(cfg['keywords'] as Map)
          : {};
      _keywords = {
        'important': _stringList(kw['important']),
        'normal': _stringList(kw['normal']),
        'unimportant': _stringList(kw['unimportant']),
      };

      final dedup = (cfg['dedup_beta'] is Map)
          ? Map<String, dynamic>.from(cfg['dedup_beta'] as Map)
          : {};
      final weights = (dedup['weights'] is Map)
          ? Map<String, dynamic>.from(dedup['weights'] as Map)
          : {};
      _dedupEnabled = dedup['enabled'] != false;
      _dedupWindowController.text =
          (dedup['time_window_hours'] ?? 72).toString();
      _dedupThresholdController.text =
          (dedup['auto_merge_threshold'] ?? 0.85).toString();
      _dedupWeights['title']!.text = (weights['title'] ?? 0.35).toString();
      _dedupWeights['time']!.text = (weights['time'] ?? 0.30).toString();
      _dedupWeights['tags']!.text = (weights['tags'] ?? 0.20).toString();
      _dedupWeights['sender']!.text = (weights['sender'] ?? 0.10).toString();
      _dedupWeights['location']!.text =
          (weights['location'] ?? 0.05).toString();

      final notification = (cfg['notification'] is Map)
          ? Map<String, dynamic>.from(cfg['notification'] as Map)
          : {};
      final mobilePushPrefs = (notification['mobile_push_prefs'] is Map)
          ? Map<String, dynamic>.from(notification['mobile_push_prefs'] as Map)
          : const <String, dynamic>{};
      _taskNotification = mobilePushPrefs['task_notification'] is bool
          ? mobilePushPrefs['task_notification'] == true
          : _taskNotification;
      _reminderNotification = mobilePushPrefs['reminder_notification'] is bool
          ? mobilePushPrefs['reminder_notification'] == true
          : _reminderNotification;
      _emailNewNotification = mobilePushPrefs['email_new_notification'] is bool
          ? mobilePushPrefs['email_new_notification'] == true
          : _emailNewNotification;
      _emailAnalysisNotification =
          mobilePushPrefs['email_analysis_notification'] is bool
              ? mobilePushPrefs['email_analysis_notification'] == true
              : _emailAnalysisNotification;
      _eventNotification = mobilePushPrefs['event_notification'] is bool
          ? mobilePushPrefs['event_notification'] == true
          : _eventNotification;
      _systemNotification = mobilePushPrefs['system_notification'] is bool
          ? mobilePushPrefs['system_notification'] == true
          : _systemNotification;
      _enableServerFcmPush = notification['enable_fcm_notifications'] == true;
      _enableServerGetuiPush = notification['enable_getui_notifications'] == true;
      final priority = (notification['mobile_push_priority'] ?? 'fcm_first')
          .toString()
          .trim()
          .toLowerCase();
      _mobilePushPriority =
          (priority == 'getui_first') ? 'getui_first' : 'fcm_first';
      _serverFcmReminder = notification['fcm_push_reminder'] != false;
      _serverFcmTask = notification['fcm_push_task'] != false;
      _serverFcmSystem = notification['fcm_push_system'] != false;
      _serverFcmEmailNew = notification['fcm_push_email_new'] != false;
      _serverFcmEmailAnalysis =
          notification['fcm_push_email_analysis'] != false;
      _serverFcmEvent = notification['fcm_push_event'] != false;
      _serverFcmWeekend = notification['fcm_push_on_weekend'] != false;
      _serverFcmQuietHours =
          notification['fcm_push_quiet_hours_enabled'] == true;
      _serverFcmStartController.text =
          (notification['fcm_push_start_time'] ?? '08:00').toString();
      _serverFcmEndController.text =
          (notification['fcm_push_end_time'] ?? '22:00').toString();
      _getuiClientId =
          (notification['mobile_getui_client_id'] ?? '').toString();

      final email = (cfg['email'] is Map)
          ? Map<String, dynamic>.from(cfg['email'] as Map)
          : const <String, dynamic>{};
      _emailAddressController.text =
          (email['username'] ?? email['email'] ?? '').toString();
      _emailPasswordController.text = (email['password'] ?? '').toString();
      _emailImapServerController.text = (email['imap_server'] ?? '').toString();
      _emailImapPortController.text = (email['imap_port'] ?? 993).toString();
      _emailFetchIntervalController.text =
          (email['fetch_interval'] ?? 1800).toString();
      _emailMaxPerFetchController.text =
          (email['max_emails_per_fetch'] ?? 50).toString();
      _emailUseSsl = email['use_ssl'] != false;
      _emailAutoFetch = email['auto_fetch'] != false;

      final ai = (cfg['ai'] is Map)
          ? Map<String, dynamic>.from(cfg['ai'] as Map)
          : const <String, dynamic>{};
      _aiProviderController.text = (ai['provider'] ?? 'openai').toString();
      _aiApiKeyController.text = (ai['api_key'] ?? '').toString();
      _aiModelController.text = (ai['model'] ?? 'gpt-3.5-turbo').toString();
      _aiBaseUrlController.text = (ai['base_url'] ?? '').toString();
      _aiMaxTokensController.text = (ai['max_tokens'] ?? 2000).toString();
      _aiTemperatureController.text = (ai['temperature'] ?? 0.7).toString();
      _aiEnableAnalysis = ai['enable_analysis'] != false;
      _aiEnableEventExtraction = ai['enable_event_extraction'] != false;
      _aiEnableSummary = ai['enable_summary'] != false;

      final tagSettings = await _repo.fetchTagSettings();
      final tagMeta = (tagSettings['_meta'] is Map)
          ? Map<String, dynamic>.from(tagSettings['_meta'] as Map)
          : const <String, dynamic>{};
      _tagRevision = (tagMeta['revision'] ?? '').toString();
      _subscriptions = _normalizeSubscriptions(tagSettings['subscriptions']);
      final retention = (tagSettings['history_retention_days'] is num)
          ? (tagSettings['history_retention_days'] as num).toInt()
          : 30;
      _retentionController.text = retention.toString();

      await _loadHistoryCandidates();
      await _loadNotionData();
      _tagDirty = false;
      _keywordDirty = false;
      _dedupDirty = false;
      _emailDirty = false;
      _aiDirty = false;
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
    final candidates = (resp['candidates'] is Map)
        ? Map<String, dynamic>.from(resp['candidates'] as Map)
        : {};
    _historyCandidates = {
      2: _normalizeHistoryList(candidates['other_level2']),
      3: _normalizeHistoryList(candidates['level3']),
      4: _normalizeHistoryList(candidates['level4']),
    };
    if (resp['history_retention_days'] is num) {
      _retentionController.text =
          (resp['history_retention_days'] as num).toInt().toString();
    }
  }

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
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
        out.add(
            {'value': item.toString(), 'manual': false, 'subscribed': false});
      }
    }
    return out
        .where((e) => (e['value'] ?? '').toString().trim().isNotEmpty)
        .toList();
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successText)));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successText)));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Notion搜索失败: $e')));
    } finally {
      if (mounted) setState(() => _loadingNotion = false);
    }
  }

  String _pickField(Map<String, dynamic> item, List<String> keys,
      {String fallback = '-'}) {
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(successText)));
  }

  Future<void> _saveConfigSectionWithConflict({
    required String section,
    required Map<String, dynamic> payload,
    required String successText,
    required String conflictTitle,
    required VoidCallback clearDirty,
    bool force = false,
  }) async {
    if (_runningAction) return;
    setState(() => _runningAction = true);
    try {
      final result = await _repo.saveConfigSection(
        section: section,
        payload: payload,
        baseRevision: _configRevision,
        force: force,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        _configRevision = (result['revision'] ?? _configRevision).toString();
        setState(clearDirty);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successText)));
        return;
      }
      if (result['conflict'] == true) {
        final shouldForce = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(conflictTitle),
            content: Text((result['error'] ?? '检测到配置冲突').toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消并刷新'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('强制覆盖'),
              ),
            ],
          ),
        );
        if (shouldForce == true) {
          setState(() => _runningAction = false);
          await _saveConfigSectionWithConflict(
            section: section,
            payload: payload,
            successText: successText,
            conflictTitle: conflictTitle,
            clearDirty: clearDirty,
            force: true,
          );
          return;
        }
        await _loadAdvancedSettings();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  Future<void> _saveKeywords() async {
    await _saveConfigSectionWithConflict(
      section: 'keywords',
      payload: _keywords,
      successText: '关键词已保存',
      conflictTitle: '检测到多端关键词配置冲突',
      clearDirty: () => _keywordDirty = false,
    );
  }

  Future<void> _saveDedupBeta() async {
    final payload = {
      'enabled': _dedupEnabled,
      'time_window_hours':
          int.tryParse(_dedupWindowController.text.trim()) ?? 72,
      'auto_merge_threshold':
          double.tryParse(_dedupThresholdController.text.trim()) ?? 0.85,
      'weights': {
        'title': double.tryParse(_dedupWeights['title']!.text.trim()) ?? 0.35,
        'time': double.tryParse(_dedupWeights['time']!.text.trim()) ?? 0.30,
        'tags': double.tryParse(_dedupWeights['tags']!.text.trim()) ?? 0.20,
        'sender': double.tryParse(_dedupWeights['sender']!.text.trim()) ?? 0.10,
        'location':
            double.tryParse(_dedupWeights['location']!.text.trim()) ?? 0.05,
      },
    };
    await _saveConfigSectionWithConflict(
      section: 'dedup_beta',
      payload: payload,
      successText: '去重 Beta 设置已保存',
      conflictTitle: '检测到多端去重配置冲突',
      clearDirty: () => _dedupDirty = false,
    );
  }

  Future<void> _saveEmailSettings() async {
    final payload = <String, dynamic>{
      'username': _emailAddressController.text.trim(),
      'password': _emailPasswordController.text.trim(),
      'imap_server': _emailImapServerController.text.trim(),
      'imap_port': int.tryParse(_emailImapPortController.text.trim()) ?? 993,
      'use_ssl': _emailUseSsl,
      'auto_fetch': _emailAutoFetch,
      'fetch_interval':
          int.tryParse(_emailFetchIntervalController.text.trim()) ?? 1800,
      'max_emails_per_fetch':
          int.tryParse(_emailMaxPerFetchController.text.trim()) ?? 50,
    };
    await _saveConfigSectionWithConflict(
      section: 'email',
      payload: payload,
      successText: '邮箱设置已保存',
      conflictTitle: '检测到多端邮箱配置冲突',
      clearDirty: () => _emailDirty = false,
    );
  }

  Future<void> _saveAiSettings() async {
    final payload = <String, dynamic>{
      'provider': _aiProviderController.text.trim(),
      'api_key': _aiApiKeyController.text.trim(),
      'model': _aiModelController.text.trim(),
      'base_url': _aiBaseUrlController.text.trim(),
      'max_tokens': int.tryParse(_aiMaxTokensController.text.trim()) ?? 2000,
      'temperature':
          double.tryParse(_aiTemperatureController.text.trim()) ?? 0.7,
      'enable_analysis': _aiEnableAnalysis,
      'enable_event_extraction': _aiEnableEventExtraction,
      'enable_summary': _aiEnableSummary,
    };
    await _saveConfigSectionWithConflict(
      section: 'ai',
      payload: payload,
      successText: 'AI 设置已保存',
      conflictTitle: '检测到多端 AI 配置冲突',
      clearDirty: () => _aiDirty = false,
    );
  }

  Future<void> _saveTagSettings({bool force = false}) async {
    if (_runningAction) return;
    final retention = int.tryParse(_retentionController.text.trim()) ?? 30;
    setState(() => _runningAction = true);
    try {
      await _repo.saveTagSettings(
        subscriptions: _subscriptions,
        historyRetentionDays: retention,
        baseRevision: _tagRevision,
        force: force,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标签配置已保存')),
      );
      await _loadAdvancedSettings();
    } catch (e) {
      final msg = e.toString();
      if (!mounted) return;
      if (msg.contains('CONFLICT:')) {
        final shouldForce = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('检测到多端标签配置冲突'),
            content: Text(msg.replaceFirst('Exception: CONFLICT:', '')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消并刷新'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('强制覆盖'),
              ),
            ],
          ),
        );
        if (shouldForce == true) {
          setState(() => _runningAction = false);
          await _saveTagSettings(force: true);
          return;
        }
        await _loadAdvancedSettings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  void _addKeyword(String type) {
    final input = _keywordInput[type]!;
    final value = input.text.trim();
    if (value.isEmpty) return;
    final list = _keywords[type] ?? [];
    if (!list.contains(value)) {
      setState(() {
        list.add(value);
        _keywordDirty = true;
      });
    }
    input.clear();
  }

  void _removeKeyword(String type, String value) {
    setState(() {
      _keywords[type]?.remove(value);
      _keywordDirty = true;
    });
  }

  List<Map<String, dynamic>> _subsByLevel(int level) =>
      _subscriptions.where((s) => (s['level'] as int?) == level).toList();

  void _setCandidateSubscribed(int level, String value, bool subscribed) {
    final items = _historyCandidates[level] ?? const <Map<String, dynamic>>[];
    for (final item in items) {
      if ((item['value'] ?? '').toString().trim() == value.trim()) {
        item['subscribed'] = subscribed;
      }
    }
  }

  Future<void> _addSubscription(int level) async {
    final ctrl = _subInputs[level]!;
    final value = ctrl.text.trim();
    if (value.isEmpty) return;
    final exists = _subscriptions.any(
      (s) =>
          (s['level'] as int?) == level &&
          (s['value'] ?? '').toString().trim() == value,
    );
    if (exists) {
      ctrl.clear();
      return;
    }
    setState(() {
      _subscriptions.add({'level': level, 'value': value});
      _setCandidateSubscribed(level, value, true);
      _tagDirty = true;
    });
    ctrl.clear();
  }

  Future<void> _removeSubscription(int level, String value) async {
    setState(() {
      _subscriptions.removeWhere(
        (s) =>
            (s['level'] as int?) == level &&
            (s['value'] ?? '').toString().trim() == value.trim(),
      );
      _setCandidateSubscribed(level, value, false);
      _tagDirty = true;
    });
  }

  Future<void> _toggleCandidateSubscription(
      int level, Map<String, dynamic> item) async {
    final value = (item['value'] ?? '').toString().trim();
    if (value.isEmpty) return;
    final subscribed = item['subscribed'] == true;
    if (subscribed) {
      await _removeSubscription(level, value);
      return;
    }
    final exists = _subscriptions.any(
      (s) =>
          (s['level'] as int?) == level &&
          (s['value'] ?? '').toString().trim() == value,
    );
    if (exists) return;
    setState(() {
      _subscriptions.add({'level': level, 'value': value});
      _setCandidateSubscribed(level, value, true);
      _tagDirty = true;
    });
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

  Widget _keywordSection({bool showInlineSave = true}) {
    Widget block(String type, String label, Color color) {
      final list = _keywords[type] ?? [];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color)),
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
          child: Text('关键词管理',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              block('important', '重要关键词', Colors.red),
              block('normal', '普通关键词', Colors.blue),
              block('unimportant', '不重要关键词', Colors.grey),
              const SizedBox(height: 4),
              if (showInlineSave)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: (_runningAction || !_keywordDirty)
                        ? null
                        : _saveKeywords,
                    child: const Text('保存关键词'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dedupSection({bool showInlineSave = true}) {
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
          onChanged: (_) => setState(() => _dedupDirty = true),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('去重 Beta 设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                    onChanged: (v) => setState(() {
                      _dedupEnabled = v;
                      _dedupDirty = true;
                    }),
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
                          onChanged: (_) => setState(() => _dedupDirty = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _dedupThresholdController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: '自动合并阈值',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() => _dedupDirty = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    weightInput('title', '标题权重'),
                    const SizedBox(width: 8),
                    weightInput('time', '时间权重')
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    weightInput('tags', '标签权重'),
                    const SizedBox(width: 8),
                    weightInput('sender', '发件人权重')
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    weightInput('location', '地点权重'),
                    const Spacer()
                  ]),
                  const SizedBox(height: 10),
                  if (showInlineSave)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: (_runningAction || !_dedupDirty)
                            ? null
                            : _saveDedupBeta,
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

  Widget _emailSection({bool showInlineSave = true}) {
    Widget textField(
      TextEditingController controller,
      String label, {
      TextInputType? keyboardType,
      bool obscureText = false,
    }) {
      return TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() => _emailDirty = true),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('邮箱设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  textField(_emailAddressController, '邮箱账号'),
                  const SizedBox(height: 8),
                  textField(_emailPasswordController, '邮箱密码/授权码',
                      obscureText: true),
                  const SizedBox(height: 8),
                  textField(_emailImapServerController, 'IMAP 服务器'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: textField(
                          _emailImapPortController,
                          'IMAP 端口',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: textField(
                          _emailFetchIntervalController,
                          '抓取间隔(秒)',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  textField(
                    _emailMaxPerFetchController,
                    '每次抓取数量',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用 SSL'),
                    value: _emailUseSsl,
                    onChanged: (v) => setState(() {
                      _emailUseSsl = v;
                      _emailDirty = true;
                    }),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自动抓取邮件'),
                    value: _emailAutoFetch,
                    onChanged: (v) => setState(() {
                      _emailAutoFetch = v;
                      _emailDirty = true;
                    }),
                  ),
                  if (showInlineSave)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: (_runningAction || !_emailDirty)
                            ? null
                            : _saveEmailSettings,
                        child: const Text('保存邮箱设置'),
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

  Widget _aiSection({bool showInlineSave = true}) {
    Widget textField(
      TextEditingController controller,
      String label, {
      TextInputType? keyboardType,
      bool obscureText = false,
    }) {
      return TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() => _aiDirty = true),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('AI 设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  textField(_aiProviderController, '提供商'),
                  const SizedBox(height: 8),
                  textField(_aiApiKeyController, 'API Key', obscureText: true),
                  const SizedBox(height: 8),
                  textField(_aiModelController, '模型'),
                  const SizedBox(height: 8),
                  textField(_aiBaseUrlController, 'Base URL (可选)'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: textField(
                          _aiMaxTokensController,
                          'Max Tokens',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: textField(
                          _aiTemperatureController,
                          'Temperature',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用邮件分析'),
                    value: _aiEnableAnalysis,
                    onChanged: (v) => setState(() {
                      _aiEnableAnalysis = v;
                      _aiDirty = true;
                    }),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用事件抽取'),
                    value: _aiEnableEventExtraction,
                    onChanged: (v) => setState(() {
                      _aiEnableEventExtraction = v;
                      _aiDirty = true;
                    }),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用摘要生成'),
                    value: _aiEnableSummary,
                    onChanged: (v) => setState(() {
                      _aiEnableSummary = v;
                      _aiDirty = true;
                    }),
                  ),
                  if (showInlineSave)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: (_runningAction || !_aiDirty)
                            ? null
                            : _saveAiSettings,
                        child: const Text('保存 AI 设置'),
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
                        onDeleted: () =>
                            _removeSubscription(level, s['value'].toString()),
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
                  onPressed:
                      _runningAction ? null : () => _addSubscription(level),
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
                      subscribed
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_none_outlined,
                      size: 16,
                      color: subscribed ? Colors.red : Colors.blueGrey,
                    ),
                    onPressed: _runningAction
                        ? null
                        : () => _toggleCandidateSubscription(level, item),
                    onDeleted: _runningAction
                        ? null
                        : () => _deleteHistory(level, item),
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
                  onPressed:
                      _runningAction ? null : () => _addManualHistory(level),
                  child: const Text('添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagSection({bool showInlineSave = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('标签订阅与历史',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                          onChanged: (_) => setState(() => _tagDirty = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (showInlineSave)
                        FilledButton.tonal(
                          onPressed: (_runningAction || !_tagDirty)
                              ? null
                              : _saveTagSettings,
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
      final title = _pickField(item, ['title', 'subject', 'name', 'page_title'],
          fallback: '(无标题)');
      final url =
          _pickField(item, ['url', 'page_url', 'notion_url'], fallback: '-');
      final date = _pickField(item,
          ['archived_at', 'archive_date', 'created_time', 'last_edited_time'],
          fallback: '-');
      return Card(
        child: ListTile(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              Text('$date\n$url', maxLines: 2, overflow: TextOverflow.ellipsis),
          isThreeLine: true,
          trailing: IconButton(
            icon: const Icon(Icons.copy_outlined),
            onPressed: url == '-' ? null : () => _copyText(url, 'Notion链接已复制'),
          ),
        ),
      );
    }

    final showing = _notionSearchController.text.trim().isNotEmpty
        ? _notionSearchResults
        : _notionArchived;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Notion归档',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
    _serverFcmStartController.dispose();
    _serverFcmEndController.dispose();
    _emailAddressController.dispose();
    _emailPasswordController.dispose();
    _emailImapServerController.dispose();
    _emailImapPortController.dispose();
    _emailFetchIntervalController.dispose();
    _emailMaxPerFetchController.dispose();
    _aiProviderController.dispose();
    _aiApiKeyController.dispose();
    _aiModelController.dispose();
    _aiBaseUrlController.dispose();
    _aiMaxTokensController.dispose();
    _aiTemperatureController.dispose();
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

    Future<void> openEditableSection({
      required String title,
      required Widget body,
      required bool dirty,
      required Future<void> Function() onSave,
      bool saving = false,
    }) async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(title),
              actions: [
                TextButton.icon(
                  onPressed: (!saving && dirty) ? onSave : null,
                  icon: saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ],
            ),
            body: body,
          ),
        ),
      );
    }

    Future<void> openNotificationSection() async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StatefulBuilder(
            builder: (ctx, setInnerState) {
              void onChanged(void Function() updater) {
                setState(updater);
                setInnerState(() {});
                if (!_notificationDirty) {
                  setState(() => _notificationDirty = true);
                }
              }

              return Scaffold(
                appBar: AppBar(
                  title: const Text('通知设置'),
                  actions: [
                    TextButton.icon(
                      onPressed:
                          (_notificationDirty && !_savingNotificationPrefs)
                              ? _saveNotificationPrefs
                              : null,
                      icon: _savingNotificationPrefs
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('保存'),
                    ),
                  ],
                ),
                body: ListView(
                  children: [
                    SwitchListTile(
                      title: const Text('任务通知'),
                      subtitle: const Text('任务失败/完成时推送通知'),
                      value: _taskNotification,
                      onChanged: (v) => onChanged(() => _taskNotification = v),
                    ),
                    SwitchListTile(
                      title: const Text('日程提醒通知'),
                      subtitle: const Text('事件提醒时弹出系统通知'),
                      value: _reminderNotification,
                      onChanged: (v) =>
                          onChanged(() => _reminderNotification = v),
                    ),
                    SwitchListTile(
                      title: const Text('新邮件通知'),
                      subtitle: const Text('收到新邮件时推送通知'),
                      value: _emailNewNotification,
                      onChanged: (v) =>
                          onChanged(() => _emailNewNotification = v),
                    ),
                    SwitchListTile(
                      title: const Text('邮件分析完成通知'),
                      subtitle: const Text('AI 分析完成时推送通知'),
                      value: _emailAnalysisNotification,
                      onChanged: (v) =>
                          onChanged(() => _emailAnalysisNotification = v),
                    ),
                    SwitchListTile(
                      title: const Text('日程变更通知'),
                      subtitle: const Text('日程新增/更新/取消时推送通知'),
                      value: _eventNotification,
                      onChanged: (v) => onChanged(() => _eventNotification = v),
                    ),
                    SwitchListTile(
                      title: const Text('系统公告通知'),
                      subtitle: const Text('系统消息与公告推送'),
                      value: _systemNotification,
                      onChanged: (v) =>
                          onChanged(() => _systemNotification = v),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('开启服务端主动推送（FCM）'),
                      subtitle: const Text('由后端主动下发通知到手机'),
                      value: _enableServerFcmPush,
                      onChanged: (v) =>
                          onChanged(() => _enableServerFcmPush = v),
                    ),
                    SwitchListTile(
                      title: const Text('开启服务端主动推送（Getui）'),
                      subtitle: const Text('国内网络可优先走 Getui 通道'),
                      value: _enableServerGetuiPush,
                      onChanged: (v) =>
                          onChanged(() => _enableServerGetuiPush = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'fcm_first',
                            label: Text('FCM优先'),
                          ),
                          ButtonSegment<String>(
                            value: 'getui_first',
                            label: Text('Getui优先'),
                          ),
                        ],
                        selected: {_mobilePushPriority},
                        onSelectionChanged: (set) {
                          if (set.isEmpty) return;
                          onChanged(() => _mobilePushPriority = set.first);
                        },
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('主动推送：日程提醒'),
                      value: _serverFcmReminder,
                      onChanged: (v) => onChanged(() => _serverFcmReminder = v),
                    ),
                    SwitchListTile(
                      title: const Text('主动推送：任务告警'),
                      value: _serverFcmTask,
                      onChanged: (v) => onChanged(() => _serverFcmTask = v),
                    ),
                    SwitchListTile(
                      title: const Text('主动推送：系统消息'),
                      value: _serverFcmSystem,
                      onChanged: (v) => onChanged(() => _serverFcmSystem = v),
                    ),
                    SwitchListTile(
                      title: const Text('主动推送：新邮件同步'),
                      value: _serverFcmEmailNew,
                      onChanged: (v) => onChanged(() => _serverFcmEmailNew = v),
                    ),
                    SwitchListTile(
                      title: const Text('主动推送：邮件分析完成'),
                      value: _serverFcmEmailAnalysis,
                      onChanged: (v) =>
                          onChanged(() => _serverFcmEmailAnalysis = v),
                    ),
                    SwitchListTile(
                      title: const Text('主动推送：日程变更'),
                      value: _serverFcmEvent,
                      onChanged: (v) => onChanged(() => _serverFcmEvent = v),
                    ),
                    SwitchListTile(
                      title: const Text('周末允许主动推送'),
                      value: _serverFcmWeekend,
                      onChanged: (v) => onChanged(() => _serverFcmWeekend = v),
                    ),
                    SwitchListTile(
                      title: const Text('启用推送时段限制'),
                      subtitle: const Text('仅在指定时间范围内发送主动推送'),
                      value: _serverFcmQuietHours,
                      onChanged: (v) =>
                          onChanged(() => _serverFcmQuietHours = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _serverFcmStartController,
                              decoration: const InputDecoration(
                                labelText: '开始时间',
                                hintText: '08:00',
                                isDense: true,
                              ),
                              onChanged: (_) => onChanged(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _serverFcmEndController,
                              decoration: const InputDecoration(
                                labelText: '结束时间',
                                hintText: '22:00',
                                isDense: true,
                              ),
                              onChanged: (_) => onChanged(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: FilledButton.tonal(
                        onPressed: (_savingNotificationPrefs ||
                                ((_mobilePushPriority == 'getui_first'
                                        ? (_getuiClientId ?? '').isEmpty
                                        : (_fcmToken ?? '').isEmpty)))
                            ? null
                            : _sendFcmTestPush,
                        child: const Text('发送一次推送测试'),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        _notificationPermissionGranted
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: _notificationPermissionGranted
                            ? Colors.green
                            : Colors.orange,
                      ),
                      title: const Text('系统通知权限'),
                      subtitle: Text(_notificationPermissionGranted
                          ? '已允许'
                          : '未允许（国产安卓常需手动开启）'),
                    ),
                    ListTile(
                      leading: Icon(
                        (_fcmToken ?? '').isNotEmpty
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined,
                        color: (_fcmToken ?? '').isNotEmpty
                            ? Colors.green
                            : Colors.orange,
                      ),
                      title: const Text('FCM 推送通道'),
                      subtitle: Text(
                        (_fcmToken ?? '').isNotEmpty
                            ? 'FCM Token 已就绪（可用于远程推送）'
                            : (NotificationService.instance.firebaseReady
                                ? 'FCM 已初始化，但 Token 暂不可用'
                                : '未就绪（请确认已放置 google-services.json）'),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        (_getuiClientId ?? '').isNotEmpty
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined,
                        color: (_getuiClientId ?? '').isNotEmpty
                            ? Colors.green
                            : Colors.orange,
                      ),
                      title: const Text('Getui 推送通道'),
                      subtitle: Text(
                        (_getuiClientId ?? '').isNotEmpty
                            ? 'Getui ClientID 已就绪（可用于远程推送）'
                            : (NotificationService.instance.getuiReady
                                ? 'Getui 已初始化，但 ClientID 暂不可用'
                                : '未就绪（请确认 Android Getui 配置已完成）'),
                      ),
                    ),
                    if ((_fcmToken ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SelectableText(
                          _fcmToken!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if ((_getuiClientId ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SelectableText(
                          _getuiClientId!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _checkingNotificationPermission
                                  ? null
                                  : _requestNotificationPermission,
                              child: const Text('申请通知权限'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _checkingNotificationPermission
                                  ? null
                                  : () async {
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      final ok = await NotificationService
                                          .instance
                                          .openSystemNotificationSettings();
                                      if (!mounted) return;
                                      if (!ok) {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                              content: Text('无法打开系统设置')),
                                        );
                                        return;
                                      }
                                      await _refreshNotificationPermission(
                                          silent: true);
                                    },
                              child: const Text('打开系统设置'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  _loadingFcmToken ? null : _refreshFcmToken,
                              child: _loadingFcmToken
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('刷新 FCM Token'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: (_fcmToken ?? '').isEmpty
                                  ? null
                                  : () =>
                                      _copyText(_fcmToken!, 'FCM Token 已复制'),
                              child: const Text('复制 Token'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _loadingGetuiClientId
                                  ? null
                                  : _refreshGetuiClientId,
                              child: _loadingGetuiClientId
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('刷新 Getui CID'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: (_getuiClientId ?? '').isEmpty
                                  ? null
                                  : () => _copyText(
                                      _getuiClientId!, 'Getui ClientID 已复制'),
                              child: const Text('复制 Getui CID'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text(
                        '国产系统建议：到系统设置里同时开启 通知权限、自启动、后台运行白名单，避免被系统拦截。',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    Future<void> openTagSection() async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: const Text('标签订阅与历史'),
              actions: [
                TextButton.icon(
                  onPressed:
                      (_runningAction || !_tagDirty) ? null : _saveTagSettings,
                  icon: _runningAction
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ],
            ),
            body: ListView(children: [_tagSection(showInlineSave: false)]),
          ),
        ),
      );
    }

    Future<void> openKeywordSection() async {
      await openEditableSection(
        title: '关键词管理',
        body: ListView(children: [_keywordSection(showInlineSave: false)]),
        dirty: _keywordDirty,
        onSave: _saveKeywords,
        saving: _runningAction,
      );
    }

    Future<void> openDedupSection() async {
      await openEditableSection(
        title: '去重 Beta 设置',
        body: ListView(children: [_dedupSection(showInlineSave: false)]),
        dirty: _dedupDirty,
        onSave: _saveDedupBeta,
        saving: _runningAction,
      );
    }

    Future<void> openEmailSection() async {
      await openEditableSection(
        title: '邮箱设置',
        body: ListView(children: [_emailSection(showInlineSave: false)]),
        dirty: _emailDirty,
        onSave: _saveEmailSettings,
        saving: _runningAction,
      );
    }

    Future<void> openAiSection() async {
      await openEditableSection(
        title: 'AI 设置',
        body: ListView(children: [_aiSection(showInlineSave: false)]),
        dirty: _aiDirty,
        onSave: _saveAiSettings,
        saving: _runningAction,
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
          subtitle: '精细化选择推送信息类型',
          onTap: openNotificationSection,
        ),
        sectionEntry(
          icon: Icons.mail_outline,
          title: '邮箱设置',
          subtitle: '邮箱账号、IMAP、抓取策略',
          loading: _loadingAdvanced,
          onTap: openEmailSection,
        ),
        sectionEntry(
          icon: Icons.psychology_outlined,
          title: 'AI 设置',
          subtitle: '模型、密钥、分析开关',
          loading: _loadingAdvanced,
          onTap: openAiSection,
        ),
        sectionEntry(
          icon: Icons.key_outlined,
          title: '关键词管理',
          subtitle: '重要/普通/不重要关键词',
          loading: _loadingAdvanced,
          onTap: openKeywordSection,
        ),
        sectionEntry(
          icon: Icons.merge_type_outlined,
          title: '去重 Beta 设置',
          subtitle: '时间窗口、阈值与权重',
          loading: _loadingAdvanced,
          onTap: openDedupSection,
        ),
        sectionEntry(
          icon: Icons.label_outline,
          title: '标签订阅与历史',
          subtitle: '订阅规则、候选标签、手工标签',
          loading: _loadingAdvanced,
          onTap: openTagSection,
        ),
        sectionEntry(
          icon: Icons.notes_outlined,
          title: 'Notion 归档',
          subtitle: '查看归档与搜索',
          loading: _loadingAdvanced,
          onTap: () =>
              openSection('Notion 归档', ListView(children: [_notionSection()])),
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
