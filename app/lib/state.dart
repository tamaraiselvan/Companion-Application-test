import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'location.dart';
import 'push.dart';

class AppState extends ChangeNotifier {
  Map<String, dynamic>? user;
  bool ready = false;
  bool onboarded = false;
  List services = [];
  int unread = 0;
  LatLng? here;
  Timer? _poll;

  /// Device location, fetched once per session (null if denied).
  Future<LatLng?> locate() async => here ??= await currentLocation();

  Future<void> refreshUnread() async {
    if (!loggedIn) return;
    try {
      final n = await Api.I.get('/notifications/') as List;
      unread = n.where((x) => x['unread'] == true).length;
      notifyListeners();
    } catch (_) {}
  }

  void _onLoggedIn() {
    Push.register();
    refreshUnread();
    _poll?.cancel();
    // Fallback for devices without push: refresh the badge periodically.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => refreshUnread());
  }

  String get role => user?['role'] ?? 'user';
  bool get loggedIn => user != null;

  Future<void> init() async {
    Push.onMessage = refreshUnread;
    Api.I.onSessionExpired = () {
      _poll?.cancel();
      user = null;
      notifyListeners();
    };
    try {
      services = await Api.I.get('/services/');
      if (await Api.I.restore()) user = await Api.I.get('/auth/me/');
      if (user != null) _onLoggedIn();
    } catch (_) {
      user = null;
    }
    ready = true;
    notifyListeners();
  }

  Future<void> _afterAuth(Map data) async {
    await Api.I.saveTokens(data);
    user = Map<String, dynamic>.from(data['user']);
    onboarded = true;
    _onLoggedIn();
    notifyListeners();
  }

  Future<void> login(String id, String pw) async =>
      _afterAuth(await Api.I.post('/auth/login/', {'username': id, 'password': pw}));
  Future<void> loginOtp(String phone, String otp) async =>
      _afterAuth(await Api.I.post('/auth/otp/verify/', {'phone': phone, 'otp': otp}));
  Future<void> register(Map<String, dynamic> body) async => _afterAuth(await Api.I.post('/auth/register/', body));

  Future<void> refreshMe() async {
    user = await Api.I.get('/auth/me/');
    notifyListeners();
  }

  Future<void> logout() async {
    _poll?.cancel();
    await Push.unregister();
    await Api.I.clear();
    user = null;
    notifyListeners();
  }

  void finishOnboarding() {
    onboarded = true;
    notifyListeners();
  }
}
