import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_screen.dart';
import '../../repositories/notification_repository.dart';
import '../../services/locale_controller.dart';
import '../../services/notification_service.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../onboarding/onboarding_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Ink, not white. The bar is transparent over `AppBackdrop`'s default
        // `sky` variant, which is cream at the top — so a white title and a
        // white back arrow were invisible. This page has no dark header; the
        // one on the overview screen does, which is where the white came from.
        iconTheme: const IconThemeData(color: AppTheme.ink),
        titleTextStyle: const TextStyle(
          color: AppTheme.ink,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: AppBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 100, 20, 40),
          children: [
            _buildSettingSection(
              title: l10n.settingsSectionTour,
              children: [
                _buildListTile(
                  icon: Icons.exit_to_app,
                  title: l10n.settingsLeaveTour,
                  textColor: Colors.redAccent,
                  iconColor: Colors.redAccent,
                  onTap: () {
                    context.read<AppBloc>().add(const LeaveTourEvent());
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSettingSection(
              title: l10n.settingsSectionArHunt,
              children: [
                _buildSwitchTile(
                  icon: Icons.science_outlined,
                  title: l10n.settingsTestingMode,
                  subtitle: l10n.settingsTestingModeSubtitle,
                  value: state.arTestingMode,
                  onChanged: (_) =>
                      context.read<AppBloc>().add(const ToggleArTestingModeEvent()),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // No REWARDS row here. The shop is reached from the header on Home
            // and Overview, next to the points count — a currency belongs
            // beside the number that counts it, not three taps away in a
            // settings list.
            _buildSettingSection(
              title: l10n.settingsSectionAccount,
              children: const [_AccountSettings()],
            ),
            const SizedBox(height: 32),
            _buildSettingSection(
              title: l10n.settingsSectionNotifications,
              children: const [_NotificationSettings()],
            ),
            const SizedBox(height: 32),
            _buildSettingSection(
              title: l10n.settingsSectionLanguage,
              children: const [_LanguageSettings()],
            ),
            const SizedBox(height: 32),
            // Offline Maps, Help Center and Privacy Policy used to sit here as
            // rows with an empty `onTap`. A settings screen where half the rows
            // do nothing teaches the traveller that none of them are worth
            // pressing, which costs more than the placeholders were worth. Add
            // each back at the point it does something — as Language, directly
            // above, now has.
            _buildSettingSection(
              title: l10n.settingsSectionAbout,
              children: [
                _buildListTile(
                  icon: Icons.slideshow_outlined,
                  title: l10n.settingsReplayIntro,
                  subtitle: l10n.settingsReplayIntroSubtitle,
                  onTap: () => _replayIntro(context),
                ),
              ],
            ),
            const SizedBox(height: 48),
            Center(
              child: Text(
                l10n.settingsVersion('1.0.0'),
                style: TextStyle(color: AppTheme.text.withValues(alpha: 0.5), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Re-runs the intro as a normal pushed route rather than by clearing the
  /// seen flag: this is "show me that again", not "pretend I never installed
  /// the app", and it should end back in Settings rather than at the sign-in
  /// screen.
  void _replayIntro(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => OnboardingScreen(
          finishLabel: AppLocalizations.of(routeContext).actionDone,
          onFinish: () => Navigator.of(routeContext).pop(),
        ),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _buildSettingSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppTheme.text.withValues(alpha: 0.5),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: AppTheme.brLg),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(height: 1, indent: 56, color: AppTheme.ink.withValues(alpha: 0.1)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.text.withValues(alpha: 0.6))),
      trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: AppTheme.accent),
      onTap: () => onChanged(!value),
    );
  }

  /// [onTap] is required on purpose. It used to default to `() {}`, which is
  /// how four rows that did nothing ended up shipping — a placeholder was one
  /// omitted argument away. Now a row that goes nowhere will not compile.
  Widget _buildListTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Color? textColor,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppTheme.textSecondary),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.text.withValues(alpha: 0.6))) : null,
      trailing: Icon(Icons.chevron_right, size: 20, color: AppTheme.text.withValues(alpha: 0.3)),
      onTap: onTap,
    );
  }
}

/// Who the traveller is, what they have scored, and the way out.
///
/// The score shown here is [AppState.lifetimePoints] — the running total from
/// `profiles.total_points`, not the current tour's pill. It is the only place
/// in the app that answers "how much have I earned overall", which is the
/// number the rewards screen will eventually spend.
class _AccountSettings extends StatelessWidget {
  const _AccountSettings();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final l10n = AppLocalizations.of(context);
    final lifetimePoints = context.select<AppBloc, int?>((b) => b.state.lifetimePoints);
    final isSignedIn = auth.status == AuthStatus.authenticated;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.stars_outlined, color: AppTheme.textSecondary),
          title: Text(l10n.settingsTotalPoints,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(
            // Null is "not synced yet", which is not the same as zero — see
            // AppState.lifetimePoints.
            lifetimePoints == null
                ? l10n.settingsSyncing
                : l10n.settingsEarnedAcrossTours,
            style: TextStyle(fontSize: 12, color: AppTheme.text.withValues(alpha: 0.6)),
          ),
          trailing: Text(
            lifetimePoints?.toString() ?? '—',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.accent,
            ),
          ),
        ),
        Divider(height: 1, indent: 56, color: AppTheme.ink.withValues(alpha: 0.1)),
        ListTile(
          leading: Icon(
            isSignedIn ? Icons.person_outline : Icons.person_add_alt,
            color: AppTheme.textSecondary,
          ),
          title: Text(
            isSignedIn
                ? (auth.email ?? l10n.settingsSignedIn)
                : l10n.settingsCreateAccount,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            isSignedIn
                ? l10n.settingsAccountFollows
                : l10n.settingsGuestOnDevice,
            style: TextStyle(fontSize: 12, color: AppTheme.text.withValues(alpha: 0.6)),
          ),
          trailing: isSignedIn
              ? null
              : Icon(Icons.chevron_right, size: 20, color: AppTheme.text.withValues(alpha: 0.3)),
          onTap: isSignedIn
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (routeContext) => AuthScreen(
                        onContinue: () => Navigator.of(routeContext).pop(),
                      ),
                      fullscreenDialog: true,
                    ),
                  ),
        ),
        if (isSignedIn) ...[
          Divider(height: 1, indent: 56, color: AppTheme.ink.withValues(alpha: 0.1)),
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.textSecondary),
            title: Text(l10n.settingsSignOut,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            onTap: () => context.read<AuthBloc>().add(const SignOutEvent()),
          ),
        ],
      ],
    );
  }
}

/// The master notification switch, plus one per category once it is on.
///
/// The master switch is the same preference the "Notify me" button on the
/// thinking screen writes — there is one per user, not one per route, so
/// turning it off here silences everything the app would otherwise say and
/// drops this device's push token.
///
/// The three category switches only appear while it is on. They are not
/// decoration: "a fennec is nearby" is the one notification the app volunteers
/// unprompted, and a traveller who wants to be told their model finished but
/// not to be interrupted mid-walk should not have to choose between all of it
/// and none of it.
class _NotificationSettings extends StatefulWidget {
  const _NotificationSettings();

  @override
  State<_NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<_NotificationSettings> {
  bool _busy = false;

  Future<void> _toggleMaster(bool on) async {
    setState(() => _busy = true);
    final service = NotificationService.instance;

    if (!on) {
      await service.disable();
      if (mounted) setState(() => _busy = false);
      return;
    }

    final outcome = await service.enable();
    if (!mounted) return;
    setState(() => _busy = false);

    final l10n = AppLocalizations.of(context);
    final message = switch (outcome) {
      EnableOutcome.enabled => null,
      EnableOutcome.enabledLocalOnly => l10n.notifyLocalOnlySettings,
      EnableOutcome.permissionDenied => l10n.notifyDeniedSettings,
      EnableOutcome.backendUnreachable => l10n.notifyOffline,
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = NotificationService.instance;
    final l10n = AppLocalizations.of(context);

    return ValueListenableBuilder<NotificationPrefs>(
      valueListenable: service.prefs,
      builder: (context, prefs, _) {
        return Column(
          children: [
            _switchTile(
              icon: Icons.notifications_none,
              title: l10n.settingsNotifications,
              subtitle: prefs.enabled
                  ? l10n.settingsNotificationsOn
                  : l10n.settingsNotificationsOff,
              value: prefs.enabled,
              onChanged: _busy ? null : _toggleMaster,
            ),
            if (prefs.enabled) ...[
              _divider(),
              _switchTile(
                icon: Icons.route_outlined,
                title: l10n.settingsRouteReady,
                subtitle: l10n.settingsRouteReadySubtitle,
                value: prefs.routeReady,
                onChanged: (v) => service.setCategory(routeReady: v),
              ),
              _divider(),
              _switchTile(
                icon: Icons.view_in_ar_outlined,
                title: l10n.settings3dCaptures,
                subtitle: l10n.settings3dCapturesSubtitle,
                value: prefs.modelReady,
                onChanged: (v) => service.setCategory(modelReady: v),
              ),
              _divider(),
              _switchTile(
                icon: Icons.pets_outlined,
                title: l10n.settingsFennecNearby,
                subtitle: l10n.settingsFennecNearbySubtitle,
                value: prefs.mascotNearby,
                onChanged: (v) => service.setCategory(mascotNearby: v),
              ),
              _divider(),
              _switchTile(
                icon: Icons.blur_on,
                title: l10n.settingsSplatReady,
                subtitle: l10n.settingsSplatReadySubtitle,
                value: prefs.splatReady,
                onChanged: (v) => service.setCategory(splatReady: v),
              ),
              // Worth saying rather than leaving to be discovered: with no
              // Firebase configuration in this build nothing arrives while the
              // app is fully closed, which is exactly when a 3D job finishes.
              if (!service.fcmAvailable || !prefs.pushConfigured)
                _pushUnavailableNote(context),
            ],
          ],
        );
      },
    );
  }

  Widget _divider() =>
      Divider(height: 1, indent: 56, color: AppTheme.ink.withValues(alpha: 0.1));

  Widget _pushUnavailableNote(BuildContext context) => Padding(
        // 56 lines this note up under the tile text rather than the icon.
        padding: const EdgeInsetsDirectional.fromSTEB(56, 4, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 13, color: AppTheme.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                AppLocalizations.of(context).settingsPushNotConfigured,
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.text.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return ListTile(
      leading: _busy && onChanged == null
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, color: AppTheme.textSecondary),
      title: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: AppTheme.text.withValues(alpha: 0.6))),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppTheme.accent,
      ),
      onTap: onChanged == null ? null : () => onChanged(!value),
    );
  }
}

/// The language the app draws itself in.
///
/// Sits below Notifications rather than under About because it changes how
/// every other row on this screen reads — a traveller who opened Settings
/// because the app is in a language they do not speak is looking for this, and
/// the row shows its value in that value's own script so it can be found by
/// sight rather than by reading.
///
/// "Follow device" is the default and stays an option rather than being
/// implied by the absence of a choice: someone who picked Arabic on a French
/// phone needs a way back that does not involve guessing which entry the
/// system would have chosen.
class _LanguageSettings extends StatelessWidget {
  const _LanguageSettings();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleController.instance.locale,
      builder: (context, selected, _) {
        return ListTile(
          leading: const Icon(Icons.translate_outlined, color: AppTheme.textSecondary),
          title: Text(l10n.settingsLanguage,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(
            selected == null
                ? l10n.settingsLanguageSystem
                : LocaleController.languageNames[selected.languageCode] ??
                    selected.languageCode,
            style: TextStyle(fontSize: 12, color: AppTheme.text.withValues(alpha: 0.6)),
          ),
          trailing: Icon(Icons.chevron_right,
              size: 20, color: AppTheme.text.withValues(alpha: 0.3)),
          onTap: () => _pick(context, selected),
        );
      },
    );
  }

  Future<void> _pick(BuildContext context, Locale? selected) async {
    final l10n = AppLocalizations.of(context);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.settingsLanguage,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              _option(
                sheetContext,
                title: l10n.settingsLanguageSystem,
                subtitle: l10n.settingsLanguageSystemSubtitle,
                isSelected: selected == null,
                value: null,
              ),
              for (final locale in AppLocalizations.supportedLocales)
                _option(
                  sheetContext,
                  // Its own name, in its own script — see
                  // [LocaleController.languageNames].
                  title: LocaleController.languageNames[locale.languageCode] ??
                      locale.languageCode,
                  isSelected: selected?.languageCode == locale.languageCode,
                  value: locale,
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _option(
    BuildContext sheetContext, {
    required String title,
    String? subtitle,
    required bool isSelected,
    required Locale? value,
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? AppTheme.accent : AppTheme.text,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(
                  fontSize: 12, color: AppTheme.text.withValues(alpha: 0.6))),
      trailing: isSelected
          ? const Icon(Icons.check_rounded, color: AppTheme.accent, size: 20)
          : null,
      onTap: () {
        // Not awaited: the write is to SharedPreferences and the notifier has
        // already changed, so the app is repainting in the new language before
        // the disk ever comes back.
        LocaleController.instance.setLocale(value);
        Navigator.of(sheetContext).pop();
      },
    );
  }
}
