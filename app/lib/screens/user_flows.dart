import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../location.dart';
import '../state.dart';
import '../widgets.dart';
import 'common.dart';
import 'maps.dart';

class CompanionScreen extends StatefulWidget {
  final int id;
  const CompanionScreen(this.id, {super.key});
  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  bool? fav;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Loader(
          load: () async {
            final favs = await Api.I.get('/companions/favorites/') as List;
            fav ??= favs.any((f) => f['id'] == widget.id);
            return Api.I.get('/companions/${widget.id}/');
          },
          builder: (ctx, c, _) {
            Widget chips(List items, {bool pill = false}) => Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in items) Chip(label: Text(pill ? '✔ $s' : '$s'), backgroundColor: pill ? C.sagePale : C.sandDark),
                ]);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Center(child: Avatar(c['name'], color: c['color'], size: 84)),
              const SizedBox(height: 8),
              Center(child: Text(c['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.ink))),
              Center(child: Text('${c['service_name']} · ${c['experience']} yrs experience', style: const TextStyle(color: C.muted))),
              Center(child: Text('⭐ ${c['rating']} (${c['reviews_count']} reviews) · ${inr(c['price'])}/hr',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton.outlined(
                    tooltip: 'Chat',
                    icon: const Icon(Icons.chat_bubble_outline),
                    onPressed: () => push(context, ChatScreen(peerUserId: c['user_id'], peerName: c['name'], color: c['color']))),
                IconButton.outlined(
                    tooltip: 'Call', icon: const Icon(Icons.call), onPressed: () => push(context, CallScreen(name: c['name'], video: false))),
                IconButton.outlined(
                    tooltip: 'Video', icon: const Icon(Icons.videocam), onPressed: () => push(context, CallScreen(name: c['name'], video: true))),
                IconButton.outlined(
                  tooltip: 'Save',
                  icon: Icon(fav == true ? Icons.favorite : Icons.favorite_border, color: C.coral),
                  onPressed: () async {
                    final r = await guard(context, () => Api.I.post('/companions/${c['id']}/favorite/'));
                    if (r != null) setState(() => fav = r['favorite']);
                  },
                ),
              ]),
              const Section('About'),
              Text(c['bio'] ?? ''),
              const Section('Skills'),
              chips(c['skills']),
              const Section('Languages'),
              chips(c['languages']),
              const Section('Certifications'),
              chips(c['certs'], pill: true),
              const Section('Reviews'),
              if ((c['reviews'] as List).isEmpty) const Text('No reviews yet.', style: TextStyle(color: C.muted)),
              for (final r in c['reviews'])
                Card(child: ListTile(title: Text(r['user']), subtitle: Text(r['text']), trailing: Text('★' * (r['stars'] as int), style: const TextStyle(color: C.gold)))),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: c['available'] ? () => push(context, BookingWizard(c)) : null,
                  child: Text(c['available'] ? 'Book now' : 'Currently unavailable')),
            ]);
          },
        ),
      );
}

class BookingWizard extends StatefulWidget {
  final Map companion;
  const BookingWizard(this.companion, {super.key});
  @override
  State<BookingWizard> createState() => _BookingWizardState();
}

class _BookingWizardState extends State<BookingWizard> {
  int step = 0, duration = 1;
  DateTime date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay time = const TimeOfDay(hour: 10, minute: 0);
  late final address = TextEditingController(text: context.read<AppState>().user?['address'] ?? '');
  final instructions = TextEditingController(), coupon = TextEditingController();
  String payment = 'UPI';
  LatLng? dest;
  bool busy = false;

  int get subtotal => (widget.companion['price'] as int) * duration;

  Future<void> next() async {
    if (step == 1 && address.text.trim().isEmpty) return toast(context, 'Please enter an address');
    if (step < 3) return setState(() => step++);
    setState(() => busy = true);
    final b = await guard(context, () => Api.I.post('/bookings/', {
          'companion': widget.companion['id'],
          'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          'duration': duration,
          'address': address.text.trim(),
          'instructions': instructions.text.trim(),
          if (dest != null) 'dest_lat': double.parse(dest!.latitude.toStringAsFixed(6)),
          if (dest != null) 'dest_lng': double.parse(dest!.longitude.toStringAsFixed(6)),
          'payment': payment,
          'coupon': coupon.text.trim(),
        }));
    if (!mounted) return;
    setState(() => busy = false);
    if (b != null) {
      context.read<AppState>().refreshMe();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ConfirmationScreen(b)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      Column(children: [
        ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text('${date.day}/${date.month}/${date.year}'),
            subtitle: const Text('Date'),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
              if (d != null) setState(() => date = d);
            }),
        ListTile(
            leading: const Icon(Icons.access_time),
            title: Text(time.format(context)),
            subtitle: const Text('Time'),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: time);
              if (t != null) setState(() => time = t);
            }),
        ListTile(
          leading: const Icon(Icons.timelapse),
          title: Text('$duration hour${duration > 1 ? 's' : ''}'),
          subtitle: Text('${inr(widget.companion['price'])} × $duration = ${inr(subtotal)}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(onPressed: duration > 1 ? () => setState(() => duration--) : null, icon: const Icon(Icons.remove)),
            IconButton(onPressed: duration < 8 ? () => setState(() => duration++) : null, icon: const Icon(Icons.add)),
          ]),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: address, maxLines: 3, decoration: const InputDecoration(labelText: 'Service address')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.my_location),
              label: const Text('Current location'),
              onPressed: () async {
                final here = await currentLocation();
                if (!context.mounted) return;
                if (here == null) return toast(context, 'Location unavailable — check permissions');
                setState(() => dest = here);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: const Text('Pick on map'),
              onPressed: () async {
                final p = await push<LatLng>(context, LocationPicker(initial: dest));
                if (p != null) setState(() => dest = p);
              },
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (dest != null)
          LiveMap(destination: dest, height: 160)
        else
          const Text('Add a map pin so your companion can navigate to you and you get arrival alerts.',
              style: TextStyle(color: C.muted, fontSize: 12)),
      ]),
      TextField(controller: instructions, maxLines: 5,
          decoration: const InputDecoration(labelText: 'Special instructions', hintText: 'e.g. Prefers Tamil conversation, needs wheelchair assistance…')),
      Column(children: [
        Card(
            child: ListTile(
                title: Text('${widget.companion['name']} · $duration hr'),
                trailing: Text(inr(subtotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))),
        TextField(controller: coupon, decoration: const InputDecoration(labelText: 'Coupon code (optional)')),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: payment,
          onChanged: (v) => setState(() => payment = v!),
          child: Column(children: [
            for (final m in ['UPI', 'Card', 'Net Banking', 'Wallet', 'Cash'])
              RadioListTile<String>(
                value: m,
                title: Text(m == 'Wallet' ? 'Wallet (${inr(num.parse('${context.read<AppState>().user?['wallet'] ?? 0}'))})' : m),
              ),
          ]),
        ),
      ]),
    ];
    const titles = ['Date & time', 'Address', 'Instructions', 'Payment'];
    return Scaffold(
      appBar: AppBar(title: Text('Book ${widget.companion['name']}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: List.generate(4, (i) => Expanded(
            child: Container(height: 5, margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: i <= step ? C.coral : C.sandDark, borderRadius: BorderRadius.circular(4)))))),
        Section('Step ${step + 1} · ${titles[step]}'),
        steps[step],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            if (step > 0) OutlinedButton(onPressed: () => setState(() => step--), child: const Text('Back')),
            const SizedBox(width: 10),
            Expanded(
                child: FilledButton(
                    onPressed: busy ? null : next,
                    child: Text(step < 3 ? 'Continue' : (busy ? 'Processing…' : 'Pay & confirm')))),
          ]),
        ),
      ),
    );
  }
}

class ConfirmationScreen extends StatelessWidget {
  final Map b;
  const ConfirmationScreen(this.b, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const CircleAvatar(radius: 36, backgroundColor: C.successPale, child: Icon(Icons.check, color: C.success, size: 40)),
              const SizedBox(height: 12),
              const Text('Booking placed!', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const Text('Waiting for your companion to accept.', textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
              const SizedBox(height: 12),
              Center(child: SelectableText(b['code'], style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.bold))),
              const SizedBox(height: 12),
              Card(
                  child: ListTile(
                      title: Text(b['companion_detail']['name']),
                      subtitle: Text('${b['date']} ${b['time'].toString().substring(0, 5)} · ${b['address']}'),
                      trailing: Text(inr(b['price'])))),
              if ((b['discount'] ?? 0) > 0) Text('Coupon saved you ${inr(b['discount'])}', textAlign: TextAlign.center, style: const TextStyle(color: C.success)),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TrackingScreen(b['id']))),
                  child: const Text('Track booking')),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back to home')),
            ]),
          ),
        ),
      );
}

/// Booking summary card with role-aware actions (customer or partner).
class BookingCard extends StatelessWidget {
  final Map b;
  final VoidCallback onChanged;
  const BookingCard(this.b, {super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final partner = context.read<AppState>().role == 'partner';
    final c = b['companion_detail'];
    final st = b['status'] as String;
    Future<void> act(String a, String ok) async {
      if (await guard(context, () => Api.I.post('/bookings/${b['id']}/$a/'), ok: ok) != null) onChanged();
    }

    final peerName = partner ? (b['user_name'] ?? 'Customer') : c['name'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Avatar(peerName, color: partner ? null : c['color']),
            const SizedBox(width: 10),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(peerName, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${c['service_name']} · ${b['date']}, ${b['time'].toString().substring(0, 5)} · ${b['duration']} hr',
                  style: const TextStyle(fontSize: 12, color: C.muted)),
            ])),
            StatusTag(st),
          ]),
          const Divider(),
          Row(children: [
            Text('${b['code']} · ${inr(b['price'])}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: C.muted)),
            const Spacer(),
            Flexible(
              flex: 4,
              child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [
                if (['accepted', 'in_progress'].contains(st))
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chat_bubble_outline),
                      onPressed: () => push(context, ChatScreen(peerUserId: partner ? b['user_id'] : c['user_id'], peerName: peerName))),
                if (partner && st == 'pending') ...[
                  OutlinedButton(onPressed: () => act('reject', 'Job rejected'), child: const Text('Reject')),
                  FilledButton(onPressed: () => act('accept', 'Job accepted'), child: const Text('Accept')),
                ],
                if (!partner && ['pending', 'accepted'].contains(st))
                  OutlinedButton(onPressed: () => act('cancel', 'Booking cancelled'), child: const Text('Cancel')),
                if (['accepted', 'in_progress'].contains(st))
                  FilledButton(
                      onPressed: () => push(context, TrackingScreen(b['id'])).then((_) => onChanged()),
                      child: Text(partner ? 'Open job' : 'Track')),
                if (st == 'completed') ...[
                  OutlinedButton(onPressed: () => push(context, InvoiceScreen(b)), child: const Text('Invoice')),
                  if (!partner && b['rated'] != true)
                    FilledButton(onPressed: () => push(context, RatingScreen(b)).then((_) => onChanged()), child: const Text('Rate')),
                ],
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Live status of a booking on a map. Polls every 5s; the assigned partner shares GPS while the job is active.
class TrackingScreen extends StatefulWidget {
  final int bookingId;
  const TrackingScreen(this.bookingId, {super.key});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Map? b;
  Timer? poll;
  StreamSubscription<LatLng>? share;
  DateTime _lastSent = DateTime(2000);
  String? shareError;

  bool get partner => context.read<AppState>().role == 'partner';
  bool get active => ['accepted', 'in_progress'].contains(b?['status']);

  @override
  void initState() {
    super.initState();
    load();
    poll = Timer.periodic(const Duration(seconds: 5), (_) => load());
  }

  @override
  void dispose() {
    poll?.cancel();
    share?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await Api.I.get('/bookings/${widget.bookingId}/');
      if (!mounted) return;
      setState(() => b = d);
      _syncSharing();
    } catch (_) {}
  }

  /// Partner: stream GPS to the backend (at most every 10s) while the job is accepted/in progress.
  Future<void> _syncSharing() async {
    if (!partner) return;
    if (!active) {
      await share?.cancel();
      share = null;
      return;
    }
    if (share != null) return;
    if (await currentLocation() == null) {
      if (mounted) setState(() => shareError = 'Enable location to share your live position with the customer.');
      return;
    }
    share = positionStream().listen((p) async {
      if (DateTime.now().difference(_lastSent) < const Duration(seconds: 10)) return;
      _lastSent = DateTime.now();
      try {
        final d = await Api.I.post('/bookings/${widget.bookingId}/location/', {'lat': p.latitude, 'lng': p.longitude});
        if (mounted) {
          setState(() {
            b = d;
            shareError = null;
          });
        }
      } catch (_) {}
    });
  }

  Future<void> act(String a, String ok) async {
    final r = await guard(context, () => Api.I.post('/bookings/${widget.bookingId}/$a/'), ok: ok);
    if (r != null) {
      setState(() => b = r);
      _syncSharing();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (b == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final st = b!['status'];
    final c = b!['companion_detail'];
    final live = latLngOf(b), dest = latLngOf(b, 'dest_lat', 'dest_lng');
    const flow = ['pending', 'accepted', 'in_progress', 'completed'];
    final idx = flow.indexOf(st);
    String info;
    if (st == 'accepted' && live == null) {
      info = partner ? 'Sharing your location once GPS is available…' : 'Waiting for ${c['name']} to start sharing location';
    } else if (st == 'accepted' && b!['eta_min'] != null) {
      info = '${b!['remaining_km']} km away · ETA ${b!['eta_min']} min';
    } else {
      info = {'pending': 'Waiting for confirmation', 'in_progress': 'Service in progress', 'completed': 'Completed'}[st] ?? st;
    }
    return Scaffold(
      appBar: AppBar(title: Text(partner ? 'Job ${b!['code']}' : 'Live tracking')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (dest != null || live != null)
          LiveMap(companion: live, destination: dest, companionLabel: c['name'])
        else
          Card(child: ListTile(leading: const Icon(Icons.map_outlined), title: const Text('No map location for this booking'), subtitle: Text(b!['address']))),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Avatar(partner ? (b!['user_name'] ?? 'Customer') : c['name'], color: partner ? null : c['color']),
            title: Text(partner ? (b!['user_name'] ?? 'Customer') : c['name']),
            subtitle: Text('$info\n${b!['address']}'),
            isThreeLine: true,
            trailing: StatusTag(st),
          ),
        ),
        if (partner && active)
          Card(
            color: shareError == null ? C.successPale : C.dangerPale,
            child: ListTile(
              dense: true,
              leading: Icon(shareError == null ? Icons.share_location : Icons.location_disabled),
              title: Text(shareError ?? 'Sharing live location while this screen is open'),
            ),
          ),
        const Section('Status'),
        for (var i = 0; i < flow.length; i++)
          ListTile(
              dense: true,
              leading: Icon(i <= idx ? Icons.check_circle : Icons.radio_button_unchecked, color: i <= idx ? C.success : C.muted),
              title: Text(['Requested', 'Accepted by companion', 'Checked in — service ongoing', 'Completed'][i])),
        if (b!['instructions'] != null && b!['instructions'] != '') ...[const Section('Instructions'), Text(b!['instructions'])],
        const SizedBox(height: 16),
        if (st == 'accepted') FilledButton(onPressed: () => act('check-in', 'Checked in'), child: const Text('Check in')),
        if (st == 'in_progress')
          FilledButton(style: FilledButton.styleFrom(backgroundColor: C.ink), onPressed: () => act('check-out', 'Service completed'), child: const Text('Check out')),
        if (st == 'completed' && !partner && b!['rated'] != true)
          FilledButton(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RatingScreen(b!))), child: const Text('Rate this session')),
      ]),
    );
  }
}

class RatingScreen extends StatefulWidget {
  final Map b;
  const RatingScreen(this.b, {super.key});
  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int stars = 0;
  final text = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final c = widget.b['companion_detail'];
    return Scaffold(
      appBar: AppBar(title: const Text('Rate your session')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: Avatar(c['name'], color: c['color'], size: 64)),
        Center(child: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.w700))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(iconSize: 40, onPressed: () => setState(() => stars = i), icon: Icon(Icons.star, color: i <= stars ? C.gold : C.sandDark)),
        ]),
        TextField(controller: text, maxLines: 4, decoration: const InputDecoration(hintText: 'Share details of your experience…')),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: stars == 0
                ? null
                : () async {
                    final r = await guard(context, () => Api.I.post('/bookings/${widget.b['id']}/rate/', {'stars': stars, 'text': text.text}),
                        ok: 'Thanks for your feedback!');
                    if (r != null && context.mounted) Navigator.pop(context);
                  },
            child: const Text('Submit rating')),
      ]),
    );
  }
}

class InvoiceScreen extends StatelessWidget {
  final Map b;
  const InvoiceScreen(this.b, {super.key});
  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Text(k, style: const TextStyle(color: C.muted)), const Spacer(), Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600))]));
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              row('Maitrio', b['code'], bold: true),
              const Divider(),
              row('Companion', b['companion_detail']['name']),
              row('Service', b['companion_detail']['service_name']),
              row('Date', '${b['date']}, ${b['time'].toString().substring(0, 5)}'),
              row('Duration', '${b['duration']} hr'),
              row('Payment', b['payment']),
              const Divider(),
              row('Subtotal', inr(b['subtotal'])),
              if ((b['discount'] ?? 0) > 0) row('Discount (${b['coupon']})', '- ${inr(b['discount'])}'),
              row('Total paid', inr(b['price']), bold: true),
            ]),
          ),
        ),
      ]),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const fields = {'name': 'Name', 'email': 'Email', 'address': 'Address', 'emergency_contact': 'Emergency contact', 'medical': 'Medical information'};
  late final c = {for (final k in fields.keys) k: TextEditingController(text: '${context.read<AppState>().user?[k] ?? ''}')};
  late String language = context.read<AppState>().user?['language'] ?? 'English';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final e in fields.entries) ...[
            TextField(controller: c[e.key], maxLines: e.key == 'medical' ? 3 : 1, decoration: InputDecoration(labelText: e.value)),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            initialValue: language,
            decoration: const InputDecoration(labelText: 'Language'),
            items: [for (final l in ['English', 'Tamil', 'Hindi', 'Telugu', 'Malayalam']) DropdownMenuItem(value: l, child: Text(l))],
            onChanged: (v) => language = v!,
          ),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: () async {
                final r = await guard(context, () => Api.I.patch('/auth/me/', {for (final e in c.entries) e.key: e.value.text.trim(), 'language': language}),
                    ok: 'Profile updated');
                if (r != null && context.mounted) {
                  await context.read<AppState>().refreshMe();
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Save changes')),
        ]),
      );
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Saved favourites')),
        body: Loader(
          load: () => Api.I.get('/companions/favorites/'),
          builder: (ctx, d, _) => ListView(padding: const EdgeInsets.all(12), children: [
            if ((d as List).isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No favourites saved yet.')),
            for (final c in d)
              Card(
                  child: ListTile(
                      leading: Avatar(c['name'], color: c['color']),
                      title: Text(c['name']),
                      subtitle: Text(c['service_name']),
                      onTap: () => push(context, CompanionScreen(c['id'])))),
          ]),
        ),
      );
}
