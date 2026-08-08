import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets/glass_surface.dart';
import '../../../widgets/pressable_scale.dart';

/// Undo / Reject / Info / Keep button row at the bottom of the swipe screen.
///
/// Every action here mirrors a gesture, so the screen is fully usable without
/// swiping at all — which matters for anyone who can't make a confident drag,
/// and for the assistive-technology path, where a drag is not expressible.
class SwipeActionsBar extends StatelessWidget {
  const SwipeActionsBar({
    super.key,
    required this.onReject,
    required this.onInfo,
    required this.onAccept,
    required this.onUndo,
    required this.canUndo,
  });

  final VoidCallback onReject;
  final VoidCallback onInfo;
  final VoidCallback onAccept;
  final VoidCallback onUndo;

  /// False on the first card, where there is nothing to take back.
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppTheme.space4,
          bottom: AppTheme.space4,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SecondaryAction(
              icon: Icons.undo_rounded,
              label: 'Undo the last swipe',
              size: 44,
              iconSize: 21,
              enabled: canUndo,
              onTap: onUndo,
            ),
            const SizedBox(width: AppTheme.space4),
            _SecondaryAction(
              icon: Icons.close_rounded,
              label: 'Drop this stop',
              size: 58,
              iconSize: 28,
              onTap: onReject,
            ),
            const SizedBox(width: AppTheme.space5),
            _SecondaryAction(
              icon: Icons.info_outline_rounded,
              label: 'About this stop',
              size: 44,
              iconSize: 21,
              onTap: onInfo,
            ),
            const SizedBox(width: AppTheme.space5),
            Semantics(
              button: true,
              label: 'Keep this stop',
              excludeSemantics: true,
              child: PressableScale(
                onTap: onAccept,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.shadowLg,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppTheme.onAccent,
                    size: 30,
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

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.size,
    required this.iconSize,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final double size;
  final double iconSize;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: PressableScale(
          onTap: enabled ? onTap : () {},
          child: GlassSurface(
            borderRadius: AppTheme.brPill,
            boxShadow: AppTheme.shadowMd,
            alignment: Alignment.center,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: AppTheme.text, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}
