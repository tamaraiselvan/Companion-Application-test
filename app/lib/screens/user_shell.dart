import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../widgets.dart';
import 'common.dart';
import 'maps.dart';
import 'user_flows.dart';

class UserShell extends StatefulWidget {
  const UserShell({super.key});
  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  int tab = 0;
  String? searchService;

  void openSearch([String? service]) => setState(() {
        searchService = service;
        tab = 1;
      });

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(onSearch: openSearch),
      SearchTab(key: ValueKey(searchService), initialService: searchService),
      const BookingsTab(),
      const WalletTab(),
      const ProfileTab(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      floatingActionButton: const SafetyButtons(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), label: 'Bookings'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  final void Function([String?]) onSearch;
  const HomeTab({super.key, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Loader(
      load: () async {
        final loc = await locParams(context);
        return [
          await Api.I.get('/companions/', {'ordering': '-rating', ...loc}),
          await Api.I.get('/companions/', {'ordering': 'distance_km', 'available': 'true', ...loc}),
          await Api.I.get('/bookings/', {'status': 'pending,accepted,in_progress'}),
          await Api.I.get('/cms/'),
        ];
      },
      builder: (ctx, d, reload) {
        final upcoming = d[2] as List;
        final unread = s.unread;
        final banners = (d[3] as List).where((c) => c['kind'] == 'banner').toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(
                child: Text('Hi ${(s.user?['name'] ?? '').toString().split(' ').first} 👋',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: C.ink))),
            Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => push(context, const NotificationsScreen()).then((_) => s.refreshUnread())),
            ),
          ]),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => onSearch(),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: const Text('🔎  Search companions, services…', style: TextStyle(color: C.muted)),
            ),
          ),
          if (banners.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final b in banners)
                  Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: C.sagePale, borderRadius: BorderRadius.circular(14)),
                    child: Text(b['title'], style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink)),
                  ),
              ]),
            ),
          ],
          if (upcoming.isNotEmpty) ...[
            const Section('Upcoming booking'),
            BookingCard(upcoming.first, onChanged: reload),
          ],
          const Section('Services'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.05,
            children: [
              for (final sv in s.services)
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onSearch(sv['slug']),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(sv['icon'], style: const TextStyle(fontSize: 26)),
                      const SizedBox(height: 4),
                      Text(sv['name'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.ink)),
                    ]),
                  ),
                ),
            ],
          ),
          const Section('✨ Top rated for you'),
          CompanionStrip(d[0] as List),
          const Section('Nearby & available'),
          CompanionStrip(d[1] as List),
          const SizedBox(height: 80),
        ]);
      },
    );
  }
}

class CompanionStrip extends StatelessWidget {
  final List items;
  const CompanionStrip(this.items, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 150,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final c in items.take(8))
            SizedBox(
              width: 160,
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => push(context, CompanionScreen(c['id'])),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Avatar(c['name'], color: c['color']), const Spacer(), Text('⭐ ${c['rating']}')]),
                      const SizedBox(height: 8),
                      Text(c['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${c['service_name']} · ${c['distance_km']} km',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.muted)),
                      Text('${inr(c['price'])}/hr', style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class SearchTab extends StatefulWidget {
  final String? initialService;
  const SearchTab({super.key, this.initialService});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  late String? service = widget.initialService;
  String q = '', language = 'Any', gender = 'Any';
  double minRating = 0, maxPrice = 1000;
  bool available = false, mapView = false;
  Key k = UniqueKey();

  void apply() => setState(() => k = UniqueKey());

  Map<String, String> get params => {
        if (service != null) 'service': service!,
        if (q.isNotEmpty) 'q': q,
        if (language != 'Any') 'language': language,
        if (gender != 'Any') 'gender': gender,
        if (minRating > 0) 'min_rating': '$minRating',
        'max_price': '${maxPrice.round()}',
        if (available) 'available': 'true',
      };

  @override
  Widget build(BuildContext context) {
    final services = context.watch<AppState>().services;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
                decoration: const InputDecoration(hintText: 'Search by name or service', prefixIcon: Icon(Icons.search)),
                onSubmitted: (v) {
                  q = v.trim();
                  apply();
                }),
          ),
          IconButton(
              tooltip: mapView ? 'List view' : 'Map view',
              icon: Icon(mapView ? Icons.list : Icons.map_outlined),
              onPressed: () => setState(() => mapView = !mapView)),
        ]),
      ),
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final sv in [null, ...services])
            Padding(
              padding: const EdgeInsets.all(4),
              child: ChoiceChip(
                label: Text(sv == null ? 'All' : '${sv['icon']} ${sv['name']}'),
                selected: service == sv?['slug'],
                onSelected: (_) {
                  service = sv?['slug'];
                  apply();
                },
              ),
            ),
        ]),
      ),
      ExpansionTile(title: const Text('Filters'), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            Row(children: [
              Expanded(child: _drop('Language', language, ['Any', 'English', 'Tamil', 'Hindi', 'Telugu', 'Malayalam'], (v) => language = v)),
              const SizedBox(width: 10),
              Expanded(child: _drop('Gender', gender, ['Any', 'Female', 'Male'], (v) => gender = v)),
            ]),
            Row(children: [
              const Text('Min rating'),
              Expanded(
                  child: Slider(value: minRating, max: 5, divisions: 10, label: '$minRating★',
                      onChanged: (v) => setState(() => minRating = v), onChangeEnd: (_) => apply())),
            ]),
            Row(children: [
              const Text('Max ₹/hr'),
              Expanded(
                  child: Slider(value: maxPrice, min: 200, max: 1000, divisions: 16, label: inr(maxPrice),
                      onChanged: (v) => setState(() => maxPrice = v), onChangeEnd: (_) => apply())),
            ]),
            SwitchListTile(
                value: available,
                title: const Text('Available now only'),
                onChanged: (v) {
                  available = v;
                  apply();
                }),
          ]),
        ),
      ]),
      Expanded(
        child: Loader(
          key: k,
          load: () async => Api.I.get('/companions/', {...params, ...await locParams(context), 'ordering': 'distance_km'}),
          builder: (ctx, d, _) => mapView
              ? CompanionsMap(
                  companions: d, me: context.read<AppState>().here, onOpen: (c) => push(context, CompanionScreen(c['id'])))
              : (d as List).isEmpty
              ? ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Text('No matches — try widening your filters.'))])
              : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 90), children: [
                  Padding(padding: const EdgeInsets.all(6), child: Text('${d.length} companions found', style: const TextStyle(color: C.muted))),
                  for (final c in d) CompanionTile(c),
                ]),
        ),
      ),
    ]);
  }

  Widget _drop(String label, String value, List<String> items, void Function(String) set) => DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i))],
        onChanged: (v) {
          set(v!);
          apply();
        },
      );
}

class CompanionTile extends StatelessWidget {
  final Map c;
  const CompanionTile(this.c, {super.key});
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: () => push(context, CompanionScreen(c['id'])),
          leading: Avatar(c['name'], color: c['color']),
          title: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${c['service_name']} · ${(c['languages'] as List).join(', ')}\n'
              '${c['experience']} yrs · ${c['distance_km']} km · ${c['available'] ? 'Available' : 'Busy'}'),
          isThreeLine: true,
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('⭐ ${c['rating']}'),
            Text('${inr(c['price'])}/hr', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});
  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  static const tabs = {
    'Upcoming': 'pending,accepted,in_progress',
    'Completed': 'completed',
    'Cancelled': 'cancelled,rejected',
  };
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(alignment: Alignment.centerLeft,
                  child: Text('My bookings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.ink)))),
          TabBar(tabs: [for (final t in tabs.keys) Tab(text: t)]),
          Expanded(
            child: TabBarView(children: [
              for (final st in tabs.values)
                Loader(
                  load: () => Api.I.get('/bookings/', {'status': st}),
                  builder: (ctx, d, reload) => (d as List).isEmpty
                      ? ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Text('No bookings here yet.'))])
                      : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
                          for (final b in d) BookingCard(b, onChanged: reload),
                        ]),
                ),
            ]),
          ),
        ]),
      );
}

class WalletTab extends StatelessWidget {
  const WalletTab({super.key});
  @override
  Widget build(BuildContext context) => Loader(
        load: () async => [await Api.I.get('/wallet/'), await Api.I.get('/coupons/')],
        builder: (ctx, d, reload) => ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Wallet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.ink)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [C.ink, Color(0xFF2D5A5F)]), borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Available balance', style: TextStyle(color: Colors.white70)),
              Text(inr(num.parse('${d[0]['balance']}')),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final a in [100, 500, 1000])
                  ActionChip(
                      label: Text('+ ₹$a'),
                      onPressed: () async {
                        await guard(ctx, () => Api.I.post('/wallet/', {'amount': a}), ok: '₹$a added');
                        reload();
                      }),
              ]),
            ]),
          ),
          const Section('Coupons'),
          for (final c in d[1])
            Card(child: ListTile(title: Text(c['code'], style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                subtitle: Text(c['desc']), trailing: const Text('Use at checkout'))),
          const Section('Transactions'),
          for (final t in d[0]['tx'])
            ListTile(
              title: Text(t['label']),
              subtitle: Text(fmtDate(t['created'])),
              trailing: Text(inr(num.parse('${t['amount']}')),
                  style: TextStyle(fontWeight: FontWeight.bold, color: num.parse('${t['amount']}') >= 0 ? C.success : C.danger)),
            ),
          const SizedBox(height: 80),
        ]),
      );
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final u = s.user ?? {};
    Widget row(IconData i, String t, VoidCallback f) =>
        Card(child: ListTile(leading: Icon(i), title: Text(t), trailing: const Icon(Icons.chevron_right), onTap: f));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(child: Avatar(u['name'] ?? '?', size: 72)),
      const SizedBox(height: 8),
      Center(child: Text(u['name'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
      Center(child: Text(u['phone'] ?? '', style: const TextStyle(color: C.muted))),
      const SizedBox(height: 16),
      row(Icons.edit, 'Edit profile & medical info', () => push(context, const EditProfileScreen())),
      row(Icons.favorite_border, 'Saved favourites', () => push(context, const FavoritesScreen())),
      row(Icons.notifications_none, 'Notifications', () => push(context, const NotificationsScreen())),
      row(Icons.tune, 'Notification settings', () => push(context, const NotificationSettingsScreen())),
      row(Icons.lock_outline, 'Change password', () => changePasswordDialog(context)),
      row(Icons.logout, 'Log out', () => s.logout()),
    ]);
  }
}
