import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../blocs/app/app_state.dart';
import '../../../models/location.dart';
import '../../../theme.dart';
import '../../ar_hunt/hunt_radar_screen.dart';

/// Task row for the current stop — shows label, points, and action buttons
/// (Record / Scan / Hunt, and an optional Regenerate button).
class CurrentTaskPanel extends StatelessWidget {
  const CurrentTaskPanel({super.key, required this.stop});

  final Location stop;

  /// Opens the proximity hunt for [stop]'s mascot.
  ///
  /// In testing mode the hunt targets a spawn point generated near the
  /// tester's own position at app start ([AppState.testMascotSpawn]) instead
  /// of the stop's real coordinates — so the hunt is playable without
  /// travelling to an actual POI. See `AppConfig.arTestingMode`.
  static void _openMascotHunt(BuildContext context, AppState state, Location stop) {
    final testSpawn = state.testMascotSpawn;
    final useTestSpawn = state.arTestingMode && testSpawn != null;
    final spawnLocation = useTestSpawn ? testSpawn : LatLng(stop.lat, stop.lng);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HuntRadarScreen(
          spawnLocation: spawnLocation,
          stopName: stop.name,
          isTestSpawn: useTestSpawn,
          routeId: state.route?.id,
          poiId: stop.id,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final currentTask = state.currentStopIdx < state.tasks.length
        ? state.tasks[state.currentStopIdx]
        : null;

    if (currentTask == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'CURRENT TASK',
              style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppTheme.text.withValues(alpha: 0.55), fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (currentTask.state == 'pending' && state.taskRegenerationsLeft > 0)
              InkWell(
                onTap: () => context.read<AppBloc>().add(const RegenerateTaskEvent()),
                borderRadius: AppTheme.brPill,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.ink.withValues(alpha: 0.05),
                    borderRadius: AppTheme.brPill,
                    border: Border.all(color: AppTheme.ink.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Regenerate (${state.taskRegenerationsLeft})',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '+${currentTask.points} pts',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.cocoa),
                  ),
                  const SizedBox(height: 2),
                  Text(currentTask.label, style: const TextStyle(fontSize: 13.5)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: currentTask.state == 'pending'
                  ? ElevatedButton(
                      key: const ValueKey('pending'),
                      onPressed: currentTask.type == 'mascot'
                          ? () => _openMascotHunt(context, state, stop)
                          : () => context.read<AppBloc>().add(const CompleteTaskEvent()),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                      ),
                      child: Text(switch (currentTask.type) {
                        'video' => 'Record',
                        'mascot' => 'Hunt',
                        _ => 'Scan',
                      }),
                    )
                  : Container(
                      key: const ValueKey('done'),
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                      child: const Icon(Icons.check, color: Colors.white, size: 16),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
