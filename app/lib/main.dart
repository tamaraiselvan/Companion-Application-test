import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/admin.dart';
import 'screens/auth.dart';
import 'screens/partner.dart';
import 'screens/user_shell.dart';
import 'state.dart';
import 'widgets.dart';

void main() {
  runApp(ChangeNotifierProvider(create: (_) => AppState()..init(), child: const MaitrioApp()));
}

class MaitrioApp extends StatelessWidget {
  const MaitrioApp({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget home;
    if (!s.ready) {
      home = const SplashScreen();
    } else if (!s.loggedIn) {
      home = s.onboarded ? const LoginScreen() : const OnboardingScreen();
    } else {
      home = switch (s.role) { 'admin' => const AdminShell(), 'partner' => const PartnerShell(), _ => const UserShell() };
    }
    return MaterialApp(
      title: 'Maitrio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Key on role so switching account resets navigation.
      home: KeyedSubtree(key: ValueKey('${s.ready}-${s.loggedIn}-${s.role}-${s.onboarded}'), child: home),
    );
  }
}
