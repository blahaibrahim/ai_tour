import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../auth/auth_screen.dart';
import '../../repositories/notification_repository.dart';
import '../../services/notification_service.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../onboarding/onboarding_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Settings'),
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
              title: 'TOUR',
              children: [
                _buildListTile(
                  icon: Icons.exit_to_app,
                  title: 'Leave Current Tour',
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
              title: 'AR HUNT',
              children: [
                _buildSwitchTile(
                  icon: Icons.science_outlined,
                  title: 'Testing mode',
                  subtitle: 'Spawn the mascot near your current location',
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
              title: 'ACCOUNT',
              children: const [_AccountSettings()],
            ),
            const SizedBox(height: 32),
            _buildSettingSection(
              title: 'NOTIFICATIONS',
              children: const [_NotificationSettings()],
            ),
            const SizedBox(height: 32),
            // Everything that used to sit between here and the version string —
            // Offline Maps, Language, Help Center, Privacy Policy — was a row
            // with an empty `onTap`. A settings screen where half the rows do
            // nothing teaches the traveller that none of them are worth
            // pressing, which costs more than the four placeholders were worth.
            // Add each back at the point it does something.
            _buildSettingSection(
              title: 'ABOUT',
              children: [
                _buildListTile(
                  icon: Icons.slideshow_outlined,
                  title: 'Replay intro',
                  subtitle: 'The tour of what Massar does',
                  onTap: () => _replayIntro(context),
                ),
              ],
            ),
            const SizedBox(height: 48),
            Center(
              child: Text(
                'Massar v1.0.0',
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
          finishLabel: 'Done',
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
          padding: const EdgeInsets.only(left: 4, bottom: 8),
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
    final lifetimePoints = context.select<AppBloc, int?>((b) => b.state.lifetimePoints);
    final isSignedIn = auth.status == AuthStatus.authenticated;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.stars_outlined, color: AppTheme.textSecondary),
          title: const Text('Total points',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(
            // Null is "not synced yet", which is not the same as zero — see
            // AppState.lifetimePoints.
            lifetimePoints == null
                ? 'Syncing…'
                : 'Earned across every tour',
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
            isSignedIn ? (auth.email ?? 'Signed in') : 'Create an account',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            isSignedIn
                ? 'Your points and souvenirs follow this account'
                : 'Guest — your progress lives only on this device',
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
            title: const Text('Sign out',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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

    final message = switch (outcome) {
      EnableOutcome.enabled => null,
      EnableOutcome.enabledLocalOnly =>
        'On, but only while the app is running — push is not set up on this build.',
      EnableOutcome.permissionDenied =>
        'Notifications are turned off for this app in your system settings.',
      EnableOutcome.backendUnreachable =>
        "Couldn't save that right now. Try again once you're back online.",
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = NotificationService.instance;

    return ValueListenableBuilder<NotificationPrefs>(
      valueListenable: service.prefs,
      builder: (context, prefs, _) {
        return Column(
          children: [
            _switchTile(
              icon: Icons.notifications_none,
              title: 'Notifications',
              subtitle: prefs.enabled
                  ? 'Routes, 3D models, and nearby fennecs'
                  : 'Off — you will not be told when anything is ready',
              value: prefs.enabled,
              onChanged: _busy ? null : _toggleMaster,
            ),
            if (prefs.enabled) ...[
              _divider(),
              _switchTile(
                icon: Icons.route_outlined,
                title: 'Route ready',
                subtitle: 'When a route you asked for has finished generating',
                value: prefs.routeReady,
                onChanged: (v) => service.setCategory(routeReady: v),
              ),
              _divider(),
              _switchTile(
                icon: Icons.view_in_ar_outlined,
                title: '3D captures',
                subtitle: 'When a model you photographed is ready, or failed',
                value: prefs.modelReady,
                onChanged: (v) => service.setCategory(modelReady: v),
              ),
              _divider(),
              _switchTile(
                icon: Icons.pets_outlined,
                title: 'Fennec nearby',
                subtitle: 'While a hunt is on, when you get close to one',
                value: prefs.mascotNearby,
                onChanged: (v) => service.setCategory(mascotNearby: v),
              ),
              // Worth saying rather than leaving to be discovered: with no
              // Firebase configuration in this build nothing arrives while the
              // app is fully closed, which is exactly when a 3D job finishes.
              if (!service.fcmAvailable || !prefs.pushConfigured) _pushUnavailableNote(),
            ],
          ],
        );
      },
    );
  }

  Widget _divider() =>
      Divider(height: 1, indent: 56, color: AppTheme.ink.withValues(alpha: 0.1));

  Widget _pushUnavailableNote() => Padding(
        padding: const EdgeInsets.fromLTRB(56, 4, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 13, color: AppTheme.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Push is not configured, so these arrive only while the app is '
                'open or in the background.',
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
