import 'dart:math';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:massar/models/quest_type.dart';
import 'package:massar/l10n/app_localizations.dart';

void main() {
  // The English strings, loaded once. These tests assert on wording, so they
  // need the same lookup the app uses rather than the literals that used to be
  // baked into the models.
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('quest types', () {
    test('the vocabulary is photo, video and the fennec hunt', () {
      // 3D scan is deliberately absent — it stays a capture mode people can
      // choose, but it is a poor thing to be assigned. See quest_type.dart.
      expect(kQuestTypes, ['photo', 'video', 'mascot']);
    });

    test('an opening quest is always one of the three', () {
      final random = Random(1);
      for (var i = 0; i < 200; i++) {
        expect(kQuestTypes, contains(initialQuestType(random: random)));
      }
    });

    test('opening quests are not all the same type', () {
      // The point of randomising: a route whose every stop asks for a photo is
      // a route people stop doing by the third stop.
      final random = Random(7);
      final drawn = {for (var i = 0; i < 60; i++) initialQuestType(random: random)};
      expect(drawn.length, greaterThan(1));
    });
  });

  group('no do-overs', () {
    test('a regenerated quest is never one already offered here', () {
      final random = Random(3);
      for (final start in kQuestTypes) {
        final offered = <String>{start};

        // Two swaps are available with three types, and neither may repeat.
        final second = nextQuestType(offered, random: random);
        expect(second, isNotNull);
        expect(second, isNot(start));
        offered.add(second!);

        final third = nextQuestType(offered, random: random);
        expect(third, isNotNull);
        expect(offered, isNot(contains(third)));
        offered.add(third!);

        expect(offered, containsAll(kQuestTypes));
      }
    });

    test('starting on the fennec hunt means never being offered it again', () {
      // The case named in the requirement.
      final offered = <String>{'mascot'};
      for (var i = 0; i < 2; i++) {
        final next = nextQuestType(offered, random: Random(i));
        expect(next, isNot('mascot'));
        offered.add(next!);
      }
    });

    test('a stop that has shown everything has nothing left to offer', () {
      // Null rather than a repeat: the caller hides the control instead of
      // handing back something already refused.
      expect(nextQuestType(kQuestTypes.toSet()), isNull);
    });
  });

  group('labels', () {
    test('every type has a label', () {
      for (final type in kQuestTypes) {
        expect(questLabel(l10n, type), isNotEmpty);
      }
    });

    test('the seed varies the wording across stops', () {
      final wordings = {
        for (var i = 0; i < 6; i++) questLabel(l10n, 'photo', seed: i),
      };
      expect(wordings.length, greaterThan(1));
    });

    test('a negative seed does not throw', () {
      // seed is a stop index plus an offered-count, but nothing guarantees the
      // caller passes a positive one.
      expect(() => questLabel(l10n, 'photo', seed: -3), returnsNormally);
    });

    test('an unknown type still yields a usable label', () {
      // A session restored from before this vocabulary existed can carry
      // 'scan'; it must render, not crash.
      expect(questLabel(l10n, 'scan'), isNotEmpty);
    });
  });
}
