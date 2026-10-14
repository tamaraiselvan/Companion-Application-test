import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Default map centre (Chennai) when the device location is unavailable.
const fallbackCenter = LatLng(13.0827, 80.2707);

/// Asks for permission if needed and returns the current position, or null if denied/unavailable.
Future<LatLng?> currentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}

/// Position updates every [meters] of movement (used by partners to share live location).
Stream<LatLng> positionStream({int meters = 20}) => Geolocator.getPositionStream(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: meters))
    .map((p) => LatLng(p.latitude, p.longitude));

LatLng? latLngOf(Map? m, [String lat = 'lat', String lng = 'lng']) =>
    m == null || m[lat] == null || m[lng] == null ? null : LatLng((m[lat] as num).toDouble(), (m[lng] as num).toDouble());
