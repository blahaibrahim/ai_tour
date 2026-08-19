import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massar/l10n/app_localizations.dart';
import 'package:massar/services/locale_controller.dart';

/// Guards the parts of localization that no screen test would notice.
///
/// A missing key does not break the build — gen-l10n falls back to English and
/// writes a line into `l10n_missing.txt` that nobody reads — so the drift shows
/// up as one English sentence in the middle of an Arabic screen. These tests
/// are what turn that into a red build instead.
void main() {
  Map<String, dynamic> readArb(String locale) => jsonDecode(
        File('lib/l10n/app_$locale.arb').readAsStringSync(),
      ) as Map<String, dynamic>;

  Set<String> messageKeys(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  group('the ARBs agree', () {
    final english = messageKeys(readArb('en'));

    test('English carries every string the app can show', () {
      // Sanity floor rather than an exact count, which would need updating on
      // every copy change and so would be edited out of meaning.
      expect(english.length, greaterThan(300));
    });

    for (final locale in ['fr', 'ar']) {
      test('$locale translates every English key, and invents none', () {
        final translated = messageKeys(readArb(locale));

        expect(
          english.difference(translated),
          isEmpty,
          reason: 'these keys would silently fall back to English',
        );
        expect(
          translated.difference(english),
          isEmpty,
          reason: 'these keys are translated but no longer exist in English',
        );
      });

      test('$locale keeps every value the message is passed', () {
        final source = readArb('en');
        final target = readArb(locale);

        for (final key in english) {
          // The declared placeholders are the authority — a regex over the
          // message body cannot tell `{version}` in "Massar v{version}" from
          // the `{jour}` of an ICU branch such as `one{jour}`.
          final meta = source['@$key'] as Map<String, dynamic>?;
          final declared =
              (meta?['placeholders'] as Map<String, dynamic>?)?.keys ?? const [];
          if (declared.isEmpty) continue;

          final translated = target[key] as String;
          final isPlural = translated.contains(', plural,');

          for (final name in declared) {
            // A plural may legitimately leave the count out of a branch —
            // Arabic's dual says "محطتان" without repeating the 2 — so only
            // non-plural messages are held to naming every value they get.
            if (isPlural) continue;
            expect(
              translated,
              contains('{$name}'),
              reason: '$key in $locale drops {$name}, so the value it was '
                  'given never reaches the traveller',
            );
          }
        }
      });
    }
  });

  group('loading a locale', () {
    test('each supported locale resolves its own strings', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final fr = await AppLocalizations.delegate.load(const Locale('fr'));
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));

      expect(en.settingsTitle, 'Settings');
      expect(fr.settingsTitle, 'Réglages');
      expect(ar.settingsTitle, 'الإعدادات');
    });

    test('Arabic uses its own plural categories, not English ones', () async {
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));

      // Arabic distinguishes two from few from many; English has only one and
      // other, so a translation that copied English shape would give the same
      // string for all of these.
      final forms = {
        ar.resultStopCount(1),
        ar.resultStopCount(2),
        ar.resultStopCount(3),
        ar.resultStopCount(11),
      };
      expect(forms.length, 4);
    });

    test('French agrees its singular and plural', () async {
      final fr = await AppLocalizations.delegate.load(const Locale('fr'));
      expect(fr.resultStopCount(1), '1 étape');
      expect(fr.resultStopCount(6), '6 étapes');
    });
  });

  group('the language preference', () {
    test('every supported locale has a name in its own script', () {
      for (final locale in AppLocalizations.supportedLocales) {
        expect(
          LocaleController.languageNames[locale.languageCode],
          isNotNull,
          reason: 'the picker would show a bare language code for this one',
        );
      }
    });

    test('an explicit choice is honoured over the device', () {
      expect(LocaleController.resolve(const Locale('ar')), const Locale('ar'));
    });

    test('following the device never lands on an unsupported language', () {
      // resolve(null) reads the platform locale, whatever the test host is set
      // to — the guarantee worth asserting is that it is always one we ship.
      expect(
        AppLocalizations.supportedLocales,
        contains(LocaleController.resolve(null)),
      );
    });
  });

  testWidgets('Arabic lays the app out right-to-left', (tester) async {
    late BuildContext captured;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox.shrink();
      }),
    ));

    // This is what GlobalWidgetsLocalizations buys, and the reason
    // flutter_localizations is a dependency rather than just the ARBs: every
    // Row, EdgeInsetsDirectional and Positioned in the app mirrors off it.
    expect(Directionality.of(captured), TextDirection.rtl);
    expect(AppLocalizations.of(captured).settingsTitle, 'الإعدادات');
  });

  testWidgets('French stays left-to-right', (tester) async {
    late BuildContext captured;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox.shrink();
      }),
    ));

    expect(Directionality.of(captured), TextDirection.ltr);
  });
}
