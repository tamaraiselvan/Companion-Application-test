import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';

// Firebase config comes from build-time defines, e.g. `--dart-define-from-file=firebase.json`
// (see firebase.example.json). Without it, push is disabled and the app relies on in-app notifications.
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const _vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
const _keys = {
  'web': (String.fromEnvironment('FIREBASE_WEB_API_KEY'), String.fromEnvironment('FIREBASE_WEB_APP_ID')),
  'android': (String.fromEnvironment('FIREBASE_ANDROID_API_KEY'), String.fromEnvironment('FIREBASE_ANDROID_APP_ID')),
  'ios': (String.fromEnvironment('FIREBASE_IOS_API_KEY'), String.fromEnvironment('FIREBASE_IOS_APP_ID')),
};

String get platformName => kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage m) async {
  // Notification payloads are shown by the OS while the app is in the background; nothing else to do.
}

class Push {
  static bool enabled = false;
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Called on every incoming message (foreground) — used to refresh unread counts.
  static VoidCallback? onMessage;

  /// Called when the user taps a notification; receives its data payload.
  static void Function(Map<String, dynamic> data)? onOpen;

  static final _local = FlutterLocalNotificationsPlugin();
  static String? _token;
  static StreamSubscription? _refreshSub;

  static Future<void> init() async {
    final k = _keys[platformName]!;
    if (_projectId.isEmpty || k.$1.isEmpty) return;
    try {
      await Firebase.initializeApp(
          options: FirebaseOptions(apiKey: k.$1, appId: k.$2, messagingSenderId: _senderId, projectId: _projectId));
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
        await _local.initialize(
          settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings()),
          onDidReceiveNotificationResponse: (r) => onOpen?.call({'booking_id': r.payload ?? ''}),
        );
        await _local
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(const AndroidNotificationChannel('maitrio', 'Maitrio alerts',
                description: 'Bookings, arrivals, payments and safety alerts', importance: Importance.high));
      }
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen?.call(m.data));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) Future.delayed(const Duration(seconds: 1), () => onOpen?.call(initial.data));
      enabled = true;
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  static void _showForeground(RemoteMessage m) {
    onMessage?.call();
    final n = m.notification;
    if (n == null) return;
    if (kIsWeb) {
      messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text('${n.title ?? ''}\n${n.body ?? ''}'),
        action: m.data['booking_id'] != null ? SnackBarAction(label: 'Open', onPressed: () => onOpen?.call(m.data)) : null,
      ));
      return;
    }
    _local.show(
      id: m.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('maitrio', 'Maitrio alerts', importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails()),
      payload: m.data['booking_id']?.toString(),
    );
  }

  /// Ask permission and register this device's token with the backend (call after login).
  static Future<void> register() async {
    if (!enabled) return;
    try {
      final fm = FirebaseMessaging.instance;
      final perm = await fm.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      _token = await fm.getToken(vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null);
      if (_token != null) await Api.I.post('/devices/', {'token': _token, 'platform': platformName});
      _refreshSub ??= fm.onTokenRefresh.listen((t) {
        _token = t;
        Api.I.post('/devices/', {'token': t, 'platform': platformName}).catchError((_) {});
      });
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  /// Remove this device from the account (call before logout).
  static Future<void> unregister() async {
    if (!enabled || _token == null) return;
    try {
      await Api.I.deleteWith('/devices/', {'token': _token});
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
  }
}
