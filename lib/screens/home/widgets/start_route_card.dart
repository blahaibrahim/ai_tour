import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../theme.dart';
import '../../../widgets/pressable_scale.dart';

/// The screen's one primary action: plan another route.
///
/// A filled card rather than a row in a list, because it is the reason most
/// launches happen and everything else on this screen is a way of not doing it.
/// It leads to the map — which used to *be* the launch screen, and is now
/// somewhere the traveller chooses to go.
class StartRouteCard extends StatelessWidget {
  const StartRouteCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => context.read<AppBloc>().add(const SetScreenEvent('map')),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.space5),
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: AppTheme.brLg,
          boxShadow: AppTheme.shadowLg,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.explore_outlined,
                  color: AppTheme.onAccent, size: 22),
            ),
            const SizedBox(width: AppTheme.space4),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan a new route',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onAccent,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Pick a city, a theme, and how long you have',
                    style: TextStyle(fontSize: 13, color: Color(0xCCFFFFFF)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded,
                color: AppTheme.onAccent, size: 20),
          ],
        ),
      ),
    );
  }
}
