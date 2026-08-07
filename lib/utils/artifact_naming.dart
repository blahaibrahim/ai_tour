import '../models/location.dart';
import '../models/location_data.dart';

/// Area label used when a capture happens away from any accepted stop.
const String kUnplacedArea = 'On the go';

/// Slugifies an area label for the `area_name_modelnum` convention:
/// "Algiers & the Casbah" -> "algiers_the_casbah".
String artifactAreaSlug(String area) {
  final slug = area
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'capture' : slug;
}

/// Builds the next name in the `area_name_modelnum` convention.
///
/// Numbering is per area and derived from the artifacts already in the folder.
/// Because the folder is rehydrated from Supabase at startup, that set includes
/// everything captured in previous sessions — so a second scan of the Casbah is
/// `algiers_the_casbah_2` whether or not the app was restarted in between.
String nextArtifactName(Iterable<Artifact> existing, String area) {
  final slug = artifactAreaSlug(area);
  final numbered = RegExp('^${RegExp.escape(slug)}_(\\d+)\$');

  var highest = 0;
  for (final artifact in existing) {
    final match = numbered.firstMatch(artifact.name);
    if (match == null) continue;
    final n = int.tryParse(match.group(1)!) ?? 0;
    if (n > highest) highest = n;
  }
  return '${slug}_${highest + 1}';
}

/// Recovers the display area from a name built by [nextArtifactName].
///
/// `artifacts.title` is the only free-text column on the row, so the area
/// travels to the server inside the name and is resolved back here rather than
/// being stored twice. Matching against the known region list keeps the
/// punctuation the slug threw away ("Tassili n'Ajjer / Sahara"); anything else
/// — a live-ingested region, or a stop name used as a fallback — degrades to a
/// readable title-cased form.
String artifactAreaLabel(String name) {
  final slug = name.replaceFirst(RegExp(r'_\d+$'), '');

  for (final area in [...regions, kUnplacedArea]) {
    if (artifactAreaSlug(area) == slug) return area;
  }

  final words = slug.split('_').where((w) => w.isNotEmpty);
  if (words.isEmpty) return kUnplacedArea;
  return words
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
