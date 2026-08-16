import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:massar/blocs/app/app_bloc.dart';
import 'package:massar/blocs/app/app_event.dart';

/// Wilaya selection is single-select for now.
///
/// Worth pinning down in a test rather than leaving to the reducer, because the
/// restriction is a product decision that the *type* does not express — the
/// state is still a `Set`, so nothing but these tests stops a future handler
/// from quietly letting a second wilaya in and reintroducing a selection the
/// route request cannot honour. When multi-wilaya routing lands, these are the
/// tests to delete, and their failure is the reminder to do it deliberately.
void main() {
  late AppBloc bloc;

  // Constructing an AppBloc drags in the whole app's boot sequence: it reads
  // AppConfig (dotenv), arms a realtime subscription and starts watching auth
  // (Supabase). None of that matters to wilaya selection, but all of it has to
  // exist or the constructor throws. Stubs are enough — the URL is never
  // reached, since with no signed-in user the subscription returns immediately
  // and the load events this fires fail into their own catch blocks.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.testLoad(fileInput: '');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-publishable-key',
      debug: false,
    );
  });

  setUp(() => bloc = AppBloc());
  tearDown(() => bloc.close());

  /// Dispatches an event and lets the reducer run.
  ///
  /// Asserts against `bloc.state` rather than the next stream emission on
  /// purpose: the constructor fires five load events of its own, so "the next
  /// state" is usually one of those settling and has nothing to do with the
  /// event under test. None of them touch the wilaya selection, which is what
  /// makes reading the settled state the stable check.
  Future<void> dispatch(AppEvent event) async {
    bloc.add(event);
    await Future<void>.delayed(Duration.zero);
  }

  group('tapping a wilaya on the map', () {
    test('selects it when nothing is selected', () async {
      await dispatch(const ToggleWilayaEvent('16'));

      expect(bloc.state.selectedWilayas, {'16'});
    });

    test('replaces the selection rather than adding to it', () async {
      await dispatch(const ToggleWilayaEvent('16'));
      await dispatch(const ToggleWilayaEvent('31'));

      expect(bloc.state.selectedWilayas, {'31'});
    });

    test('never accumulates, however many are tapped', () async {
      for (final id in ['16', '31', '25', '09']) {
        await dispatch(ToggleWilayaEvent(id));
        expect(bloc.state.selectedWilayas, hasLength(lessThanOrEqualTo(1)));
      }

      expect(bloc.state.selectedWilayas, {'09'});
    });

    test('clears the selection when the selected one is tapped again', () async {
      await dispatch(const ToggleWilayaEvent('16'));
      await dispatch(const ToggleWilayaEvent('16'));

      expect(bloc.state.selectedWilayas, isEmpty);
    });
  });

  group('choosing a wilaya from search', () {
    test('selects it', () async {
      await dispatch(const SelectWilayaEvent('31'));

      expect(bloc.state.selectedWilayas, {'31'});
    });

    test('replaces a different selection', () async {
      await dispatch(const ToggleWilayaEvent('16'));
      await dispatch(const SelectWilayaEvent('31'));

      expect(bloc.state.selectedWilayas, {'31'});
    });

    // The reason SelectWilayaEvent exists at all: searching for the wilaya you
    // already have selected must not toggle it off underneath you.
    test('is idempotent for the already-selected wilaya', () async {
      await dispatch(const SelectWilayaEvent('31'));
      await dispatch(const SelectWilayaEvent('31'));

      expect(bloc.state.selectedWilayas, {'31'});
    });
  });
}
