import 'package:flutter_test/flutter_test.dart';
import 'package:massar/models/route.dart';

RouteStop _stop(String id, int cluster) => RouteStop(
      poiId: id,
      sequenceOrder: 0,
      clusterId: cluster,
      name: id,
      categoryKey: 'museum',
      lat: 36.78,
      lng: 3.06,
      dwellMinutes: 30,
      checkpointRadiusMeters: 30,
    );

/// An intra-cluster walk: stop to stop, so it carries both POI ids.
RouteSegment _walk(String from, String to, int cluster) => RouteSegment(
      mode: SegmentMode.walk,
      fromPoiId: from,
      toPoiId: to,
      clusterId: cluster,
      durationMinutes: 5,
      distanceMeters: 400,
      geometry: const [],
    );

/// An inter-cluster hop: anchor to anchor, so both POI ids are null. This is
/// the shape that made every drive disappear from the itinerary.
RouteSegment _interCluster(SegmentMode mode) => RouteSegment(
      mode: mode,
      fromPoiId: null,
      toPoiId: null,
      clusterId: null,
      durationMinutes: 12,
      distanceMeters: 3000,
      geometry: const [],
    );

GeneratedRoute _route(List<RouteStop> stops, List<RouteSegment> segments) =>
    GeneratedRoute(
      id: 'r1',
      cityId: 'c1',
      theme: 'history',
      timeBudgetMinutes: 480,
      transportMode: TransportMode.hybrid,
      stops: stops,
      segments: segments,
      estimatedTotalDurationMinutes: 200,
      dayCountFlag: 1,
    );

void main() {
  group('the leg leading into a stop', () {
    test('the first stop has none', () {
      final route = _route([_stop('a', 0)], const []);
      expect(route.legInto(0), isNull);
    });

    test('a drive is found even though it carries no POI ids', () {
      // The regression this exists for. Looking a leg up by `toPoiId` never
      // matched an inter-cluster hop, because both its ids are null by design —
      // so the itinerary rendered walks only, and a route that drove across the
      // city looked like one continuous stroll.
      final route = _route(
        [_stop('a', 0), _stop('b', 1)],
        [_interCluster(SegmentMode.drive)],
      );
      expect(route.legInto(1)?.mode, SegmentMode.drive);
    });

    test('a short inter-cluster hop reads as a walk and is still found', () {
      // Tagged walk by the walkable-hop rule, but still anchor-to-anchor with
      // null ids — the case that makes id-matching wrong for walks too.
      final route = _route(
        [_stop('a', 0), _stop('b', 1)],
        [_interCluster(SegmentMode.walk)],
      );
      expect(route.legInto(1)?.mode, SegmentMode.walk);
      expect(route.legInto(1)?.fromPoiId, isNull);
    });

    test('a mixed route maps every stop to the leg before it', () {
      // Two stops in cluster 0, a drive, then two in cluster 1 — the layout the
      // server emits: intra-cluster walks, then one hop per cluster boundary.
      final stops = [
        _stop('a', 0), _stop('b', 0), _stop('c', 1), _stop('d', 1),
      ];
      final segments = [
        _walk('a', 'b', 0),
        _interCluster(SegmentMode.drive),
        _walk('c', 'd', 1),
      ];
      final route = _route(stops, segments);

      expect(route.legInto(0), isNull);
      expect(route.legInto(1), same(segments[0]));
      expect(route.legInto(2), same(segments[1]));
      expect(route.legInto(3), same(segments[2]));
    });

    test('every leg after the first stop is reachable', () {
      // The count the server guarantees: one leg between each pair of stops.
      final stops = [for (var i = 0; i < 6; i++) _stop('s$i', i ~/ 2)];
      final segments = [for (var i = 0; i < 5; i++) _interCluster(SegmentMode.drive)];
      final route = _route(stops, segments);

      final found = [for (var i = 1; i < stops.length; i++) route.legInto(i)];
      expect(found.whereType<RouteSegment>().length, 5);
    });

    test('an out-of-range index is null rather than a crash', () {
      final route = _route([_stop('a', 0), _stop('b', 0)], [_walk('a', 'b', 0)]);
      expect(route.legInto(9), isNull);
      expect(route.legInto(-1), isNull);
    });

    test('a route whose segments went missing does not throw', () {
      // Degraded responses are a real state — the server drops to straight-line
      // legs when the provider is unavailable, and a client that crashes on a
      // short list turns a degraded route into no route.
      final route = _route([_stop('a', 0), _stop('b', 1)], const []);
      expect(route.legInto(1), isNull);
    });
  });
}
