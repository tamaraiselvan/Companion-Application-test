import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../location.dart';
import '../widgets.dart';

/// Map tiles. OpenStreetMap's public server is for light/demo use only — for production set
/// MAP_TILE_URL to a provider you have a plan with (MapTiler, Stadia, Mapbox, self-hosted…).
const tileUrl = String.fromEnvironment('MAP_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

TileLayer tiles() => TileLayer(urlTemplate: tileUrl, userAgentPackageName: 'app.dayfello.dayfello', maxZoom: 19);

Marker pin(LatLng p, {Color color = C.coral, IconData icon = Icons.location_on, double size = 40, VoidCallback? onTap}) => Marker(
      point: p,
      width: size,
      height: size,
      alignment: Alignment.topCenter,
      child: GestureDetector(onTap: onTap, child: Icon(icon, color: color, size: size)),
    );

Marker dot(LatLng p, Color color, {String? label}) => Marker(
      point: p,
      width: 44,
      height: 44,
      child: Container(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)]),
        alignment: Alignment.center,
        child: Text(label ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );

const _attribution = RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]);

/// Booking map: companion live position, service address and the straight-line route between them.
class LiveMap extends StatefulWidget {
  final LatLng? companion, destination;
  final String companionLabel;
  final double height;
  const LiveMap({super.key, this.companion, this.destination, this.companionLabel = '', this.height = 240});
  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  final ctrl = MapController();
  bool ready = false;

  void _fit() {
    final pts = [widget.companion, widget.destination].whereType<LatLng>().toList();
    if (!ready || pts.isEmpty) return;
    if (pts.length == 1) {
      ctrl.move(pts.first, 15);
      return;
    }
    ctrl.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(48), maxZoom: 16));
  }

  @override
  void didUpdateWidget(LiveMap old) {
    super.didUpdateWidget(old);
    if (old.companion != widget.companion || old.destination != widget.destination) _fit();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: widget.height,
          child: FlutterMap(
            mapController: ctrl,
            options: MapOptions(
              initialCenter: widget.companion ?? widget.destination ?? fallbackCenter,
              initialZoom: 14,
              onMapReady: () {
                ready = true;
                _fit();
              },
            ),
            children: [
              tiles(),
              if (widget.companion != null && widget.destination != null)
                PolylineLayer(polylines: [
                  Polyline(points: [widget.companion!, widget.destination!], color: C.coral, strokeWidth: 4, pattern: StrokePattern.dashed(segments: const [10, 8])),
                ]),
              MarkerLayer(markers: [
                if (widget.destination != null) pin(widget.destination!, color: C.danger, icon: Icons.home_rounded, size: 36),
                if (widget.companion != null) dot(widget.companion!, C.ink, label: initials(widget.companionLabel)),
              ]),
              _attribution,
            ],
          ),
        ),
      );
}

/// Full-screen picker: tap or drag the map to place the service address pin.
class LocationPicker extends StatefulWidget {
  final LatLng? initial;
  const LocationPicker({super.key, this.initial});
  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final ctrl = MapController();
  late LatLng picked = widget.initial ?? fallbackCenter;

  Future<void> _locateMe() async {
    final me = await currentLocation();
    if (me == null) {
      if (mounted) toast(context, 'Location unavailable — check permissions');
      return;
    }
    setState(() => picked = me);
    ctrl.move(me, 16);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) _locateMe();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Pick service location')),
        body: Stack(children: [
          FlutterMap(
            mapController: ctrl,
            options: MapOptions(
              initialCenter: picked,
              initialZoom: 15,
              onTap: (_, p) => setState(() => picked = p),
              onPositionChanged: (cam, byUser) {
                if (byUser) setState(() => picked = cam.center);
              },
            ),
            children: [tiles(), MarkerLayer(markers: [pin(picked, size: 44)]), _attribution],
          ),
          Positioned(
            right: 16,
            bottom: 96,
            child: FloatingActionButton.small(heroTag: 'me', onPressed: _locateMe, child: const Icon(Icons.my_location)),
          ),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
                onPressed: () => Navigator.pop(context, picked),
                child: Text('Use this location (${picked.latitude.toStringAsFixed(4)}, ${picked.longitude.toStringAsFixed(4)})')),
          ),
        ),
      );
}

/// Companions plotted on a map; tapping a marker shows a card that opens the profile.
class CompanionsMap extends StatefulWidget {
  final List companions;
  final LatLng? me;
  final void Function(Map c) onOpen;
  const CompanionsMap({super.key, required this.companions, this.me, required this.onOpen});
  @override
  State<CompanionsMap> createState() => _CompanionsMapState();
}

class _CompanionsMapState extends State<CompanionsMap> {
  Map? selected;
  @override
  Widget build(BuildContext context) {
    final withLoc = widget.companions.where((c) => c['lat'] != null).toList();
    return Stack(children: [
      FlutterMap(
        options: MapOptions(initialCenter: widget.me ?? latLngOf(withLoc.isEmpty ? null : withLoc.first) ?? fallbackCenter, initialZoom: 13),
        children: [
          tiles(),
          MarkerLayer(markers: [
            if (widget.me != null) dot(widget.me!, Colors.blue),
            for (final c in withLoc) pin(latLngOf(c)!, color: hex(c['color']), onTap: () => setState(() => selected = c)),
          ]),
          _attribution,
        ],
      ),
      if (selected != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Card(
            child: ListTile(
              leading: Avatar(selected!['name'], color: selected!['color']),
              title: Text(selected!['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${selected!['service_name']} · ${selected!['distance_km']} km · ⭐ ${selected!['rating']}'),
              trailing: FilledButton(onPressed: () => widget.onOpen(selected!), child: const Text('View')),
            ),
          ),
        ),
    ]);
  }
}
