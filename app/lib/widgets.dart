import 'package:flutter/material.dart';

import 'api.dart';

class C {
  static const ink = Color(0xFF1B3A3F), inkLight = Color(0xFF274F55), coral = Color(0xFFFF6F5E);
  static const coralDark = Color(0xFFE85A49), sand = Color(0xFFFBF7F2), sandDark = Color(0xFFF1E9DE);
  static const sage = Color(0xFF7FA69A), sagePale = Color(0xFFE7F0EC), muted = Color(0xFF7A7A76);
  static const gold = Color(0xFFE8A33D), danger = Color(0xFFD64545), dangerPale = Color(0xFFFBE2E2);
  static const success = Color(0xFF3E9142), successPale = Color(0xFFE4F3E4);
}

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true, colorSchemeSeed: C.coral, scaffoldBackgroundColor: C.sand);
  return base.copyWith(
    appBarTheme: const AppBarTheme(backgroundColor: C.sand, foregroundColor: C.ink, elevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
        color: Colors.white, elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: C.coral,
            minimumSize: const Size(64, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
  );
}

Color hex(String? h) => Color(int.parse('FF${(h ?? '#FF6F5E').substring(1)}', radix: 16));
String inr(num? n) => '₹${(n ?? 0).round()}';
String initials(String n) => n.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join();

class Avatar extends StatelessWidget {
  final String name;
  final String? color;
  final double size;
  const Avatar(this.name, {super.key, this.color, this.size = 44});
  @override
  Widget build(BuildContext context) => CircleAvatar(
      radius: size / 2,
      backgroundColor: color == null ? C.inkLight : hex(color),
      child: Text(initials(name),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * .36)));
}

class Section extends StatelessWidget {
  final String text;
  const Section(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(text.toUpperCase(),
          style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: C.coralDark)));
}

void toast(BuildContext context, Object msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));

/// Runs an API action, shows errors as a snackbar, returns null on failure.
Future<T?> guard<T>(BuildContext context, Future<T> Function() fn, {String? ok}) async {
  try {
    final r = await fn();
    if (ok != null && context.mounted) toast(context, ok);
    return r;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
  } catch (e) {
    if (context.mounted) toast(context, 'Network error — check your connection');
  }
  return null;
}

/// Loads data via [load] and rebuilds with [builder]; pull-to-refresh included.
class Loader extends StatefulWidget {
  final Future Function() load;
  final Widget Function(BuildContext, dynamic data, VoidCallback reload) builder;
  const Loader({super.key, required this.load, required this.builder});
  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader> {
  late Future _f = widget.load();
  void reload() => setState(() => _f = widget.load());
  @override
  Widget build(BuildContext context) => FutureBuilder(
      future: _f,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$snap.error'.replaceFirst('Instance of ', ''), textAlign: TextAlign.center),
            TextButton(onPressed: reload, child: const Text('Retry')),
          ]));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return RefreshIndicator(onRefresh: () async => reload(), child: widget.builder(ctx, snap.data, reload));
      });
}

class StatusTag extends StatelessWidget {
  final String status;
  const StatusTag(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final bad = ['cancelled', 'rejected', 'suspended', 'disabled'].contains(status);
    final wait = ['pending'].contains(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bad ? C.dangerPale : (wait ? const Color(0xFFFCEDD3) : C.successPale),
          borderRadius: BorderRadius.circular(99)),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: bad ? C.danger : (wait ? const Color(0xFF9C6B15) : C.success))),
    );
  }
}

class Stat extends StatelessWidget {
  final String label, value;
  const Stat(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
          ])));
}
