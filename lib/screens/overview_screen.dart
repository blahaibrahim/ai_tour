import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/net_image.dart';
import '../widgets/staggered_entrance.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.routeAccepted) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.map_outlined, color: AppTheme.accent, size: 42),
                const SizedBox(height: 14),
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
      );
    }

    final nextStop = state.currentStopIdx < state.accepted.length ? state.accepted[state.currentStopIdx] : null;
    final currentTask = state.currentStopIdx < state.tasks.length ? state.tasks[state.currentStopIdx] : null;
    final remainingRows = state.accepted.skip(state.currentStopIdx + 1).toList();

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OVERVIEW', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                    Text('Next up', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 23)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.tertiary,
                    borderRadius: AppTheme.brPill,
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: AppTheme.accent, size: 15),
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Next Stop Card
            if (nextStop != null) ...[
              Container(
                height: 190,
                decoration: BoxDecoration(
                  borderRadius: AppTheme.brLg,
                  boxShadow: AppTheme.shadowMd,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: NetImage(url: nextStop.overviewPhotoUrl, fit: BoxFit.cover),
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
                          stops: [0.0, 0.55],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 14,
                      left: 16,
                      right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nextStop.name,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 18),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${nextStop.region} · ${nextStop.distanceLabel(false)}',
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Current Task
              if (currentTask != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: AppTheme.brLg,
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            currentTask.type == 'video' ? Icons.videocam_outlined : Icons.qr_code_scanner_outlined,
                            color: AppTheme.accent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${currentTask.type == 'video' ? 'Video task' : 'Scan task'} · +${currentTask.points} pts',
                            style: TextStyle(
                              fontFamily: AppTheme.theme.textTheme.headlineSmall?.fontFamily,
                              fontSize: 14,
                              color: AppTheme.text,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(currentTask.label, style: const TextStyle(fontSize: 13.5)),
                      const SizedBox(height: 12),

                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(animation),
                            child: child,
                          ),
                        ),
                        child: currentTask.state == 'pending'
                            ? ElevatedButton(
                                key: const ValueKey('pending'),
                                onPressed: state.onCompleteTask,
                                child: Text(currentTask.type == 'video' ? 'Record it' : 'Scan it'),
                              )
                            : const Row(
                                key: ValueKey('done'),
                                children: [
                                  Icon(Icons.check, color: AppTheme.text, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    'Nice! Points banked.',
                                    style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),

              // Grows/retracts and cross-fades in step with the task-status
              // swap above, instead of popping in instantly (which used to
              // flash oddly against the still-animating card above it).
              AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: currentTask?.state != 'done'
                      ? const SizedBox(key: ValueKey('hidden'), height: 18)
                      : Padding(
                          key: ValueKey(state.currentStopIdx < state.accepted.length - 1 ? 'advance' : 'finish'),
                          padding: const EdgeInsets.only(top: 18),
                          child: state.currentStopIdx < state.accepted.length - 1
                              ? OutlinedButton(
                                  onPressed: state.onAdvanceStop,
                                  style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                                  child: const Text('Mark as visited · continue to next stop'),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.flag_outlined, size: 16, color: AppTheme.text.withOpacity(0.55)),
                                    const SizedBox(width: 8),
                                    Text(
                                      "That's the whole route — safe travels!",
                                      style: TextStyle(fontSize: 13.5, color: AppTheme.text.withOpacity(0.55)),
                                    ),
                                  ],
                                ),
                        ),
                ),
              ),
            ],

            if (remainingRows.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('COMING UP', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppTheme.text.withOpacity(0.55))),
              const SizedBox(height: 8),
              ...remainingRows.asMap().entries.map((entry) {
                final loc = entry.value;
                final number = state.currentStopIdx + 2 + entry.key;
                return StaggeredEntrance(
                  index: entry.key,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: AppTheme.brMd,
                      boxShadow: AppTheme.shadowSm,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(color: AppTheme.tertiary, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Text('$number', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(loc.name, style: const TextStyle(fontSize: 13))),
                        Text(loc.distanceLabel(false), style: TextStyle(fontSize: 11.5, color: AppTheme.text.withOpacity(0.6))),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
