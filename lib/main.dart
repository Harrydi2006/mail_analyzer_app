import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app.dart';
import 'core/notifications/notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // Ignore background init errors when Firebase isn't configured yet.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MailAnalyzerApp());
  unawaited(
    NotificationService.instance
        .init()
        .timeout(const Duration(seconds: 12))
        .catchError((Object error, StackTrace stackTrace) {
      debugPrint('Notification init failed: $error');
    }),
  );
}
