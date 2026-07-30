import 'package:flutter/material.dart';
import '../theme.dart';

/// A single pill-shaped item in the bottom navigation bar.
class NavButton extends StatelessWidget {
  const NavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.brPill,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        padding: EdgeInsets.symmetric(horizontal: isActive ? 20 : 16, vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accent : Colors.transparent,
          borderRadius: AppTheme.brPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isActive ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: Icon(
                icon,
                size: 22,
                color: isActive ? AppTheme.onAccent : AppTheme.ink.withOpacity(0.5),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: isActive
                  ? Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: AppTheme.theme.textTheme.headlineSmall?.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onAccent,
                        ),
                      ),
                    )
                  : const SizedBox(height: 22),
            ),
          ],
        ),
      ),
    );
  }
}
