import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../widgets.dart';
import 'common.dart';
import 'user_flows.dart';

class PartnerShell extends StatefulWidget {
  const PartnerShell({super.key});
  @override
  State<PartnerShell> createState() => _PartnerShellState();
}

class _PartnerShellState extends State<PartnerShell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: [const PartnerDashboard(), const PartnerJobs(), const PartnerDocs(), const PartnerProfile()][tab]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Jobs'),
            NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Docs'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      );
}

class PartnerDashboard extends StatelessWidget {
  const PartnerDashboard({super.key});
  @override
  Widget build(BuildContext context) => Loader(
        load: () async => [await Api.I.get('/partner/dashboard/'), await Api.I.get('/bookings/', {'as': 'partner', 'status': 'pending'})],
        builder: (ctx, d, reload) {
          final s = d[0], c = s['companion'], e = s['earnings'];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Welcome back', style: TextStyle(color: C.muted)),
                Text(c['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.ink)),
              ])),
              StatusTag(c['status']),
            ]),
            if (c['status'] != 'active')
              const Card(color: Color(0xFFFCEDD3), child: ListTile(title: Text('Profile under review — upload all documents to get approved.'))),
            SwitchListTile(
                title: const Text('Available for new jobs'),
                value: c['available'],
                onChanged: (v) async {
                  await guard(ctx, () => Api.I.patch('/partner/dashboard/', {'available': v}));
                  reload();
                }),
            GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.9, children: [
              Stat("Today's earnings", inr(e['daily'])),
              Stat('Rating', '⭐ ${s['rating']}'),
              Stat('Completed jobs', '${s['completed']}'),
              Stat("Today's jobs", '${s['today_jobs']}'),
              Stat('This week', inr(e['weekly'])),
              Stat('This month', inr(e['monthly'])),
            ]),
            const Section('Pending job requests'),
            if ((d[1] as List).isEmpty) const Text('No pending requests right now.', style: TextStyle(color: C.muted)),
            for (final b in d[1]) BookingCard(b, onChanged: reload),
          ]);
        },
      );
}

class PartnerJobs extends StatelessWidget {
  const PartnerJobs({super.key});
  static const tabs = {'Active': 'accepted,in_progress', 'Requests': 'pending', 'History': 'completed,cancelled,rejected'};
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: tabs.length,
        child: Column(children: [
          TabBar(tabs: [for (final t in tabs.keys) Tab(text: t)]),
          Expanded(
            child: TabBarView(children: [
              for (final st in tabs.values)
                Loader(
                  load: () => Api.I.get('/bookings/', {'as': 'partner', 'status': st}),
                  builder: (ctx, d, reload) => ListView(padding: const EdgeInsets.all(12), children: [
                    if ((d as List).isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No jobs here.')),
                    for (final b in d) BookingCard(b, onChanged: reload),
                  ]),
                ),
            ]),
          ),
        ]),
      );
}

class PartnerDocs extends StatelessWidget {
  const PartnerDocs({super.key});
  @override
  Widget build(BuildContext context) => Loader(
        load: () => Api.I.get('/partner/docs/'),
        builder: (ctx, d, reload) => ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Documents', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.ink)),
          const Text('Upload PDF/JPG/PNG up to 5MB. Admin verifies each document.', style: TextStyle(color: C.muted)),
          const SizedBox(height: 10),
          for (final doc in d)
            Card(
              child: ListTile(
                title: Text(doc['name']),
                subtitle: Text(doc['verified'] ? 'Verified' : (doc['uploaded'] ? 'Uploaded — awaiting verification' : 'Not uploaded')),
                trailing: Icon(doc['verified'] ? Icons.verified : Icons.upload_file, color: doc['verified'] ? C.success : C.coral),
                onTap: () async {
                  final pick = await FilePicker.platform
                      .pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], withData: true);
                  final f = pick?.files.single;
                  if (f?.bytes == null || !ctx.mounted) return;
                  await guard(ctx, () => Api.I.upload('/partner/docs/${doc['id']}/upload/', f!.bytes!, f.name), ok: '${doc['name']} uploaded');
                  reload();
                },
              ),
            ),
        ]),
      );
}

class PartnerProfile extends StatelessWidget {
  const PartnerProfile({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(child: Avatar(s.user?['name'] ?? '?', size: 72)),
      Center(child: Text(s.user?['name'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
      Center(child: Text(s.user?['phone'] ?? '', style: const TextStyle(color: C.muted))),
      const SizedBox(height: 16),
      Card(child: ListTile(leading: const Icon(Icons.notifications_none), title: const Text('Notifications'), onTap: () => push(context, const NotificationsScreen()))),
      Card(child: ListTile(leading: const Icon(Icons.tune), title: const Text('Notification settings'), onTap: () => push(context, const NotificationSettingsScreen()))),
      Card(child: ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Change password'), onTap: () => changePasswordDialog(context))),
      Card(child: ListTile(leading: const Icon(Icons.logout), title: const Text('Log out'), onTap: () => s.logout())),
    ]);
  }
}
