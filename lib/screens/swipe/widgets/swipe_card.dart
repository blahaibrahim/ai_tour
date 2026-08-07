import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../models/location.dart';
import '../../../theme.dart';
import '../../../widgets/net_image.dart';
import '../../../widgets/pressable_scale.dart';

/// The visual card shown during swiping — photo, gradient, name, region,
/// bookmark button, and drag-overlay badges (LIKE / NOPE / MORE INFO).
///
/// [isBackground] suppresses the badges on stack-depth cards.
class SwipeCard extends StatelessWidget {
  const SwipeCard({
    super.key,
    required this.loc,
    this.isBackground = false,
    this.dx = 0,
    this.dy = 0,
  });

  final Location loc;
  final bool isBackground;
  final double dx;
  final double dy;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;

    final likeOpacity = (dx / 110).clamp(0.0, 1.0);
    final nopeOpacity = (-dx / 110).clamp(0.0, 1.0);
    final infoOpacity =
        ((dy / 110).clamp(0.0, 1.0) * (1 - (dx.abs() / 70).clamp(0.0, 1.0)));

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.deepNavy,
        borderRadius: BorderRadius.circular(40),
        boxShadow: AppTheme.shadowLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetImage(url: loc.photoUrl, fit: BoxFit.cover),

          // Soft gradient for legibility of overlaid text
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomRight,
                end: Alignment.topLeft,
                colors: [AppTheme.photoScrim, AppTheme.photoScrimFade],
                stops: [0.0, 0.55],
              ),
            ),
          ),

          // Says so when the picture is of the surrounding area rather than
          // this place. Bottom-left, clear of the LIKE/NOPE badges.
          if (loc.photoCredit != null)
            Positioned(
              left: 16,
              bottom: 12,
              right: 80,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StockPhotoTag(label: loc.photoCredit!),
              ),
            ),

          // Labels (LIKE, NOPE, MORE INFO)
          if (!isBackground) ...[
            Positioned(
              top: 16,
              left: 16,
              child: Opacity(
                opacity: likeOpacity,
                child: Transform.rotate(
                  angle: -14 * (math.pi / 180),
                  child: _buildBadge('LIKE', AppTheme.accent),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Opacity(
                opacity: nopeOpacity,
                child: Transform.rotate(
                  angle: 14 * (math.pi / 180),
                  child: _buildBadge('NOPE', AppTheme.textSecondary),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Opacity(
                  opacity: infoOpacity,
                  child: _buildBadge('MORE INFO ↓', AppTheme.text),
                ),
              ),
            ),
          ],

          // Content
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    loc.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          loc.region,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            height: 1.3,
                          ),
                        ),
                      ),
                      PressableScale(
                        onTap: () => context.read<AppBloc>().add(ToggleSavedLocationEvent(loc.id)),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Icon(
                            state.savedLocationIds.contains(loc.id)
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color: state.savedLocationIds.contains(loc.id)
                                ? AppTheme.accent
                                : Colors.white,
                            size: 42,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: AppTheme.brPill,
        boxShadow: AppTheme.shadowSm,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
