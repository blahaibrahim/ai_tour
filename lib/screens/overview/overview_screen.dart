import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_state.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/pressable_scale.dart';
import '../settings/settings_screen.dart';
import 'widgets/current_stop_card.dart';
import 'widgets/current_task_panel.dart';
import 'widgets/upcoming_stops_row.dart';

/// The screen the traveller lives on while walking the route.
///
/// Restructured into a dark header over light content cards. Before, white text
/// was used throughout a page whose backdrop runs from blue at the top to cream
/// at the bottom — so the lower half of the screen was white text on a near
/// white ground. Anything below the hero card now sits on an explicit surface
/// and takes the normal ink colour, which makes the contrast a property of the
/// layout rather than of how far the traveller has scrolled.
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final currentStop = state.currentStopIdx < state.accepted.length
        ? state.accepted[state.currentStopIdx]
        : null;

    return Scaffold(
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
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('YOUR ROUTE', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white70, fontWeight: FontWeight.bold)),
                          Text('Overview', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 23, color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.space3),
                    Semantics(
                      label: '${state.points} points earned',
                      excludeSemantics: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space3,
                          vertical: AppTheme.space2 - 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: AppTheme.brPill,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.stars_rounded, size: 15, color: AppTheme.sand),
                            const SizedBox(width: AppTheme.space1),
                            Text(
                              '${state.points}',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.space2),
                    PressableScale(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                      ),
                      child: GlassSurface(
                        tint: GlassTint.dark,
                        borderRadius: AppTheme.brPill,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: AppTheme.minTapTarget,
                          height: AppTheme.minTapTarget,
                          child: Icon(
                            Icons.settings_outlined,
                            color: Colors.white,
                            size: 20,
                            semanticLabel: 'Settings',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _CurrentStopHeader(state: state, currentStopName: currentStop?.name),
              const SizedBox(height: AppTheme.space4),
              if (state.accepted.isNotEmpty) ...[
                _ProgressTrack(state: state),
                const SizedBox(height: AppTheme.space4),
              ],
              if (currentStop != null) ...[
                CurrentStopCard(stop: currentStop),
                const SizedBox(height: AppTheme.space4),
                _ContentCard(child: CurrentTaskPanel(stop: currentStop)),
                const SizedBox(height: AppTheme.space4),
                const UpcomingStopsRow(),
              ] else
                const _RouteComplete(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentStopHeader extends StatelessWidget {
  const _CurrentStopHeader({required this.state, required this.currentStopName});

  final AppState state;
  final String? currentStopName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          currentStopName == null
              ? 'ROUTE COMPLETE'
              : 'STOP ${state.currentStopIdx + 1} OF ${state.accepted.length}',
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.space1),
        Text(
          currentStopName ?? 'All done!',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(color: Colors.white, fontSize: 25),
        ),
      ],
    );
  }
}

/// Per-stop progress. Segmented rather than dots so it scales past the handful
/// of stops a dot row stays readable at.
class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Stop ${state.currentStopIdx + 1} of ${state.accepted.length}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < state.accepted.length; i++) ...[
            if (i > 0) const SizedBox(width: AppTheme.space1),
            Expanded(
              child: AnimatedContainer(
                duration: AppTheme.motionBase,
                height: 5,
                decoration: BoxDecoration(
                  color: i < state.currentStopIdx
                      ? AppTheme.sand
                      : i == state.currentStopIdx
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.22),
                  borderRadius: AppTheme.brPill,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// An opaque light surface. Everything below the hero sits on one of these, so
/// body text has a guaranteed ground rather than whatever the backdrop gradient
/// happens to be at that scroll offset.
class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.space4),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: AppTheme.brLg,
        boxShadow: AppTheme.shadowSm,
      ),
      child: child,
    );
  }
}

class _RouteComplete extends StatelessWidget {
  const _RouteComplete();

  @override
  Widget build(BuildContext context) {
    return _ContentCard(
      padding: const EdgeInsets.all(AppTheme.space6),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppTheme.successSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: AppTheme.success,
              size: 32,
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          Text(
            'Route complete!',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontSize: 20),
          ),
          const SizedBox(height: AppTheme.space2),
          Text(
            'You visited every stop. Your captures are waiting in the folder.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppTheme.text.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
