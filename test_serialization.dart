import 'dart:convert';
import 'lib/models/route.dart';
import 'lib/models/location.dart';

void main() {
  final stop = RouteStop(
    poiId: 'poi1',
    sequenceOrder: 1,
    clusterId: 1,
    name: 'Test Stop',
    categoryKey: 'park',
    lat: 1.0,
    lng: 1.0,
    dwellMinutes: 15,
    checkpointRadiusMeters: 40,
  );
  
  final route = GeneratedRoute(
    id: 'test-id',
    cityId: 'city1',
    theme: 'theme1',
    timeBudgetMinutes: 60,
    transportMode: TransportMode.walking,
    stops: [stop],
    segments: [],
    estimatedTotalDurationMinutes: 60,
    dayCountFlag: 1,
  );
  
  try {
    final jsonStr = jsonEncode(route.toJson());
    print('Encoded: $jsonStr');
    
    final decoded = jsonDecode(jsonStr);
    final restored = GeneratedRoute.fromJson(decoded);
    print('Restored: ${restored.id}');
  } catch (e, st) {
    print('Error: $e\n$st');
  }
}
