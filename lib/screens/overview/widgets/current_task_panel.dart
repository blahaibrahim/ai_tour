import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../blocs/app/app_state.dart';
import '../../../models/location.dart';
import '../../../theme.dart';
import '../../ar_hunt/ar_hunt_screen.dart';
import 'inline_mascot_hunt.dart';

/// Task row for the current stop — shows label, points, and action buttons
/// (Record / Scan / Hunt, and an optional Regenerate button).
///
/// A mascot task's hot/cold hunt runs inline underneath the row rather than on
/// a screen of its own, so the visitor keeps the task, its points, and the
/// route in view while walking the fennec down.
class CurrentTaskPanel extends StatefulWidget {
  const CurrentTaskPanel({super.key, required this.stop});

  final Location stop;

  @override
  State<CurrentTaskPanel> createState() => _CurrentTaskPanelState();
}

class _CurrentTaskPanelState extends State<CurrentTaskPanel> {
  /// Whether the inline hunt is running. Disposing the widget tears the GPS
  /// session down, so this doubles as the session's on/off switch.
  bool _hunting = false;

  Location get stop => widget.stop;

  /// Opens the camera locked to what this quest asks for.
  ///
  /// The button used to dispatch [CompleteTaskEvent] directly, which marked the
  /// quest done without anything being captured — the traveller was awarded
  /// points for pressing a button. Now the quest is finished by the capture
  /// itself, in [AppBloc], and only when the capture is the kind the quest
  /// asked for.
  void _openQuestCamera(String questType) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArHuntScreen(
          mode: ArCameraMode.capture,
          intent: questType == 'video' ? CaptureIntent.video : CaptureIntent.photo,
          stopName: stop.name,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  void didUpdateWidget(CurrentTaskPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Moving on to the next stop ends the hunt — its mascot is behind us.
    if (oldWidget.stop.id != widget.stop.id && _hunting) {
      setState(() => _hunting = false);
    }
  }

  /// The inline hunt for [stop]'s mascot.
  ///
  /// In testing mode the hunt targets a spawn point generated near the
  /// tester's own position at app start ([AppState.testMascotSpawn]) instead
  /// of the stop's real coordinates — so the hunt is playable without
  /// travelling to an actual POI. See `AppConfig.arTestingMode`.
  Widget _buildMascotHunt(AppState state) {
    final testSpawn = state.testMascotSpawn;
    final useTestSpawn = state.arTestingMode && testSpawn != null;
    final spawnLocation = useTestSpawn ? testSpawn : LatLng(stop.lat, stop.lng);

    return InlineMascotHunt(
      // Keyed by stop so advancing to the next stop restarts the session
      // rather than re-targeting a live one.
      key: ValueKey('hunt-${stop.id}'),
      spawnLocation: spawnLocation,
      stopName: stop.name,
      isTestSpawn: useTestSpawn,
      routeId: state.route?.id,
      poiId: stop.id,
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
            // Hidden once this stop has shown every quest type it has, not
            // just once the budget runs out — offering a swap that could only
            // return something already refused is the 'do-over' the rule
            // exists to prevent.
            if (state.canRegenerateQuest)
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
                          ? () => setState(() => _hunting = !_hunting)
                          : () => _openQuestCamera(currentTask.type),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                      ),
                      // Quests are now drawn from photo/video/mascot, so the
                      // old default of 'Scan' would have labelled every photo
                      // quest as a 3D scan — a different action entirely, and
                      // the one type no longer assigned at all.
                      child: Text(switch (currentTask.type) {
                        'photo' => 'Shoot',
                        'video' => 'Film',
                        'mascot' => _hunting ? 'Stop' : 'Hunt',
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
        if (_hunting && currentTask.type == 'mascot' && currentTask.state == 'pending') ...[
          const SizedBox(height: 12),
          _buildMascotHunt(state),
        ],
      ],
    );
  }
}
