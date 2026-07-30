import 'package:flutter/material.dart';
import '../../../theme.dart';
import '../../../widgets/glass_surface.dart';
import '../../../widgets/pressable_scale.dart';

/// Reject / Info / Accept button row at the bottom of the swipe screen.
class SwipeActionsBar extends StatelessWidget {
  const SwipeActionsBar({
    super.key,
    required this.onReject,
    required this.onInfo,
    required this.onAccept,
  });

  final VoidCallback onReject;
  final VoidCallback onInfo;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PressableScale(
            onTap: onReject,
            child: GlassSurface(
              borderRadius: AppTheme.brPill,
              boxShadow: AppTheme.shadowMd,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 58,
                height: 58,
                child: Icon(Icons.close, color: AppTheme.textSecondary, size: 28),
              ),
            ),
          ),
          const SizedBox(width: 22),
          PressableScale(
            onTap: onInfo,
            child: GlassSurface(
              borderRadius: AppTheme.brPill,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.info_outline, color: AppTheme.text, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 22),
          PressableScale(
            onTap: onAccept,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                shape: BoxShape.circle,
                boxShadow: AppTheme.shadowLg,
              ),
              child: const Icon(Icons.favorite, color: AppTheme.onAccent, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}
