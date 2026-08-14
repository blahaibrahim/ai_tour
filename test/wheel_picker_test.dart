import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massar/screens/map/widgets/time_budget_picker.dart';

/// Mounts one wheel with its own value, the way the panel does, and hands back
/// a reader for whatever the wheel has most recently reported.
Future<int Function()> _pump(
  WidgetTester tester, {
  required List<int> values,
  required int initial,
}) async {
  var current = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: SizedBox(
            height: 120,
            child: WheelPicker(
              values: values,
              selected: current,
              unit: (v) => v == 1 ? 'day' : 'days',
              semanticLabel: 'Trip length',
              onChanged: (v) => setState(() => current = v),
            ),
          ),
        ),
      ),
    ),
  );
  return () => current;
}

void main() {
  group('nearestIndex', () {
    test('finds an exact value', () {
      expect(nearestIndex([2, 4, 6, 8], 6), 2);
    });

    test('snaps a value the wheel no longer offers', () {
      // A restored session can carry a budget from an older options list. -1
      // from indexOf would scroll the wheel off its own top.
      expect(nearestIndex([2, 4, 6, 8], 5), anyOf(1, 2));
      expect(nearestIndex([2, 4, 6, 8], 99), 3);
      expect(nearestIndex([2, 4, 6, 8], 0), 0);
    });

    test('an empty list does not throw', () {
      expect(nearestIndex(const [], 3), 0);
    });
  });

  group('the wheel', () {
    testWidgets('opens on the selected value', (tester) async {
      await _pump(tester, values: const [1, 2, 3, 4], initial: 3);
      await tester.pumpAndSettle();

      // The unit is rendered once, beside the wheel, from the selected value.
      expect(find.text('days'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('spinning it changes the value', (tester) async {
      final read = await _pump(tester, values: const [1, 2, 3, 4], initial: 1);
      await tester.pumpAndSettle();
      expect(read(), 1);

      // Dragging up moves down the list, the way a physical drum does.
      await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -70));
      await tester.pumpAndSettle();

      expect(read(), greaterThan(1));
    });

    testWidgets('it cannot be spun past either end', (tester) async {
      final read = await _pump(tester, values: const [1, 2, 3, 4], initial: 1);
      await tester.pumpAndSettle();

      // Far further than the list is long, in both directions.
      await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(read(), 4);

      await tester.drag(find.byType(ListWheelScrollView), const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(read(), 1);
    });

    testWidgets('the singular unit is used for one', (tester) async {
      await _pump(tester, values: const [1, 2, 3, 4], initial: 1);
      await tester.pumpAndSettle();
      expect(find.text('day'), findsOneWidget);
      expect(find.text('days'), findsNothing);
    });

    testWidgets('it follows a value changed from outside', (tester) async {
      // A restored session sets the value without touching the wheel; the
      // wheel has to catch up or it shows one number while the request carries
      // another.
      var selected = 1;
      late StateSetter setOuter;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return Scaffold(
                body: SizedBox(
                  height: 120,
                  child: WheelPicker(
                    values: const [1, 2, 3, 4],
                    selected: selected,
                    unit: (_) => 'days',
                    semanticLabel: 'Trip length',
                    onChanged: (v) => selected = v,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      setOuter(() => selected = 4);
      await tester.pumpAndSettle();

      final wheel = tester.widget<ListWheelScrollView>(find.byType(ListWheelScrollView));
      expect((wheel.controller as FixedExtentScrollController?)?.selectedItem, 3);
    });
  });
}
