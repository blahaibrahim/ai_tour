import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// Which language the app is drawn in, and the device-local memory of it.
///
/// Modelled on [NotificationService]: a singleton holding a [ValueNotifier] the
/// widget tree listens to, which also owns its own persistence. The alternative
/// — a field on [AppState] — would have tied the language to the bloc that
/// owns the *tour*, and the language outlives any one tour.
///
/// A null [locale] means "follow the device", which is the default and what
/// most travellers want: someone whose phone is in French should not have to
/// find a setting to be spoken to in French. Choosing a language explicitly
/// pins it, and that choice survives reinstalling a route, signing out, and
/// restarting the app.
class LocaleController {
  LocaleController._();

  static final LocaleController instance = LocaleController._();

  static const String _kLocaleKey = 'massar_locale';

  /// `null` = follow the device locale.
  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  /// Read before `runApp` so the first frame is already in the right language —
  /// reading it after would paint one frame of English and then swap, which is
  /// exactly the flicker a returning Arabic speaker would notice most, because
  /// the whole layout mirrors when it lands.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_kLocaleKey);
      if (code == null || code.isEmpty) return;
      // A code that is no longer supported (a language removed in a later
      // build) falls back to following the device rather than to a locale with
      // no translations behind it.
      if (AppLocalizations.supportedLocales
          .any((l) => l.languageCode == code)) {
        locale.value = Locale(code);
      }
    } catch (_) {
      // Follow the device. A preference that cannot be read is not worth
      // failing startup over.
    }
  }

  /// Pass `null` to go back to following the device.
  Future<void> setLocale(Locale? value) async {
    if (locale.value == value) return;
    locale.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_kLocaleKey);
      } else {
        await prefs.setString(_kLocaleKey, value.languageCode);
      }
    } catch (_) {
      // The language still changed for this run; only the memory of it failed.
    }
  }

  /// What each language calls itself.
  ///
  /// Endonyms, deliberately: a picker that lists "Arabic" in French is no use
  /// to the person looking for العربية, and someone who has landed in a
  /// language they cannot read needs to find their own by sight. This is why
  /// these live here rather than in the ARBs — they are the same in every
  /// translation, so translating them would be three copies of one truth.
  static const Map<String, String> languageNames = {
    'en': 'English',
    'fr': 'Français',
    'ar': 'العربية',
  };

  /// The app's strings, for code that has no `BuildContext` to look them up
  /// through — the notification service, which also runs in a background
  /// isolate where no widget tree exists at all.
  ///
  /// Re-reads the stored preference each time rather than trusting [locale]:
  /// in a background isolate this singleton is a fresh instance that has never
  /// had [load] called on it, so its notifier would still be sitting on null.
  static Future<AppLocalizations> localizations() async {
    await instance.load();
    return AppLocalizations.delegate.load(resolve(instance.locale.value));
  }

  /// The locale the app will actually draw in, given a stored preference of
  /// [explicit] (null = follow the device).
  ///
  /// This mirrors what MaterialApp resolves internally, but the theme needs the
  /// answer *before* MaterialApp exists — Arabic changes the typefaces, so
  /// `themeFor` has to be handed a concrete locale rather than a null.
  static Locale resolve(Locale? explicit) {
    if (explicit != null) return explicit;
    for (final deviceLocale in WidgetsBinding.instance.platformDispatcher.locales) {
      for (final supported in AppLocalizations.supportedLocales) {
        if (supported.languageCode == deviceLocale.languageCode) return supported;
      }
    }
    // English: the source language, and the only one guaranteed complete.
    return const Locale('en');
  }
}
