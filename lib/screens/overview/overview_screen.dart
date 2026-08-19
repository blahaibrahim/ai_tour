import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_state.dart';
import '../../theme.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/points_pill.dart';
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
              // Offline banner — visible only when backend is unreachable.
              if (state.isOffline || state.pendingSyncCount > 0)
                OfflineBanner(
                  isOffline: state.isOffline,
                  pendingSyncCount: state.pendingSyncCount,
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.of(context).overviewYourRoute, style: const TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white70, fontWeight: FontWeight.bold)),
                          Text(AppLocalizations.of(context).overviewTitle, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 23, color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.space3),
                    // This pill counts *this walk*, not the wallet — that is
                    // what the overview screen is a readout of. The shop beside
                    // it spends the balance, which is a different number, so the
                    // semantic label says which one this is rather than leaving
                    // the two to be read as the same figure.
                    PointsPill(
                      value: state.points,
                      semanticLabel: AppLocalizations.of(context)
                          .overviewPointsEarned(state.points),
                    ),
                    const SizedBox(width: AppTheme.space2),
                    const ShopButton(),
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
                        child: SizedBox(
                          width: AppTheme.minTapTarget,
                          height: AppTheme.minTapTarget,
                          child: Icon(
                            Icons.settings_outlined,
                            color: Colors.white,
                            size: 20,
                            semanticLabel: AppLocalizations.of(context).actionSettings,
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
              ? AppLocalizations.of(context).overviewRouteCompleteBanner
              : AppLocalizations.of(context).overviewStopOfBanner(
                  state.currentStopIdx + 1, state.accepted.length),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.space1),
        Text(
          currentStopName ?? AppLocalizations.of(context).overviewAllDone,
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
      label: AppLocalizations.of(context)
          .overviewStopOf(state.currentStopIdx + 1, state.accepted.length),
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
            AppLocalizations.of(context).overviewRouteCompleteTitle,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontSize: 20),
          ),
          const SizedBox(height: AppTheme.space2),
          Text(
            AppLocalizations.of(context).overviewRouteCompleteBody,
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
