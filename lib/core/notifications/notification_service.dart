import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();

  NotificationService._();

  static const _taskChannelId = 'mail_analyzer_tasks';
  static const _taskChannelName = '任务通知';
  static const _taskChannelDesc = '后台任务完成与失败提醒';
  static const _reminderChannelId = 'mail_analyzer_reminders';
  static const _reminderChannelName = '日程提醒';
  static const _reminderChannelDesc = '日程即将开始提醒';
  static const _mailChannelId = 'mail_analyzer_mails';
  static const _mailChannelName = '邮件通知';
  static const _mailChannelDesc = '新邮件与分析结果提醒';
  static const _systemChannelId = 'mail_analyzer_system';
  static const _systemChannelName = '系统通知';
  static const _systemChannelDesc = '系统公告与其他提醒';

  static const pushTypeTask = 'task';
  static const pushTypeReminder = 'reminder';
  static const pushTypeEmailNew = 'email_new';
  static const pushTypeEmailAnalysis = 'email_analysis';
  static const pushTypeEvent = 'event';
  static const pushTypeSystem = 'system';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _firebaseReady = false;
  String? _fcmToken;
  Map<String, dynamic>? _lastOpenedMessageData;
  int _notificationId = 1000;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      macOS: iosInit,
    );
    await _plugin.initialize(initSettings);
    await _createChannels();
    await requestPermissionIfNeeded();
    await _initFirebaseMessaging();
    _initialized = true;
  }

  bool get firebaseReady => _firebaseReady;
  String? get cachedFcmToken => _fcmToken;
  Map<String, dynamic>? get lastOpenedMessageData => _lastOpenedMessageData;

  Future<void> _initFirebaseMessaging() async {
    if (kIsWeb) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _fcmToken = await messaging.getToken();
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _lastOpenedMessageData = Map<String, dynamic>.from(initialMessage.data);
      }
      messaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _lastOpenedMessageData = Map<String, dynamic>.from(message.data);
      });
      FirebaseMessaging.onMessage.listen((message) async {
        final pushType = _resolvePushType(message);
        if (!await isPushTypeEnabled(pushType)) return;
        final title = message.notification?.title ??
            message.data['title']?.toString() ??
            '新通知';
        final body = message.notification?.body ??
            message.data['body']?.toString() ??
            '';
        await _showNotificationByType(
          pushType: pushType,
          title: title,
          body: body,
        );
      });
      _firebaseReady = true;
    } catch (_) {
      // Missing Firebase config (google-services.json/GoogleService-Info.plist) or init errors.
      _firebaseReady = false;
    }
  }

  Future<void> _createChannels() async {
    if (kIsWeb) return;
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _taskChannelId,
        _taskChannelName,
        description: _taskChannelDesc,
        importance: Importance.high,
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _reminderChannelId,
        _reminderChannelName,
        description: _reminderChannelDesc,
        importance: Importance.high,
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _mailChannelId,
        _mailChannelName,
        description: _mailChannelDesc,
        importance: Importance.high,
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _systemChannelId,
        _systemChannelName,
        description: _systemChannelDesc,
        importance: Importance.high,
      ),
    );
  }

  Future<bool> isPermissionGranted() async {
    if (kIsWeb) return true;
    final status = await Permission.notification.status;
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  Future<bool> requestPermissionIfNeeded() async {
    if (kIsWeb) return true;
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return true;
    }
    final result = await Permission.notification.request();
    return result.isGranted || result.isLimited || result.isProvisional;
  }

  Future<String?> getFcmToken({bool refresh = false}) async {
    if (kIsWeb) return null;
    await init();
    if (!_firebaseReady) return null;
    if (refresh) {
      _fcmToken = await FirebaseMessaging.instance.getToken();
      return _fcmToken;
    }
    return _fcmToken ?? await FirebaseMessaging.instance.getToken();
  }

  Future<bool> openSystemNotificationSettings() async {
    if (kIsWeb) return false;
    return openAppSettings();
  }

  Future<bool> isPushTypeEnabled(String pushType) async {
    final pref = await SharedPreferences.getInstance();
    return pref.getBool(_prefKey(pushType)) ?? _defaultEnabled(pushType);
  }

  Future<void> showTaskNotification({
    required String title,
    required String body,
  }) async {
    if (!await isPushTypeEnabled(pushTypeTask)) return;
    await _showNotificationByType(
        pushType: pushTypeTask, title: title, body: body);
  }

  Future<void> showReminderNotification({
    required String title,
    required String body,
  }) async {
    if (!await isPushTypeEnabled(pushTypeReminder)) return;
    await _showNotificationByType(
        pushType: pushTypeReminder, title: title, body: body);
  }

  Future<void> showEmailNotification({
    required String title,
    required String body,
    bool analysis = false,
  }) async {
    final pushType = analysis ? pushTypeEmailAnalysis : pushTypeEmailNew;
    if (!await isPushTypeEnabled(pushType)) return;
    await _showNotificationByType(pushType: pushType, title: title, body: body);
  }

  Future<void> showSystemNotification({
    required String title,
    required String body,
  }) async {
    if (!await isPushTypeEnabled(pushTypeSystem)) return;
    await _showNotificationByType(
        pushType: pushTypeSystem, title: title, body: body);
  }

  Future<void> _showNotificationByType({
    required String pushType,
    required String title,
    required String body,
  }) async {
    final channel = _channelForType(pushType);
    await _showGenericNotification(
      title: title,
      body: body,
      channelId: channel.id,
      channelName: channel.name,
      channelDesc: channel.desc,
    );
  }

  Future<void> _showGenericNotification({
    required String title,
    required String body,
    String? channelId,
    String? channelName,
    String? channelDesc,
  }) async {
    if (kIsWeb) return;
    if (!await isPermissionGranted()) return;
    await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId ?? _taskChannelId,
        channelName ?? _taskChannelName,
        channelDescription: channelDesc ?? _taskChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _plugin.show(_notificationId++, title, body, details);
  }

  String _resolvePushType(RemoteMessage message) {
    final raw = (message.data['push_type'] ??
            message.data['type'] ??
            message.data['category'] ??
            message.data['biz_type'] ??
            '')
        .toString()
        .toLowerCase()
        .trim();
    if (raw.isEmpty) return pushTypeSystem;
    if (raw == 'task' ||
        raw == 'task_status' ||
        raw == 'task_done' ||
        raw == 'task_failed') {
      return pushTypeTask;
    }
    if (raw == 'reminder' ||
        raw == 'event_reminder' ||
        raw == 'schedule_reminder') {
      return pushTypeReminder;
    }
    if (raw == 'email' || raw == 'new_email' || raw == 'email_new') {
      return pushTypeEmailNew;
    }
    if (raw == 'email_analysis' ||
        raw == 'analysis_done' ||
        raw == 'mail_analysis') {
      return pushTypeEmailAnalysis;
    }
    if (raw == 'event' || raw == 'event_update' || raw == 'calendar') {
      return pushTypeEvent;
    }
    if (raw == 'system' || raw == 'announcement' || raw == 'notice') {
      return pushTypeSystem;
    }
    return pushTypeSystem;
  }

  String _prefKey(String pushType) {
    switch (pushType) {
      case pushTypeTask:
        return 'task_notification';
      case pushTypeReminder:
        return 'reminder_notification';
      case pushTypeEmailNew:
        return 'email_new_notification';
      case pushTypeEmailAnalysis:
        return 'email_analysis_notification';
      case pushTypeEvent:
        return 'event_notification';
      case pushTypeSystem:
      default:
        return 'system_notification';
    }
  }

  bool _defaultEnabled(String pushType) {
    switch (pushType) {
      case pushTypeTask:
      case pushTypeReminder:
      case pushTypeEmailNew:
      case pushTypeEmailAnalysis:
      case pushTypeEvent:
      case pushTypeSystem:
        return true;
      default:
        return true;
    }
  }

  _NotifyChannel _channelForType(String pushType) {
    switch (pushType) {
      case pushTypeReminder:
      case pushTypeEvent:
        return const _NotifyChannel(
            _reminderChannelId, _reminderChannelName, _reminderChannelDesc);
      case pushTypeEmailNew:
      case pushTypeEmailAnalysis:
        return const _NotifyChannel(
            _mailChannelId, _mailChannelName, _mailChannelDesc);
      case pushTypeTask:
        return const _NotifyChannel(
            _taskChannelId, _taskChannelName, _taskChannelDesc);
      case pushTypeSystem:
      default:
        return const _NotifyChannel(
            _systemChannelId, _systemChannelName, _systemChannelDesc);
    }
  }
}

class _NotifyChannel {
  final String id;
  final String name;
  final String desc;
  const _NotifyChannel(this.id, this.name, this.desc);
}
