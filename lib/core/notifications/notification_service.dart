import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();

  NotificationService._();

  Future<void> init() async {
    await requestPermissionIfNeeded();
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

  Future<bool> openSystemNotificationSettings() async {
    if (kIsWeb) return false;
    return openAppSettings();
  }

  Future<void> showTaskNotification({
    required String title,
    required String body,
  }) async {
    // TODO: 接入 flutter_local_notifications 真正发送通知
  }

  Future<void> showReminderNotification({
    required String title,
    required String body,
  }) async {
    // TODO: 接入 flutter_local_notifications 真正发送通知
  }
}
