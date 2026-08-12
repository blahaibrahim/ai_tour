import 'package:shared_preferences/shared_preferences.dart';

/// Whether the first-run intro has already been shown.
///
/// Deliberately local rather than a column on the user's row: the intro
/// explains the app, not the account. It should not reappear because the
/// traveller signed out, and it *should* appear on a fresh install even for
/// someone who already has an account — which is exactly what a device-local
/// flag gives and a server-side one does not.
class OnboardingRepository {
  static const String _kIntroSeenKey = 'massar_onboarding_seen';

  /// False on a fresh install, and on any device where the read fails — the
  /// intro is cheap to show and expensive to wrongly skip.
  static Future<bool> hasSeenIntro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kIntroSeenKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Written when the traveller reaches the end of the flow *or* skips it —
  /// skipping is an answer ("I don't want this"), not a postponement.
  static Future<void> markIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIntroSeenKey, true);
  }

  /// Used by the Settings "Replay intro" entry, which re-runs the flow without
  /// clearing the rest of the app's data.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kIntroSeenKey);
  }
}
