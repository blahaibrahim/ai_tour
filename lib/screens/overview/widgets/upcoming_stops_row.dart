import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../theme.dart';
import '../../../widgets/net_image.dart';
import '../../../widgets/pressable_scale.dart';
import '../../../widgets/staggered_entrance.dart';

/// Horizontal scroll of stops after the current one so the user can see
/// what is coming up on the route.
class UpcomingStopsRow extends StatelessWidget {
  const UpcomingStopsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final bloc = context.read<AppBloc>();

    final upcoming = state.accepted.sublist(
      state.currentStopIdx + 1 < state.accepted.length
          ? state.currentStopIdx + 1
          : state.accepted.length,
    );

    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'UPCOMING',
          style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppTheme.text.withOpacity(0.55), fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: upcoming.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final loc = upcoming[i];
              return StaggeredEntrance(
                index: i,
                child: PressableScale(
                  onTap: () => bloc.add(OpenDetailEvent(loc)),
                  child: SizedBox(
                    width: 220,
                    child: Container(
                      decoration: BoxDecoration(borderRadius: AppTheme.brLg, boxShadow: AppTheme.shadowSm),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: NetImage(url: loc.thumbUrl, fit: BoxFit.cover),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [AppTheme.photoScrim, AppTheme.photoScrimFade],
                                stops: [0.0, 0.5],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            left: 10,
                            right: 10,
                            child: Text(
                              loc.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
