import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../settings/settings_screen.dart';
import 'widgets/home_header.dart';
import 'widgets/route_history_list.dart';
import 'widgets/start_route_card.dart';

/// Where the app opens, and where it returns between tours.
///
/// It answers the three things a traveller who is not currently walking wants:
/// start another route, look at the ones they have already done, or spend what
/// those earned. Before this screen the app booted straight into the planning
/// map, which assumed the only reason to open Massar was to build something new
/// — and left every past route reachable only through a notification.
///
/// The screen is stateless and reads everything from [AppState]; the two loads
/// it needs are dispatched by [_HomeLoader] on first build rather than in the
/// bloc's constructor, so a signed-out launch does not fetch a history that
/// belongs to nobody.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _HomeLoader(
      child: Scaffold(
        body: AppBackdrop(
          variant: AppBackdropVariant.deep,
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space5,
                AppTheme.space4,
                AppTheme.space5,
                // Clears the floating nav bar and camera button.
                120,
              ),
              children: [
                HomeHeader(
                  onSettings: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen()),
                  ),
                ),
                const SizedBox(height: AppTheme.space6),
                const StartRouteCard(),
                const SizedBox(height: AppTheme.space6),
                const RouteHistoryList(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for the balance and the history once, when the screen first appears.
///
/// A `StatefulWidget` purely for `initState`: dispatching from `build` would
/// re-fire on every rebuild, and dispatching from the bloc's constructor would
/// run before the auth session is restored.
class _HomeLoader extends StatefulWidget {
  const _HomeLoader({required this.child});

  final Widget child;

  @override
  State<_HomeLoader> createState() => _HomeLoaderState();
}

class _HomeLoaderState extends State<_HomeLoader> {
  @override
  void initState() {
    super.initState();
    final bloc = context.read<AppBloc>();
    bloc.add(const LoadPointsEvent());
    bloc.add(const LoadRouteHistoryEvent());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
