import 'dart:math';
import '../l10n/app_localizations.dart';

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
///
/// Resolved from the ARBs at read time rather than stored on the task: a route
/// planned in French and walked after switching to Arabic should read in
/// Arabic, which a string baked in at generation time could not do.
List<String> _questLabels(AppLocalizations l10n, String type) => switch (type) {
      'video' => [l10n.questVideo1, l10n.questVideo2, l10n.questVideo3],
      'mascot' => [l10n.questMascot1, l10n.questMascot2, l10n.questMascot3],
      // Photo is also the fallback for any type the server invents that this
      // build does not know about — a generic "take a picture" is a better
      // thing to show than an empty row.
      _ => [l10n.questPhoto1, l10n.questPhoto2, l10n.questPhoto3],
    };

/// A label for [type], varied by [seed] so neighbouring stops read differently.
String questLabel(AppLocalizations l10n, String type, {int seed = 0}) {
  final options = _questLabels(l10n, type);
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
