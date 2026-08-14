import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../models/route.dart';
import '../../../theme.dart';
import '../../../widgets/net_image.dart';
import '../../../widgets/pressable_scale.dart';
import '../../../widgets/staggered_entrance.dart';

/// The generated route's stops, with the leg that leads into each one.
///
/// Two changes from the list this replaces:
///
///   * **Legs are shown, tagged with their mode.** The server tags every
///     segment `drive` or `walk`; the client renders that tag and never infers
///     it — a cluster with one stop in it would defeat any inference.
///   * **No manual reordering.** The order is the optimizer's output over a
///     real travel-time matrix, and a hand-dragged order would leave every
///     segment duration and the route total describing a route that no longer
///     exists. Dropping a stop re-generates instead.
class ItineraryList extends StatelessWidget {
  const ItineraryList({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final bloc = context.read<AppBloc>();
    final route = state.route;
    if (route == null) return const SizedBox.shrink();

    final regionLabel = state.selectedCity?.name ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < route.stops.length; i++)
          StaggeredEntrance(
            key: ValueKey(route.stops[i].poiId),
            index: i,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (route.legInto(i) case final segment?)
                  _LegRow(segment: segment),
                _StopRow(
                  stop: route.stops[i],
                  index: i,
                  // Trimming stops below the requested budget is refused, so
                  // the control that would do it is not offered.
                  modifyMode: state.modifyMode && state.canRemoveStop(route.stops[i].dwellMinutes),
                  onTap: () => bloc.add(
                    OpenDetailEvent(route.stops[i].toLocation(regionLabel: regionLabel)),
                  ),
                  onRemove: () => bloc.add(RemoveStopEvent(i)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One travel leg between two stops, with its mode tag.
class _LegRow extends StatelessWidget {
  const _LegRow({required this.segment});
  final RouteSegment segment;

  @override
  Widget build(BuildContext context) {
    final isDrive = segment.mode == SegmentMode.drive;
    final color = isDrive ? AppTheme.accentDark : AppTheme.text.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.only(left: 44, bottom: 12),
      child: Row(
        children: [
          // A dashed connector would be nicer; a short rule reads clearly
          // enough and costs no custom painter.
          Container(width: 2, height: 18, color: AppTheme.text.withValues(alpha: 0.15)),
          const SizedBox(width: 12),
          Icon(
            isDrive ? Icons.directions_car_filled_outlined : Icons.directions_walk,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            isDrive ? 'Drive' : 'Walk',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            '${formatMinutes(segment.durationMinutes)} · ${segment.distanceLabel}',
            style: TextStyle(fontSize: 12, color: AppTheme.text.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.index,
    required this.modifyMode,
    required this.onTap,
    required this.onRemove,
  });

  final RouteStop stop;
  final int index;
  final bool modifyMode;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppTheme.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentDark,
                ),
              ),
            ),
            const SizedBox(width: 12),
            NetImage(
              url: stop.photoUrl ?? '',
              width: 76,
              height: 60,
              fit: BoxFit.cover,
              borderRadius: AppTheme.brMd,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 11, color: AppTheme.text.withValues(alpha: 0.5)),
                      const SizedBox(width: 4),
                      Text(
                        '${formatMinutes(stop.dwellMinutes)} here',
                        style: TextStyle(fontSize: 12, color: AppTheme.text.withValues(alpha: 0.65)),
                      ),
                      if (stop.categoryKey.isNotEmpty) ...[
                        Text(
                          ' · ',
                          style: TextStyle(fontSize: 12, color: AppTheme.text.withValues(alpha: 0.4)),
                        ),
                        Flexible(
                          child: Text(
                            stop.categoryKey,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.text.withValues(alpha: 0.65),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.centerRight,
              child: !modifyMode
                  ? const SizedBox(height: 60)
                  : Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: PressableScale(
                        onTap: onRemove,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.delete_outline,
                              size: 20, color: AppTheme.error),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
