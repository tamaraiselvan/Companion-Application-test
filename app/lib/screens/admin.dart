import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../location.dart';
import '../state.dart';
import '../widgets.dart';
import 'maps.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int tab = 0;
  static const nav = [
    (Icons.dashboard_outlined, 'Dashboard'), (Icons.people_outline, 'Users'), (Icons.handshake_outlined, 'Maitrions'),
    (Icons.event_note_outlined, 'Bookings'), (Icons.sell_outlined, 'Coupons'), (Icons.web_outlined, 'CMS'),
    (Icons.campaign_outlined, 'Broadcast'), (Icons.flag_outlined, 'Feature flags'), (Icons.sos_outlined, 'SOS alerts'),
  ];
  static final pages = <Widget Function()>[
    () => const AdminDashboard(), () => const AdminUsers(), () => const AdminCompanions(), () => const AdminBookings(),
    () => const AdminCoupons(), () => const AdminCms(), () => const AdminBroadcast(), () => const AdminFlags(), () => const AdminSos(),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    final body = Padding(padding: const EdgeInsets.all(16), child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]()));
    final logout = IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: () => context.read<AppState>().logout());
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: true,
            backgroundColor: C.ink,
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white70),
            selectedLabelTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            unselectedIconTheme: const IconThemeData(color: Colors.white70),
            leading: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Maitrio Admin', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600))),
            trailing: Theme(data: ThemeData.dark(), child: logout),
            destinations: [for (final n in nav) NavigationRailDestination(icon: Icon(n.$1), label: Text(n.$2))],
          ),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(nav[tab].$2), actions: [logout]),
      drawer: NavigationDrawer(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          setState(() => tab = i);
          Navigator.pop(context);
        },
        children: [
          const Padding(padding: EdgeInsets.all(20), child: Text('Maitrio Admin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
          for (final n in nav) NavigationDrawerDestination(icon: Icon(n.$1), label: Text(n.$2)),
        ],
      ),
      body: body,
    );
  }
}

Widget _title(String t, String sub) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: C.ink)),
      Text(sub, style: const TextStyle(color: C.muted)),
    ]));

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});
  @override
  Widget build(BuildContext context) => Loader(
        load: () => Api.I.get('/admin/stats/'),
        builder: (ctx, s, _) => ListView(children: [
          _title('Dashboard', 'An overview of platform activity.'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in {
              'Total users': '${s['total_users']}', 'Active users': '${s['active_users']}',
              'Maitrions': '${s['total_companions']}', 'Pending approvals': '${s['pending_companions']}',
              'Live services': '${s['live_services']}', "Today's bookings": '${s['today_bookings']}',
              'Revenue': inr(s['revenue']), 'Open SOS': '${s['open_sos']}',
            }.entries)
              SizedBox(width: 180, child: Stat(e.key, e.value)),
          ]),
          const Section('Top services'),
          for (final t in s['top_services'])
            ListTile(title: Text('${t['name']}'), trailing: Text('${t['count']} bookings')),
        ]),
      );
}

class AdminUsers extends StatefulWidget {
  const AdminUsers({super.key});
  @override
  State<AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsers> {
  String q = '';
  Key k = UniqueKey();
  @override
  Widget build(BuildContext context) => Column(children: [
        _title('User management', 'Search, suspend and delete platform users.'),
        TextField(
            decoration: const InputDecoration(hintText: 'Search name, email or phone', prefixIcon: Icon(Icons.search)),
            onSubmitted: (v) => setState(() {
                  q = v;
                  k = UniqueKey();
                })),
        const SizedBox(height: 8),
        Expanded(
          child: Loader(
            key: k,
            load: () => Api.I.get('/admin/users/', {if (q.isNotEmpty) 'q': q}),
            builder: (ctx, d, reload) => ListView(children: [
              for (final u in d)
                Card(
                  child: ListTile(
                    leading: Avatar('${u['name'] ?? u['username']}'),
                    title: Text('${u['name'] ?? ''} (${u['role']})'),
                    subtitle: Text('${u['email'] ?? ''} · ${u['phone'] ?? ''}'),
                    trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      StatusTag(u['is_active'] ? 'active' : 'suspended'),
                      IconButton(
                          tooltip: u['is_active'] ? 'Suspend' : 'Unsuspend',
                          icon: Icon(u['is_active'] ? Icons.block : Icons.check_circle_outline),
                          onPressed: () async {
                            await guard(ctx, () => Api.I.post('/admin/users/${u['id']}/suspend/'));
                            reload();
                          }),
                      IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline, color: C.danger),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                                context: ctx,
                                builder: (c) => AlertDialog(title: Text('Delete ${u['name']}?'), actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                                    ]));
                            if (ok == true && ctx.mounted) {
                              await guard(ctx, () => Api.I.delete('/admin/users/${u['id']}/'), ok: 'User deleted');
                              reload();
                            }
                          }),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ]);
}

class AdminCompanions extends StatelessWidget {
  const AdminCompanions({super.key});
  @override
  Widget build(BuildContext context) => Loader(
        load: () => Api.I.get('/admin/companions/'),
        builder: (ctx, d, reload) => ListView(children: [
          _title('Maitrion management', 'Approve, verify and manage companion partners.'),
          for (final c in d)
            Card(
              child: ListTile(
                leading: Avatar(c['name'], color: c['color']),
                title: Text(c['name']),
                subtitle: Text('${c['service_name']} · ⭐ ${c['rating']} · ${inr(c['price'])}/hr'),
                trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusTag(c['status']),
                  if (c['status'] != 'active')
                    IconButton(tooltip: 'Approve', icon: const Icon(Icons.check, color: C.success), onPressed: () async {
                      await guard(ctx, () => Api.I.post('/admin/companions/${c['id']}/approve/'), ok: 'Approved');
                      reload();
                    }),
                  if (c['status'] != 'rejected')
                    IconButton(tooltip: 'Reject', icon: const Icon(Icons.close, color: C.danger), onPressed: () async {
                      await guard(ctx, () => Api.I.post('/admin/companions/${c['id']}/reject/'), ok: 'Rejected');
                      reload();
                    }),
                ]),
              ),
            ),
        ]),
      );
}

class AdminBookings extends StatelessWidget {
  const AdminBookings({super.key});
  static const tabs = {'Live': 'pending,accepted,in_progress', 'Completed': 'completed', 'Cancelled': 'cancelled,rejected'};
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title('Booking management', 'Monitor bookings across the platform.'),
          TabBar(tabs: [for (final t in tabs.keys) Tab(text: t)]),
          Expanded(
            child: TabBarView(children: [
              for (final st in tabs.values)
                Loader(
                  load: () => Api.I.get('/bookings/', {'status': st}),
                  builder: (ctx, d, _) => ListView(children: [
                    if ((d as List).isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No records')),
                    for (final b in d)
                      ListTile(
                        title: Text('${b['code']} · ${b['user_name']} → ${b['companion_detail']['name']}'),
                        subtitle: Text('${b['date']} ${b['time'].toString().substring(0, 5)} · ${b['payment']}'),
                        trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [Text(inr(b['price'])), StatusTag(b['status'])]),
                      ),
                  ]),
                ),
            ]),
          ),
        ]),
      );
}

class AdminCoupons extends StatelessWidget {
  const AdminCoupons({super.key});
  @override
  Widget build(BuildContext context) => Loader(
        load: () => Api.I.get('/admin/coupons/'),
        builder: (ctx, d, reload) => ListView(children: [
          _title('Coupons', 'Create and manage promotional coupons.'),
          Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Create coupon'),
                  onPressed: () async {
                    if (await _couponDialog(ctx) == true) reload();
                  })),
          const SizedBox(height: 8),
          for (final c in d)
            Card(
              child: ListTile(
                title: Text(c['code'], style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                subtitle: Text('${c['desc']} · ${c['percent'] ? '${c['value']}%' : inr(c['value'])} off'),
                trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Switch(
                      value: c['enabled'],
                      onChanged: (v) async {
                        await guard(ctx, () => Api.I.patch('/admin/coupons/${c['id']}/', {'enabled': v}));
                        reload();
                      }),
                  IconButton(
                      icon: const Icon(Icons.delete_outline, color: C.danger),
                      onPressed: () async {
                        await guard(ctx, () => Api.I.delete('/admin/coupons/${c['id']}/'), ok: 'Coupon removed');
                        reload();
                      }),
                ]),
              ),
            ),
        ]),
      );

  Future<bool?> _couponDialog(BuildContext context) {
    final code = TextEditingController(), desc = TextEditingController(), value = TextEditingController();
    var percent = false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('New coupon'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, decoration: const InputDecoration(labelText: 'Code')),
            TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')),
            TextField(controller: value, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Value')),
            SwitchListTile(title: const Text('Percentage'), value: percent, onChanged: (v) => set(() => percent = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () async {
                  final r = await guard(ctx, () => Api.I.post('/admin/coupons/', {
                        'code': code.text.trim().toUpperCase(), 'desc': desc.text.trim(),
                        'value': int.tryParse(value.text) ?? 0, 'percent': percent, 'enabled': true,
                      }));
                  if (r != null && ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('Create')),
          ],
        ),
      ),
    );
  }
}

class AdminCms extends StatelessWidget {
  const AdminCms({super.key});
  @override
  Widget build(BuildContext context) => Loader(
        load: () => Api.I.get('/admin/cms/'),
        builder: (ctx, d, reload) {
          Future<void> add(String kind) async {
            final t = TextEditingController(), b = TextEditingController();
            final ok = await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                      title: Text('Add $kind'),
                      content: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(controller: t, decoration: const InputDecoration(labelText: 'Title')),
                        if (kind == 'faq') TextField(controller: b, decoration: const InputDecoration(labelText: 'Answer')),
                      ]),
                      actions: [FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
                    ));
            if (ok == true && ctx.mounted) {
              await guard(ctx, () => Api.I.post('/admin/cms/', {'kind': kind, 'title': t.text, 'body': b.text}));
              reload();
            }
          }

          return ListView(children: [
            _title('CMS', 'Manage home banners and FAQs shown in the app.'),
            for (final kind in ['banner', 'faq']) ...[
              Row(children: [Section(kind == 'banner' ? 'Banners' : 'FAQs'), const Spacer(), TextButton(onPressed: () => add(kind), child: const Text('+ Add'))]),
              for (final i in (d as List).where((x) => x['kind'] == kind))
                Card(
                    child: ListTile(
                        title: Text(i['title']),
                        subtitle: i['body'] == '' ? null : Text(i['body']),
                        trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await guard(ctx, () => Api.I.delete('/admin/cms/${i['id']}/'));
                              reload();
                            }))),
            ],
          ]);
        },
      );
}

class AdminBroadcast extends StatefulWidget {
  const AdminBroadcast({super.key});
  @override
  State<AdminBroadcast> createState() => _AdminBroadcastState();
}

class _AdminBroadcastState extends State<AdminBroadcast> {
  final title = TextEditingController(text: 'Offer'), body = TextEditingController();
  String role = 'user';
  @override
  Widget build(BuildContext context) => ListView(children: [
        _title('Broadcast', 'Send an in-app notification to all users or partners.'),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'user', label: Text('Users')), ButtonSegment(value: 'partner', label: Text('Partners'))],
          selected: {role},
          onSelectionChanged: (v) => setState(() => role = v.first),
        ),
        const SizedBox(height: 12),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
        const SizedBox(height: 12),
        TextField(controller: body, maxLines: 4, decoration: const InputDecoration(labelText: 'Message')),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: () async {
              final r = await guard(context, () => Api.I.post('/admin/broadcast/', {'title': title.text, 'body': body.text, 'role': role}));
              if (r != null && context.mounted) toast(context, 'Sent to ${r['sent']} accounts');
            },
            child: const Text('Send broadcast')),
      ]);
}

class AdminFlags extends StatelessWidget {
  const AdminFlags({super.key});
  @override
  Widget build(BuildContext context) => Loader(
        load: () => Api.I.get('/admin/flags/'),
        builder: (ctx, d, reload) => ListView(children: [
          _title('Feature flags', 'Toggle platform features without a release.'),
          for (final f in d)
            SwitchListTile(
                title: Text(f['key']),
                value: f['enabled'],
                onChanged: (v) async {
                  await guard(ctx, () => Api.I.patch('/admin/flags/${f['id']}/', {'enabled': v}));
                  reload();
                }),
        ]),
      );
}

class AdminSos extends StatelessWidget {
  const AdminSos({super.key});
  @override
  Widget build(BuildContext context) => Loader(
        load: () => Api.I.get('/admin/sos/'),
        builder: (ctx, d, reload) => ListView(children: [
          _title('SOS alerts', 'Emergency alerts raised by users.'),
          if ((d as List).isEmpty) const Text('No alerts.'),
          for (final a in d)
            Card(
              color: a['resolved'] ? null : C.dangerPale,
              child: ListTile(
                leading: const Text('🆘', style: TextStyle(fontSize: 24)),
                title: Text('${a['user_name']} · #${a['id']}'),
                subtitle: Text('${a['created']}${a['lat'] == null ? ' · no location' : ' · tap to view on map'}'),
                onTap: a['lat'] == null
                    ? null
                    : () => showDialog(
                        context: ctx,
                        builder: (_) => Dialog(
                            child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: SizedBox(width: 480, child: LiveMap(destination: latLngOf(a), height: 360))))),
                trailing: a['resolved']
                    ? const StatusTag('resolved')
                    : FilledButton(
                        onPressed: () async {
                          await guard(ctx, () => Api.I.post('/admin/sos/${a['id']}/resolve/'), ok: 'Marked resolved');
                          reload();
                        },
                        child: const Text('Resolve')),
              ),
            ),
        ]),
      );
}
