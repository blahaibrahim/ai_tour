import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/app/app_bloc.dart';
import '../../../theme.dart';
import '../../../widgets/glass_surface.dart';
import '../../../widgets/points_pill.dart';
import '../../../widgets/pressable_scale.dart';

/// Title, spendable balance, the way into the shop, and settings.
///
/// The number here is [AppState.pointsBalance] — what is left to spend — rather
/// than the lifetime score, because the control immediately to its right spends
/// exactly that. A pill showing one number beside a button that spends another
/// would be a small lie told every time the screen is opened.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final balance = context.select<AppBloc, int?>((b) => b.state.pointsBalance);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MASSAR',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _Greeting(),
            ],
          ),
        ),
        const SizedBox(width: AppTheme.space3),
        PointsPill(
          value: balance,
          semanticLabel: balance == null
              ? 'Points balance syncing'
              : '$balance points to spend',
        ),
        const SizedBox(width: AppTheme.space2),
        const ShopButton(),
        const SizedBox(width: AppTheme.space2),
        PressableScale(
          onTap: onSettings,
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
    );
  }
}

/// Rendered separately so the headline can pick up the display face the rest of
/// the app's screen titles use, which needs a `BuildContext` the enclosing
/// const `Column` would otherwise deny it.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Where to next?',
      style: Theme.of(context)
          .textTheme
          .headlineSmall
          ?.copyWith(fontSize: 23, color: Colors.white),
    );
  }
}
