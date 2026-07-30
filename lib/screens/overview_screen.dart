import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'ar_hunt_screen.dart';
import 'settings_screen.dart';
import '../widgets/app_backdrop.dart';
import '../widgets/glass_surface.dart';
import '../widgets/net_image.dart';
import '../widgets/staggered_entrance.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  /// Opens the AR mascot hunt for the current stop. The photo taken there is
  /// filed through [AppState.addCapturedArtifact], which completes the task.
  static void _openMascotHunt(BuildContext context, String stopName) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArHuntScreen(stopName: stopName),
        fullscreenDialog: true,
      ),
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Still up?';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.routeAccepted) {
      return Scaffold(
        body: AppBackdrop(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppTheme.heroGradient,
                      ),
                      boxShadow: [BoxShadow(color: Color(0x552F1B3D), blurRadius: 28, offset: Offset(0, 12))],
                    ),
                    child: const Icon(Icons.map_outlined, color: AppTheme.onAccent, size: 34),
                  ),
                  const SizedBox(height: 18),
                  Text('No route yet', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 23)),
                  const SizedBox(height: 8),
                  Text(
                    'Plan a route to see your next stop and daily tasks here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.text.withOpacity(0.75)),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => state.setScreen('map'),
                    child: const Text('Plan a route'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final nextStop = state.currentStopIdx < state.accepted.length ? state.accepted[state.currentStopIdx] : null;
    final currentTask = state.currentStopIdx < state.tasks.length ? state.tasks[state.currentStopIdx] : null;
    final remainingRows = state.accepted.skip(state.currentStopIdx + 1).toList();
    final totalStops = state.accepted.length;
    final progress = totalStops == 0 ? 0.0 : (state.currentStopIdx + 1) / totalStops;

    return Scaffold(
      body: AppBackdrop(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 56, 0, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header & Score Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_greeting().toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white70, fontWeight: FontWeight.bold)),
                            Text('Your Route', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 23, color: Colors.white)),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: AppTheme.brPill,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, color: AppTheme.duskGold, size: 15),
                                  const SizedBox(width: 5),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 320),
                                    transitionBuilder: (child, animation) => ScaleTransition(
                                      scale: animation,
                                      child: FadeTransition(opacity: animation, child: child),
                                    ),
                                    child: Text(
                                      '${state.points}',
                                      key: ValueKey(state.points),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.white70),
                              onPressed: () {
                                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Current Stop Section
                    if (nextStop != null) ...[
                      const Text('CURRENT STOP', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: Colors.white70, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Container(
                        height: 380,
                        decoration: BoxDecoration(
                          borderRadius: AppTheme.brLg,
                          boxShadow: AppTheme.shadowMd,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: NetImage(url: nextStop.photoUrl, fit: BoxFit.cover),
                            ),
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Color(0xBF140E08), Colors.transparent],
                                  stops: [0.0, 0.4],
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 14,
                              left: 16,
                              right: 16,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nextStop.name,
                                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 22),
                                        ),
                                        const SizedBox(height: 4),
                                        Text('${nextStop.region}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                                      ],
                                    ),
                                  ),
                                  if (state.currentStopIdx < state.accepted.length - 1)
                                    ElevatedButton(
                                      onPressed: state.onAdvanceStop,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white.withOpacity(0.15),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        minimumSize: Size.zero,
                                      ),
                                      child: const Text('End visit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    )
                                  else
                                    Row(
                                      children: [
                                        Icon(Icons.flag_outlined, size: 16, color: Colors.white.withOpacity(0.8)),
                                        const SizedBox(width: 4),
                                        Text(
                                          "End of route",
                                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    state.savedLocationIds.contains(nextStop.id) ? Icons.bookmark : Icons.bookmark_border,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  onPressed: () => state.toggleSavedLocation(nextStop.id),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Task Section
                      if (currentTask != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('CURRENT TASK', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppTheme.text.withOpacity(0.55), fontWeight: FontWeight.bold)),
                            const Spacer(),
                            if (currentTask.state == 'pending' && state.taskRegenerationsLeft > 0)
                              InkWell(
                                onTap: state.onRegenerateTask,
                                borderRadius: AppTheme.brPill,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.ink.withOpacity(0.05),
                                    borderRadius: AppTheme.brPill,
                                    border: Border.all(color: AppTheme.ink.withOpacity(0.1)),
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '+${currentTask.points} pts',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accent),
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
                                          // A mascot task is played out in the
                                          // AR view, which banks the points
                                          // itself once the photo is taken.
                                          onPressed: currentTask.type == 'mascot'
                                              ? () => _openMascotHunt(context, nextStop.name)
                                              : state.onCompleteTask,
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
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              if (remainingRows.isNotEmpty) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('COMING UP', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppTheme.text.withOpacity(0.55))),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: remainingRows.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final loc = remainingRows[index];
                      final number = state.currentStopIdx + 2 + index;
                      return StaggeredEntrance(
                        index: index,
                        child: Container(
                          width: 150,
                          decoration: BoxDecoration(
                            borderRadius: AppTheme.brMd,
                            boxShadow: AppTheme.shadowSm,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: NetImage(
                                  url: loc.overviewPhotoUrl,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Color(0xBF140E08),
                                      Colors.transparent,
                                    ],
                                    stops: [0.0, 0.6],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 10,
                                bottom: 10,
                                right: 10,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      loc.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      loc.region,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
