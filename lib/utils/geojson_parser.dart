import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class WilayaPolygon {
  final String id;
  final String name;
  final List<List<LatLng>> polygons;

  WilayaPolygon({required this.id, required this.name, required this.polygons});
}

List<WilayaPolygon>? _cachedWilayas;

Future<List<WilayaPolygon>> loadWilayasGeoJson() async {
  if (_cachedWilayas != null) return _cachedWilayas!;

  final String jsonString = await rootBundle.loadString('assets/dz_wilayas.geojson');
  final Map<String, dynamic> data = json.decode(jsonString);
  final List<WilayaPolygon> wilayas = [];

  for (final feature in data['features']) {
    final properties = feature['properties'];
    final geometry = feature['geometry'];
    
    if (geometry == null) continue;

    final String id = properties['code'].toString();
    final String name = properties['name'] ?? 'Unknown';
    
    final List<List<LatLng>> polygons = [];
    
    if (geometry['type'] == 'Polygon') {
      final List coords = geometry['coordinates'];
      if (coords.isNotEmpty) {
        final List ring = coords[0];
        polygons.add(ring.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList());
      }
    } else if (geometry['type'] == 'MultiPolygon') {
      final List multiCoords = geometry['coordinates'];
      for (final coords in multiCoords) {
        if (coords.isNotEmpty) {
          final List ring = coords[0];
          polygons.add(ring.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList());
        }
      }
    }
    
    wilayas.add(WilayaPolygon(id: id, name: name, polygons: polygons));
  }
  _cachedWilayas = wilayas;
  return wilayas;
}

bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
  bool isInside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i].longitude;
    final yi = polygon[i].latitude;
    final xj = polygon[j].longitude;
    final yj = polygon[j].latitude;

    final intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
    if (intersect) isInside = !isInside;
  }
  return isInside;
}
