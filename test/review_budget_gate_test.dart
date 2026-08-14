import 'package:flutter_test/flutter_test.dart';
import 'package:massar/blocs/app/app_state.dart';
import 'package:massar/models/location.dart';
import 'package:massar/models/route.dart';

RouteStop _stop(String id, int dwell) => RouteStop(
      poiId: id,
      sequenceOrder: 0,
      clusterId: 0,
      name: id,
      categoryKey: 'museum',
      lat: 36.78,
      lng: 3.06,
      dwellMinutes: dwell,
      checkpointRadiusMeters: 30,
    );

Location _loc(String id, int dwell) => Location(
      id: id,
      name: id,
      region: 'Algiers',
      category: 'museum',
      distanceKm: 0,
      blurb: '',
      dwellMinutes: dwell,
      lat: 36.78,
      lng: 3.06,
      task: const Task(type: 'photo', label: ''),
    );

/// Four stops of 30 minutes' dwell and 40 minutes of travel between them, so
/// the route runs to 160 minutes and each stop costs 40 all in.
GeneratedRoute _route({List<RouteStop>? stops, int total = 160}) => GeneratedRoute(
      id: 'r1',
      cityId: 'c1',
      theme: 'history',
      timeBudgetMinutes: 480,
      transportMode: TransportMode.hybrid,
      stops: stops ?? [for (var i = 0; i < 4; i++) _stop('s$i', 30)],
      segments: const [],
      estimatedTotalDurationMinutes: total,
      dayCountFlag: 1,
    );

void main() {
  group('what the review has to clear', () {
    test('the bar is the route, not the raw budget', () {
      // A city whose catalogue cannot fill a day would otherwise leave the
      // traveller behind a button that can never enable — Constantine's
      // "culture" theme has one POI in it.
      final state = AppState(route: _route(), tripDays: 1, hoursPerDay: 8);
      expect(state.timeBudgetMinutes, 480);
      expect(state.requiredMinutes, 160);
    });

    test('a route longer than the budget is capped at the budget', () {
      final state = AppState(route: _route(total: 900), tripDays: 1, hoursPerDay: 8);
      expect(state.requiredMinutes, 480);
    });

    test('no route means nothing to clear', () {
      expect(const AppState().requiredMinutes, 0);
      expect(const AppState().budgetFilled, true);
    });
  });

  group('what has been kept', () {
    test('a kept stop counts its dwell plus its share of the travel', () {
      // 160 total − 120 dwell = 40 travel over 4 stops = 10 each.
      final state = AppState(route: _route(), accepted: [_loc('s0', 30)]);
      expect(state.acceptedMinutes, 40);
    });

    test('keeping everything clears the bar', () {
      final state = AppState(
        route: _route(),
        accepted: [for (var i = 0; i < 4; i++) _loc('s$i', 30)],
      );
      expect(state.acceptedMinutes, 160);
      expect(state.budgetFilled, true);
    });

    test('keeping half does not', () {
      final state = AppState(route: _route(), accepted: [_loc('s0', 30), _loc('s1', 30)]);
      expect(state.budgetFilled, false);
    });

    test('rejecting everything leaves nothing', () {
      final state = AppState(route: _route(), accepted: const []);
      expect(state.acceptedMinutes, 0);
      expect(state.budgetFilled, false);
    });
  });

  group('removing a stop later', () {
    test('a full route can spare one', () {
      // 160 − 30 − 10 = 120, still at or above what a 120-minute bar needs.
      final state = AppState(route: _route(total: 160), tripDays: 1, hoursPerDay: 2);
      expect(state.requiredMinutes, 120);
      expect(state.canRemoveStop(30), true);
    });

    test('a route already at the bar cannot', () {
      // The route is exactly the bar, so anything removed drops below it.
      final state = AppState(route: _route(total: 160), tripDays: 1, hoursPerDay: 8);
      expect(state.requiredMinutes, 160);
      expect(state.canRemoveStop(30), false);
    });

    test('the last stop is never removable', () {
      final state = AppState(route: _route(stops: [_stop('only', 30)], total: 30));
      expect(state.canRemoveStop(30), false);
    });
  });

  group('are there more to offer', () {
    test('an undrawn deck counts', () {
      final state = AppState(route: _route(), queue: [_loc('a', 30)], currentIndex: 0);
      expect(state.hasMoreCandidates, true);
    });

    test('held-back alternates count', () {
      final route = _route();
      final withAlternates = route.copyWithAlternates([_stop('alt', 30)]);
      final state = AppState(route: withAlternates, queue: const [], currentIndex: 0);
      expect(state.hasMoreCandidates, true);
    });

    test('an empty deck with no alternates has nothing left', () {
      final state = AppState(
        route: _route(),
        queue: [_loc('a', 30)],
        currentIndex: 1,
      );
      expect(state.hasMoreCandidates, false);
    });
  });
}
