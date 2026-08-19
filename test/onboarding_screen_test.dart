import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massar/screens/onboarding/onboarding_content.dart';
import 'package:massar/screens/onboarding/onboarding_screen.dart';
import 'package:massar/l10n/app_localizations.dart';

/// Covers the two ways out of the intro and the way through it.
///
/// The default `MaterialApp` theme is used rather than `AppTheme.theme`,
/// because the latter resolves Google Fonts over the network — which a test
/// has no business doing, and which fails in CI.
void main() {
  // The English strings, loaded once. These tests assert on wording, so they
  // need the same lookup the app uses rather than the literals that used to be
  // baked into the models.
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Future<int> pumpFlow(WidgetTester tester) async {
    var finishCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        // The delegates are what make AppLocalizations.of resolvable — the
        // intro's copy is looked up rather than held in the page list now.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingScreen(onFinish: () => finishCount++),
      ),
    );
    // Lets the staggered entrance settle so the text is actually laid out.
    await tester.pumpAndSettle();
    return finishCount;
  }

  testWidgets('opens on the first page with a skip out of it', (tester) async {
    await pumpFlow(tester);

    expect(find.text(onboardingPages.first.title(l10n)), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    // Nothing to go back to yet.
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(
      tester.widget<IgnorePointer>(
        find.ancestor(
          of: find.byIcon(Icons.arrow_back_rounded),
          matching: find.byType(IgnorePointer),
        ).first,
      ).ignoring,
      isTrue,
    );
  });

  testWidgets('Next walks to the last page, which finishes', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingScreen(onFinish: () => finished++),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < onboardingPages.length - 1; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    expect(find.text(onboardingPages.last.title(l10n)), findsOneWidget);
    // The last page trades Skip for the primary call to action.
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('Skip finishes from the first page', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingScreen(onFinish: () => finished++),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('back returns to the previous page', (tester) async {
    await pumpFlow(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text(onboardingPages[1].title(l10n)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text(onboardingPages.first.title(l10n)), findsOneWidget);
  });

  testWidgets('finishing twice only reports once', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingScreen(onFinish: () => finished++),
      ),
    );
    await tester.pumpAndSettle();

    final skip = find.text('Skip');
    await tester.tap(skip);
    await tester.tap(skip);
    await tester.pumpAndSettle();

    expect(finished, 1);
  });
}
