import 'dart:math';

/// The three things a stop can ask a traveller to do.
///
/// One per stop, drawn at random when the route is accepted, and never the
/// same one twice at the same stop — see [nextQuestType].
///
/// **3D scan is deliberately not here.** It is still a capture mode people can
/// choose for themselves, but it is a poor thing to be *assigned*: it needs a
/// single well-lit object with space to walk around it, which most stops on a
/// heritage route do not offer, and it spends a GPU generation credit whether
/// or not the result is any good. Photo, video and the fennec hunt can be done
/// anywhere the traveller is standing.
const List<String> kQuestTypes = ['photo', 'video', 'mascot'];

/// Labels for each type, written to be true wherever the traveller is standing.
///
/// Several per type so the same wording does not appear at every stop of a
/// route — the variety is cosmetic, but a list of eleven identical instructions
/// reads as a bug in the generator.
const Map<String, List<String>> _questLabels = {
  'photo': [
    'Take a photo that shows why this place is worth stopping at.',
    'Frame one detail here that a passing tourist would miss.',
    'Photograph this stop the way you would describe it to someone.',
  ],
  'video': [
    'Hold the shutter and film a slow pan across this place.',
    'Film a short clip walking up to it — hold the shutter to record.',
    'Hold the shutter for a few seconds of this place with its sound.',
  ],
  'mascot': [
    'A fennec is hiding somewhere here — find it and photograph it.',
    'There is a fennec nearby. Follow the signal and catch it.',
    'Hunt down the fennec hiding at this stop.',
  ],
};

/// A label for [type], varied by [seed] so neighbouring stops read differently.
String questLabel(String type, {int seed = 0}) {
  final options = _questLabels[type] ?? _questLabels['photo']!;
  return options[seed.abs() % options.length];
}

/// Picks a quest type, never one already used at this stop.
///
/// Returns null when every type has been offered — which is what "no do-overs"
/// means in practice: with three types a traveller can regenerate twice, and
/// the third press has nothing honest left to give. The caller disables the
/// control rather than handing back something already refused.
String? nextQuestType(Set<String> alreadyOffered, {Random? random}) {
  final remaining = kQuestTypes.where((t) => !alreadyOffered.contains(t)).toList();
  if (remaining.isEmpty) return null;
  return remaining[(random ?? Random()).nextInt(remaining.length)];
}

/// The opening quest for a stop. Uniform across the three types.
String initialQuestType({Random? random}) =>
    kQuestTypes[(random ?? Random()).nextInt(kQuestTypes.length)];
