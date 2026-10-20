import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'push.dart';

import 'screens/admin.dart';
import 'screens/auth.dart';
import 'screens/common.dart';
import 'screens/partner.dart';
import 'screens/user_flows.dart';
import 'screens/user_shell.dart';
import 'state.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Push.init();
  final state = AppState();
  // Tapping a push opens the related booking (or the notification list).
  Push.onOpen = (data) {
    final nav = Push.navigatorKey.currentState;
    if (nav == null || !state.loggedIn) return;
    final id = int.tryParse('${data['booking_id'] ?? ''}');
    nav.push(MaterialPageRoute(builder: (_) => id != null ? TrackingScreen(id) : const NotificationsScreen()));
    state.refreshUnread();
  };
  runApp(ChangeNotifierProvider.value(value: state..init(), child: const DayfelloApp()));
}

class DayfelloApp extends StatelessWidget {
  const DayfelloApp({super.key});
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
      title: 'dayfello',
      debugShowCheckedModeBanner: false,
      navigatorKey: Push.navigatorKey,
      scaffoldMessengerKey: Push.messengerKey,
      theme: buildTheme(),
      // Key on role so switching account resets navigation.
      home: KeyedSubtree(key: ValueKey('${s.ready}-${s.loggedIn}-${s.role}-${s.onboarded}'), child: home),
    );
  }
}
