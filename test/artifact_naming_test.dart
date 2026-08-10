import 'package:flutter_test/flutter_test.dart';

import 'package:massar/models/location.dart';
import 'package:massar/utils/artifact_naming.dart';

Artifact named(String name) =>
    Artifact(id: name, name: name, region: '', kindLabel: '3D Model', photoUrl: '');

void main() {
  group('artifactAreaSlug', () {
    test('collapses punctuation and spacing into single underscores', () {
      expect(artifactAreaSlug('Algiers & the Casbah'), 'algiers_the_casbah');
      expect(artifactAreaSlug("Tassili n'Ajjer / Sahara"), 'tassili_n_ajjer_sahara');
      expect(artifactAreaSlug('Constantine'), 'constantine');
    });

    test('never yields an empty or edge-underscored slug', () {
      expect(artifactAreaSlug('  '), 'capture');
      expect(artifactAreaSlug('!!!'), 'capture');
      expect(artifactAreaSlug(' Djemila & Timgad '), 'djemila_timgad');
    });
  });

  group('nextArtifactName', () {
    test('starts at 1 for an area with nothing in it', () {
      expect(nextArtifactName(const [], 'Constantine'), 'constantine_1');
    });

    test('numbers per area, not across the whole folder', () {
      final folder = [
        named('constantine_1'),
        named('constantine_2'),
        named('algiers_the_casbah_1'),
      ];
      expect(nextArtifactName(folder, 'Constantine'), 'constantine_3');
      expect(nextArtifactName(folder, 'Algiers & the Casbah'), 'algiers_the_casbah_2');
      expect(nextArtifactName(folder, 'Djemila & Timgad'), 'djemila_timgad_1');
    });

    test('continues from the highest number, not the count', () {
      // A deleted middle entry must not hand out a name that is already taken.
      final folder = [named('constantine_1'), named('constantine_7')];
      expect(nextArtifactName(folder, 'Constantine'), 'constantine_8');
    });

    test('is not confused by an area whose slug prefixes another', () {
      final folder = [named('constantine_bridge_4')];
      expect(nextArtifactName(folder, 'Constantine'), 'constantine_1');
    });

    test('ignores legacy names that predate the convention', () {
      final folder = [named('Your scan'), named('Casbah of Algiers')];
      expect(nextArtifactName(folder, 'Algiers & the Casbah'), 'algiers_the_casbah_1');
    });
  });

  group('artifactAreaLabel', () {
    test('recovers the punctuation of a known region', () {
      expect(artifactAreaLabel('algiers_the_casbah_2'), 'Algiers & the Casbah');
      expect(artifactAreaLabel('tassili_n_ajjer_sahara_1'), "Tassili n'Ajjer / Sahara");
      expect(artifactAreaLabel('on_the_go_3'), kUnplacedArea);
    });

    test('title-cases an area it does not know', () {
      expect(artifactAreaLabel('roman_theatre_1'), 'Roman Theatre');
    });

    test('round-trips every known region', () {
      for (final area in [
        'Algiers & the Casbah',
        'Constantine',
        'Djemila & Timgad',
        "Tassili n'Ajjer / Sahara",
        'Kabylie mountains & coast',
        kUnplacedArea,
      ]) {
        expect(artifactAreaLabel(nextArtifactName(const [], area)), area);
      }
    });
  });
}
