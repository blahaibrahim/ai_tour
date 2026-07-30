import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../models/location.dart';
import '../../../theme.dart';
import '../../../widgets/net_image.dart';
import '../../../widgets/pressable_scale.dart';

/// Large hero card for the current stop, with a bookmark toggle and
/// an "End visit" / "End of route" footer.
class CurrentStopCard extends StatelessWidget {
  const CurrentStopCard({super.key, required this.stop});

  final Location stop;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final bloc = context.read<AppBloc>();

    return PressableScale(
      onTap: () => bloc.add(OpenDetailEvent(stop)),
      child: Container(
        height: 380,
        decoration: BoxDecoration(borderRadius: AppTheme.brLg, boxShadow: AppTheme.shadowMd),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: NetImage(url: stop.photoUrl, fit: BoxFit.cover)),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [AppTheme.photoScrim, AppTheme.photoScrimFade],
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
                          stop.name,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 22),
                        ),
                        const SizedBox(height: 4),
                        Text('${stop.region}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                  if (state.currentStopIdx < state.accepted.length - 1)
                    ElevatedButton(
                      onPressed: () => bloc.add(const AdvanceStopEvent()),
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
                        Icon(Icons.flag_outlined, size: 16, color: AppTheme.onNavy.withOpacity(0.8)),
                        const SizedBox(width: 4),
                        Text('End of route',
                            style: TextStyle(fontSize: 12, color: AppTheme.onNavy.withOpacity(0.8), fontWeight: FontWeight.bold)),
                      ],
                    ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                decoration: const BoxDecoration(color: AppTheme.photoScrim, shape: BoxShape.circle),
                child: IconButton(
                  icon: Icon(
                    state.savedLocationIds.contains(stop.id) ? Icons.bookmark : Icons.bookmark_border,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: () => bloc.add(ToggleSavedLocationEvent(stop.id)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
