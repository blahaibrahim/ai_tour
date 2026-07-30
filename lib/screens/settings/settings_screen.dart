import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
              title: 'ACCOUNT',
              children: [
                _buildListTile(icon: Icons.person_outline, title: 'Profile details'),
                _buildListTile(icon: Icons.stars_outlined, title: 'AI Tour Pro', subtitle: 'Manage subscription'),
              ],
            ),
            const SizedBox(height: 32),
            _buildSettingSection(
              title: 'PREFERENCES',
              children: [
                _buildListTile(icon: Icons.notifications_none, title: 'Notifications'),
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
                style: TextStyle(color: AppTheme.text.withOpacity(0.5), fontSize: 12),
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
              color: AppTheme.text.withOpacity(0.5),
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
                  Divider(height: 1, indent: 56, color: AppTheme.ink.withOpacity(0.1)),
              ],
            ],
          ),
        ),
      ],
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
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.text.withOpacity(0.6))) : null,
      trailing: Icon(Icons.chevron_right, size: 20, color: AppTheme.text.withOpacity(0.3)),
      onTap: onTap ?? () {},
    );
  }
}
