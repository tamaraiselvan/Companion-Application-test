import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../widgets.dart';

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.push<T>(context, MaterialPageRoute(builder: (_) => page));

/// lat/lng query params for distance-aware companion search (empty if location is unavailable).
Future<Map<String, String>> locParams(BuildContext context) async {
  final here = await context.read<AppState>().locate();
  return here == null ? {} : {'lat': '${here.latitude}', 'lng': '${here.longitude}'};
}

String fmtDate(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Floating SOS + chatbot buttons shown on the user app.
class SafetyButtons extends StatelessWidget {
  const SafetyButtons({super.key});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(
            heroTag: 'bot', backgroundColor: C.ink, foregroundColor: Colors.white,
            onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const ChatbotSheet()),
            child: const Icon(Icons.smart_toy_outlined)),
        const SizedBox(height: 10),
        FloatingActionButton(
            heroTag: 'sos', backgroundColor: C.danger, foregroundColor: Colors.white,
            onPressed: () => showModalBottomSheet(context: context, isDismissible: false, builder: (_) => const SosSheet()),
            child: const Text('SOS', style: TextStyle(fontWeight: FontWeight.w900))),
      ]);
}

class SosSheet extends StatefulWidget {
  const SosSheet({super.key});
  @override
  State<SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<SosSheet> {
  int stage = 0;
  String? error;
  static const stages = ['Sending alert to Maitrio safety team…', 'Notifying your emergency contact…', 'Admin team alerted', 'Help is on the way'];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final here = await context.read<AppState>().locate();
      await Api.I.post('/sos/', {if (here != null) 'lat': here.latitude, if (here != null) 'lng': here.longitude});
      for (var i = 1; i < stages.length && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) setState(() => stage = i);
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Could not reach server. Call 112 directly.');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🆘', style: TextStyle(fontSize: 40)),
          const Text('Emergency SOS activated', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.danger)),
          const SizedBox(height: 12),
          if (error != null) Text(error!, style: const TextStyle(color: C.danger)),
          for (var i = 0; i < stages.length; i++)
            ListTile(dense: true, leading: Text(i <= stage ? '✅' : '⏳'), title: Text(stages[i])),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ]),
      );
}

class ChatbotSheet extends StatefulWidget {
  const ChatbotSheet({super.key});
  @override
  State<ChatbotSheet> createState() => _ChatbotSheetState();
}

class _ChatbotSheetState extends State<ChatbotSheet> {
  final msgs = <(bool, String)>[(false, "Hi! I'm the Maitrio Assistant 👋 How can I help?")];
  static const opts = ['Booking help', 'Pricing', 'Cancellation', 'FAQ', 'Emergency'];

  Future<void> ask(String q) async {
    setState(() => msgs.add((true, q)));
    final r = await guard(context, () => Api.I.post('/bot/', {'q': q}));
    if (r != null && mounted) setState(() => msgs.add((false, r['answer'])));
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * .6,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Text('🤖 Maitrio Assistant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Expanded(child: ListView(children: [for (final m in msgs) Bubble(m.$2, mine: m.$1)])),
            Wrap(spacing: 6, children: [for (final o in opts) ActionChip(label: Text(o), onPressed: () => ask(o))]),
          ]),
        ),
      );
}

class Bubble extends StatelessWidget {
  final String text;
  final bool mine;
  final String? meta;
  const Bubble(this.text, {super.key, required this.mine, this.meta});
  @override
  Widget build(BuildContext context) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(color: mine ? C.ink : Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(text, style: TextStyle(color: mine ? Colors.white : Colors.black87)),
            if (meta != null) Text(meta!, style: TextStyle(fontSize: 10, color: mine ? Colors.white60 : C.muted)),
          ]),
        ),
      );
}

/// 1:1 chat with the other party of a booking. Polls every 4s.
class ChatScreen extends StatefulWidget {
  final int peerUserId;
  final String peerName;
  final String? color;
  const ChatScreen({super.key, required this.peerUserId, required this.peerName, this.color});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List msgs = [];
  String? error;
  final input = TextEditingController();
  Timer? t;

  @override
  void initState() {
    super.initState();
    load();
    t = Timer.periodic(const Duration(seconds: 4), (_) => load());
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await Api.I.get('/chat/${widget.peerUserId}/');
      if (mounted) setState(() => msgs = d);
    } on ApiException catch (e) {
      t?.cancel();
      if (mounted) setState(() => error = e.message);
    } catch (_) {}
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    await guard(context, () => Api.I.post('/chat/${widget.peerUserId}/', {'text': text}));
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Row(children: [Avatar(widget.peerName, color: widget.color, size: 34), const SizedBox(width: 10), Text(widget.peerName)]),
          actions: [
            IconButton(icon: const Icon(Icons.call), onPressed: () => push(context, CallScreen(name: widget.peerName, video: false))),
            IconButton(icon: const Icon(Icons.videocam), onPressed: () => push(context, CallScreen(name: widget.peerName, video: true))),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center)))
                : ListView(reverse: true, padding: const EdgeInsets.all(12), children: [
                    for (final m in msgs.reversed)
                      Bubble(m['text'], mine: m['mine'], meta: m['mine'] ? (m['read'] ? '✓✓ Read' : '✓ Sent') : null),
                  ]),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(child: TextField(controller: input, decoration: const InputDecoration(hintText: 'Type a message…'), onSubmitted: (_) => send())),
                IconButton.filled(onPressed: send, icon: const Icon(Icons.send)),
              ]),
            ),
          ),
        ]),
      );
}

/// Call UI. Wire a real RTC provider (e.g. Agora/Twilio/WebRTC) here; the backend should mint call tokens.
class CallScreen extends StatefulWidget {
  final String name;
  final bool video;
  const CallScreen({super.key, required this.name, required this.video});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  int secs = -1;
  bool muted = false, speaker = false, camOff = false;
  Timer? t;

  @override
  void initState() {
    super.initState();
    t = Timer(const Duration(milliseconds: 1500), () {
      t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => secs++));
      setState(() => secs = 0);
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  Widget btn(IconData i, bool on, VoidCallback f, {Color? bg}) => Padding(
      padding: const EdgeInsets.all(8),
      child: IconButton.filled(
          iconSize: 28,
          style: IconButton.styleFrom(backgroundColor: bg ?? (on ? Colors.white : Colors.white12), foregroundColor: on ? C.ink : Colors.white),
          onPressed: f,
          icon: Icon(i)));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.ink,
        body: SafeArea(
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const SizedBox(height: 20),
            Column(children: [
              Avatar(widget.name, size: 120),
              const SizedBox(height: 12),
              Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
              Text(secs < 0 ? 'Connecting…' : '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white70)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              btn(muted ? Icons.mic_off : Icons.mic, muted, () => setState(() => muted = !muted)),
              if (widget.video) btn(Icons.videocam_off, camOff, () => setState(() => camOff = !camOff)),
              btn(Icons.volume_up, speaker, () => setState(() => speaker = !speaker)),
              btn(Icons.call_end, false, () => Navigator.pop(context), bg: C.danger),
            ]),
          ]),
        ),
      );
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: Loader(
          load: () => Api.I.get('/notifications/'),
          builder: (ctx, d, reload) => ListView(children: [
            Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () async {
                      await guard(ctx, () => Api.I.post('/notifications/mark-all-read/'));
                      if (ctx.mounted) ctx.read<AppState>().refreshUnread();
                      reload();
                    },
                    child: const Text('Mark all read'))),
            if ((d as List).isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No notifications yet.')),
            for (final n in d)
              Card(
                color: n['unread'] ? Colors.white : C.sandDark,
                child: ListTile(
                  leading: Text(n['icon'], style: const TextStyle(fontSize: 22)),
                  title: Text(n['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${n['body']}\n${fmtDate(n['created'])}'),
                  isThreeLine: true,
                ),
              ),
          ]),
        ),
      );
}

Future<void> changePasswordDialog(BuildContext context) {
  final old = TextEditingController(), nw = TextEditingController();
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Change password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: old, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
        const SizedBox(height: 10),
        TextField(controller: nw, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () async {
              final r = await guard(ctx, () => Api.I.post('/auth/change-password/', {'old_password': old.text, 'new_password': nw.text}),
                  ok: 'Password updated');
              if (r != null && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Update')),
      ],
    ),
  );
}

/// Per-category notification opt-outs (stored on the server so push respects them too).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettingsScreen> {
  static const cats = {
    'booking': ('Booking updates', 'Confirmations, cancellations, new job requests'),
    'arrival': ('Companion arriving', 'Check-in and arrival at your location'),
    'payment': ('Payments', 'Wallet top-ups and refunds'),
    'offers': ('Offers & promotions', 'Discounts and announcements'),
    'emergency': ('Emergency alerts', 'Always on for your safety'),
  };
  late Map<String, dynamic> prefs = Map.of(context.read<AppState>().user?['notif_prefs'] ?? {});

  Future<void> set(String k, bool v) async {
    setState(() => prefs[k] = v);
    final r = await guard(context, () => Api.I.patch('/auth/me/', {'notif_prefs': prefs}));
    if (!mounted) return;
    if (r == null) {
      setState(() => prefs[k] = !v);
    } else {
      context.read<AppState>().refreshMe();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notification settings')),
        body: ListView(children: [
          for (final e in cats.entries)
            SwitchListTile(
              title: Text(e.value.$1),
              subtitle: Text(e.value.$2),
              value: e.key == 'emergency' || prefs[e.key] != false,
              onChanged: e.key == 'emergency' ? null : (v) => set(e.key, v),
            ),
        ]),
      );
}
