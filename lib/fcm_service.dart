import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

class FCMService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize({
    required void Function(RemoteMessage message) onData,
  }) async {
    // Request permission (required on iOS, good practice on Android 13+)
    final NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('📋 Notification permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('⚠️  User denied notification permission.');
      return;
    }

    // FOREGROUND: app is open and visible
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📨 [Foreground] Message received: ${message.messageId}');
      debugPrint('   Title : ${message.notification?.title}');
      debugPrint('   Body  : ${message.notification?.body}');
      debugPrint('   Data  : ${message.data}');
      onData(message);
    });

    // BACKGROUND → OPEN: user tapped notification while app was backgrounded
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('📭 [Background→Open] Notification tapped: ${message.messageId}');
      debugPrint('   Data: ${message.data}');
      onData(message);
    });

    // TERMINATED → LAUNCH: app cold-started from a notification tap
    final RemoteMessage? initialMessage =
        await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🚀 [Terminated→Launch] App opened via notification: ${initialMessage.messageId}');
      debugPrint('   Data: ${initialMessage.data}');
      onData(initialMessage);
    }
  }

  Future<String?> getToken() async {
    final String? token = await _messaging.getToken();
    debugPrint('🔑 FCM Token: $token');
    return token;
  }
}