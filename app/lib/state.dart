import 'package:flutter/material.dart';

import 'api.dart';

class AppState extends ChangeNotifier {
  Map<String, dynamic>? user;
  bool ready = false;
  bool onboarded = false;
  List services = [];

  String get role => user?['role'] ?? 'user';
  bool get loggedIn => user != null;

  Future<void> init() async {
    Api.I.onSessionExpired = () {
      user = null;
      notifyListeners();
    };
    try {
      services = await Api.I.get('/services/');
      if (await Api.I.restore()) user = await Api.I.get('/auth/me/');
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
    await Api.I.clear();
    user = null;
    notifyListeners();
  }

  void finishOnboarding() {
    onboarded = true;
    notifyListeners();
  }
}
