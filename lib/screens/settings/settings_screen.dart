import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../repositories/notification_repository.dart';
import '../../services/notification_service.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';

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
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
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
            _buildSettingSection(
              title: 'ACCOUNT',
              children: [
                _buildListTile(icon: Icons.person_outline, title: 'Profile details'),
                _buildListTile(icon: Icons.stars_outlined, title: 'AI Tour Pro', subtitle: 'Manage subscription'),
              ],
            ),
            const SizedBox(height: 32),
            _buildSettingSection(
              title: 'NOTIFICATIONS',
              children: const [_NotificationSettings()],
            ),
            const SizedBox(height: 32),
            _buildSettingSection(
              title: 'PREFERENCES',
              children: [
                _buildListTile(icon: Icons.map_outlined, title: 'Offline Maps'),
                _buildListTile(icon: Icons.language, title: 'Language', subtitle: 'English'),
              ],
            ),
            const SizedBox(height: 32),
            _buildSettingSection(
              title: 'ABOUT',
              children: [
                _buildListTile(icon: Icons.help_outline, title: 'Help Center'),
                _buildListTile(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy'),
              ],
            ),
            const SizedBox(height: 48),
            Center(
              child: Text(
                'AI Tour v1.0.0',
                style: TextStyle(color: AppTheme.text.withValues(alpha: 0.5), fontSize: 12),
              ),
            ),
          ],
        ),
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

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? textColor,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppTheme.textSecondary),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.text.withValues(alpha: 0.6))) : null,
      trailing: Icon(Icons.chevron_right, size: 20, color: AppTheme.text.withValues(alpha: 0.3)),
      onTap: onTap ?? () {},
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
