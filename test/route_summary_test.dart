import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:massar/models/route.dart';
import 'package:massar/l10n/app_localizations.dart';

/// The home screen's history crosses a language boundary: the row is built in
/// `routeRepository.ts`, serialized by `serializeRouteSummary` in `routes.ts`,
/// and read here. The wire is snake_case, like every other route payload, and a
/// silent drift to camelCase would show up as a list of blank cards rather than
/// as an error — which is exactly the kind of failure worth a test.
void main() {
  // The English strings, loaded once. These tests assert on wording, so they
  // need the same lookup the app uses rather than the literals that used to be
  // baked into the models.
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('reading a summary off the wire', () {
    test('parses the shape serializeRouteSummary actually sends', () {
      final summary = RouteSummary.fromJson(const {
        'id': '9af75011-cabf-44a3-9690-7769ab53c633',
        'city_id': '00000000-0000-4000-a000-000000000010',
        'city_name': 'Algiers',
        'theme': 'history',
        'transport_mode': 'hybrid',
        'time_budget_minutes': 480,
        'estimated_total_duration_minutes': 393,
        'day_count_flag': 1,
        'stop_count': 9,
        'generated_at': '2026-08-17T09:30:00Z',
      });

      expect(summary.id, '9af75011-cabf-44a3-9690-7769ab53c633');
      expect(summary.cityName, 'Algiers');
      expect(summary.transportMode, TransportMode.hybrid);
      expect(summary.stopCount, 9);
      expect(summary.estimatedTotalDurationMinutes, 393);
      expect(summary.generatedAt, isNotNull);
    });

    test('a missing city name falls back to the theme, never to a uuid', () {
      // The city can leave the catalogue after a route was generated against
      // it. Printing `00000000-0000-…` at a traveller is the one outcome the
      // card must not have.
      final summary = RouteSummary.fromJson(const {
        'id': 'r1',
        'city_id': '00000000-0000-4000-a000-000000000010',
        'city_name': null,
        'theme': 'history',
        'transport_mode': 'walking',
        'stop_count': 3,
        'estimated_total_duration_minutes': 90,
      });

      expect(summary.title(l10n), 'History');
      expect(summary.title(l10n), isNot(contains('0000')));
    });

    test('with neither a city nor a theme it still says something', () {
      final summary = RouteSummary.fromJson(const {
        'id': 'r2',
        'city_id': '',
        'theme': '',
        'transport_mode': 'driving',
        'stop_count': 0,
        'estimated_total_duration_minutes': 0,
      });

      expect(summary.title(l10n), 'Route');
    });

    test('an unknown transport mode reads as hybrid', () {
      // Same rule the rest of the route model follows: hybrid is the mode that
      // renders correctly whatever the legs turn out to be.
      final summary = RouteSummary.fromJson(const {
        'id': 'r3',
        'city_id': 'c',
        'theme': 'food',
        'transport_mode': 'teleport',
        'stop_count': 1,
        'estimated_total_duration_minutes': 30,
      });

      expect(summary.transportMode, TransportMode.hybrid);
    });
  });

  group('the line under the title', () {
    RouteSummary make({required int stops, required int minutes}) => RouteSummary(
          id: 'r',
          cityId: 'c',
          theme: 'history',
          transportMode: TransportMode.walking,
          stopCount: stops,
          estimatedTotalDurationMinutes: minutes,
        );

    test('counts stops, time and mode', () {
      expect(make(stops: 6, minutes: 240).subtitle(l10n), '6 stops · 4h · Walking');
    });

    test('one stop is singular', () {
      expect(make(stops: 1, minutes: 45).subtitle(l10n), '1 stop · 45 min · Walking');
    });

    test('an odd duration keeps its minutes', () {
      expect(make(stops: 2, minutes: 95).subtitle(l10n), contains('1h 35m'));
    });
  });
}
